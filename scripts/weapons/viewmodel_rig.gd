class_name ViewmodelRig
extends Node3D
## Procedural greybox viewmodel animation controller.
## Handles fire kick, reload dip/tilt, equip raise, movement/look sway, ADS, and muzzle flash.

@export var hip_position: Vector3 = Vector3(0.24, -0.22, -0.45)
@export var ads_position: Vector3 = Vector3(0.0, -0.145, -0.36)
@export var ads_lerp_speed: float = 14.0
@export var sway_amount: float = 0.015
@export var sway_lerp_speed: float = 10.0

@onready var weapon_pivot: Node3D = $WeaponPivot
@onready var muzzle_point: Marker3D = $WeaponPivot/MuzzlePoint
@onready var muzzle_light: OmniLight3D = $WeaponPivot/MuzzlePoint/MuzzleLight
@onready var muzzle_particles: CPUParticles3D = $WeaponPivot/MuzzlePoint/MuzzleParticles

var _recoil_offset: Vector3 = Vector3.ZERO
var _recoil_rot: Vector3 = Vector3.ZERO
var _equip_offset_y: float = 0.0
var _is_reloading: bool = false
var _sway_offset: Vector2 = Vector2.ZERO
var _bob_time: float = 0.0
var _muzzle_flash_timer: float = 0.0


func _ready() -> void:
	position = hip_position
	_set_meshes_layer_2(self)
	if muzzle_light:
		muzzle_light.visible = false
		muzzle_light.light_energy = 2.5


func _set_meshes_layer_2(node: Node) -> void:
	if node is VisualInstance3D:
		(node as VisualInstance3D).layers = 2
	for child: Node in node.get_children():
		_set_meshes_layer_2(child)


func _process(delta: float) -> void:
	_recoil_offset = _recoil_offset.lerp(Vector3.ZERO, clampf(16.0 * delta, 0.0, 1.0))
	_recoil_rot = _recoil_rot.lerp(Vector3.ZERO, clampf(14.0 * delta, 0.0, 1.0))
	_equip_offset_y = lerpf(_equip_offset_y, 0.0, clampf(10.0 * delta, 0.0, 1.0))

	if _muzzle_flash_timer > 0.0:
		_muzzle_flash_timer -= delta
		if _muzzle_flash_timer <= 0.0 and muzzle_light:
			muzzle_light.visible = false


func trigger_fire(kick_back: float = 0.06, kick_pitch_deg: float = 6.0) -> void:
	_recoil_offset.z += kick_back
	_recoil_offset.y += kick_back * 0.2
	_recoil_rot.x += deg_to_rad(kick_pitch_deg)
	if muzzle_light:
		muzzle_light.visible = true
		_muzzle_flash_timer = 0.045
	if muzzle_particles:
		muzzle_particles.restart()
		muzzle_particles.emitting = true


func trigger_equip() -> void:
	_equip_offset_y = -0.35


func set_reloading(reloading: bool) -> void:
	_is_reloading = reloading


func update_pose(delta: float, look_delta: Vector2, horizontal_speed: float, is_aiming: bool, is_sprinting: bool) -> void:
	var target_pos: Vector3 = ads_position if is_aiming else hip_position
	position = position.lerp(target_pos, clampf(ads_lerp_speed * delta, 0.0, 1.0))

	var target_sway: Vector2 = Vector2(
		clampf(-look_delta.x * 0.001, -sway_amount, sway_amount),
		clampf(look_delta.y * 0.001, -sway_amount, sway_amount)
	)
	if is_aiming:
		target_sway *= 0.25
	_sway_offset = _sway_offset.lerp(target_sway, clampf(sway_lerp_speed * delta, 0.0, 1.0))

	var bob_pos := Vector3.ZERO
	if horizontal_speed > 0.3:
		_bob_time += delta * horizontal_speed
		var bob_scale: float = 0.004 if is_aiming else 0.012
		bob_pos.x = cos(_bob_time * 1.1) * bob_scale
		bob_pos.y = absf(sin(_bob_time * 2.2)) * bob_scale
	else:
		_bob_time = 0.0

	var target_pivot_pos: Vector3 = Vector3(_sway_offset.x, _sway_offset.y + _equip_offset_y, 0.0) + bob_pos + _recoil_offset
	var target_pivot_rot: Vector3 = _recoil_rot

	if _is_reloading:
		target_pivot_pos += Vector3(0.0, -0.14, 0.04)
		target_pivot_rot += Vector3(deg_to_rad(-32.0), deg_to_rad(18.0), deg_to_rad(-15.0))
	elif is_sprinting:
		target_pivot_pos += Vector3(-0.04, -0.05, 0.04)
		target_pivot_rot += Vector3(deg_to_rad(-18.0), deg_to_rad(28.0), deg_to_rad(10.0))

	if weapon_pivot:
		weapon_pivot.position = weapon_pivot.position.lerp(target_pivot_pos, clampf(14.0 * delta, 0.0, 1.0))
		weapon_pivot.rotation = weapon_pivot.rotation.lerp(target_pivot_rot, clampf(14.0 * delta, 0.0, 1.0))
