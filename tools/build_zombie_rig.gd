extends SceneTree
## Generates the shared 15-bone humanoid zombie rig, both comedy variant meshes
## (male dad-bod Hawaiian shirt & female beehive leopard-print handbag), shared
## vertex-color material, animation library, and ZombieVariantData resources.
## Run with: godot --headless --script res://tools/build_zombie_rig.gd

const MAT_PATH := "res://resources/materials/mat_zombie_shared.tres"
const MALE_MESH_PATH := "res://resources/enemies/zombie_male_mesh.tres"
const FEMALE_MESH_PATH := "res://resources/enemies/zombie_female_mesh.tres"
const LIB_PATH := "res://resources/enemies/zombie_anim_lib.tres"
const RIG_SCENE_PATH := "res://scenes/enemies/zombie_rig.tscn"
const MALE_RES_PATH := "res://resources/enemies/variant_male.tres"
const FEMALE_RES_PATH := "res://resources/enemies/variant_female.tres"

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
	BELLY = 12,
	HAIR = 13,
	HANDBAG = 14,
}

const BONE_NAMES := [
	"Hips", "Spine", "Chest", "Head",
	"UpperArm_L", "Forearm_L", "UpperArm_R", "Forearm_R",
	"Thigh_L", "Shin_L", "Thigh_R", "Shin_R",
	"Belly", "Hair", "Handbag",
]

const BONE_PARENTS := [
	-1,               # Hips
	Bone.HIPS,        # Spine
	Bone.SPINE,       # Chest
	Bone.CHEST,       # Head
	Bone.CHEST,       # UpperArm_L
	Bone.UPPER_ARM_L, # Forearm_L
	Bone.CHEST,       # UpperArm_R
	Bone.UPPER_ARM_R, # Forearm_R
	Bone.HIPS,        # Thigh_L
	Bone.THIGH_L,     # Shin_L
	Bone.HIPS,        # Thigh_R
	Bone.THIGH_R,     # Shin_R
	Bone.SPINE,       # Belly (secondary bounce)
	Bone.HEAD,        # Hair (beehive sway)
	Bone.FOREARM_R,   # Handbag (swing)
]

const BONE_LOCAL_POS := [
	Vector3(0.0, 0.88, 0.0),    # Hips
	Vector3(0.0, 0.14, 0.0),    # Spine
	Vector3(0.0, 0.26, 0.0),    # Chest
	Vector3(0.0, 0.28, -0.02),  # Head
	Vector3(-0.27, 0.16, 0.0),  # UpperArm_L
	Vector3(0.0, -0.28, 0.0),   # Forearm_L
	Vector3(0.27, 0.16, 0.0),   # UpperArm_R
	Vector3(0.0, -0.28, 0.0),   # Forearm_R
	Vector3(-0.12, -0.04, 0.0), # Thigh_L
	Vector3(0.0, -0.42, 0.0),   # Shin_L
	Vector3(0.12, -0.04, 0.0),  # Thigh_R
	Vector3(0.0, -0.42, 0.0),   # Shin_R
	Vector3(0.0, 0.05, -0.14),  # Belly
	Vector3(0.0, 0.26, 0.02),   # Hair
	Vector3(0.0, -0.32, -0.04), # Handbag
]


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://resources/enemies"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://resources/materials"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://scenes/enemies"))

	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.86
	mat.metallic = 0.02
	ResourceSaver.save(mat, MAT_PATH)

	var skel := Skeleton3D.new()
	skel.name = "Skeleton3D"
	var world_pos: Array[Vector3] = []
	world_pos.resize(BONE_NAMES.size())
	for i: int in range(BONE_NAMES.size()):
		skel.add_bone(BONE_NAMES[i])
		skel.set_bone_parent(i, BONE_PARENTS[i])
		skel.set_bone_rest(i, Transform3D(Basis.IDENTITY, BONE_LOCAL_POS[i]))
		skel.set_bone_pose_position(i, BONE_LOCAL_POS[i])
		var p_idx: int = BONE_PARENTS[i]
		world_pos[i] = BONE_LOCAL_POS[i] if p_idx < 0 else (world_pos[p_idx] + BONE_LOCAL_POS[i])

	var skin := Skin.new()
	for i: int in range(BONE_NAMES.size()):
		skin.add_named_bind(BONE_NAMES[i], Transform3D(Basis.IDENTITY, -world_pos[i]))

	var male_mesh: ArrayMesh = _build_male_mesh(world_pos)
	var female_mesh: ArrayMesh = _build_female_mesh(world_pos)
	ResourceSaver.save(male_mesh, MALE_MESH_PATH)
	ResourceSaver.save(female_mesh, FEMALE_MESH_PATH)

	var anim_lib: AnimationLibrary = _build_animation_library()
	ResourceSaver.save(anim_lib, LIB_PATH)

	# Save ZombieVariantData resources
	var var_script: Script = load("res://scripts/enemies/zombie_variant_data.gd")
	var v_male: Resource = var_script.new()
	v_male.set("variant_id", "male")
	v_male.set("weight", 1.0)
	v_male.set("mesh", load(MALE_MESH_PATH))
	v_male.set("idle_quirk_anim", &"idle_male_pat")
	v_male.set("attack_anim", &"attack_male_shove")
	v_male.set("death_anim", &"death_male_collapse")
	ResourceSaver.save(v_male, MALE_RES_PATH)

	var v_female: Resource = var_script.new()
	v_female.set("variant_id", "female")
	v_female.set("weight", 1.0)
	v_female.set("mesh", load(FEMALE_MESH_PATH))
	v_female.set("idle_quirk_anim", &"idle_female_nails")
	v_female.set("attack_anim", &"attack_female_handbag")
	v_female.set("death_anim", &"death_female_faint")
	ResourceSaver.save(v_female, FEMALE_RES_PATH)

	# Build shared ZombieRig scene (1 Skeleton3D + 1 MeshInstance3D + AnimationPlayer)
	var rig_root := Node3D.new()
	rig_root.name = "ZombieRig"
	rig_root.add_child(skel)
	skel.owner = rig_root

	var mi := MeshInstance3D.new()
	mi.name = "ZombieMesh"
	mi.mesh = load(MALE_MESH_PATH)
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

	print("[build_zombie_rig] Built male+female comedy variants, shared material, and anim lib.")
	quit(0)


func _build_male_mesh(wp: Array[Vector3]) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var col_skin := Color(0.42, 0.54, 0.36, 1.0)
	var col_hawaii_bg := Color(0.12, 0.52, 0.56, 1.0)
	var col_flower_red := Color(0.92, 0.24, 0.28, 1.0)
	var col_flower_yel := Color(0.96, 0.82, 0.20, 1.0)
	var col_shorts := Color(0.32, 0.28, 0.20, 1.0)
	var col_sock := Color(0.88, 0.88, 0.84, 1.0)
	var col_sandal := Color(0.36, 0.20, 0.10, 1.0)
	var col_hair := Color(0.14, 0.10, 0.08, 1.0)
	var col_eye := Color(0.95, 0.28, 0.10, 1.0)

	# Hips / Dad shorts
	_add_box(st, wp[Bone.HIPS] + Vector3(0.0, 0.02, 0.0), Vector3(0.42, 0.20, 0.28), Bone.HIPS, col_shorts)
	# Spine + too-short torn Hawaiian shirt + floral blotches
	_add_box(st, wp[Bone.SPINE] + Vector3(0.0, 0.14, 0.0), Vector3(0.44, 0.22, 0.28), Bone.SPINE, col_hawaii_bg)
	_add_box(st, wp[Bone.CHEST] + Vector3(0.0, 0.08, 0.0), Vector3(0.50, 0.28, 0.28), Bone.CHEST, col_hawaii_bg)
	_add_box(st, wp[Bone.CHEST] + Vector3(-0.14, 0.10, -0.145), Vector3(0.10, 0.10, 0.02), Bone.CHEST, col_flower_red)
	_add_box(st, wp[Bone.CHEST] + Vector3(0.12, 0.04, -0.145), Vector3(0.09, 0.09, 0.02), Bone.CHEST, col_flower_yel)
	_add_box(st, wp[Bone.CHEST] + Vector3(0.04, 0.12, 0.145), Vector3(0.12, 0.10, 0.02), Bone.CHEST, col_flower_red)

	# Exaggerated dad-bod belly sticking WAY out below the shirt!
	_add_box(st, wp[Bone.BELLY] + Vector3(0.0, -0.02, -0.04), Vector3(0.42, 0.28, 0.30), Bone.BELLY, col_skin)
	_add_box(st, wp[Bone.BELLY] + Vector3(0.0, -0.05, -0.195), Vector3(0.04, 0.03, 0.02), Bone.BELLY, Color(0.24, 0.32, 0.20, 1.0)) # belly button

	# Head + bald dome + tragic comb-over strip + eyes
	_add_box(st, wp[Bone.HEAD] + Vector3(0.0, 0.10, -0.01), Vector3(0.26, 0.27, 0.25), Bone.HEAD, col_skin)
	_add_box(st, wp[Bone.HEAD] + Vector3(-0.02, 0.245, -0.01), Vector3(0.22, 0.035, 0.14), Bone.HEAD, col_hair) # comb-over
	_add_box(st, wp[Bone.HEAD] + Vector3(0.135, 0.15, 0.0), Vector3(0.03, 0.10, 0.16), Bone.HEAD, col_hair) # side fringe
	_add_box(st, wp[Bone.HEAD] + Vector3(-0.065, 0.14, -0.14), Vector3(0.045, 0.035, 0.02), Bone.HEAD, col_eye)
	_add_box(st, wp[Bone.HEAD] + Vector3(0.065, 0.14, -0.14), Vector3(0.045, 0.035, 0.02), Bone.HEAD, col_eye)

	# Arms (short Hawaiian sleeves + thick arms)
	_add_box(st, wp[Bone.UPPER_ARM_L] + Vector3(0.0, -0.12, 0.0), Vector3(0.14, 0.26, 0.14), Bone.UPPER_ARM_L, col_hawaii_bg)
	_add_box(st, wp[Bone.FOREARM_L] + Vector3(0.0, -0.15, 0.0), Vector3(0.12, 0.30, 0.12), Bone.FOREARM_L, col_skin)
	_add_box(st, wp[Bone.UPPER_ARM_R] + Vector3(0.0, -0.12, 0.0), Vector3(0.14, 0.26, 0.14), Bone.UPPER_ARM_R, col_hawaii_bg)
	_add_box(st, wp[Bone.FOREARM_R] + Vector3(0.0, -0.15, 0.0), Vector3(0.12, 0.30, 0.12), Bone.FOREARM_R, col_skin)

	# Left Leg: Shorts + tall white sock + brown sandal
	_add_box(st, wp[Bone.THIGH_L] + Vector3(0.0, -0.16, 0.0), Vector3(0.19, 0.34, 0.19), Bone.THIGH_L, col_shorts)
	_add_box(st, wp[Bone.THIGH_L] + Vector3(0.0, -0.37, 0.0), Vector3(0.14, 0.10, 0.14), Bone.THIGH_L, col_skin)
	_add_box(st, wp[Bone.SHIN_L] + Vector3(0.0, -0.19, 0.0), Vector3(0.13, 0.36, 0.13), Bone.SHIN_L, col_sock)
	_add_box(st, wp[Bone.SHIN_L] + Vector3(0.0, -0.40, -0.04), Vector3(0.16, 0.06, 0.24), Bone.SHIN_L, col_sandal)

	# Right Leg: Shorts + tall white sock + MISSING SHOE (bare green foot!)
	_add_box(st, wp[Bone.THIGH_R] + Vector3(0.0, -0.16, 0.0), Vector3(0.19, 0.34, 0.19), Bone.THIGH_R, col_shorts)
	_add_box(st, wp[Bone.THIGH_R] + Vector3(0.0, -0.37, 0.0), Vector3(0.14, 0.10, 0.14), Bone.THIGH_R, col_skin)
	_add_box(st, wp[Bone.SHIN_R] + Vector3(0.0, -0.19, 0.0), Vector3(0.13, 0.36, 0.13), Bone.SHIN_R, col_sock)
	_add_box(st, wp[Bone.SHIN_R] + Vector3(0.0, -0.40, -0.04), Vector3(0.13, 0.05, 0.22), Bone.SHIN_R, col_skin)

	st.generate_normals()
	return st.commit()


func _build_female_mesh(wp: Array[Vector3]) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var col_skin := Color(0.45, 0.55, 0.40, 1.0)
	var col_leo_base := Color(0.82, 0.64, 0.24, 1.0)
	var col_leo_spot := Color(0.18, 0.11, 0.06, 1.0)
	var col_skirt := Color(0.14, 0.12, 0.18, 1.0)
	var col_hair := Color(0.24, 0.14, 0.09, 1.0)
	var col_curler1 := Color(0.95, 0.35, 0.68, 1.0)
	var col_curler2 := Color(0.28, 0.78, 0.94, 1.0)
	var col_bag := Color(0.86, 0.16, 0.46, 1.0)
	var col_gold := Color(0.95, 0.80, 0.22, 1.0)
	var col_heel := Color(0.75, 0.12, 0.18, 1.0)
	var col_eye := Color(0.95, 0.28, 0.12, 1.0)

	# Hips / Skirt
	_add_box(st, wp[Bone.HIPS] + Vector3(0.0, 0.00, 0.0), Vector3(0.40, 0.24, 0.26), Bone.HIPS, col_skirt)
	# Leopard-print top with prominent spot patches
	_add_box(st, wp[Bone.SPINE] + Vector3(0.0, 0.12, 0.0), Vector3(0.32, 0.24, 0.22), Bone.SPINE, col_leo_base)
	_add_box(st, wp[Bone.CHEST] + Vector3(0.0, 0.08, 0.0), Vector3(0.38, 0.26, 0.24), Bone.CHEST, col_leo_base)
	for sp: Vector3 in [
		Vector3(-0.10, 0.12, -0.125), Vector3(0.08, 0.05, -0.125),
		Vector3(-0.02, -0.02, -0.125), Vector3(0.11, 0.14, 0.125),
		Vector3(-0.09, 0.04, 0.125),
	]:
		_add_box(st, wp[Bone.CHEST] + sp, Vector3(0.07, 0.06, 0.02), Bone.CHEST, col_leo_spot)

	# Head + eyes
	_add_box(st, wp[Bone.HEAD] + Vector3(0.0, 0.10, -0.01), Vector3(0.23, 0.25, 0.22), Bone.HEAD, col_skin)
	_add_box(st, wp[Bone.HEAD] + Vector3(-0.055, 0.13, -0.125), Vector3(0.04, 0.032, 0.02), Bone.HEAD, col_eye)
	_add_box(st, wp[Bone.HEAD] + Vector3(0.055, 0.13, -0.125), Vector3(0.04, 0.032, 0.02), Bone.HEAD, col_eye)

	# HUGE Beehive Hair (on Hair bone for secondary bounce!) + TWO CURLERS!
	_add_box(st, wp[Bone.HAIR] + Vector3(0.0, 0.08, 0.02), Vector3(0.32, 0.24, 0.30), Bone.HAIR, col_hair)
	_add_box(st, wp[Bone.HAIR] + Vector3(0.0, 0.26, 0.03), Vector3(0.25, 0.20, 0.24), Bone.HAIR, col_hair)
	_add_box(st, wp[Bone.HAIR] + Vector3(0.0, 0.40, 0.04), Vector3(0.16, 0.12, 0.16), Bone.HAIR, col_hair)
	_add_box(st, wp[Bone.HAIR] + Vector3(-0.17, 0.18, -0.05), Vector3(0.11, 0.08, 0.08), Bone.HAIR, col_curler1)
	_add_box(st, wp[Bone.HAIR] + Vector3(0.16, 0.28, -0.02), Vector3(0.11, 0.08, 0.08), Bone.HAIR, col_curler2)

	# Slender Arms
	_add_box(st, wp[Bone.UPPER_ARM_L] + Vector3(0.0, -0.13, 0.0), Vector3(0.10, 0.27, 0.10), Bone.UPPER_ARM_L, col_skin)
	_add_box(st, wp[Bone.FOREARM_L] + Vector3(0.0, -0.14, 0.0), Vector3(0.09, 0.28, 0.09), Bone.FOREARM_L, col_skin)
	_add_box(st, wp[Bone.UPPER_ARM_R] + Vector3(0.0, -0.13, 0.0), Vector3(0.10, 0.27, 0.10), Bone.UPPER_ARM_R, col_skin)
	_add_box(st, wp[Bone.FOREARM_R] + Vector3(0.0, -0.14, 0.0), Vector3(0.09, 0.28, 0.09), Bone.FOREARM_R, col_skin)

	# OVERSIZED HANDBAG on Handbag bone!
	_add_box(st, wp[Bone.HANDBAG] + Vector3(0.0, 0.05, 0.0), Vector3(0.04, 0.16, 0.06), Bone.HANDBAG, col_bag) # strap
	_add_box(st, wp[Bone.HANDBAG] + Vector3(0.02, -0.14, 0.0), Vector3(0.22, 0.30, 0.42), Bone.HANDBAG, col_bag) # giant bag
	_add_box(st, wp[Bone.HANDBAG] + Vector3(0.135, -0.08, 0.0), Vector3(0.02, 0.08, 0.10), Bone.HANDBAG, col_gold) # gold clasp

	# Legs + One Intact Stiletto Heel (Left) & One Broken Heel (Right)
	_add_box(st, wp[Bone.THIGH_L] + Vector3(0.0, -0.20, 0.0), Vector3(0.14, 0.40, 0.14), Bone.THIGH_L, col_skin)
	_add_box(st, wp[Bone.SHIN_L] + Vector3(0.0, -0.19, 0.0), Vector3(0.11, 0.38, 0.11), Bone.SHIN_L, col_skin)
	_add_box(st, wp[Bone.SHIN_L] + Vector3(0.0, -0.39, -0.04), Vector3(0.12, 0.06, 0.22), Bone.SHIN_L, col_heel)
	_add_box(st, wp[Bone.SHIN_L] + Vector3(0.0, -0.43, 0.04), Vector3(0.04, 0.08, 0.04), Bone.SHIN_L, col_heel) # intact heel spike!

	_add_box(st, wp[Bone.THIGH_R] + Vector3(0.0, -0.20, 0.0), Vector3(0.14, 0.40, 0.14), Bone.THIGH_R, col_skin)
	_add_box(st, wp[Bone.SHIN_R] + Vector3(0.0, -0.19, 0.0), Vector3(0.11, 0.38, 0.11), Bone.SHIN_R, col_skin)
	_add_box(st, wp[Bone.SHIN_R] + Vector3(0.0, -0.40, -0.04), Vector3(0.12, 0.05, 0.21), Bone.SHIN_R, col_heel) # broken flat!

	st.generate_normals()
	return st.commit()


func _add_box(st: SurfaceTool, center: Vector3, size: Vector3, bone_idx: int, col: Color) -> void:
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

	for f: Array in [
		[v0, v1, v2, v3], [v5, v4, v7, v6],
		[v4, v0, v3, v7], [v1, v5, v6, v2],
		[v3, v2, v6, v7], [v4, v5, v1, v0],
	]:
		for tri: Array in [[f[0], f[1], f[2]], [f[0], f[2], f[3]]]:
			for v: Vector3 in tri:
				st.set_color(col)
				st.set_bones(bones)
				st.set_weights(weights)
				st.add_vertex(v)


func _build_animation_library() -> AnimationLibrary:
	var lib := AnimationLibrary.new()
	lib.add_animation("idle", _make_idle())
	lib.add_animation("idle_male_pat", _make_idle_male_pat())
	lib.add_animation("idle_female_nails", _make_idle_female_nails())
	lib.add_animation("walk", _make_walk())
	lib.add_animation("attack_male_shove", _make_attack_male_shove())
	lib.add_animation("attack_female_handbag", _make_attack_female_handbag())
	lib.add_animation("hit_react", _make_hit_react())
	lib.add_animation("death_male_collapse", _make_death_male_collapse())
	lib.add_animation("death_female_faint", _make_death_female_faint())
	return lib


func _rot(a: Animation, bone: String, keys: Array) -> void:
	var idx: int = a.add_track(Animation.TYPE_ROTATION_3D)
	a.track_set_path(idx, NodePath("Skeleton3D:" + bone))
	for k: Array in keys:
		var d: Vector3 = k[1]
		a.rotation_track_insert_key(idx, float(k[0]), Quaternion.from_euler(Vector3(deg_to_rad(d.x), deg_to_rad(d.y), deg_to_rad(d.z))))


func _pos(a: Animation, bone: String, keys: Array) -> void:
	var idx: int = a.add_track(Animation.TYPE_POSITION_3D)
	a.track_set_path(idx, NodePath("Skeleton3D:" + bone))
	for k: Array in keys:
		a.position_track_insert_key(idx, float(k[0]), k[1])


func _make_idle() -> Animation:
	var a := Animation.new()
	a.length = 1.6
	a.loop_mode = Animation.LOOP_LINEAR
	_pos(a, "Hips", [[0.0, Vector3(0, 0.88, 0)], [0.8, Vector3(0, 0.85, 0)], [1.6, Vector3(0, 0.88, 0)]])
	_rot(a, "Spine", [[0.0, Vector3(10, 0, 0)], [0.8, Vector3(14, 2, 0)], [1.6, Vector3(10, 0, 0)]])
	_rot(a, "Head", [[0.0, Vector3(-10, -4, 3)], [0.8, Vector3(-8, 5, -4)], [1.6, Vector3(-10, -4, 3)]])
	_rot(a, "UpperArm_L", [[0.0, Vector3(45, 0, 8)], [0.8, Vector3(50, 0, 10)], [1.6, Vector3(45, 0, 8)]])
	_rot(a, "UpperArm_R", [[0.0, Vector3(45, 0, -8)], [0.8, Vector3(50, 0, -10)], [1.6, Vector3(45, 0, -8)]])
	_rot(a, "Hair", [[0.0, Vector3(0, 0, -2)], [0.8, Vector3(2, 0, 2)], [1.6, Vector3(0, 0, -2)]])
	return a


func _make_idle_male_pat() -> Animation:
	# He pats his belly and looks confused
	var a := Animation.new()
	a.length = 1.8
	a.loop_mode = Animation.LOOP_NONE
	_rot(a, "Head", [[0.0, Vector3(-8, 0, 0)], [0.45, Vector3(-12, -16, 12)], [1.2, Vector3(-10, 14, -10)], [1.8, Vector3(-8, 0, 0)]])
	_rot(a, "UpperArm_R", [[0.0, Vector3(45, 0, -8)], [0.35, Vector3(42, 24, 18)], [0.9, Vector3(42, 24, 18)], [1.8, Vector3(45, 0, -8)]])
	_rot(a, "Forearm_R", [[0.0, Vector3(15, 0, 0)], [0.35, Vector3(72, 28, 0)], [0.6, Vector3(56, 28, 0)], [0.85, Vector3(74, 28, 0)], [1.8, Vector3(15, 0, 0)]])
	_pos(a, "Belly", [[0.0, Vector3(0, 0.05, -0.14)], [0.5, Vector3(0, 0.03, -0.12)], [0.75, Vector3(0, 0.06, -0.16)], [1.8, Vector3(0, 0.05, -0.14)]])
	return a


func _make_idle_female_nails() -> Animation:
	# She checks her nails casually
	var a := Animation.new()
	a.length = 1.8
	a.loop_mode = Animation.LOOP_NONE
	_rot(a, "Head", [[0.0, Vector3(-6, 0, 0)], [0.4, Vector3(16, -18, 6)], [1.3, Vector3(14, -14, -4)], [1.8, Vector3(-6, 0, 0)]])
	_rot(a, "UpperArm_L", [[0.0, Vector3(45, 0, 8)], [0.4, Vector3(88, -24, -10)], [1.3, Vector3(84, -20, -10)], [1.8, Vector3(45, 0, 8)]])
	_rot(a, "Forearm_L", [[0.0, Vector3(15, 0, 0)], [0.4, Vector3(68, 0, 0)], [1.3, Vector3(62, 0, 0)], [1.8, Vector3(15, 0, 0)]])
	_rot(a, "Hair", [[0.0, Vector3(0, 0, 0)], [0.6, Vector3(6, 0, -8)], [1.2, Vector3(4, 0, 6)], [1.8, Vector3(0, 0, 0)]])
	return a


func _make_walk() -> Animation:
	# Shared comedy locomotion with hip sway, stiff-legged belly-lead + secondary hair/handbag bounce
	var a := Animation.new()
	a.length = 1.0
	a.loop_mode = Animation.LOOP_LINEAR
	_pos(a, "Hips", [
		[0.0, Vector3(-0.04, 0.88, 0)], [0.25, Vector3(0.0, 0.83, 0)],
		[0.5, Vector3(0.04, 0.86, 0)], [0.75, Vector3(0.0, 0.82, 0)], [1.0, Vector3(-0.04, 0.88, 0)]
	])
	_rot(a, "Hips", [[0.0, Vector3(0, 6, -5)], [0.5, Vector3(0, -6, 7)], [1.0, Vector3(0, 6, -5)]])
	_rot(a, "Spine", [[0.0, Vector3(-6, 6, 4)], [0.5, Vector3(-4, -6, -4)], [1.0, Vector3(-6, 6, 4)]]) # belly-leading lean
	_rot(a, "Chest", [[0.0, Vector3(10, 8, -4)], [0.5, Vector3(10, -8, 4)], [1.0, Vector3(10, 8, -4)]])
	_rot(a, "Head", [[0.0, Vector3(-12, -6, 6)], [0.5, Vector3(-12, 6, -6)], [1.0, Vector3(-12, -6, 6)]])
	_rot(a, "UpperArm_L", [[0.0, Vector3(64, 0, 10)], [0.5, Vector3(80, 0, 6)], [1.0, Vector3(64, 0, 10)]])
	_rot(a, "UpperArm_R", [[0.0, Vector3(78, 0, -8)], [0.5, Vector3(60, 0, -12)], [1.0, Vector3(78, 0, -8)]])
	_rot(a, "Thigh_L", [[0.0, Vector3(28, 0, 0)], [0.5, Vector3(-24, 0, 0)], [1.0, Vector3(28, 0, 0)]])
	_rot(a, "Shin_L", [[0.0, Vector3(-10, 0, 0)], [0.75, Vector3(-38, 0, 0)], [1.0, Vector3(-10, 0, 0)]])
	_rot(a, "Thigh_R", [[0.0, Vector3(-24, 0, 0)], [0.5, Vector3(28, 0, 0)], [1.0, Vector3(-24, 0, 0)]])
	_rot(a, "Shin_R", [[0.0, Vector3(-16, 0, 0)], [0.25, Vector3(-34, 0, 0)], [1.0, Vector3(-16, 0, 0)]])
	_pos(a, "Belly", [[0.0, Vector3(0, 0.06, -0.14)], [0.25, Vector3(0, 0.02, -0.17)], [0.5, Vector3(0, 0.06, -0.14)], [0.75, Vector3(0, 0.02, -0.17)], [1.0, Vector3(0, 0.06, -0.14)]])
	_rot(a, "Hair", [[0.0, Vector3(4, 0, -7)], [0.5, Vector3(-4, 0, 7)], [1.0, Vector3(4, 0, -7)]])
	_rot(a, "Handbag", [[0.0, Vector3(14, 0, -12)], [0.5, Vector3(-16, 0, 12)], [1.0, Vector3(14, 0, -12)]])
	return a


func _make_attack_male_shove() -> Animation:
	# Offended double-handed shove
	var a := Animation.new()
	a.length = 0.62
	a.loop_mode = Animation.LOOP_NONE
	_pos(a, "Hips", [[0.0, Vector3(0, 0.88, 0)], [0.25, Vector3(0, 0.90, 0.08)], [0.44, Vector3(0, 0.85, -0.14)], [0.62, Vector3(0, 0.88, 0)]])
	_rot(a, "Spine", [[0.0, Vector3(6, 0, 0)], [0.25, Vector3(-16, 0, 0)], [0.44, Vector3(26, 0, 0)], [0.62, Vector3(10, 0, 0)]])
	_rot(a, "UpperArm_L", [[0.0, Vector3(60, 0, 10)], [0.25, Vector3(40, 18, 22)], [0.44, Vector3(108, -10, 4)], [0.62, Vector3(60, 0, 10)]])
	_rot(a, "Forearm_L", [[0.0, Vector3(25, 0, 0)], [0.25, Vector3(85, 0, 0)], [0.44, Vector3(5, 0, 0)], [0.62, Vector3(20, 0, 0)]])
	_rot(a, "UpperArm_R", [[0.0, Vector3(60, 0, -10)], [0.25, Vector3(40, -18, -22)], [0.44, Vector3(108, 10, -4)], [0.62, Vector3(60, 0, -10)]])
	_rot(a, "Forearm_R", [[0.0, Vector3(25, 0, 0)], [0.25, Vector3(85, 0, 0)], [0.44, Vector3(5, 0, 0)], [0.62, Vector3(20, 0, 0)]])
	return a


func _make_attack_female_handbag() -> Animation:
	# Dramatic oversized handbag swing
	var a := Animation.new()
	a.length = 0.62
	a.loop_mode = Animation.LOOP_NONE
	_rot(a, "Spine", [[0.0, Vector3(8, 0, 0)], [0.26, Vector3(4, -28, 0)], [0.46, Vector3(20, 32, 0)], [0.62, Vector3(8, 0, 0)]])
	_rot(a, "UpperArm_R", [[0.0, Vector3(55, 0, -10)], [0.26, Vector3(120, -45, -45)], [0.46, Vector3(95, 45, 10)], [0.62, Vector3(55, 0, -10)]])
	_rot(a, "Forearm_R", [[0.0, Vector3(20, 0, 0)], [0.26, Vector3(10, 0, 0)], [0.46, Vector3(25, 0, 0)], [0.62, Vector3(20, 0, 0)]])
	_rot(a, "Handbag", [[0.0, Vector3(0, 0, 0)], [0.26, Vector3(-35, 0, -45)], [0.46, Vector3(55, 0, 20)], [0.62, Vector3(0, 0, 0)]])
	_rot(a, "Hair", [[0.0, Vector3(0, 0, 0)], [0.26, Vector3(0, 0, 12)], [0.46, Vector3(0, 0, -16)], [0.62, Vector3(0, 0, 0)]])
	return a


func _make_hit_react() -> Animation:
	var a := Animation.new()
	a.length = 0.28
	a.loop_mode = Animation.LOOP_NONE
	_rot(a, "Spine", [[0.0, Vector3(10, 0, 0)], [0.10, Vector3(-22, 8, -6)], [0.28, Vector3(10, 0, 0)]])
	_rot(a, "Head", [[0.0, Vector3(-10, 0, 0)], [0.10, Vector3(-34, 14, 0)], [0.28, Vector3(-10, 0, 0)]])
	_rot(a, "Hair", [[0.0, Vector3(0, 0, 0)], [0.10, Vector3(-18, 0, 12)], [0.28, Vector3(0, 0, 0)]])
	return a


func _make_death_male_collapse() -> Animation:
	# Theatrical slow collapse, one arm flung over his face
	var a := Animation.new()
	a.length = 1.05
	a.loop_mode = Animation.LOOP_NONE
	_pos(a, "Hips", [[0.0, Vector3(0, 0.88, 0)], [0.4, Vector3(0, 0.56, 0.14)], [0.8, Vector3(0, 0.22, 0.36)], [1.05, Vector3(0, 0.15, 0.44)]])
	_rot(a, "Hips", [[0.0, Vector3(0, 0, 0)], [0.4, Vector3(-24, 6, 0)], [0.8, Vector3(-78, 10, 4)], [1.05, Vector3(-88, 10, 4)]])
	_rot(a, "UpperArm_R", [[0.0, Vector3(50, 0, -8)], [0.35, Vector3(135, 18, 18)], [1.05, Vector3(128, 22, 22)]])
	_rot(a, "Forearm_R", [[0.0, Vector3(20, 0, 0)], [0.35, Vector3(105, 35, 0)], [1.05, Vector3(105, 35, 0)]]) # flung over face!
	_rot(a, "UpperArm_L", [[0.0, Vector3(50, 0, 8)], [0.7, Vector3(16, 0, 52)], [1.05, Vector3(8, 0, 64)]])
	return a


func _make_death_female_faint() -> Animation:
	# Dramatic faint, hand to the forehead on the way down
	var a := Animation.new()
	a.length = 1.05
	a.loop_mode = Animation.LOOP_NONE
	_pos(a, "Hips", [[0.0, Vector3(0, 0.88, 0)], [0.4, Vector3(0, 0.62, 0.12)], [0.8, Vector3(0, 0.22, 0.36)], [1.05, Vector3(0, 0.14, 0.45)]])
	_rot(a, "Hips", [[0.0, Vector3(0, 0, 0)], [0.4, Vector3(-18, -14, -10)], [0.8, Vector3(-76, -16, -12)], [1.05, Vector3(-88, -16, -12)]])
	_rot(a, "UpperArm_L", [[0.0, Vector3(50, 0, 8)], [0.25, Vector3(145, -18, -16)], [1.05, Vector3(138, -18, -16)]])
	_rot(a, "Forearm_L", [[0.0, Vector3(20, 0, 0)], [0.25, Vector3(112, -25, 0)], [1.05, Vector3(112, -25, 0)]]) # hand to forehead!
	_rot(a, "UpperArm_R", [[0.0, Vector3(50, 0, -8)], [0.7, Vector3(12, 0, -56)], [1.05, Vector3(6, 0, -68)]])
	_rot(a, "Handbag", [[0.0, Vector3(0, 0, 0)], [0.8, Vector3(28, 0, -35)], [1.05, Vector3(36, 0, -45)]])
	return a
