class_name ViewmodelRig
extends Node3D
## Original first-person arm & weapon viewmodel rig.
## Builds articulated left/right arms with CharacterData skin_tone & sleeve_color,
## category-specific hand poses, AnimationPlayer clips driven by WeaponData &
## PlayerStats, stride/look bob & sway, landing dip, and per-category muzzle flash/smoke.

const HAND_POSES := {
	"pistol": {"l_pos": Vector3(-0.04, -0.055, 0.04), "l_rot": Vector3(14.0, 22.0, -10.0), "r_pos": Vector3(0.025, -0.06, 0.12), "r_rot": Vector3(6.0, -6.0, 0.0)},
	"smg": {"l_pos": Vector3(-0.055, -0.05, -0.08), "l_rot": Vector3(12.0, 18.0, -14.0), "r_pos": Vector3(0.035, -0.06, 0.14), "r_rot": Vector3(4.0, -4.0, 0.0)},
	"rifle": {"l_pos": Vector3(-0.06, -0.05, -0.14), "l_rot": Vector3(10.0, 20.0, -16.0), "r_pos": Vector3(0.035, -0.065, 0.14), "r_rot": Vector3(4.0, -4.0, 0.0)},
	"shotgun": {"l_pos": Vector3(-0.055, -0.06, -0.16), "l_rot": Vector3(8.0, 16.0, -18.0), "r_pos": Vector3(0.04, -0.065, 0.15), "r_rot": Vector3(5.0, -5.0, 0.0)},
	"sniper": {"l_pos": Vector3(-0.06, -0.055, -0.18), "l_rot": Vector3(8.0, 18.0, -16.0), "r_pos": Vector3(0.04, -0.065, 0.16), "r_rot": Vector3(4.0, -4.0, 0.0)},
	"heavy": {"l_pos": Vector3(-0.075, -0.07, -0.15), "l_rot": Vector3(12.0, 22.0, -20.0), "r_pos": Vector3(0.045, -0.075, 0.15), "r_rot": Vector3(6.0, -6.0, 0.0)},
}

const MUZZLE_PROFILES := {
	"pistol": {"color": Color(1.0, 0.86, 0.55), "energy": 2.2, "flash_amt": 5, "smoke_amt": 3, "smoke_scale": 0.05},
	"smg": {"color": Color(1.0, 0.84, 0.50), "energy": 2.0, "flash_amt": 5, "smoke_amt": 3, "smoke_scale": 0.045},
	"rifle": {"color": Color(1.0, 0.80, 0.45), "energy": 2.8, "flash_amt": 7, "smoke_amt": 5, "smoke_scale": 0.065},
	"shotgun": {"color": Color(1.0, 0.68, 0.32), "energy": 3.8, "flash_amt": 11, "smoke_amt": 8, "smoke_scale": 0.095},
	"sniper": {"color": Color(1.0, 0.88, 0.60), "energy": 4.2, "flash_amt": 10, "smoke_amt": 8, "smoke_scale": 0.090},
	"heavy": {"color": Color(1.0, 0.74, 0.38), "energy": 3.4, "flash_amt": 9, "smoke_amt": 7, "smoke_scale": 0.085},
}

@export var hip_position: Vector3 = Vector3(0.24, -0.22, -0.45)
@export var ads_position: Vector3 = Vector3(0.0, -0.145, -0.36)
@export var ads_lerp_speed: float = 14.0
@export var sway_amount: float = 0.015
@export var sway_lerp_speed: float = 10.0

@onready var weapon_pivot: Node3D = $WeaponPivot
@onready var muzzle_point: Marker3D = $WeaponPivot/MuzzlePoint
@onready var muzzle_light: OmniLight3D = $WeaponPivot/MuzzlePoint/MuzzleLight
@onready var muzzle_particles: CPUParticles3D = $WeaponPivot/MuzzlePoint/MuzzleParticles

var anim_player: AnimationPlayer = null
var anim_offset_node: Node3D = null
var left_arm_root: Node3D = null
var right_arm_root: Node3D = null
var muzzle_smoke: CPUParticles3D = null

var _recoil_offset: Vector3 = Vector3.ZERO
var _recoil_rot: Vector3 = Vector3.ZERO
var _equip_offset_y: float = 0.0
var _land_offset_y: float = 0.0
var _is_reloading: bool = false
var _was_aiming: bool = false
var _sway_offset: Vector2 = Vector2.ZERO
var _bob_time: float = 0.0
var _muzzle_flash_timer: float = 0.0
var _category: String = "rifle"
var _skin_mats: Array[StandardMaterial3D] = []
var _sleeve_mats: Array[StandardMaterial3D] = []


func _ready() -> void:
	position = hip_position
	_ensure_anim_node_and_clips()
	_build_arm_rig()
	_build_muzzle_smoke()
	_set_meshes_layer_2(self)
	if muzzle_light:
		muzzle_light.visible = false
		muzzle_light.light_energy = 2.5


func _ensure_anim_node_and_clips() -> void:
	if anim_player != null:
		return
	anim_offset_node = Node3D.new()
	anim_offset_node.name = "AnimOffset"
	if weapon_pivot != null:
		var wp_parent: Node = weapon_pivot.get_parent()
		wp_parent.remove_child(weapon_pivot)
		add_child(anim_offset_node)
		anim_offset_node.add_child(weapon_pivot)
	else:
		add_child(anim_offset_node)

	anim_player = AnimationPlayer.new()
	anim_player.name = "ViewmodelAnimPlayer"
	anim_offset_node.add_child(anim_player)

	var lib := AnimationLibrary.new()
	lib.add_animation("draw", _make_pos_rot_clip(0.25, [
		[0.0, Vector3(0.0, -0.28, 0.06), Vector3(-25.0, 12.0, -8.0)],
		[0.18, Vector3(0.0, 0.015, -0.01), Vector3(2.5, 0.0, 0.0)],
		[0.25, Vector3.ZERO, Vector3.ZERO],
	]))
	lib.add_animation("fire", _make_pos_rot_clip(0.14, [
		[0.0, Vector3.ZERO, Vector3.ZERO],
		[0.03, Vector3(0.0, 0.008, 0.055), Vector3(6.5, 0.0, 0.0)],
		[0.14, Vector3.ZERO, Vector3.ZERO],
	]))
	lib.add_animation("empty_fire", _make_pos_rot_clip(0.12, [
		[0.0, Vector3.ZERO, Vector3.ZERO],
		[0.04, Vector3(0.0, -0.006, 0.012), Vector3(-2.5, 0.0, 4.0)],
		[0.12, Vector3.ZERO, Vector3.ZERO],
	]))
	lib.add_animation("ads_in", _make_pos_rot_clip(0.14, [
		[0.0, Vector3(0.02, -0.01, 0.01), Vector3(-1.5, 0.0, 2.0)],
		[0.14, Vector3.ZERO, Vector3.ZERO],
	]))
	lib.add_animation("ads_out", _make_pos_rot_clip(0.14, [
		[0.0, Vector3(-0.02, 0.005, -0.01), Vector3(1.5, 0.0, -2.0)],
		[0.14, Vector3.ZERO, Vector3.ZERO],
	]))
	lib.add_animation("reload_pistol", _make_pos_rot_clip(1.0, [
		[0.0, Vector3.ZERO, Vector3.ZERO],
		[0.25, Vector3(0.02, -0.14, 0.04), Vector3(-34.0, 18.0, -18.0)],
		[0.65, Vector3(0.0, -0.10, 0.02), Vector3(-24.0, 12.0, -10.0)],
		[0.85, Vector3(0.0, 0.02, -0.01), Vector3(4.0, 0.0, 0.0)],
		[1.0, Vector3.ZERO, Vector3.ZERO],
	]))
	lib.add_animation("reload_rifle", _make_pos_rot_clip(1.0, [
		[0.0, Vector3.ZERO, Vector3.ZERO],
		[0.20, Vector3(-0.02, -0.11, 0.03), Vector3(-24.0, 24.0, -22.0)],
		[0.60, Vector3(-0.03, -0.13, 0.05), Vector3(-28.0, 22.0, -18.0)],
		[0.84, Vector3(0.0, 0.018, -0.015), Vector3(5.0, 2.0, 0.0)],
		[1.0, Vector3.ZERO, Vector3.ZERO],
	]))
	lib.add_animation("reload_shotgun", _make_pos_rot_clip(1.0, [
		[0.0, Vector3.ZERO, Vector3.ZERO],
		[0.22, Vector3(0.03, -0.08, 0.04), Vector3(22.0, -14.0, 28.0)],
		[0.62, Vector3(0.02, -0.10, 0.03), Vector3(18.0, -10.0, 22.0)],
		[0.86, Vector3(0.0, 0.02, -0.02), Vector3(-4.0, 0.0, 0.0)],
		[1.0, Vector3.ZERO, Vector3.ZERO],
	]))
	lib.add_animation("reload_sniper", _make_pos_rot_clip(1.0, [
		[0.0, Vector3.ZERO, Vector3.ZERO],
		[0.24, Vector3(-0.03, -0.12, 0.04), Vector3(-20.0, 26.0, -24.0)],
		[0.68, Vector3(-0.02, -0.11, 0.03), Vector3(-16.0, 18.0, -18.0)],
		[0.88, Vector3(0.0, 0.015, -0.01), Vector3(3.5, 0.0, 0.0)],
		[1.0, Vector3.ZERO, Vector3.ZERO],
	]))
	lib.add_animation("reload_heavy", _make_pos_rot_clip(1.0, [
		[0.0, Vector3.ZERO, Vector3.ZERO],
		[0.28, Vector3(0.0, -0.16, 0.06), Vector3(-18.0, 20.0, -14.0)],
		[0.70, Vector3(0.0, -0.15, 0.05), Vector3(-16.0, 18.0, -12.0)],
		[0.90, Vector3(0.0, 0.02, -0.02), Vector3(4.0, 0.0, 0.0)],
		[1.0, Vector3.ZERO, Vector3.ZERO],
	]))
	anim_player.add_animation_library("", lib)


func _make_pos_rot_clip(length_sec: float, keys: Array) -> Animation:
	var anim := Animation.new()
	anim.length = length_sec
	var t_pos: int = anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(t_pos, NodePath(".:position"))
	var t_rot: int = anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(t_rot, NodePath(".:rotation"))
	for k: Array in keys:
		var tm: float = float(k[0])
		var pos_v: Vector3 = k[1] as Vector3
		var rot_deg: Vector3 = k[2] as Vector3
		anim.track_insert_key(t_pos, tm, pos_v)
		anim.track_insert_key(t_rot, tm, Vector3(deg_to_rad(rot_deg.x), deg_to_rad(rot_deg.y), deg_to_rad(rot_deg.z)))
	return anim


func _build_arm_rig() -> void:
	if weapon_pivot == null or left_arm_root != null:
		return
	var skin_mat := StandardMaterial3D.new()
	skin_mat.albedo_color = Color(0.76, 0.57, 0.44, 1.0)
	skin_mat.roughness = 0.72
	_skin_mats.append(skin_mat)

	var sleeve_mat := StandardMaterial3D.new()
	sleeve_mat.albedo_color = Color(0.25, 0.28, 0.35, 1.0)
	sleeve_mat.roughness = 0.85
	_sleeve_mats.append(sleeve_mat)

	left_arm_root = _create_single_arm("LeftArmRoot", skin_mat, sleeve_mat, -1.0)
	right_arm_root = _create_single_arm("RightArmRoot", skin_mat, sleeve_mat, 1.0)
	weapon_pivot.add_child(left_arm_root)
	weapon_pivot.add_child(right_arm_root)
	_apply_hand_pose(_category)


func _create_single_arm(arm_name: String, skin_mat: StandardMaterial3D, sleeve_mat: StandardMaterial3D, side: float) -> Node3D:
	var root_n := Node3D.new()
	root_n.name = arm_name

	# Hand
	var hand := MeshInstance3D.new()
	hand.name = "Hand"
	var hand_m := BoxMesh.new()
	hand_m.size = Vector3(0.052, 0.048, 0.075)
	hand.mesh = hand_m
	hand.material_override = skin_mat
	root_n.add_child(hand)

	# Thumb
	var thumb := MeshInstance3D.new()
	thumb.name = "Thumb"
	var thumb_m := BoxMesh.new()
	thumb_m.size = Vector3(0.022, 0.026, 0.042)
	thumb.mesh = thumb_m
	thumb.material_override = skin_mat
	thumb.position = Vector3(-side * 0.026, 0.015, -0.01)
	root_n.add_child(thumb)

	# Forearm (skin wrist)
	var forearm := MeshInstance3D.new()
	forearm.name = "Forearm"
	var fa_m := BoxMesh.new()
	fa_m.size = Vector3(0.056, 0.056, 0.14)
	forearm.mesh = fa_m
	forearm.material_override = skin_mat
	forearm.position = Vector3(side * 0.018, -0.02, 0.095)
	forearm.rotation_degrees = Vector3(10.0, side * 12.0, 0.0)
	root_n.add_child(forearm)

	# Sleeve (upper forearm/cuff)
	var sleeve := MeshInstance3D.new()
	sleeve.name = "Sleeve"
	var sl_m := BoxMesh.new()
	sl_m.size = Vector3(0.072, 0.072, 0.24)
	sleeve.mesh = sl_m
	sleeve.material_override = sleeve_mat
	sleeve.position = Vector3(side * 0.055, -0.055, 0.24)
	sleeve.rotation_degrees = Vector3(14.0, side * 16.0, 0.0)
	root_n.add_child(sleeve)

	return root_n


func _build_muzzle_smoke() -> void:
	if muzzle_point == null or muzzle_smoke != null:
		return
	muzzle_smoke = CPUParticles3D.new()
	muzzle_smoke.name = "MuzzleSmoke"
	muzzle_smoke.emitting = false
	muzzle_smoke.one_shot = true
	muzzle_smoke.explosiveness = 0.85
	muzzle_smoke.lifetime = 0.45
	muzzle_smoke.amount = 4
	muzzle_smoke.direction = Vector3(0.0, 0.35, -1.0)
	muzzle_smoke.spread = 28.0
	muzzle_smoke.initial_velocity_min = 0.6
	muzzle_smoke.initial_velocity_max = 1.6
	muzzle_smoke.gravity = Vector3(0.0, 0.4, 0.0)
	var sm_mat := StandardMaterial3D.new()
	sm_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm_mat.albedo_color = Color(0.68, 0.68, 0.70, 0.35)
	var sm_mesh := SphereMesh.new()
	sm_mesh.radius = 0.06
	sm_mesh.height = 0.12
	sm_mesh.material = sm_mat
	muzzle_smoke.mesh = sm_mesh
	muzzle_point.add_child(muzzle_smoke)


func configure_character_and_weapon(skin_tone: Color, sleeve_color: Color, weapon_category: String) -> void:
	for sm: StandardMaterial3D in _skin_mats:
		sm.albedo_color = skin_tone
	for slm: StandardMaterial3D in _sleeve_mats:
		slm.albedo_color = sleeve_color
	_category = _normalize_category(weapon_category)
	_apply_hand_pose(_category)
	_apply_muzzle_profile(_category)


static func _normalize_category(cat: String) -> String:
	var c: String = cat.to_lower()
	if c.contains("pistol"):
		return "pistol"
	if c.contains("smg"):
		return "smg"
	if c.contains("shotgun"):
		return "shotgun"
	if c.contains("sniper"):
		return "sniper"
	if c.contains("lmg") or c.contains("heavy"):
		return "heavy"
	return "rifle"


func _apply_hand_pose(cat: String) -> void:
	var pose: Dictionary = HAND_POSES.get(cat, HAND_POSES["rifle"])
	if left_arm_root != null:
		left_arm_root.position = pose["l_pos"]
		left_arm_root.rotation_degrees = pose["l_rot"]
	if right_arm_root != null:
		right_arm_root.position = pose["r_pos"]
		right_arm_root.rotation_degrees = pose["r_rot"]


func _apply_muzzle_profile(cat: String) -> void:
	var prof: Dictionary = MUZZLE_PROFILES.get(cat, MUZZLE_PROFILES["rifle"])
	if muzzle_light != null:
		muzzle_light.light_color = prof["color"]
		muzzle_light.light_energy = float(prof["energy"])
	if muzzle_particles != null:
		muzzle_particles.amount = int(prof["flash_amt"])
	if muzzle_smoke != null:
		muzzle_smoke.amount = int(prof["smoke_amt"])
		if muzzle_smoke.mesh is SphereMesh:
			var r: float = float(prof["smoke_scale"])
			(muzzle_smoke.mesh as SphereMesh).radius = r
			(muzzle_smoke.mesh as SphereMesh).height = r * 2.0


func _set_meshes_layer_2(node: Node) -> void:
	if node is VisualInstance3D:
		(node as VisualInstance3D).layers = 2
	for child: Node in node.get_children():
		_set_meshes_layer_2(child)


func _process(delta: float) -> void:
	_recoil_offset = _recoil_offset.lerp(Vector3.ZERO, clampf(16.0 * delta, 0.0, 1.0))
	_recoil_rot = _recoil_rot.lerp(Vector3.ZERO, clampf(14.0 * delta, 0.0, 1.0))
	_equip_offset_y = lerpf(_equip_offset_y, 0.0, clampf(10.0 * delta, 0.0, 1.0))
	_land_offset_y = lerpf(_land_offset_y, 0.0, clampf(12.0 * delta, 0.0, 1.0))

	if _muzzle_flash_timer > 0.0:
		_muzzle_flash_timer -= delta
		if _muzzle_flash_timer <= 0.0 and muzzle_light:
			muzzle_light.visible = false


func trigger_fire(kick_back: float = 0.06, kick_pitch_deg: float = 6.0) -> void:
	_recoil_offset.z += kick_back
	_recoil_offset.y += kick_back * 0.2
	_recoil_rot.x += deg_to_rad(kick_pitch_deg)
	if anim_player != null and anim_player.has_animation("fire") and not _is_reloading:
		anim_player.speed_scale = 1.0
		anim_player.play("fire")
	if muzzle_light:
		muzzle_light.visible = true
		_muzzle_flash_timer = 0.045
	if muzzle_particles:
		muzzle_particles.restart()
		muzzle_particles.emitting = true
	if muzzle_smoke:
		muzzle_smoke.restart()
		muzzle_smoke.emitting = true


func trigger_empty_fire() -> void:
	if anim_player != null and anim_player.has_animation("empty_fire") and not _is_reloading:
		anim_player.speed_scale = 1.0
		anim_player.play("empty_fire")


func trigger_equip(draw_duration: float = 0.25) -> void:
	_equip_offset_y = -0.35
	if anim_player != null and anim_player.has_animation("draw"):
		anim_player.speed_scale = 0.25 / maxf(draw_duration, 0.05)
		anim_player.play("draw")


func trigger_reload(reload_duration: float = 1.6) -> void:
	_is_reloading = true
	var clip: String = "reload_%s" % _category
	if anim_player != null:
		if not anim_player.has_animation(clip):
			clip = "reload_rifle"
		anim_player.speed_scale = 1.0 / maxf(reload_duration, 0.1)
		anim_player.play(clip)


func set_reloading(reloading: bool) -> void:
	_is_reloading = reloading
	if not reloading and anim_player != null and anim_player.is_playing():
		if anim_player.current_animation.begins_with("reload_"):
			anim_player.stop()


func trigger_land(strength: float = 1.0) -> void:
	_land_offset_y = clampf(-0.07 * strength, -0.14, 0.0)


func trigger_jump() -> void:
	_land_offset_y = 0.035


func update_pose(delta: float, look_delta: Vector2, horizontal_speed: float, is_aiming: bool, is_sprinting: bool) -> void:
	if is_aiming != _was_aiming:
		_was_aiming = is_aiming
		if anim_player != null and not _is_reloading:
			anim_player.speed_scale = 1.0
			anim_player.play("ads_in" if is_aiming else "ads_out")

	var target_pos: Vector3 = ads_position if is_aiming else hip_position
	position = position.lerp(target_pos, clampf(ads_lerp_speed * delta, 0.0, 1.0))

	var wpn_bob_mul: float = 1.0
	var sm: Node = get_node_or_null("/root/SettingsManager") if is_inside_tree() else null
	if sm != null:
		wpn_bob_mul = float(sm.get("weapon_bob_intensity"))

	var target_sway: Vector2 = Vector2(
		clampf(-look_delta.x * 0.001, -sway_amount, sway_amount),
		clampf(look_delta.y * 0.001, -sway_amount, sway_amount)
	) * wpn_bob_mul
	if is_aiming:
		target_sway *= 0.25
	_sway_offset = _sway_offset.lerp(target_sway, clampf(sway_lerp_speed * delta, 0.0, 1.0))

	var bob_pos := Vector3.ZERO
	if horizontal_speed > 0.3:
		_bob_time += delta * horizontal_speed
		var bob_scale: float = (0.004 if is_aiming else 0.012) * wpn_bob_mul
		bob_pos.x = cos(_bob_time * 1.1) * bob_scale
		bob_pos.y = absf(sin(_bob_time * 2.2)) * bob_scale
	else:
		_bob_time = 0.0

	var target_pivot_pos: Vector3 = Vector3(_sway_offset.x, _sway_offset.y + _equip_offset_y + _land_offset_y, 0.0) + bob_pos + _recoil_offset
	var target_pivot_rot: Vector3 = _recoil_rot

	if _is_reloading:
		target_pivot_pos += Vector3(0.0, -0.04, 0.02)
	elif is_sprinting:
		target_pivot_pos += Vector3(-0.04, -0.05, 0.04)
		target_pivot_rot += Vector3(deg_to_rad(-18.0), deg_to_rad(28.0), deg_to_rad(10.0))

	if weapon_pivot:
		weapon_pivot.position = weapon_pivot.position.lerp(target_pivot_pos, clampf(14.0 * delta, 0.0, 1.0))
		weapon_pivot.rotation = weapon_pivot.rotation.lerp(target_pivot_rot, clampf(14.0 * delta, 0.0, 1.0))
