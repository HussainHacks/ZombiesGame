class_name RoundManager
extends Node
## Manages round progression, zombie spawning with strict out-of-sight
## validation, per-round scaling, and zombie instance pooling.

enum Phase {
	IDLE,
	COUNTDOWN,
	ACTIVE,
	INTERMISSION,
}

const DebugGateScript := preload("res://scripts/core/debug_gate.gd")

signal round_countdown_started(round_num: int, duration: float)
signal round_started(round_num: int, total_zombies: int)
signal round_ended(round_num: int)
signal zombie_spawned(zombie: ZombieAI)
signal zombie_killed(zombie: ZombieAI, is_headshot: bool)
signal zombie_hit(zombie: ZombieAI, is_headshot: bool, source: Node)
signal zombies_remaining_changed(remaining: int)

@export var round_config: RoundConfig
@export var zombie_scene: PackedScene
@export var max_navmesh_distance: float = 1.0
@export var min_spawn_distance: float = 10.0

var phase: Phase = Phase.IDLE
var current_round: int = 0
var zombies_to_spawn: int = 0
var killed_this_round: int = 0
var alive_zombies: Array[ZombieAI] = []

var _pool: Array[ZombieAI] = []
var _phase_timer: float = 0.0
var _spawn_timer: float = 0.0
var _last_marker_index: int = -1
var _zombie_container: Node3D = null
var spawn_stall_seconds: float = 0.0
var _stall_warned: bool = false


func _ready() -> void:
	_zombie_container = Node3D.new()
	_zombie_container.name = "ActiveZombies"
	get_parent().call_deferred("add_child", _zombie_container)


func _unhandled_input(event: InputEvent) -> void:
	if not DebugGateScript.is_debug_enabled():
		return
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_F12:
			if phase != Phase.IDLE:
				jump_to_round(maxi(current_round + 1, 1))


func start_new_run() -> void:
	stop_and_cleanup()
	if round_config == null:
		return
	current_round = maxi(round_config.start_round, 1)
	phase = Phase.COUNTDOWN
	_phase_timer = round_config.initial_countdown
	round_countdown_started.emit(current_round, _phase_timer)


func stop_and_cleanup() -> void:
	ImpactEffect.clear_all()
	phase = Phase.IDLE
	_phase_timer = 0.0
	_spawn_timer = 0.0
	zombies_to_spawn = 0
	killed_this_round = 0

	for z: ZombieAI in alive_zombies:
		if is_instance_valid(z):
			z.queue_free()
	alive_zombies.clear()

	for z: ZombieAI in _pool:
		if is_instance_valid(z):
			z.queue_free()
	_pool.clear()
	zombies_remaining_changed.emit(0)


func jump_to_round(target_round: int) -> void:
	for z: ZombieAI in alive_zombies:
		if is_instance_valid(z):
			_recycle_zombie(z)
	alive_zombies.clear()
	_begin_round(maxi(target_round, 1))


func _process(delta: float) -> void:
	if round_config == null or phase == Phase.IDLE:
		return
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null and not gs.call("is_playing"):
		return

	match phase:
		Phase.COUNTDOWN:
			_phase_timer -= delta
			if _phase_timer <= 0.0:
				_begin_round(current_round)
		Phase.ACTIVE:
			_process_active(delta)
		Phase.INTERMISSION:
			_phase_timer -= delta
			if _phase_timer <= 0.0:
				_begin_round(current_round + 1)


func _begin_round(round_num: int) -> void:
	current_round = round_num
	phase = Phase.ACTIVE
	zombies_to_spawn = round_config.get_zombie_count(current_round)
	killed_this_round = 0
	_spawn_timer = 0.0

	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null:
		gs.call("set_round_reached", current_round)

	for node: Node in get_tree().get_nodes_in_group("barricade"):
		if node is Barricade:
			(node as Barricade).reset_round_repair_cap()

	round_started.emit(current_round, zombies_to_spawn)
	zombies_remaining_changed.emit(get_total_remaining())
	if is_inside_tree():
		var ge: Node = get_node_or_null("/root/GameEvents")
		if ge != null:
			ge.emit_signal("round_started", current_round, zombies_to_spawn)


func _process_active(delta: float) -> void:
	if zombies_to_spawn > 0 and alive_zombies.size() < round_config.max_concurrent_zombies:
		_spawn_timer -= delta
		if _spawn_timer <= 0.0:
			if _try_spawn_one():
				_spawn_timer = round_config.get_spawn_interval(current_round)
				spawn_stall_seconds = 0.0
				_stall_warned = false
			else:
				# No valid hidden marker right now; wait briefly and retry
				_spawn_timer = 0.25
				spawn_stall_seconds += 0.25
				if spawn_stall_seconds > 10.0 and not _stall_warned:
					_stall_warned = true
					push_warning("[RoundManager] Spawn stall > 10s: no valid hidden spawn marker available.")
	else:
		spawn_stall_seconds = 0.0
		_stall_warned = false

	if zombies_to_spawn == 0 and alive_zombies.is_empty():
		round_ended.emit(current_round)
		if is_inside_tree():
			var ge: Node = get_node_or_null("/root/GameEvents")
			if ge != null:
				ge.emit_signal("round_ended", current_round)
		phase = Phase.INTERMISSION
		_phase_timer = round_config.intermission_duration


func _try_spawn_one() -> bool:
	if zombie_scene == null or _zombie_container == null or not _zombie_container.is_inside_tree():
		return false

	var chosen: Dictionary = _find_valid_spawn_entry()
	if chosen.is_empty():
		return false
	var chosen_marker := chosen["marker"] as Marker3D
	var chosen_barricade: Barricade = chosen.get("barricade") as Barricade
	_spawn_at(chosen_marker.global_position, chosen_barricade)
	return true


func _find_valid_spawn_entry() -> Dictionary:
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	var player_pos: Vector3 = player.global_position if player != null else Vector3.ZERO
	var zm: ZoneManager = get_tree().get_first_node_in_group("zone_manager") as ZoneManager

	var candidates: Array[Dictionary] = []
	if zm != null:
		candidates = zm.get_eligible_spawn_entries(player_pos)
	else:
		for node: Node in get_tree().get_nodes_in_group("zombie_spawn"):
			if node is Marker3D:
				candidates.append({"marker": node, "barricade": null, "weight": 1.0})

	if candidates.is_empty():
		return {}

	var valid_entries: Array[Dictionary] = []
	var total_weight: float = 0.0
	for entry: Dictionary in candidates:
		var marker := entry["marker"] as Marker3D
		if marker == null:
			continue
		if is_valid_spawn_position(marker.global_position, player):
			valid_entries.append(entry)
			total_weight += float(entry.get("weight", 1.0))

	if valid_entries.is_empty():
		return {}

	return _pick_weighted_entry(valid_entries, total_weight)


func _pick_weighted_entry(valid_entries: Array[Dictionary], total_weight: float) -> Dictionary:
	if valid_entries.size() == 1:
		_last_marker_index = valid_entries[0]["marker"].get_instance_id()
		return valid_entries[0]

	var filtered: Array[Dictionary] = []
	var filtered_weight: float = 0.0
	for entry: Dictionary in valid_entries:
		if entry["marker"].get_instance_id() != _last_marker_index:
			filtered.append(entry)
			filtered_weight += float(entry.get("weight", 1.0))

	var pool_to_pick: Array[Dictionary] = filtered if not filtered.is_empty() else valid_entries
	var w_sum: float = filtered_weight if not filtered.is_empty() else total_weight

	var roll: float = randf() * maxf(w_sum, 0.001)
	var acc: float = 0.0
	for entry: Dictionary in pool_to_pick:
		acc += float(entry.get("weight", 1.0))
		if roll <= acc:
			_last_marker_index = entry["marker"].get_instance_id()
			return entry
	var last: Dictionary = pool_to_pick.back()
	_last_marker_index = last["marker"].get_instance_id()
	return last


func _spawn_at(world_pos: Vector3, barricade: Barricade = null) -> ZombieAI:
	var health_mult: float = round_config.get_health_multiplier(current_round)
	var speed_mult: float = round_config.get_speed_multiplier(current_round)
	var zombie: ZombieAI = _acquire_zombie()
	if zombie == null:
		return null

	zombie.despawn_to_pool = true
	if zombie.get_parent() == null:
		_zombie_container.add_child(zombie)
	zombie.reset_for_pool(world_pos, health_mult, speed_mult)
	zombie.assign_barricade(barricade)
	zombie.transition_to(ZombieAI.State.CHASE)

	alive_zombies.append(zombie)
	zombies_to_spawn -= 1
	zombie_spawned.emit(zombie)
	zombies_remaining_changed.emit(get_total_remaining())
	if is_inside_tree():
		var ge: Node = get_node_or_null("/root/GameEvents")
		if ge != null:
			ge.emit_signal("zombie_spotted", zombie)
	return zombie


func _acquire_zombie() -> ZombieAI:
	while not _pool.is_empty():
		var pooled: ZombieAI = _pool.pop_back()
		if is_instance_valid(pooled):
			return pooled

	var instance := zombie_scene.instantiate() as ZombieAI
	if instance == null:
		return null
	instance.died.connect(_on_zombie_died)
	instance.hit_registered.connect(_on_zombie_hit)
	instance.pool_returned.connect(_on_zombie_pool_returned)
	instance.stall_watchdog_triggered.connect(_on_zombie_stall_watchdog)
	return instance


func _on_zombie_stall_watchdog(zombie: ZombieAI) -> void:
	if not is_instance_valid(zombie) or zombie.current_state == ZombieAI.State.DEAD:
		return
	var entry: Dictionary = _find_valid_spawn_entry()
	if entry.is_empty():
		return
	var marker := entry["marker"] as Marker3D
	var barricade: Barricade = entry.get("barricade") as Barricade
	if marker == null:
		return
	zombie.global_position = marker.global_position
	zombie.velocity = Vector3.ZERO
	zombie.assign_barricade(barricade)
	zombie.reset_watchdog()


func _on_zombie_hit(zombie: ZombieAI, is_headshot: bool, source: Node) -> void:
	zombie_hit.emit(zombie, is_headshot, source)


func _on_zombie_died(zombie: ZombieAI) -> void:
	var idx: int = alive_zombies.find(zombie)
	if idx == -1:
		return
	alive_zombies.remove_at(idx)
	killed_this_round += 1

	var is_headshot: bool = zombie.last_hit_headshot
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null:
		gs.call("record_kill", is_headshot)

	zombie_killed.emit(zombie, is_headshot)
	zombies_remaining_changed.emit(get_total_remaining())
	if is_inside_tree():
		var ge: Node = get_node_or_null("/root/GameEvents")
		if ge != null:
			ge.emit_signal("zombie_killed", zombie, is_headshot)


func _on_zombie_pool_returned(zombie: ZombieAI) -> void:
	_recycle_zombie(zombie)


func _recycle_zombie(zombie: ZombieAI) -> void:
	if not is_instance_valid(zombie):
		return
	zombie.set_physics_process(false)
	zombie.visible = false
	if not _pool.has(zombie):
		_pool.append(zombie)


func get_total_remaining() -> int:
	return zombies_to_spawn + alive_zombies.size()


func is_valid_spawn_position(pos: Vector3, player: Node3D = null) -> bool:
	var world_3d: World3D = get_viewport().world_3d if get_viewport() else null
	if world_3d == null:
		return false

	# 1. Navmesh check
	var nav_map: RID = world_3d.navigation_map
	if not nav_map.is_valid():
		return false
	var closest: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, pos)
	if pos.distance_to(closest) > max_navmesh_distance:
		return false

	# 2. Geometry overlap check
	var space_state: PhysicsDirectSpaceState3D = world_3d.direct_space_state
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.6
	var shape_query := PhysicsShapeQueryParameters3D.new()
	shape_query.shape = capsule
	shape_query.transform = Transform3D(Basis.IDENTITY, pos + Vector3(0.0, 0.95, 0.0))
	shape_query.collision_mask = 1
	if not space_state.intersect_shape(shape_query, 1).is_empty():
		return false

	# 3. Distance & player line-of-sight check (never spawn in view or close range)
	if player != null:
		if pos.distance_to(player.global_position) < min_spawn_distance:
			return false
		var from_pos: Vector3 = player.global_position + Vector3(0.0, 1.5, 0.0)
		var to_pos: Vector3 = pos + Vector3(0.0, 1.5, 0.0)
		var los_query := PhysicsRayQueryParameters3D.create(from_pos, to_pos, 1, [player.get_rid()])
		var hit: Dictionary = space_state.intersect_ray(los_query)
		if hit.is_empty():
			return false

	return true
