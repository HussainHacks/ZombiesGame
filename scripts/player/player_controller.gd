class_name PlayerController
extends CharacterBody3D
## First-person character controller for Hood Zombies (Phase 1).
## Handles mouse-look, walk/sprint/crouch/jump, head-bob, sprint FOV,
## pause mouse-capture toggling, and a stub interact raycast.

const InputDeviceManagerScript := preload("res://scripts/core/input_device_manager.gd")

@export_group("Movement")
@export var walk_speed: float = 5.0
@export var sprint_speed: float = 8.0
@export var crouch_speed: float = 2.8
@export var acceleration: float = 14.0
@export var deceleration: float = 16.0
@export var air_acceleration: float = 4.0
@export var jump_velocity: float = 5.5
@export var gravity: float = 14.0

@export_group("Camera & Look")
@export var mouse_sensitivity: float = 0.0022
@export var controller_sensitivity: float = 160.0
@export var controller_deadzone: float = 0.20
@export var controller_invert_y: bool = false
@export var controller_aim_look_multiplier: float = 0.55
@export var controller_look_exponent: float = 1.6
@export var min_pitch_degrees: float = -89.0
@export var max_pitch_degrees: float = 89.0
@export var base_fov: float = 80.0
@export var sprint_fov_boost: float = 8.0
@export var fov_lerp_speed: float = 10.0

@export_group("Crouch")
@export var standing_height: float = 1.8
@export var crouch_height: float = 1.0
@export var standing_eye_height: float = 1.6
@export var crouch_eye_height: float = 0.85
@export var crouch_lerp_speed: float = 12.0

@export_group("Head Bob")
@export var head_bob_frequency: float = 2.2
@export var head_bob_amplitude: float = 0.05

@export_group("Interaction")
@export var interact_distance: float = 3.0

@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var interact_ray: RayCast3D = $Head/Camera3D/InteractRayCast
@onready var flashlight: SpotLight3D = get_node_or_null("Head/Camera3D/Flashlight") as SpotLight3D
@onready var ceiling_check: ShapeCast3D = $CeilingCheck
@onready var weapon_manager: WeaponManager = get_node_or_null("WeaponManager") as WeaponManager
@onready var player_health: PlayerHealth = get_node_or_null("PlayerHealth") as PlayerHealth
@onready var player_stats: PlayerStats = get_node_or_null("PlayerStats") as PlayerStats
@onready var perk_manager: PerkManager = get_node_or_null("PerkManager") as PerkManager
@onready var viewmodel_camera: Camera3D = get_node_or_null("ViewmodelLayer/SubViewportContainer/ViewmodelViewport/ViewmodelCamera") as Camera3D

var is_crouching: bool = false
var is_paused: bool = false
var is_dead: bool = false
var _pitch_degrees: float = 0.0
var _bob_time: float = 0.0
var _look_delta: Vector2 = Vector2.ZERO
var _hold_progress: float = 0.0
var _hold_target: Barricade = null
var _controller_sprint: bool = false
var _last_move_dir: Vector2 = Vector2.ZERO


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_apply_config_defaults()
	floor_snap_length = 0.25
	floor_max_angle = deg_to_rad(46.0)
	floor_stop_on_slope = true
	floor_constant_speed = true

	if camera:
		camera.fov = base_fov
	if interact_ray:
		interact_ray.target_position = Vector3(0.0, 0.0, -interact_distance)
	if weapon_manager:
		weapon_manager.setup_player(self, camera, viewmodel_camera)

	if DisplayServer.get_name() != "headless":
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _apply_config_defaults() -> void:
	var settings_mgr: Node = get_node_or_null("/root/SettingsManager")
	if settings_mgr != null:
		mouse_sensitivity = float(settings_mgr.get("mouse_sensitivity"))
		base_fov = float(settings_mgr.get("fov"))
		controller_sensitivity = float(settings_mgr.get("controller_sensitivity"))
		controller_deadzone = float(settings_mgr.get("controller_deadzone"))
		controller_invert_y = bool(settings_mgr.get("controller_invert_y"))


func apply_settings(new_sensitivity: float, new_fov: float) -> void:
	mouse_sensitivity = new_sensitivity
	base_fov = new_fov
	_apply_config_defaults()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		toggle_pause()
		return

	if is_paused or is_dead:
		return

	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		var mouse_event := event as InputEventMouseMotion
		_look_delta += mouse_event.relative
		rotate_y(-mouse_event.relative.x * mouse_sensitivity)
		_pitch_degrees = clamp_pitch_degrees(
			_pitch_degrees - rad_to_deg(mouse_event.relative.y * mouse_sensitivity),
			min_pitch_degrees,
			max_pitch_degrees
		)
		if head:
			head.rotation.x = deg_to_rad(_pitch_degrees)

	if event.is_action_pressed("interact"):
		_try_interact()
	elif event.is_action_pressed("toggle_flashlight"):
		toggle_flashlight()


func toggle_flashlight() -> void:
	if flashlight != null:
		flashlight.visible = not flashlight.visible


func is_flashlight_on() -> bool:
	return flashlight != null and flashlight.visible


func _physics_process(delta: float) -> void:
	if is_dead:
		if head:
			head.position.y = lerpf(head.position.y, 0.35, 6.0 * delta)
			head.rotation.z = lerpf(head.rotation.z, deg_to_rad(32.0), 6.0 * delta)
		if viewmodel_camera and camera:
			viewmodel_camera.global_transform = camera.global_transform
		return

	if is_paused:
		return

	_handle_controller_look(delta)
	_handle_crouch(delta)
	_handle_movement(delta)
	move_and_slide()
	_update_camera_effects(delta)
	_handle_hold_interact(delta)


func _get_active_joy_id() -> int:
	var idm: Node = get_node_or_null("/root/InputDeviceManager") if is_inside_tree() else null
	if idm != null and int(idm.get("active_joypad_id")) >= 0:
		return int(idm.get("active_joypad_id"))
	return 0


func _get_axis(dev: int, axis: JoyAxis) -> float:
	var idm: Node = get_node_or_null("/root/InputDeviceManager") if is_inside_tree() else null
	if idm != null:
		return float(idm.call("get_axis_value", dev, axis))
	return Input.get_joy_axis(dev, axis)


func _handle_controller_look(delta: float) -> void:
	var dev: int = _get_active_joy_id()
	var raw_look := Vector2(
		_get_axis(dev, JOY_AXIS_RIGHT_X),
		_get_axis(dev, JOY_AXIS_RIGHT_Y)
	)
	var dz: Vector2 = InputDeviceManagerScript.apply_radial_deadzone(raw_look, controller_deadzone)
	if dz.length_squared() <= 0.000001:
		return
	var curved: Vector2 = InputDeviceManagerScript.apply_look_curve(dz, controller_look_exponent)
	var aim_mult: float = controller_aim_look_multiplier if (weapon_manager != null and weapon_manager.active_weapon != null and weapon_manager.active_weapon.is_aiming) else 1.0
	var yaw_deg: float = -curved.x * controller_sensitivity * aim_mult * delta
	var pitch_sign: float = 1.0 if controller_invert_y else -1.0
	var pitch_deg: float = curved.y * (controller_sensitivity * 0.78) * aim_mult * pitch_sign * delta
	rotate_y(deg_to_rad(yaw_deg))
	_pitch_degrees = clamp_pitch_degrees(_pitch_degrees + pitch_deg, min_pitch_degrees, max_pitch_degrees)
	if head:
		head.rotation.x = deg_to_rad(_pitch_degrees)
	_look_delta += Vector2(yaw_deg * -4.0, pitch_deg * -4.0)


func _handle_crouch(delta: float) -> void:
	var wants_crouch: bool = Input.is_action_pressed("crouch")
	var ceiling_blocked: bool = _is_ceiling_blocked()
	is_crouching = resolve_crouch_state(is_crouching, wants_crouch, ceiling_blocked)

	var target_height: float = crouch_height if is_crouching else standing_height
	var target_eye: float = crouch_eye_height if is_crouching else standing_eye_height

	if collision_shape and collision_shape.shape is CapsuleShape3D:
		var capsule := collision_shape.shape as CapsuleShape3D
		capsule.height = lerpf(capsule.height, target_height, crouch_lerp_speed * delta)
		collision_shape.position.y = capsule.height * 0.5

	if head:
		head.position.y = lerpf(head.position.y, target_eye, crouch_lerp_speed * delta)


func _handle_movement(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif Input.is_action_just_pressed("jump") and not is_crouching:
		velocity.y = jump_velocity

	var kb_dir := Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_back") - Input.get_action_strength("move_forward")
	)
	# Use keyboard vector if any key is held; otherwise poll left stick with radial deadzone.
	var dev: int = _get_active_joy_id()
	var joy_raw := Vector2(
		_get_axis(dev, JOY_AXIS_LEFT_X),
		_get_axis(dev, JOY_AXIS_LEFT_Y)
	)
	var joy_dir: Vector2 = InputDeviceManagerScript.apply_radial_deadzone(joy_raw, controller_deadzone)
	var input_dir: Vector2 = kb_dir.limit_length(1.0) if kb_dir.length_squared() > 0.01 else joy_dir
	_last_move_dir = input_dir

	if Input.is_action_just_pressed("sprint") and input_dir.length() > 0.1 and not is_crouching:
		_controller_sprint = true
	if input_dir.length() <= 0.1 or is_crouching:
		_controller_sprint = false
	elif weapon_manager != null and weapon_manager.active_weapon != null and weapon_manager.active_weapon.is_aiming:
		_controller_sprint = false

	var direction: Vector3 = (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	var target_speed: float = _get_target_speed()
	var target_velocity: Vector3 = direction * target_speed

	var accel: float
	if not is_on_floor():
		accel = air_acceleration
	elif direction.length_squared() > 0.0:
		accel = acceleration
	else:
		accel = deceleration

	velocity.x = lerpf(velocity.x, target_velocity.x, clampf(accel * delta, 0.0, 1.0))
	velocity.z = lerpf(velocity.z, target_velocity.z, clampf(accel * delta, 0.0, 1.0))


func _get_target_speed() -> float:
	var speed: float = walk_speed
	if is_crouching:
		speed = crouch_speed
	elif is_sprinting_active():
		speed = sprint_speed
	if weapon_manager:
		speed *= weapon_manager.get_move_speed_multiplier()
	if player_stats:
		speed *= player_stats.get_stat(&"move_speed")
	return speed


func is_sprinting_active() -> bool:
	if is_crouching:
		return false
	var kb_sprint: bool = Input.is_action_pressed("sprint") and Input.is_action_pressed("move_forward")
	return kb_sprint or (_controller_sprint and _last_move_dir.length() > 0.1)


func cancel_controller_sprint() -> void:
	_controller_sprint = false


func apply_recoil(pitch_deg: float, yaw_deg: float) -> void:
	rotate_y(deg_to_rad(yaw_deg))
	_pitch_degrees = clamp_pitch_degrees(_pitch_degrees + pitch_deg, min_pitch_degrees, max_pitch_degrees)
	if head:
		head.rotation.x = deg_to_rad(_pitch_degrees)


func consume_look_delta() -> Vector2:
	var delta_val: Vector2 = _look_delta
	_look_delta = Vector2.ZERO
	return delta_val


func _update_camera_effects(delta: float) -> void:
	if camera == null:
		return

	var horizontal_speed: float = Vector2(velocity.x, velocity.z).length()
	var is_sprinting: bool = (
		not is_crouching
		and Input.is_action_pressed("sprint")
		and Input.is_action_pressed("move_forward")
		and horizontal_speed > walk_speed * 0.8
	)

	var target_fov: float = base_fov + (sprint_fov_boost if is_sprinting else 0.0)
	if weapon_manager:
		target_fov *= weapon_manager.get_fov_multiplier()
	camera.fov = lerpf(camera.fov, target_fov, clampf(fov_lerp_speed * delta, 0.0, 1.0))

	if viewmodel_camera:
		viewmodel_camera.global_transform = camera.global_transform

	if is_on_floor() and horizontal_speed > 0.2:
		_bob_time += delta * horizontal_speed
		var bob_offset := Vector3(
			cos(_bob_time * head_bob_frequency * 0.5) * head_bob_amplitude * 0.5,
			sin(_bob_time * head_bob_frequency) * head_bob_amplitude,
			0.0
		)
		camera.position = camera.position.lerp(bob_offset, clampf(10.0 * delta, 0.0, 1.0))
	else:
		_bob_time = 0.0
		camera.position = camera.position.lerp(Vector3.ZERO, clampf(10.0 * delta, 0.0, 1.0))


func _is_ceiling_blocked() -> bool:
	if ceiling_check == null:
		return false
	ceiling_check.force_shapecast_update()
	return ceiling_check.is_colliding()


func _try_interact() -> void:
	if interact_ray == null:
		return
	interact_ray.force_raycast_update()
	if not interact_ray.is_colliding():
		return
	var collider: Object = interact_ray.get_collider()
	if collider is Node:
		var node := collider as Node
		if node.has_method("interact"):
			node.call("interact", self)
		if node.is_in_group("interactable"):
			print("Interactable targeted: ", node.name)


func _handle_hold_interact(delta: float) -> void:
	if not Input.is_action_pressed("interact") or interact_ray == null:
		_hold_progress = 0.0
		_hold_target = null
		return

	interact_ray.force_raycast_update()
	if not interact_ray.is_colliding():
		_hold_progress = 0.0
		_hold_target = null
		return

	var collider: Object = interact_ray.get_collider()
	if not (collider is BarricadeInteract):
		_hold_progress = 0.0
		_hold_target = null
		return

	var barricade: Barricade = (collider as BarricadeInteract).get_barricade()
	if barricade == null or not barricade.can_repair(self):
		_hold_progress = 0.0
		_hold_target = null
		return

	if _hold_target != barricade:
		_hold_target = barricade
		_hold_progress = 0.0

	_hold_progress += delta
	if _hold_progress >= barricade.repair_duration:
		var pm: PointsManager = get_tree().get_first_node_in_group("points_manager") as PointsManager
		barricade.repair_one_board(pm)
		_hold_progress = 0.0


func _format_interact_prompt(raw: String) -> String:
	var idm: Node = get_node_or_null("/root/InputDeviceManager")
	if idm != null:
		return str(idm.call("format_prompt", raw))
	return raw


func get_interact_ui_state() -> Dictionary:
	var empty_state := {
		"visible": false,
		"text": "",
		"affordable": true,
		"is_hold": false,
		"progress": 0.0,
	}
	if is_dead or is_paused or interact_ray == null or not interact_ray.is_colliding():
		return empty_state

	var collider: Object = interact_ray.get_collider()
	if collider is Purchasable:
		var item := collider as Purchasable
		var pm: PointsManager = get_tree().get_first_node_in_group("points_manager") as PointsManager
		var prompt_str: String = _format_interact_prompt(item.get_prompt_text(self))
		if prompt_str.is_empty():
			return empty_state
		var affordable: bool = pm != null and pm.balance >= item.get_effective_cost(self)
		if item is UpgradeStation and (item as UpgradeStation).station_state == UpgradeStation.StationState.READY:
			affordable = true
		return {
			"visible": true,
			"text": prompt_str,
			"affordable": affordable,
			"is_hold": false,
			"progress": 0.0,
		}
	elif collider is BarricadeInteract:
		var barricade: Barricade = (collider as BarricadeInteract).get_barricade()
		if barricade == null:
			return empty_state
		var can_rep: bool = barricade.can_repair(self)
		var prog: float = (_hold_progress / maxf(barricade.repair_duration, 0.01)) if _hold_target == barricade else 0.0
		return {
			"visible": true,
			"text": _format_interact_prompt(barricade.get_prompt_text(self)),
			"affordable": can_rep,
			"is_hold": can_rep,
			"progress": clampf(prog, 0.0, 1.0),
		}
	return empty_state


func toggle_pause() -> void:
	if is_dead:
		return
	is_paused = not is_paused
	var idm: Node = get_node_or_null("/root/InputDeviceManager")
	if is_paused and idm != null:
		idm.call("stop_all_vibration")
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null:
		gs.call("set_paused", is_paused)
	if DisplayServer.get_name() != "headless":
		if is_paused:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		elif idm != null and int(idm.get("current_device")) != 0:
			Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func reset_for_new_run(spawn_transform: Transform3D) -> void:
	global_transform = spawn_transform
	velocity = Vector3.ZERO
	is_dead = false
	is_paused = false
	is_crouching = false
	_pitch_degrees = 0.0
	if head:
		head.position.y = standing_eye_height
		head.rotation = Vector3.ZERO
	if perk_manager:
		perk_manager.clear_perks()
	if player_stats:
		player_stats.clear_all()
	if player_health and player_health.health_component:
		player_health.health_component.restore_full_health()
		player_health.health_changed.emit(
			player_health.health_component.current_health,
			player_health.health_component.max_health
		)
	if weapon_manager:
		weapon_manager.reset_to_starter_weapons()
	if DisplayServer.get_name() != "headless":
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func set_dead(dead: bool) -> void:
	is_dead = dead
	if is_dead:
		velocity = Vector3.ZERO
		_controller_sprint = false
		var idm: Node = get_node_or_null("/root/InputDeviceManager")
		if idm != null:
			idm.call("play_vibration", 0.40, 0.90, 0.45, true)
		if weapon_manager:
			weapon_manager.set_process(false)
			weapon_manager.set_process_unhandled_input(false)
			if weapon_manager.active_viewmodel:
				weapon_manager.active_viewmodel.visible = false
		if DisplayServer.get_name() != "headless":
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func take_damage(amount: float, source: Node = null) -> float:
	if player_health != null:
		var dealt: float = player_health.take_damage(amount, source)
		if dealt > 0.0 and not is_dead:
			var idm: Node = get_node_or_null("/root/InputDeviceManager")
			if idm != null:
				idm.call("play_vibration", 0.25, 0.75, 0.18, false)
		return dealt
	return 0.0


static func clamp_pitch_degrees(pitch_deg: float, min_deg: float = -89.0, max_deg: float = 89.0) -> float:
	return clampf(pitch_deg, min_deg, max_deg)


static func resolve_crouch_state(currently_crouching: bool, wants_crouch: bool, ceiling_blocked: bool) -> bool:
	if wants_crouch:
		return true
	if currently_crouching and ceiling_blocked:
		return true
	return false
