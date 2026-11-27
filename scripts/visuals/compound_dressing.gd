class_name CompoundDressing
extends Node3D
## Deliberately placed primitive props, signs, outdoor farm yard ground/clutter,
## and distant tree-line MultiMesh silhouette. Non-blocking (no StaticBody3D
## inside NavRegion) so navigation paths are never obstructed.

const MAT_WOOD := preload("res://resources/materials/mat_worn_wood.tres")
const MAT_CONCRETE := preload("res://resources/materials/mat_concrete.tres")
const MAT_METAL := preload("res://resources/materials/mat_rusted_metal.tres")
const MAT_DIRT := preload("res://resources/materials/mat_dirt_grass.tres")
const MAT_FABRIC := preload("res://resources/materials/mat_fabric.tres")


func _ready() -> void:
	_build_outdoor_ground_and_treeline()
	_build_interior_props()
	_build_yard_farm_clutter()
	_build_story_signs()


func _add_box(parent: Node3D, pos: Vector3, sz: Vector3, mat: Material, rot_y: float = 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = sz
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation.y = rot_y
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _add_cyl(parent: Node3D, pos: Vector3, r: float, h: float, mat: Material, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = r
	mesh.bottom_radius = r
	mesh.height = h
	mesh.radial_segments = 10
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _build_outdoor_ground_and_treeline() -> void:
	# Outer rural night ground beyond the ±18m perimeter walls
	_add_box(self, Vector3(0.0, -0.02, 0.0), Vector3(140.0, 0.02, 140.0), MAT_DIRT)
	# Courtyard & outer yard dirt/grass overlay inside ±18m (outside interior [-6..6, -12..12])
	_add_box(self, Vector3(0.0, 0.008, -15.0), Vector3(35.6, 0.01, 5.8), MAT_DIRT)
	_add_box(self, Vector3(-12.1, 0.008, 0.0), Vector3(11.6, 0.01, 24.4), MAT_DIRT)
	_add_box(self, Vector3(12.1, 0.008, 0.0), Vector3(11.6, 0.01, 24.4), MAT_DIRT)
	_add_box(self, Vector3(0.0, 0.008, 15.2), Vector3(35.6, 0.01, 5.4), MAT_DIRT)

	# Darker grass patches
	var grass_mat := StandardMaterial3D.new()
	grass_mat.albedo_color = Color(0.09, 0.14, 0.08, 1.0)
	grass_mat.roughness = 0.96
	for gp: Vector3 in [
		Vector3(-11.0, 0.015, -15.0), Vector3(10.5, 0.015, -14.5),
		Vector3(-13.5, 0.015, 4.0), Vector3(13.0, 0.015, -3.5),
		Vector3(-11.5, 0.015, 13.5), Vector3(12.0, 0.015, 14.0),
	]:
		_add_box(self, gp, Vector3(4.2, 0.01, 3.6), grass_mat, 0.35)

	# A few simple primitive trees in the outer yard (away from spawn lanes)
	var trunk_mat := MAT_WOOD
	var leaf_mat := StandardMaterial3D.new()
	leaf_mat.albedo_color = Color(0.06, 0.11, 0.07, 1.0)
	leaf_mat.roughness = 0.95
	for tp: Vector3 in [
		Vector3(-15.5, 0.0, -15.5), Vector3(15.5, 0.0, -15.5),
		Vector3(-15.8, 0.0, 14.5), Vector3(15.8, 0.0, 14.5),
		Vector3(-16.0, 0.0, -2.0), Vector3(16.0, 0.0, 1.5),
	]:
		_add_cyl(self, tp + Vector3(0.0, 1.8, 0.0), 0.22, 3.6, trunk_mat)
		var crown := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.15
		cone.bottom_radius = 1.45
		cone.height = 3.8
		cone.radial_segments = 8
		crown.mesh = cone
		crown.material_override = leaf_mat
		crown.position = tp + Vector3(0.0, 4.5, 0.0)
		crown.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(crown)

	# Distant tree-line silhouette ring via MultiMeshInstance3D (48 trees, 1 draw call)
	var mm_inst := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	var tree_mesh := CylinderMesh.new()
	tree_mesh.top_radius = 0.3
	tree_mesh.bottom_radius = 2.6
	tree_mesh.height = 11.0
	tree_mesh.radial_segments = 6
	var sil_mat := StandardMaterial3D.new()
	sil_mat.albedo_color = Color(0.025, 0.035, 0.035, 1.0)
	sil_mat.roughness = 1.0
	tree_mesh.material = sil_mat
	mm.mesh = tree_mesh
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = 48
	var rng := RandomNumberGenerator.new()
	rng.seed = 1010
	for i: int in range(48):
		var angle: float = (float(i) / 48.0) * TAU + rng.randf_range(-0.04, 0.04)
		var rad: float = rng.randf_range(34.0, 46.0)
		var h_scale: float = rng.randf_range(0.8, 1.45)
		var pos := Vector3(cos(angle) * rad, 5.2 * h_scale, sin(angle) * rad)
		var xform := Transform3D(Basis.from_scale(Vector3(1.0, h_scale, 1.0)), pos)
		mm.set_instance_transform(i, xform)
	mm_inst.multimesh = mm
	mm_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mm_inst)


func _build_interior_props() -> void:
	# StartRoom corners: crates, table, shelf, fabric tarp
	_add_box(self, Vector3(-4.9, 0.4, 10.8), Vector3(0.9, 0.8, 0.9), MAT_WOOD, 0.15)
	_add_box(self, Vector3(-4.8, 1.15, 10.7), Vector3(0.7, 0.7, 0.7), MAT_WOOD, -0.2)
	_add_box(self, Vector3(-4.8, 0.82, 10.7), Vector3(0.85, 0.04, 0.85), MAT_FABRIC, 0.1)
	_add_cyl(self, Vector3(4.9, 0.5, 10.9), 0.32, 1.0, MAT_METAL)
	_add_cyl(self, Vector3(4.2, 0.5, 11.1), 0.32, 1.0, MAT_METAL)
	# Table near south wall (out of center path)
	_add_box(self, Vector3(2.8, 0.75, 11.2), Vector3(1.6, 0.08, 0.8), MAT_WOOD)
	_add_box(self, Vector3(2.1, 0.37, 10.9), Vector3(0.08, 0.74, 0.08), MAT_WOOD)
	_add_box(self, Vector3(3.5, 0.37, 10.9), Vector3(0.08, 0.74, 0.08), MAT_WOOD)
	# Shelf in HallRoom corner
	_add_box(self, Vector3(-5.1, 0.9, -1.6), Vector3(0.5, 1.8, 1.4), MAT_METAL)
	_add_box(self, Vector3(-5.0, 1.2, -1.6), Vector3(0.4, 0.35, 0.5), MAT_WOOD)
	_add_cyl(self, Vector3(5.0, 0.5, -10.8), 0.32, 1.0, MAT_METAL)
	_add_box(self, Vector3(4.3, 0.35, -11.0), Vector3(0.75, 0.7, 0.75), MAT_WOOD, 0.3)


func _build_yard_farm_clutter() -> void:
	var hay_mat := StandardMaterial3D.new()
	hay_mat.albedo_color = Color(0.46, 0.38, 0.16, 1.0)
	hay_mat.roughness = 0.95

	# Hay bales in courtyard corners
	_add_box(self, Vector3(-13.5, 0.45, -15.5), Vector3(1.4, 0.9, 0.9), hay_mat, 0.2)
	_add_box(self, Vector3(-12.2, 0.45, -16.2), Vector3(1.4, 0.9, 0.9), hay_mat, -0.1)
	_add_box(self, Vector3(-12.9, 1.35, -15.8), Vector3(1.3, 0.9, 0.85), hay_mat, 0.05)

	# Fence segments along courtyard edge
	for fx: float in [-14.0, -11.0, -8.0, 8.0, 11.0, 14.0]:
		_add_box(self, Vector3(fx, 0.55, -16.8), Vector3(0.14, 1.1, 0.14), MAT_WOOD)
		_add_box(self, Vector3(fx + 1.5, 0.85, -16.8), Vector3(2.9, 0.1, 0.08), MAT_WOOD)
		_add_box(self, Vector3(fx + 1.5, 0.45, -16.8), Vector3(2.9, 0.1, 0.08), MAT_WOOD)

	# Broken tractor silhouette in east yard (x=12.5, z=-15.5)
	var tractor := Node3D.new()
	tractor.position = Vector3(12.5, 0.0, -15.5)
	tractor.rotation.y = -0.45
	add_child(tractor)
	_add_box(tractor, Vector3(0.0, 0.85, 0.0), Vector3(1.3, 0.9, 2.4), MAT_METAL)
	_add_box(tractor, Vector3(0.0, 1.55, 0.55), Vector3(1.1, 0.8, 0.9), MAT_METAL)
	_add_cyl(tractor, Vector3(-0.75, 0.6, 0.6), 0.6, 0.35, MAT_CONCRETE, Vector3(0.0, 0.0, PI * 0.5))
	_add_cyl(tractor, Vector3(0.75, 0.6, 0.6), 0.6, 0.35, MAT_CONCRETE, Vector3(0.0, 0.0, PI * 0.5))
	_add_cyl(tractor, Vector3(-0.65, 0.38, -0.85), 0.38, 0.28, MAT_CONCRETE, Vector3(0.0, 0.0, PI * 0.5))
	_add_cyl(tractor, Vector3(0.65, 0.38, -0.85), 0.38, 0.28, MAT_CONCRETE, Vector3(0.0, 0.0, PI * 0.5))
	_add_cyl(tractor, Vector3(0.35, 1.55, -0.8), 0.07, 0.7, MAT_METAL)


func _build_story_signs() -> void:
	_add_sign(Vector3(0.0, 2.55, 0.22), "LOCKED: HALLWAY", Color(0.95, 0.75, 0.45))
	_add_sign(Vector3(-4.2, 1.9, 11.95), "BOARD WINDOWS. HOLD THE LINE.", Color(0.9, 0.88, 0.82), PI)
	_add_sign(Vector3(0.0, 2.55, -11.78), "COURTYARD -> POWER & PERKS", Color(0.85, 0.92, 1.0))
	_add_sign(Vector3(5.75, 1.8, -6.0), "DON'T GO OUT PAST DUSK", Color(0.95, 0.45, 0.38), -PI * 0.5)


func _add_sign(pos: Vector3, text: String, col: Color, rot_y: float = 0.0) -> void:
	var lbl := Label3D.new()
	lbl.position = pos
	lbl.rotation.y = rot_y
	lbl.text = text
	lbl.font_size = 28
	lbl.modulate = col
	lbl.outline_modulate = Color(0.02, 0.02, 0.03, 1.0)
	lbl.outline_size = 6
	add_child(lbl)
