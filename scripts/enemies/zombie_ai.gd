class_name ZombieAI
extends CharacterBody3D
## Standard zombie AI controller with explicit state machine, periodic
## NavigationAgent3D pathing, separation steering, stagger cooldown, and stuck recovery.

enum State {
	IDLE,
	CHASE,
	ATTACK_WINDUP,
	ATTACK,
	STAGGER,
	DEAD,
}

enum Mode {
	DIRECT_CHASE,
	APPROACH_BARRICADE,
	BREAK_BARRICADE,
	ENTER_BARRICADE,
}

signal died(zombie: ZombieAI)
signal hit_registered(zombie: ZombieAI, is_headshot: bool, source: Node)
signal pool_returned(zombie: ZombieAI)
signal stall_watchdog_triggered(zombie: ZombieAI)

@export var data: EnemyData
@export var path_update_interval: float = 0.25
@export var stagger_duration: float = 0.28
@export var stagger_cooldown: float = 1.2
@export var separation_radius: float = 0.85
@export var separation_strength: float = 0.55
@export var stuck_timeout: float = 1.2
@export var watchdog_timeout: float = 12.0
@export var watchdog_min_progress: float = 0.75
@export var death_despawn_delay: float = 4.0
@export var gravity: float = 14.0
@export var despawn_to_pool: bool = false
@export var debug_logging: bool = false

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var health_component: HealthComponent = $HealthComponent
@onready var body_collision: CollisionShape3D = $CollisionShape3D
@onready var body_hitbox: Hitbox = $BodyHitbox
@onready var head_hitbox: Hitbox = $HeadHitbox
@onready var visual: ZombieVisual = $VisualRoot
@onready var audio_player: AudioStreamPlayer3D = $AudioStreamPlayer3D

var current_state: State = State.IDLE
var current_mode: Mode = Mode.DIRECT_CHASE
var target_player: Node3D = null
var assigned_barricade: Barricade = null
var speed_multiplier: float = 1.0
var health_multiplier: float = 1.0
var last_hit_headshot: bool = false
var last_hit_source: Node = null
var kill_rewarded: bool = false
var stuck_recovery_count: int = 0

var _claimed_slot: Marker3D = null
var _barricade_attack_timer: float = 0.0
var _wait_index: int = 0

var _path_timer: float = 0.0
static var _cached_zombies_frame: int = -1
static var _cached_zombies: Array[Node] = []

var _state_timer: float = 0.0
var _attack_cooldown_timer: float = 0.0
var _stagger_cooldown_timer: float = 0.0
var _stuck_timer: float = 0.0
var _stuck_stage: int = 0
var _last_stuck_check_pos: Vector3 = Vector3.ZERO
var _death_emitted: bool = false
var _despawn_timer: float = 0.0
var _watchdog_timer: float = 0.0
var _watchdog_best_dist: float = INF
var _safe_velocity: Vector3 = Vector3.ZERO
var _has_safe_velocity: bool = false
var _stuck_best_dest_dist: float = INF
var _no_progress_timer: float = 0.0


func _ready() -> void:
	add_to_group("zombies")
	collision_layer = 4
	collision_mask = 1

	if data != null and health_component != null:
		health_component.max_health = data.base_health
		health_component.current_health = data.base_health

	if health_component != null:
		health_component.damaged.connect(_on_damaged)
		health_component.died.connect(_on_died)

	if nav_agent != null:
		nav_agent.avoidance_enabled = true
		nav_agent.max_speed = (data.move_speed * speed_multiplier) if data != null else 3.5
		if not nav_agent.velocity_computed.is_connected(_on_nav_velocity_computed):
			nav_agent.velocity_computed.connect(_on_nav_velocity_computed)

	_last_stuck_check_pos = global_position
	_path_timer = randf_range(0.0, path_update_interval)
	target_player = get_tree().get_first_node_in_group("player") as Node3D


func _on_nav_velocity_computed(safe_velocity: Vector3) -> void:
	_safe_velocity = safe_velocity
	_has_safe_velocity = true


func _exit_tree() -> void:
	_release_barricade_slot()


func _physics_process(delta: float) -> void:
	if current_state == State.DEAD:
		_despawn_timer -= delta
		if _despawn_timer <= 0.0:
			if despawn_to_pool:
				set_physics_process(false)
				visible = false
				pool_returned.emit(self)
			else:
				queue_free()
		if visual != null:
			visual.update_visual(delta, current_state, 0.0)
		return

	if _attack_cooldown_timer > 0.0:
		_attack_cooldown_timer = maxf(_attack_cooldown_timer - delta, 0.0)
	if _stagger_cooldown_timer > 0.0:
		_stagger_cooldown_timer = maxf(_stagger_cooldown_timer - delta, 0.0)

	if not is_on_floor():
		velocity.y -= gravity * delta

	if target_player == null or not is_instance_valid(target_player):
		target_player = get_tree().get_first_node_in_group("player") as Node3D

	match current_state:
		State.IDLE:
			_process_idle(delta)
		State.CHASE:
			_process_chase(delta)
		State.ATTACK_WINDUP:
			_process_attack_windup(delta)
		State.ATTACK:
			_process_attack(delta)
		State.STAGGER:
			_process_stagger(delta)

	move_and_slide()

	if visual != null:
		var horiz_speed: float = Vector2(velocity.x, velocity.z).length()
		visual.update_visual(delta, current_state, horiz_speed)


func _process_idle(delta: float) -> void:
	velocity.x = lerpf(velocity.x, 0.0, 10.0 * delta)
	velocity.z = lerpf(velocity.z, 0.0, 10.0 * delta)
	if _can_detect_player():
		transition_to(State.CHASE)


func _process_chase(delta: float) -> void:
	if target_player == null or data == null or _is_target_dead():
		transition_to(State.IDLE)
		return

	var can_reach_through_window: bool = (
		assigned_barricade == null
		or assigned_barricade.is_open()
		or assigned_barricade.intact_boards <= 2
	)
	var dist_to_player: float = global_position.distance_to(target_player.global_position)
	if can_reach_through_window and dist_to_player <= data.attack_range and _attack_cooldown_timer <= 0.0 and not _is_target_dead():
		transition_to(State.ATTACK_WINDUP)
		return
	_update_watchdog(delta, dist_to_player)

	match current_mode:
		Mode.APPROACH_BARRICADE:
			_process_approach_barricade(delta)
		Mode.BREAK_BARRICADE:
			_process_break_barricade(delta)
		Mode.ENTER_BARRICADE:
			_process_enter_barricade(delta)
		_:
			_navigate_toward(target_player.global_position, delta, true)


func _process_approach_barricade(delta: float) -> void:
	if assigned_barricade == null or not is_instance_valid(assigned_barricade):
		current_mode = Mode.DIRECT_CHASE
		return
	if assigned_barricade.is_open():
		var out_pos: Vector3 = assigned_barricade.get_outside_approach_point()
		var out_dist: float = Vector2(global_position.x - out_pos.x, global_position.z - out_pos.z).length()
		if out_dist <= 2.2:
			current_mode = Mode.ENTER_BARRICADE
			return
		_navigate_toward(out_pos, delta, true)
		return

	if _claimed_slot == null:
		_claimed_slot = assigned_barricade.claim_slot(self)

	var dest: Vector3 = _claimed_slot.global_position if _claimed_slot != null else assigned_barricade.get_waiting_position(_wait_index)
	var flat_dist: float = Vector2(global_position.x - dest.x, global_position.z - dest.z).length()
	if _claimed_slot != null and flat_dist <= 0.85:
		velocity.x = 0.0
		velocity.z = 0.0
		current_mode = Mode.BREAK_BARRICADE
		_barricade_attack_timer = 0.25
		return

	_navigate_toward(dest, delta, true)


func _process_break_barricade(delta: float) -> void:
	velocity.x = lerpf(velocity.x, 0.0, 12.0 * delta)
	velocity.z = lerpf(velocity.z, 0.0, 12.0 * delta)
	if assigned_barricade == null or not is_instance_valid(assigned_barricade):
		current_mode = Mode.DIRECT_CHASE
		return
	if assigned_barricade.is_open():
		current_mode = Mode.ENTER_BARRICADE
		return

	var look_dir: Vector3 = assigned_barricade.global_position - global_position
	look_dir.y = 0.0
	if look_dir.length_squared() > 0.001:
		_face_direction(look_dir.normalized(), delta)

	_barricade_attack_timer -= delta
	if _barricade_attack_timer <= 0.0:
		assigned_barricade.damage_board(self)
		_barricade_attack_timer = assigned_barricade.board_break_interval
		if assigned_barricade.is_open():
			current_mode = Mode.ENTER_BARRICADE


func _process_enter_barricade(delta: float) -> void:
	if assigned_barricade == null or not is_instance_valid(assigned_barricade):
		current_mode = Mode.DIRECT_CHASE
		return
	if not assigned_barricade.is_open():
		current_mode = Mode.APPROACH_BARRICADE
		return

	var inside_pos: Vector3 = assigned_barricade.get_inside_entry_point()
	var to_inside: Vector3 = inside_pos - global_position
	to_inside.y = 0.0
	var flat_dist: float = to_inside.length()
	if flat_dist <= 0.35:
		_release_barricade_slot()
		assigned_barricade = null
		current_mode = Mode.DIRECT_CHASE
		return

	var dir: Vector3 = to_inside / flat_dist
	_face_direction(dir, delta)
	var speed: float = data.move_speed * speed_multiplier
	var enter_vel := Vector3(dir.x * speed, 0.0, dir.z * speed)
	enter_vel = _project_out_of_wall(enter_vel)
	velocity.x = enter_vel.x
	velocity.z = enter_vel.z
	_check_stuck(delta, inside_pos)


func _project_out_of_wall(v: Vector3) -> Vector3:
	if not is_on_wall():
		return v
	var wn: Vector3 = get_wall_normal()
	wn.y = 0.0
	if wn.length_squared() > 0.0001:
		wn = wn.normalized()
		var into_wall: float = v.dot(wn)
		if into_wall < 0.0:
			v -= wn * into_wall
	return v


func _navigate_toward(dest: Vector3, delta: float, use_separation: bool) -> void:
	var far_from_player: bool = target_player != null and global_position.distance_squared_to(target_player.global_position) > 196.0
	_path_timer -= delta
	if _path_timer <= 0.0:
		_path_timer = path_update_interval * (2.0 if far_from_player else 1.0)
		if nav_agent != null:
			nav_agent.target_position = dest

	var move_dir: Vector3 = Vector3.ZERO
	if nav_agent != null:
		var next_pos: Vector3 = nav_agent.get_next_path_position()
		if not nav_agent.is_navigation_finished():
			move_dir = next_pos - global_position
			move_dir.y = 0.0

	if move_dir.length_squared() > 0.001:
		move_dir = move_dir.normalized()
		_face_direction(move_dir, delta)

	var do_sep: bool = use_separation and not far_from_player
	var separation: Vector3 = _compute_separation() if do_sep else Vector3.ZERO
	separation = _project_out_of_wall(separation)
	var sep_weight: float = separation_strength * (0.2 if (nav_agent != null and nav_agent.avoidance_enabled) else 0.5)
	var desired_dir: Vector3 = move_dir + separation * sep_weight
	desired_dir.y = 0.0
	if desired_dir.length_squared() > 0.001:
		desired_dir = desired_dir.normalized()

	var speed: float = data.move_speed * speed_multiplier
	var desired_vel := Vector3(desired_dir.x * speed, 0.0, desired_dir.z * speed)
	var applied_vel: Vector3 = desired_vel
	if nav_agent != null and nav_agent.avoidance_enabled:
		nav_agent.max_speed = speed
		nav_agent.set_velocity(desired_vel)
		if _has_safe_velocity:
			applied_vel = _safe_velocity
			applied_vel.y = 0.0
			if applied_vel.length_squared() > speed * speed:
				applied_vel = applied_vel.normalized() * speed
	applied_vel = _project_out_of_wall(applied_vel)
	velocity.x = applied_vel.x
	velocity.z = applied_vel.z

	_check_stuck(delta, dest)


func _process_attack_windup(delta: float) -> void:
	velocity.x = lerpf(velocity.x, 0.0, 12.0 * delta)
	velocity.z = lerpf(velocity.z, 0.0, 12.0 * delta)
	if target_player != null:
		var dir: Vector3 = target_player.global_position - global_position
		dir.y = 0.0
		if dir.length_squared() > 0.001:
			_face_direction(dir.normalized(), delta)

	_state_timer -= delta
	if _state_timer <= 0.0:
		transition_to(State.ATTACK)


func _process_attack(delta: float) -> void:
	velocity.x = lerpf(velocity.x, 0.0, 12.0 * delta)
	velocity.z = lerpf(velocity.z, 0.0, 12.0 * delta)

	if _state_timer > 0.0:
		_state_timer -= delta
		if _state_timer <= 0.0:
			transition_to(State.CHASE)


func _perform_attack_swing() -> void:
	_attack_cooldown_timer = data.attack_cooldown if data != null else 1.0
	if data == null or target_player == null or _is_target_dead():
		return
	var dist: float = global_position.distance_to(target_player.global_position)
	if dist <= data.attack_range * 1.2:
		if target_player.has_method("take_damage"):
			target_player.call("take_damage", data.attack_damage, self)


func _process_stagger(delta: float) -> void:
	velocity.x = lerpf(velocity.x, 0.0, 10.0 * delta)
	velocity.z = lerpf(velocity.z, 0.0, 10.0 * delta)
	_state_timer -= delta
	if _state_timer <= 0.0:
		transition_to(State.CHASE)


func transition_to(new_state: State) -> void:
	if current_state == State.DEAD and new_state != State.DEAD:
		return
	current_state = new_state
	match new_state:
		State.CHASE:
			_path_timer = 0.0
			if nav_agent != null and is_inside_tree():
				nav_agent.target_position = global_position
			_stuck_timer = 0.0
			_stuck_stage = 0
			_stuck_best_dest_dist = INF
			_no_progress_timer = 0.0
			_has_safe_velocity = false
			_last_stuck_check_pos = global_position if is_inside_tree() else position
		State.ATTACK_WINDUP:
			_state_timer = data.attack_windup if data else 0.4
		State.ATTACK:
			_perform_attack_swing()
			_state_timer = 0.22
		State.STAGGER:
			_state_timer = stagger_duration
		State.DEAD:
			_despawn_timer = death_despawn_delay


func _can_detect_player() -> bool:
	if target_player == null or data == null or _is_target_dead():
		return false
	var dist: float = global_position.distance_to(target_player.global_position)
	if dist > data.detection_range:
		return false
	if dist <= 4.0:
		return true
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state if get_world_3d() else null
	if space_state == null:
		return true
	var from_pos: Vector3 = global_position + Vector3(0.0, 1.5, 0.0)
	var to_pos: Vector3 = target_player.global_position + Vector3(0.0, 1.4, 0.0)
	var query := PhysicsRayQueryParameters3D.create(from_pos, to_pos, 1, [get_rid()])
	var hit: Dictionary = space_state.intersect_ray(query)
	return hit.is_empty()


func _is_target_dead() -> bool:
	if target_player == null:
		return true
	if "is_dead" in target_player:
		return target_player.get("is_dead")
	return false


func _face_direction(dir: Vector3, delta: float) -> void:
	var target_yaw: float = atan2(-dir.x, -dir.z)
	var turn: float = data.turn_speed if data else 8.0
	rotation.y = lerp_angle(rotation.y, target_yaw, clampf(turn * delta, 0.0, 1.0))


func _compute_separation() -> Vector3:
	var frame: int = Engine.get_physics_frames()
	if _cached_zombies_frame != frame:
		_cached_zombies_frame = frame
		_cached_zombies = get_tree().get_nodes_in_group("zombies")
	var push := Vector3.ZERO
	var sep_sq: float = separation_radius * separation_radius
	for other: Node in _cached_zombies:
		if other == self or not is_instance_valid(other) or not (other is ZombieAI):
			continue
		var other_zombie := other as ZombieAI
		if other_zombie.current_state == State.DEAD:
			continue
		var diff: Vector3 = global_position - other_zombie.global_position
		diff.y = 0.0
		var d_sq: float = diff.length_squared()
		if d_sq > 0.00001 and d_sq < sep_sq:
			var d: float = sqrt(d_sq)
			push += (diff / d) * ((separation_radius - d) / separation_radius)
	return push


func _check_stuck(delta: float, dest: Vector3 = Vector3.ZERO) -> void:
	if current_mode == Mode.APPROACH_BARRICADE and _claimed_slot == null and assigned_barricade != null and is_instance_valid(assigned_barricade):
		var wp: Vector3 = assigned_barricade.get_waiting_position(_wait_index)
		if Vector2(global_position.x - wp.x, global_position.z - wp.z).length() <= 1.25:
			_stuck_timer = 0.0
			_no_progress_timer = 0.0
			_stuck_best_dest_dist = INF
			_last_stuck_check_pos = global_position
			return

	var dest_dist: float = Vector2(global_position.x - dest.x, global_position.z - dest.z).length()
	if dest_dist <= 2.4 or _stuck_best_dest_dist == INF or dest_dist < _stuck_best_dest_dist - 0.30:
		_stuck_best_dest_dist = dest_dist
		_no_progress_timer = 0.0
	else:
		_no_progress_timer += delta
		if _no_progress_timer >= 3.2:
			_no_progress_timer = 0.0
			_stuck_best_dest_dist = INF
			_relocate_to_navmesh(dest)
			return

	_stuck_timer += delta
	if _stuck_timer < stuck_timeout:
		return
	_stuck_timer = 0.0

	var moved: float = Vector2(
		global_position.x - _last_stuck_check_pos.x,
		global_position.z - _last_stuck_check_pos.z
	).length()
	_last_stuck_check_pos = global_position

	if moved >= 0.15:
		_stuck_stage = 0
		return

	_stuck_stage += 1
	stuck_recovery_count += 1
	if _stuck_stage == 1:
		if debug_logging:
			print("[ZombieAI] ", name, " stuck stage 1: re-pathing and snapping if off-navmesh")
		_path_timer = 0.0
		if nav_agent != null:
			var nav_map: RID = nav_agent.get_navigation_map()
			var closest: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, global_position)
			if closest != Vector3.ZERO and Vector2(global_position.x - closest.x, global_position.z - closest.z).length() > 0.35:
				global_position = Vector3(closest.x, global_position.y, closest.z)
			if current_mode == Mode.APPROACH_BARRICADE and assigned_barricade != null:
				nav_agent.target_position = assigned_barricade.get_outside_approach_point()
			elif current_mode == Mode.ENTER_BARRICADE and assigned_barricade != null:
				nav_agent.target_position = assigned_barricade.get_inside_entry_point()
			elif target_player != null:
				nav_agent.target_position = target_player.global_position
	else:
		if debug_logging:
			print("[ZombieAI] ", name, " stuck stage 2: relocating to closest navmesh point")
		_relocate_to_navmesh(dest)


func _relocate_to_navmesh(dest: Vector3) -> void:
	if nav_agent != null:
		var nav_map: RID = nav_agent.get_navigation_map()
		var closest: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, global_position)
		var to_dest: Vector3 = dest - closest
		to_dest.y = 0.0
		if to_dest.length_squared() > 0.01:
			var nudged: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, closest + to_dest.normalized() * 0.6)
			if nudged != Vector3.ZERO:
				closest = nudged
		if closest != Vector3.ZERO:
			global_position = Vector3(closest.x, global_position.y, closest.z)
		nav_agent.target_position = dest if dest != Vector3.ZERO else (target_player.global_position if target_player != null else global_position)
	velocity.x = 0.0
	velocity.z = 0.0
	_safe_velocity = Vector3.ZERO
	_has_safe_velocity = false
	_path_timer = 0.0
	_stuck_stage = 0
	_stuck_best_dest_dist = INF


func _on_damaged(_amount: float, is_headshot: bool, source: Node, _remaining: float) -> void:
	last_hit_headshot = is_headshot
	last_hit_source = source
	if current_state == State.DEAD:
		return
	hit_registered.emit(self, is_headshot, source)
	if current_state != State.CHASE and current_state != State.ATTACK_WINDUP:
		if current_state == State.IDLE:
			transition_to(State.CHASE)
	if _stagger_cooldown_timer <= 0.0 and health_component != null and not health_component.is_dead:
		_stagger_cooldown_timer = stagger_cooldown
		transition_to(State.STAGGER)


func apply_round_scaling(health_mult: float, speed_mult: float) -> void:
	health_multiplier = maxf(health_mult, 0.1)
	speed_multiplier = maxf(speed_mult, 0.1)
	if data != null and health_component != null:
		health_component.max_health = data.base_health * health_multiplier
		health_component.current_health = health_component.max_health


func assign_barricade(barricade: Barricade) -> void:
	_release_barricade_slot()
	if barricade != null:
		assigned_barricade = barricade
		current_mode = Mode.APPROACH_BARRICADE
		_wait_index = posmod(get_instance_id(), 6)
	else:
		assigned_barricade = null
		current_mode = Mode.DIRECT_CHASE


func _release_barricade_slot() -> void:
	if _claimed_slot != null and assigned_barricade != null and is_instance_valid(assigned_barricade):
		assigned_barricade.release_slot(self)
	_claimed_slot = null


func reset_watchdog() -> void:
	_watchdog_timer = 0.0
	_watchdog_best_dist = INF


func _update_watchdog(delta: float, dist_to_player: float) -> void:
	if data == null or watchdog_timeout <= 0.0:
		return
	if current_mode == Mode.BREAK_BARRICADE:
		reset_watchdog()
		return
	if current_mode == Mode.APPROACH_BARRICADE and _claimed_slot == null and assigned_barricade != null:
		var wait_pos: Vector3 = assigned_barricade.get_waiting_position(_wait_index)
		if Vector2(global_position.x - wait_pos.x, global_position.z - wait_pos.z).length() <= 1.25:
			reset_watchdog()
			return
	if dist_to_player <= data.attack_range * 1.5:
		reset_watchdog()
		return
	if _watchdog_best_dist == INF or dist_to_player < _watchdog_best_dist - watchdog_min_progress:
		_watchdog_best_dist = dist_to_player
		_watchdog_timer = 0.0
		return
	_watchdog_timer += delta
	if _watchdog_timer >= watchdog_timeout:
		reset_watchdog()
		stall_watchdog_triggered.emit(self)


func reset_for_pool(spawn_pos: Vector3, health_mult: float = 1.0, speed_mult: float = 1.0) -> void:
	_release_barricade_slot()
	assigned_barricade = null
	current_mode = Mode.DIRECT_CHASE
	_barricade_attack_timer = 0.0
	stuck_recovery_count = 0
	global_position = spawn_pos
	rotation = Vector3.ZERO
	velocity = Vector3.ZERO
	current_state = State.IDLE
	_path_timer = 0.0
	_state_timer = 0.0
	_attack_cooldown_timer = 0.0
	_stagger_cooldown_timer = 0.0
	_stuck_timer = 0.0
	_stuck_stage = 0
	_stuck_best_dest_dist = INF
	_no_progress_timer = 0.0
	_safe_velocity = Vector3.ZERO
	_has_safe_velocity = false
	_last_stuck_check_pos = spawn_pos
	reset_watchdog()
	_death_emitted = false
	_despawn_timer = 0.0
	last_hit_headshot = false
	last_hit_source = null
	kill_rewarded = false

	if body_collision:
		body_collision.disabled = false
	if body_hitbox:
		body_hitbox.monitorable = true
	if head_hitbox:
		head_hitbox.monitorable = true
	if health_component:
		health_component.restore_full_health()
	apply_round_scaling(health_mult, speed_mult)
	if visual:
		visual.visible = true
		if visual.has_method("reset_visual"):
			visual.call("reset_visual")
		elif visual.body_pivot:
			visual.body_pivot.position.y = 0.0
			visual.body_pivot.rotation = Vector3.ZERO
	visible = true
	set_physics_process(true)


func _on_died(_source: Node) -> void:
	if _death_emitted:
		return
	_death_emitted = true
	_release_barricade_slot()
	transition_to(State.DEAD)
	velocity = Vector3.ZERO
	if body_collision:
		body_collision.set_deferred("disabled", true)
	if body_hitbox:
		body_hitbox.set_deferred("monitorable", false)
	if head_hitbox:
		head_hitbox.set_deferred("monitorable", false)
	died.emit(self)


func get_state_name() -> String:
	return State.keys()[current_state]
