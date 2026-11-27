class_name PlayerController
extends CharacterBody3D
## First-person character controller for Hood Zombies (Phase 1).
## Handles mouse-look, walk/sprint/crouch/jump, head-bob, sprint FOV,
## pause mouse-capture toggling, and a stub interact raycast.

const InputDeviceManagerScript := preload("res://scripts/core/input_device_manager.gd")
const MovementConfig := preload("res://scripts/core/movement_config.gd")
const DEFAULT_MOVEMENT_CONFIG := preload("res://resources/configuration/movement_config.tres")

@export_group("Movement")
@export var movement_config: MovementConfig = DEFAULT_MOVEMENT_CONFIG
@export var walk_speed: float = 4.75
@export var sprint_speed: float = 7.3625
@export var crouch_speed: float = 2.85
@export var acceleration: float = 16.5
@export var sprint_acceleration: float = 13.5
@export var deceleration: float = 16.5
@export var air_acceleration: float = 2.2
@export var jump_velocity: float = 6.3
@export var gravity: float = 19.0
@export var ads_speed_multiplier: float = 0.58
@export var scoped_ads_speed_multiplier: float = 0.40

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
@export var standing_height: float = 1.75
@export var crouch_height: float = 1.2
@export var standing_eye_height: float = 1.62
@export var crouch_eye_height: float = 1.1
@export var slide_eye_height: float = 0.85
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
var is_sliding: bool = false
var is_paused: bool = false
var is_dead: bool = false
var movement_profile: String = "riposte"
var camera_bob_intensity: float = 1.0
var weapon_bob_intensity: float = 1.0
var camera_shake_intensity: float = 1.0
var landing_dip_intensity: float = 1.0

var _pitch_degrees: float = 0.0
var _bob_time: float = 0.0
var _bob_amp: float = 0.0
var _look_delta: Vector2 = Vector2.ZERO
var _hold_progress: float = 0.0
var _hold_target: Barricade = null
var _controller_sprint: bool = false
var _last_move_dir: Vector2 = Vector2.ZERO
var _slide_timer: float = 0.0
var _slide_cooldown: float = 0.0
var _slide_buffer: float = 0.0
var _slide_speed: float = 0.0
var _slide_dir: Vector3 = Vector3.ZERO
var _slide_amount: float = 0.0
var _slide_enabled: bool = true
var _use_exp_damping: bool = true
var _was_on_floor: bool = true
var _prev_vertical_vel: float = 0.0
var _was_sprinting: bool = false
var _fov_kick: float = 0.0
var _camera_shake: float = 0.0
var _land_dip_offset: float = 0.0
var _land_dip_vel: float = 0.0
var _land_roll_deg: float = 0.0
var _ads_sway_time: float = 0.0
var _sprint_weight: float = 0.0


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
		movement_profile = str(settings_mgr.get("movement_profile"))
		camera_bob_intensity = float(settings_mgr.get("camera_bob_intensity"))
		weapon_bob_intensity = float(settings_mgr.get("weapon_bob_intensity"))
		camera_shake_intensity = float(settings_mgr.get("camera_shake_intensity"))
		landing_dip_intensity = float(settings_mgr.get("landing_dip_intensity"))
	apply_movement_profile(movement_profile)


func apply_movement_profile(profile_name: String) -> void:
	movement_profile = "classic" if profile_name.to_lower() == "classic" else "riposte"
	var cfg: MovementConfig = movement_config if movement_config != null else DEFAULT_MOVEMENT_CONFIG
	if cfg == null:
		return
	var p: Dictionary = cfg.get_profile(movement_profile)
	walk_speed = float(p["walk_speed"])
	sprint_speed = walk_speed * float(p["sprint_multiplier"])
	crouch_speed = walk_speed * float(p["crouch_multiplier"])
	ads_speed_multiplier = float(p["ads_speed_multiplier"])
	scoped_ads_speed_multiplier = float(p["scoped_ads_speed_multiplier"])
	acceleration = float(p["ground_accel"])
	sprint_acceleration = float(p["sprint_accel"])
	deceleration = float(p["ground_decel"])
	air_acceleration = float(p["air_accel"])
	gravity = float(p["gravity"])
	jump_velocity = float(p["jump_velocity"])
	standing_height = float(p["standing_height"])
	crouch_height = float(p["crouch_height"])
	standing_eye_height = float(p["standing_eye_height"])
	crouch_eye_height = float(p["crouch_eye_height"])
	slide_eye_height = float(p["slide_eye_height"])
	_slide_enabled = bool(p["slide_enabled"])
	_use_exp_damping = bool(p["use_exp_damping"])
	if not _slide_enabled:
		is_sliding = false
		_slide_timer = 0.0
		_slide_amount = 0.0


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
	var pre_slide_pos := global_position
	move_and_slide()
	if is_sliding and _slide_timer > 0.0 and delta > 0.0001:
		var moved_horiz: float = Vector2(global_position.x - pre_slide_pos.x, global_position.z - pre_slide_pos.z).length()
		if moved_horiz < _slide_speed * delta * 0.30:
			var cfg: MovementConfig = movement_config if movement_config != null else DEFAULT_MOVEMENT_CONFIG
			_slide_timer = 0.0
			is_sliding = false
			_slide_cooldown = cfg.slide_wall_cooldown if cfg != null else 0.12
	_handle_landing_detection(delta)
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
	var wants_crouch: bool = Input.is_action_pressed("crouch") or is_sliding
	var ceiling_blocked: bool = _is_ceiling_blocked()
	is_crouching = resolve_crouch_state(is_crouching, wants_crouch, ceiling_blocked)

	var target_height: float = crouch_height if is_crouching else standing_height
	var target_eye: float = slide_eye_height if is_sliding else (crouch_eye_height if is_crouching else standing_eye_height)
	var eye_rate: float = 22.0 if is_sliding else crouch_lerp_speed

	if collision_shape and collision_shape.shape is CapsuleShape3D:
		var capsule := collision_shape.shape as CapsuleShape3D
		capsule.height = lerpf(capsule.height, target_height, clampf(crouch_lerp_speed * delta, 0.0, 1.0))
		collision_shape.position.y = capsule.height * 0.5

	if head:
		head.position.y = lerpf(head.position.y, target_eye, clampf(eye_rate * delta, 0.0, 1.0))


func _handle_movement(delta: float) -> void:
	var cfg: MovementConfig = movement_config if movement_config != null else DEFAULT_MOVEMENT_CONFIG
	_slide_cooldown = maxf(_slide_cooldown - delta, 0.0)
	if _slide_enabled and Input.is_action_just_pressed("crouch") and (is_sprinting_active() or not is_on_floor()):
		_slide_buffer = cfg.slide_buffer_time if cfg != null else 0.3

	if _slide_buffer > 0.0:
		if not is_sliding and _slide_cooldown <= 0.0 and is_on_floor():
			_slide_buffer = maxf(_slide_buffer - delta, 0.0)
		var horiz_v := Vector2(velocity.x, velocity.z)
		var min_spd: float = cfg.slide_min_speed if cfg != null else 3.0
		if not is_sliding and is_sprinting_active() and is_on_floor() and _slide_cooldown <= 0.0 and horiz_v.length() > min_spd:
			var boost: float = cfg.slide_boost if cfg != null else 1.4
			var floor_spd: float = cfg.slide_floor_speed if cfg != null else 6.8
			var max_spd: float = cfg.slide_max_speed if cfg != null else 10.3
			_slide_timer = cfg.slide_duration if cfg != null else 0.75
			_slide_speed = clampf(maxf(floor_spd, horiz_v.length() * boost), floor_spd, max_spd)
			_slide_dir = Vector3(horiz_v.x, 0.0, horiz_v.y).normalized()
			is_sliding = true
			is_crouching = true
			_slide_buffer = 0.0
			_fov_kick += 6.5

	if not is_on_floor():
		velocity.y -= gravity * delta
		if is_sliding:
			is_sliding = false
			_slide_timer = 0.0
			_slide_cooldown = cfg.slide_cooldown if cfg != null else 0.26
	elif Input.is_action_just_pressed("jump"):
		if is_sliding:
			is_sliding = false
			_slide_timer = 0.0
			_slide_cooldown = cfg.slide_cooldown if cfg != null else 0.26
			is_crouching = false
			velocity.y = jump_velocity
		elif not is_crouching:
			velocity.y = jump_velocity

	var kb_dir := Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_back") - Input.get_action_strength("move_forward")
	)
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

	if is_sliding and _slide_timer > 0.0:
		var dur: float = maxf(cfg.slide_duration if cfg != null else 0.75, 0.01)
		var end_spd: float = cfg.slide_end_speed if cfg != null else 3.1
		var k: float = 1.0 - (_slide_timer / dur)
		var cur_slide_v: float = end_spd + (_slide_speed - end_spd) * pow(maxf(1.0 - k, 0.0), 1.35)
		if direction.length_squared() > 0.02:
			var turn_rate: float = cfg.slide_turn_rate if cfg != null else 2.0
			var dl: float = atan2(_slide_dir.x * direction.z - _slide_dir.z * direction.x, _slide_dir.x * direction.x + _slide_dir.z * direction.z)
			if absf(dl) < 2.6:
				var ang: float = clampf(dl * 6.0, -turn_rate, turn_rate) * delta
				_slide_dir = _slide_dir.rotated(Vector3.UP, -ang).normalized()
		velocity.x = _slide_dir.x * cur_slide_v
		velocity.z = _slide_dir.z * cur_slide_v
		_slide_timer -= delta
		if _slide_timer <= 0.0:
			is_sliding = false
			_slide_timer = 0.0
			_slide_cooldown = cfg.slide_cooldown if cfg != null else 0.26
	else:
		var target_speed: float = _get_target_speed()
		var target_velocity: Vector3 = direction * target_speed
		var accel: float
		if not is_on_floor():
			accel = air_acceleration
		elif is_sprinting_active() and direction.length_squared() > 0.0:
			accel = sprint_acceleration
		elif direction.length_squared() > 0.0:
			accel = acceleration
		else:
			accel = deceleration
		var alpha: float = (1.0 - exp(-accel * delta)) if _use_exp_damping else clampf(accel * delta, 0.0, 1.0)
		velocity.x = lerpf(velocity.x, target_velocity.x, alpha)
		velocity.z = lerpf(velocity.z, target_velocity.z, alpha)

	_slide_amount = lerpf(_slide_amount, 1.0 if is_sliding else 0.0, 1.0 - exp(-(12.0 if is_sliding else 7.0) * delta))
	_prev_vertical_vel = velocity.y


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


func _handle_landing_detection(delta: float) -> void:
	var on_floor_now: bool = is_on_floor()
	if on_floor_now and not _was_on_floor and _prev_vertical_vel < -4.0:
		var lk: float = clampf(-_prev_vertical_vel * 0.08, 0.25, 1.3) * landing_dip_intensity
		_land_dip_vel -= lk * 1.15
		_land_roll_deg += (-1.0 if randf() < 0.5 else 1.0) * 1.6 * lk
		if weapon_manager != null and weapon_manager.active_viewmodel != null:
			weapon_manager.active_viewmodel.trigger_land(lk)
	_was_on_floor = on_floor_now

	# Spring-damped landing dip recovery
	_land_dip_vel += (-160.0 * _land_dip_offset - 18.0 * _land_dip_vel) * delta
	_land_dip_offset = clampf(_land_dip_offset + _land_dip_vel * delta, -0.22, 0.08)
	_land_roll_deg = lerpf(_land_roll_deg, 0.0, 1.0 - exp(-14.0 * delta))


func add_camera_shake(amount: float) -> void:
	_camera_shake = clampf(maxf(_camera_shake, amount), 0.0, 1.0)


func _update_camera_effects(delta: float) -> void:
	if camera == null:
		return

	var horizontal_speed: float = Vector2(velocity.x, velocity.z).length()
	var is_sprinting: bool = is_sprinting_active() and horizontal_speed > walk_speed * 0.7
	if is_sprinting and not _was_sprinting and is_on_floor():
		_fov_kick += 3.0
	_was_sprinting = is_sprinting
	_sprint_weight = lerpf(_sprint_weight, 1.0 if is_sprinting else 0.0, 1.0 - exp(-11.0 * delta))

	_fov_kick = lerpf(_fov_kick, 0.0, 1.0 - exp(-7.0 * delta))
	_camera_shake = maxf(_camera_shake - delta * 1.6, 0.0)

	var is_aiming: bool = weapon_manager != null and weapon_manager.active_weapon != null and weapon_manager.active_weapon.is_aiming
	var target_fov: float = base_fov * (1.0 + 0.085 * _sprint_weight + 0.09 * _slide_amount) + _fov_kick * (0.35 if is_aiming else 1.0)
	if weapon_manager:
		target_fov *= weapon_manager.get_fov_multiplier()
	camera.fov = lerpf(camera.fov, target_fov, clampf(fov_lerp_speed * delta, 0.0, 1.0))

	if viewmodel_camera:
		viewmodel_camera.global_transform = camera.global_transform

	var stride_len: float = 2.7 if is_sprinting else 2.1
	var target_bob_amp: float = clampf(horizontal_speed / 5.0, 0.0, 1.5) if (is_on_floor() and not is_sliding) else 0.0
	_bob_amp = lerpf(_bob_amp, target_bob_amp, 1.0 - exp(-8.0 * delta))
	if horizontal_speed > 0.2 and is_on_floor() and not is_sliding:
		_bob_time += delta * PI * horizontal_speed / stride_len
	else:
		_bob_time = 0.0

	var bob_scale: float = _bob_amp * (0.2 if is_aiming else 1.0) * camera_bob_intensity
	var bob_pos := Vector3(
		cos(_bob_time) * 0.007 * bob_scale,
		sin(_bob_time * 2.0) * (0.012 + 0.008 * _sprint_weight) * bob_scale + _land_dip_offset,
		0.0
	)
	camera.position = camera.position.lerp(bob_pos, clampf(16.0 * delta, 0.0, 1.0))

	var sh: float = (_camera_shake * _camera_shake * 0.025) * camera_shake_intensity
	var ads_sway_x: float = 0.0
	var ads_sway_y: float = 0.0
	if is_aiming:
		_ads_sway_time += delta
		var is_scoped: bool = weapon_manager != null and weapon_manager.get_fov_multiplier() < 0.7
		var sway_mul: float = (0.005 if is_scoped else 0.0012) * camera_shake_intensity
		ads_sway_x = (sin(_ads_sway_time * 0.83) * 0.7 + sin(_ads_sway_time * 1.91) * 0.3) * sway_mul
		ads_sway_y = (sin(_ads_sway_time * 1.13) * 0.65 + cos(_ads_sway_time * 0.57) * 0.35) * sway_mul
	camera.rotation.x = ads_sway_y + (randf_range(-1.0, 1.0) * sh)
	camera.rotation.y = ads_sway_x + (randf_range(-1.0, 1.0) * sh)
	var bob_roll: float = cos(_bob_time) * (0.003 + 0.005 * _sprint_weight) * bob_scale
	camera.rotation.z = bob_roll + deg_to_rad(_land_roll_deg) + (_slide_amount * 0.045)


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
