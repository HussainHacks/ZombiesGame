class_name ZombieVisual
extends Node3D
## Swappable greybox zombie visual rig with code-driven procedural animation
## and per-instance skin, torn-clothing, emissive eye, and posture variation.

const SKIN_TONES := [
	Color(0.36, 0.44, 0.34, 1.0),
	Color(0.42, 0.43, 0.36, 1.0),
	Color(0.30, 0.36, 0.32, 1.0),
	Color(0.46, 0.41, 0.37, 1.0),
]

const CLOTH_COLORS := [
	Color(0.18, 0.16, 0.19, 1.0),
	Color(0.24, 0.15, 0.14, 1.0),
	Color(0.14, 0.19, 0.17, 1.0),
	Color(0.22, 0.20, 0.16, 1.0),
]

const PANTS_COLORS := [
	Color(0.12, 0.14, 0.18, 1.0),
	Color(0.15, 0.13, 0.11, 1.0),
	Color(0.10, 0.12, 0.14, 1.0),
]

@onready var body_pivot: Node3D = $BodyPivot
@onready var torso: Node3D = $BodyPivot/Torso
@onready var head: Node3D = $BodyPivot/Torso/Head
@onready var left_arm: Node3D = $BodyPivot/Torso/LeftArm
@onready var right_arm: Node3D = $BodyPivot/Torso/RightArm
@onready var left_leg: Node3D = $BodyPivot/LeftLeg
@onready var right_leg: Node3D = $BodyPivot/RightLeg

var _walk_time: float = 0.0
var _base_hunch_deg: float = 18.0


func _ready() -> void:
	apply_random_variation()


func apply_random_variation() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var s: float = rng.randf_range(0.94, 1.08)
	scale = Vector3(s, rng.randf_range(0.95, 1.07), s)
	_base_hunch_deg = rng.randf_range(13.0, 25.0)

	var skin_mat := StandardMaterial3D.new()
	skin_mat.albedo_color = SKIN_TONES[rng.randi_range(0, SKIN_TONES.size() - 1)]
	skin_mat.roughness = 0.85

	var cloth_mat := StandardMaterial3D.new()
	cloth_mat.albedo_color = CLOTH_COLORS[rng.randi_range(0, CLOTH_COLORS.size() - 1)]
	cloth_mat.roughness = 0.92

	var pants_mat := StandardMaterial3D.new()
	pants_mat.albedo_color = PANTS_COLORS[rng.randi_range(0, PANTS_COLORS.size() - 1)]
	pants_mat.roughness = 0.95

	var head_mesh := get_node_or_null("BodyPivot/Torso/Head/HeadMesh") as MeshInstance3D
	var l_arm_mesh := get_node_or_null("BodyPivot/Torso/LeftArm/ArmMesh") as MeshInstance3D
	var r_arm_mesh := get_node_or_null("BodyPivot/Torso/RightArm/ArmMesh") as MeshInstance3D
	var torso_mesh := get_node_or_null("BodyPivot/Torso/TorsoMesh") as MeshInstance3D
	var l_leg_mesh := get_node_or_null("BodyPivot/LeftLeg/LegMesh") as MeshInstance3D
	var r_leg_mesh := get_node_or_null("BodyPivot/RightLeg/LegMesh") as MeshInstance3D

	if head_mesh != null:
		head_mesh.material_override = skin_mat
	if l_arm_mesh != null:
		l_arm_mesh.material_override = skin_mat
	if r_arm_mesh != null:
		r_arm_mesh.material_override = skin_mat
	if torso_mesh != null:
		torso_mesh.material_override = cloth_mat
	if l_leg_mesh != null:
		l_leg_mesh.material_override = pants_mat
	if r_leg_mesh != null:
		r_leg_mesh.material_override = pants_mat


func update_visual(delta: float, state: int, horizontal_speed: float) -> void:
	if body_pivot == null:
		return

	# State enum values match ZombieAI.State:
	# 0=IDLE, 1=CHASE, 2=ATTACK_WINDUP, 3=ATTACK, 4=STAGGER, 5=DEAD
	if state == 5:
		body_pivot.position.y = lerpf(body_pivot.position.y, 0.25, 8.0 * delta)
		body_pivot.rotation.x = lerpf(body_pivot.rotation.x, deg_to_rad(-86.0), 8.0 * delta)
		return

	body_pivot.position.y = lerpf(body_pivot.position.y, 0.0, 10.0 * delta)
	body_pivot.rotation.x = lerpf(body_pivot.rotation.x, 0.0, 10.0 * delta)

	if state == 4: # STAGGER
		if torso:
			torso.rotation.x = lerpf(torso.rotation.x, deg_to_rad(-24.0), 16.0 * delta)
		if head:
			head.rotation.x = lerpf(head.rotation.x, deg_to_rad(-20.0), 16.0 * delta)
		return

	# Hunched forward posture
	var target_torso_pitch: float = deg_to_rad(_base_hunch_deg)
	if torso:
		torso.rotation.x = lerpf(torso.rotation.x, target_torso_pitch, 10.0 * delta)
	if head:
		head.rotation.x = lerpf(head.rotation.x, deg_to_rad(-10.0), 10.0 * delta)

	if state == 2: # ATTACK_WINDUP
		if left_arm:
			left_arm.rotation.x = lerpf(left_arm.rotation.x, deg_to_rad(-145.0), 14.0 * delta)
		if right_arm:
			right_arm.rotation.x = lerpf(right_arm.rotation.x, deg_to_rad(-145.0), 14.0 * delta)
		return

	if state == 3: # ATTACK
		if left_arm:
			left_arm.rotation.x = lerpf(left_arm.rotation.x, deg_to_rad(-35.0), 22.0 * delta)
		if right_arm:
			right_arm.rotation.x = lerpf(right_arm.rotation.x, deg_to_rad(-35.0), 22.0 * delta)
		return

	# IDLE / CHASE limb swing
	if horizontal_speed > 0.2:
		_walk_time += delta * horizontal_speed * 2.2
		var swing: float = sin(_walk_time) * deg_to_rad(32.0)
		if left_leg:
			left_leg.rotation.x = swing
		if right_leg:
			right_leg.rotation.x = -swing
		if left_arm:
			left_arm.rotation.x = lerpf(left_arm.rotation.x, deg_to_rad(-72.0) - swing * 0.25, 10.0 * delta)
		if right_arm:
			right_arm.rotation.x = lerpf(right_arm.rotation.x, deg_to_rad(-72.0) + swing * 0.25, 10.0 * delta)
	else:
		_walk_time = 0.0
		if left_leg:
			left_leg.rotation.x = lerpf(left_leg.rotation.x, 0.0, 10.0 * delta)
		if right_leg:
			right_leg.rotation.x = lerpf(right_leg.rotation.x, 0.0, 10.0 * delta)
		if left_arm:
			left_arm.rotation.x = lerpf(left_arm.rotation.x, deg_to_rad(-65.0), 10.0 * delta)
		if right_arm:
			right_arm.rotation.x = lerpf(right_arm.rotation.x, deg_to_rad(-65.0), 10.0 * delta)
