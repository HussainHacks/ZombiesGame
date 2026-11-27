extends SceneTree
## Generates the rigged humanoid zombie assets:
## - resources/materials/mat_zombie_shared.tres
## - resources/enemies/zombie_skinned_mesh.tres
## - resources/enemies/zombie_anim_lib.tres
## - scenes/enemies/zombie_rig.tscn (Skeleton3D + 1 skinned MeshInstance3D + AnimationPlayer)
## Run with: godot --headless --script res://tools/build_zombie_rig.gd

const MAT_PATH := "res://resources/materials/mat_zombie_shared.tres"
const MESH_PATH := "res://resources/enemies/zombie_skinned_mesh.tres"
const LIB_PATH := "res://resources/enemies/zombie_anim_lib.tres"
const RIG_SCENE_PATH := "res://scenes/enemies/zombie_rig.tscn"

# Bone indices
enum Bone {
	HIPS = 0,
	SPINE = 1,
	CHEST = 2,
	HEAD = 3,
	UPPER_ARM_L = 4,
	FOREARM_L = 5,
	UPPER_ARM_R = 6,
	FOREARM_R = 7,
	THIGH_L = 8,
	SHIN_L = 9,
	THIGH_R = 10,
	SHIN_R = 11,
}

const BONE_NAMES := [
	"Hips", "Spine", "Chest", "Head",
	"UpperArm_L", "Forearm_L", "UpperArm_R", "Forearm_R",
	"Thigh_L", "Shin_L", "Thigh_R", "Shin_R",
]

const BONE_PARENTS := [
	-1,         # Hips
	Bone.HIPS,  # Spine
	Bone.SPINE, # Chest
	Bone.CHEST, # Head
	Bone.CHEST, # UpperArm_L
	Bone.UPPER_ARM_L, # Forearm_L
	Bone.CHEST, # UpperArm_R
	Bone.UPPER_ARM_R, # Forearm_R
	Bone.HIPS,  # Thigh_L
	Bone.THIGH_L, # Shin_L
	Bone.HIPS,  # Thigh_R
	Bone.THIGH_R, # Shin_R
]

# Local rest positions relative to parent (Godot character faces -Z, feet at Y=0)
const BONE_LOCAL_POS := [
	Vector3(0.0, 0.88, 0.0),    # Hips
	Vector3(0.0, 0.14, 0.0),    # Spine
	Vector3(0.0, 0.26, 0.0),    # Chest
	Vector3(0.0, 0.28, -0.02),  # Head
	Vector3(-0.26, 0.16, 0.0),  # UpperArm_L
	Vector3(0.0, -0.28, 0.0),   # Forearm_L
	Vector3(0.26, 0.16, 0.0),   # UpperArm_R
	Vector3(0.0, -0.28, 0.0),   # Forearm_R
	Vector3(-0.12, -0.04, 0.0), # Thigh_L
	Vector3(0.0, -0.42, 0.0),   # Shin_L
	Vector3(0.12, -0.04, 0.0),  # Thigh_R
	Vector3(0.0, -0.42, 0.0),   # Shin_R
]


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://resources/enemies"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://resources/materials"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://scenes/enemies"))

	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.88
	mat.metallic = 0.02
	ResourceSaver.save(mat, MAT_PATH)

	var skel := Skeleton3D.new()
	skel.name = "Skeleton3D"
	var world_pos: Array[Vector3] = []
	world_pos.resize(BONE_NAMES.size())
	for i: int in range(BONE_NAMES.size()):
		skel.add_bone(BONE_NAMES[i])
		skel.set_bone_parent(i, BONE_PARENTS[i])
		var rest := Transform3D(Basis.IDENTITY, BONE_LOCAL_POS[i])
		skel.set_bone_rest(i, rest)
		skel.set_bone_pose_position(i, BONE_LOCAL_POS[i])
		var parent_idx: int = BONE_PARENTS[i]
		world_pos[i] = BONE_LOCAL_POS[i] if parent_idx < 0 else (world_pos[parent_idx] + BONE_LOCAL_POS[i])

	var skin := Skin.new()
	for i: int in range(BONE_NAMES.size()):
		var inv_bind := Transform3D(Basis.IDENTITY, -world_pos[i])
		skin.add_named_bind(BONE_NAMES[i], inv_bind)

	var mesh: ArrayMesh = _build_humanoid_mesh(world_pos)
	ResourceSaver.save(mesh, MESH_PATH)

	var anim_lib: AnimationLibrary = _build_animation_library()
	ResourceSaver.save(anim_lib, LIB_PATH)

	var rig_root := Node3D.new()
	rig_root.name = "ZombieRig"
	rig_root.add_child(skel)
	skel.owner = rig_root

	var mi := MeshInstance3D.new()
	mi.name = "ZombieMesh"
	mi.mesh = load(MESH_PATH)
	mi.skin = skin
	mi.skeleton = NodePath("..")
	mi.material_override = load(MAT_PATH)
	skel.add_child(mi)
	mi.owner = rig_root

	var ap := AnimationPlayer.new()
	ap.name = "AnimationPlayer"
	ap.add_animation_library("", load(LIB_PATH))
	rig_root.add_child(ap)
	ap.owner = rig_root

	var packed := PackedScene.new()
	packed.pack(rig_root)
	ResourceSaver.save(packed, RIG_SCENE_PATH)
	rig_root.free()

	print("[build_zombie_rig] Saved ", MESH_PATH, ", ", LIB_PATH, ", ", RIG_SCENE_PATH)
	quit(0)


func _build_humanoid_mesh(wp: Array[Vector3]) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var col_skin := Color(0.38, 0.48, 0.35, 1.0)
	var col_shirt := Color(0.22, 0.19, 0.21, 1.0)
	var col_blood := Color(0.32, 0.11, 0.11, 1.0)
	var col_pants := Color(0.14, 0.16, 0.22, 1.0)
	var col_shoe := Color(0.09, 0.08, 0.08, 1.0)
	var col_eye := Color(0.92, 0.25, 0.10, 1.0)

	# Pelvis / Hips
	_add_skinned_box(st, wp[Bone.HIPS] + Vector3(0.0, 0.02, 0.0), Vector3(0.34, 0.18, 0.22), Bone.HIPS, col_pants)
	# Abdomen / Spine
	_add_skinned_box(st, wp[Bone.SPINE] + Vector3(0.0, 0.10, 0.0), Vector3(0.36, 0.26, 0.22), Bone.SPINE, col_shirt)
	# Chest + bloodied ribs accent
	_add_skinned_box(st, wp[Bone.CHEST] + Vector3(0.0, 0.08, 0.0), Vector3(0.44, 0.28, 0.26), Bone.CHEST, col_shirt)
	_add_skinned_box(st, wp[Bone.CHEST] + Vector3(0.06, 0.08, -0.135), Vector3(0.18, 0.16, 0.02), Bone.CHEST, col_blood)
	# Neck + Head + Jaw + Eyes
	_add_skinned_box(st, wp[Bone.HEAD] + Vector3(0.0, -0.04, 0.0), Vector3(0.14, 0.12, 0.14), Bone.HEAD, col_skin)
	_add_skinned_box(st, wp[Bone.HEAD] + Vector3(0.0, 0.12, -0.01), Vector3(0.24, 0.26, 0.24), Bone.HEAD, col_skin)
	_add_skinned_box(st, wp[Bone.HEAD] + Vector3(0.0, 0.02, -0.04), Vector3(0.18, 0.09, 0.20), Bone.HEAD, col_blood)
	_add_skinned_box(st, wp[Bone.HEAD] + Vector3(-0.06, 0.15, -0.132), Vector3(0.045, 0.035, 0.02), Bone.HEAD, col_eye)
	_add_skinned_box(st, wp[Bone.HEAD] + Vector3(0.06, 0.15, -0.132), Vector3(0.045, 0.035, 0.02), Bone.HEAD, col_eye)

	# Left Arm (Upper + Forearm + Hand)
	_add_skinned_box(st, wp[Bone.UPPER_ARM_L] + Vector3(0.0, -0.13, 0.0), Vector3(0.12, 0.28, 0.12), Bone.UPPER_ARM_L, col_shirt)
	_add_skinned_box(st, wp[Bone.FOREARM_L] + Vector3(0.0, -0.13, 0.0), Vector3(0.10, 0.26, 0.10), Bone.FOREARM_L, col_skin)
	_add_skinned_box(st, wp[Bone.FOREARM_L] + Vector3(0.0, -0.29, -0.01), Vector3(0.09, 0.10, 0.11), Bone.FOREARM_L, col_blood)

	# Right Arm (Upper + Forearm + Hand)
	_add_skinned_box(st, wp[Bone.UPPER_ARM_R] + Vector3(0.0, -0.13, 0.0), Vector3(0.12, 0.28, 0.12), Bone.UPPER_ARM_R, col_shirt)
	_add_skinned_box(st, wp[Bone.FOREARM_R] + Vector3(0.0, -0.13, 0.0), Vector3(0.10, 0.26, 0.10), Bone.FOREARM_R, col_skin)
	_add_skinned_box(st, wp[Bone.FOREARM_R] + Vector3(0.0, -0.29, -0.01), Vector3(0.09, 0.10, 0.11), Bone.FOREARM_R, col_blood)

	# Left Leg (Thigh + Shin + Foot)
	_add_skinned_box(st, wp[Bone.THIGH_L] + Vector3(0.0, -0.20, 0.0), Vector3(0.16, 0.42, 0.16), Bone.THIGH_L, col_pants)
	_add_skinned_box(st, wp[Bone.SHIN_L] + Vector3(0.0, -0.19, 0.0), Vector3(0.13, 0.38, 0.13), Bone.SHIN_L, col_pants)
	_add_skinned_box(st, wp[Bone.SHIN_L] + Vector3(0.0, -0.39, -0.04), Vector3(0.13, 0.08, 0.22), Bone.SHIN_L, col_shoe)

	# Right Leg (Thigh + Shin + Foot)
	_add_skinned_box(st, wp[Bone.THIGH_R] + Vector3(0.0, -0.20, 0.0), Vector3(0.16, 0.42, 0.16), Bone.THIGH_R, col_pants)
	_add_skinned_box(st, wp[Bone.SHIN_R] + Vector3(0.0, -0.19, 0.0), Vector3(0.13, 0.38, 0.13), Bone.SHIN_R, col_pants)
	_add_skinned_box(st, wp[Bone.SHIN_R] + Vector3(0.0, -0.39, -0.04), Vector3(0.13, 0.08, 0.22), Bone.SHIN_R, col_shoe)

	st.generate_normals()
	return st.commit()


func _add_skinned_box(st: SurfaceTool, center: Vector3, size: Vector3, bone_idx: int, col: Color) -> void:
	var hx: float = size.x * 0.5
	var hy: float = size.y * 0.5
	var hz: float = size.z * 0.5
	var v0 := center + Vector3(-hx, -hy, -hz)
	var v1 := center + Vector3(hx, -hy, -hz)
	var v2 := center + Vector3(hx, hy, -hz)
	var v3 := center + Vector3(-hx, hy, -hz)
	var v4 := center + Vector3(-hx, -hy, hz)
	var v5 := center + Vector3(hx, -hy, hz)
	var v6 := center + Vector3(hx, hy, hz)
	var v7 := center + Vector3(-hx, hy, hz)

	var bones := PackedInt32Array([bone_idx, 0, 0, 0])
	var weights := PackedFloat32Array([1.0, 0.0, 0.0, 0.0])

	var faces := [
		[v0, v1, v2, v3], # -Z front
		[v5, v4, v7, v6], # +Z back
		[v4, v0, v3, v7], # -X left
		[v1, v5, v6, v2], # +X right
		[v3, v2, v6, v7], # +Y top
		[v4, v5, v1, v0], # -Y bottom
	]
	for f: Array in faces:
		_emit_tri(st, f[0], f[1], f[2], col, bones, weights)
		_emit_tri(st, f[0], f[2], f[3], col, bones, weights)


func _emit_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color, bones: PackedInt32Array, weights: PackedFloat32Array) -> void:
	for v: Vector3 in [a, b, c]:
		st.set_color(col)
		st.set_bones(bones)
		st.set_weights(weights)
		st.add_vertex(v)


func _build_animation_library() -> AnimationLibrary:
	var lib := AnimationLibrary.new()
	lib.add_animation("idle", _make_idle_anim())
	lib.add_animation("walk", _make_walk_anim())
	lib.add_animation("attack", _make_attack_anim())
	lib.add_animation("hit_react", _make_hit_react_anim())
	lib.add_animation("death", _make_death_anim())
	return lib


func _add_rot_track(anim: Animation, bone_name: String, keys: Array) -> void:
	var idx: int = anim.add_track(Animation.TYPE_ROTATION_3D)
	anim.track_set_path(idx, NodePath("Skeleton3D:" + bone_name))
	for k: Array in keys:
		var t: float = float(k[0])
		var deg: Vector3 = k[1]
		var q := Quaternion.from_euler(Vector3(deg_to_rad(deg.x), deg_to_rad(deg.y), deg_to_rad(deg.z)))
		anim.rotation_track_insert_key(idx, t, q)


func _add_pos_track(anim: Animation, bone_name: String, keys: Array) -> void:
	var idx: int = anim.add_track(Animation.TYPE_POSITION_3D)
	anim.track_set_path(idx, NodePath("Skeleton3D:" + bone_name))
	for k: Array in keys:
		anim.position_track_insert_key(idx, float(k[0]), k[1])


func _make_idle_anim() -> Animation:
	var a := Animation.new()
	a.length = 1.6
	a.loop_mode = Animation.LOOP_LINEAR
	_add_pos_track(a, "Hips", [[0.0, Vector3(0, 0.88, 0)], [0.8, Vector3(0, 0.85, 0)], [1.6, Vector3(0, 0.88, 0)]])
	_add_rot_track(a, "Spine", [[0.0, Vector3(12, 0, 0)], [0.8, Vector3(16, 2, 0)], [1.6, Vector3(12, 0, 0)]])
	_add_rot_track(a, "Chest", [[0.0, Vector3(10, 0, 0)], [0.8, Vector3(14, -3, 0)], [1.6, Vector3(10, 0, 0)]])
	_add_rot_track(a, "Head", [[0.0, Vector3(-14, -4, 3)], [0.8, Vector3(-10, 5, -4)], [1.6, Vector3(-14, -4, 3)]])
	_add_rot_track(a, "UpperArm_L", [[0.0, Vector3(58, 0, 6)], [0.8, Vector3(64, 0, 8)], [1.6, Vector3(58, 0, 6)]])
	_add_rot_track(a, "Forearm_L", [[0.0, Vector3(22, 0, 0)], [0.8, Vector3(28, 0, 0)], [1.6, Vector3(22, 0, 0)]])
	_add_rot_track(a, "UpperArm_R", [[0.0, Vector3(56, 0, -6)], [0.8, Vector3(62, 0, -8)], [1.6, Vector3(56, 0, -6)]])
	_add_rot_track(a, "Forearm_R", [[0.0, Vector3(24, 0, 0)], [0.8, Vector3(30, 0, 0)], [1.6, Vector3(24, 0, 0)]])
	_add_rot_track(a, "Thigh_L", [[0.0, Vector3(4, 0, 0)], [1.6, Vector3(4, 0, 0)]])
	_add_rot_track(a, "Shin_L", [[0.0, Vector3(-8, 0, 0)], [1.6, Vector3(-8, 0, 0)]])
	_add_rot_track(a, "Thigh_R", [[0.0, Vector3(-4, 0, 0)], [1.6, Vector3(-4, 0, 0)]])
	_add_rot_track(a, "Shin_R", [[0.0, Vector3(-6, 0, 0)], [1.6, Vector3(-6, 0, 0)]])
	return a


func _make_walk_anim() -> Animation:
	# 1.0s cycle (~1.75m stride at 1.0x rate)
	var a := Animation.new()
	a.length = 1.0
	a.loop_mode = Animation.LOOP_LINEAR
	_add_pos_track(a, "Hips", [
		[0.0, Vector3(0, 0.87, 0)], [0.25, Vector3(0, 0.83, 0)],
		[0.5, Vector3(0, 0.87, 0)], [0.75, Vector3(0, 0.83, 0)], [1.0, Vector3(0, 0.87, 0)]
	])
	_add_rot_track(a, "Spine", [[0.0, Vector3(14, 5, 0)], [0.5, Vector3(14, -5, 0)], [1.0, Vector3(14, 5, 0)]])
	_add_rot_track(a, "Chest", [[0.0, Vector3(12, 8, -3)], [0.5, Vector3(12, -8, 3)], [1.0, Vector3(12, 8, -3)]])
	_add_rot_track(a, "Head", [[0.0, Vector3(-16, -5, 4)], [0.5, Vector3(-16, 5, -4)], [1.0, Vector3(-16, -5, 4)]])
	# Arms outstretched reaching toward player with counter-swing
	_add_rot_track(a, "UpperArm_L", [[0.0, Vector3(72, 0, 6)], [0.5, Vector3(86, 0, 4)], [1.0, Vector3(72, 0, 6)]])
	_add_rot_track(a, "Forearm_L", [[0.0, Vector3(18, 0, 0)], [0.5, Vector3(10, 0, 0)], [1.0, Vector3(18, 0, 0)]])
	_add_rot_track(a, "UpperArm_R", [[0.0, Vector3(86, 0, -4)], [0.5, Vector3(72, 0, -6)], [1.0, Vector3(86, 0, -4)]])
	_add_rot_track(a, "Forearm_R", [[0.0, Vector3(10, 0, 0)], [0.5, Vector3(18, 0, 0)], [1.0, Vector3(10, 0, 0)]])
	# Legs gait cycle
	_add_rot_track(a, "Thigh_L", [[0.0, Vector3(32, 0, 0)], [0.25, Vector3(0, 0, 0)], [0.5, Vector3(-28, 0, 0)], [0.75, Vector3(10, 0, 0)], [1.0, Vector3(32, 0, 0)]])
	_add_rot_track(a, "Shin_L", [[0.0, Vector3(-12, 0, 0)], [0.25, Vector3(-6, 0, 0)], [0.5, Vector3(-20, 0, 0)], [0.75, Vector3(-48, 0, 0)], [1.0, Vector3(-12, 0, 0)]])
	_add_rot_track(a, "Thigh_R", [[0.0, Vector3(-28, 0, 0)], [0.25, Vector3(10, 0, 0)], [0.5, Vector3(32, 0, 0)], [0.75, Vector3(0, 0, 0)], [1.0, Vector3(-28, 0, 0)]])
	_add_rot_track(a, "Shin_R", [[0.0, Vector3(-20, 0, 0)], [0.25, Vector3(-48, 0, 0)], [0.5, Vector3(-12, 0, 0)], [0.75, Vector3(-6, 0, 0)], [1.0, Vector3(-20, 0, 0)]])
	return a


func _make_attack_anim() -> Animation:
	var a := Animation.new()
	a.length = 0.62
	a.loop_mode = Animation.LOOP_NONE
	_add_pos_track(a, "Hips", [[0.0, Vector3(0, 0.88, 0)], [0.28, Vector3(0, 0.90, 0.04)], [0.46, Vector3(0, 0.84, -0.08)], [0.62, Vector3(0, 0.88, 0)]])
	_add_rot_track(a, "Spine", [[0.0, Vector3(10, 0, 0)], [0.28, Vector3(-8, -10, 0)], [0.46, Vector3(26, 12, 0)], [0.62, Vector3(14, 0, 0)]])
	_add_rot_track(a, "Chest", [[0.0, Vector3(10, 0, 0)], [0.28, Vector3(-10, -14, 0)], [0.46, Vector3(28, 16, 0)], [0.62, Vector3(12, 0, 0)]])
	_add_rot_track(a, "UpperArm_L", [[0.0, Vector3(70, 0, 6)], [0.28, Vector3(145, 0, 12)], [0.46, Vector3(32, 0, 4)], [0.62, Vector3(68, 0, 6)]])
	_add_rot_track(a, "Forearm_L", [[0.0, Vector3(20, 0, 0)], [0.28, Vector3(45, 0, 0)], [0.46, Vector3(12, 0, 0)], [0.62, Vector3(22, 0, 0)]])
	_add_rot_track(a, "UpperArm_R", [[0.0, Vector3(70, 0, -6)], [0.28, Vector3(150, 0, -14)], [0.46, Vector3(28, 0, -4)], [0.62, Vector3(68, 0, -6)]])
	_add_rot_track(a, "Forearm_R", [[0.0, Vector3(20, 0, 0)], [0.28, Vector3(48, 0, 0)], [0.46, Vector3(10, 0, 0)], [0.62, Vector3(22, 0, 0)]])
	return a


func _make_hit_react_anim() -> Animation:
	var a := Animation.new()
	a.length = 0.28
	a.loop_mode = Animation.LOOP_NONE
	_add_rot_track(a, "Spine", [[0.0, Vector3(10, 0, 0)], [0.10, Vector3(-20, 8, -6)], [0.28, Vector3(10, 0, 0)]])
	_add_rot_track(a, "Chest", [[0.0, Vector3(10, 0, 0)], [0.10, Vector3(-22, -10, 6)], [0.28, Vector3(10, 0, 0)]])
	_add_rot_track(a, "Head", [[0.0, Vector3(-10, 0, 0)], [0.10, Vector3(-34, 12, 0)], [0.28, Vector3(-10, 0, 0)]])
	_add_rot_track(a, "UpperArm_L", [[0.0, Vector3(70, 0, 6)], [0.10, Vector3(45, 0, 28)], [0.28, Vector3(70, 0, 6)]])
	_add_rot_track(a, "UpperArm_R", [[0.0, Vector3(70, 0, -6)], [0.10, Vector3(45, 0, -28)], [0.28, Vector3(70, 0, -6)]])
	return a


func _make_death_anim() -> Animation:
	var a := Animation.new()
	a.length = 0.75
	a.loop_mode = Animation.LOOP_NONE
	_add_pos_track(a, "Hips", [[0.0, Vector3(0, 0.88, 0)], [0.25, Vector3(0, 0.58, 0.12)], [0.55, Vector3(0, 0.22, 0.35)], [0.75, Vector3(0, 0.14, 0.42)]])
	_add_rot_track(a, "Hips", [[0.0, Vector3(0, 0, 0)], [0.25, Vector3(-28, 4, 0)], [0.55, Vector3(-78, 8, 5)], [0.75, Vector3(-88, 8, 6)]])
	_add_rot_track(a, "Spine", [[0.0, Vector3(12, 0, 0)], [0.4, Vector3(-10, 0, 0)], [0.75, Vector3(-4, 0, 0)]])
	_add_rot_track(a, "Head", [[0.0, Vector3(-12, 0, 0)], [0.5, Vector3(-26, 14, 0)], [0.75, Vector3(-18, 18, 0)]])
	_add_rot_track(a, "UpperArm_L", [[0.0, Vector3(65, 0, 8)], [0.5, Vector3(20, 0, 42)], [0.75, Vector3(8, 0, 56)]])
	_add_rot_track(a, "UpperArm_R", [[0.0, Vector3(65, 0, -8)], [0.5, Vector3(25, 0, -40)], [0.75, Vector3(10, 0, -52)]])
	_add_rot_track(a, "Thigh_L", [[0.0, Vector3(0, 0, 0)], [0.3, Vector3(32, 0, 4)], [0.75, Vector3(10, 0, 8)]])
	_add_rot_track(a, "Shin_L", [[0.0, Vector3(0, 0, 0)], [0.3, Vector3(-62, 0, 0)], [0.75, Vector3(-18, 0, 0)]])
	_add_rot_track(a, "Thigh_R", [[0.0, Vector3(0, 0, 0)], [0.3, Vector3(24, 0, -4)], [0.75, Vector3(6, 0, -8)]])
	_add_rot_track(a, "Shin_R", [[0.0, Vector3(0, 0, 0)], [0.3, Vector3(-52, 0, 0)], [0.75, Vector3(-12, 0, 0)]])
	return a
