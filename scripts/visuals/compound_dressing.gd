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

var _car_headlight: OmniLight3D = null
var _car_headlight_mat: StandardMaterial3D = null
var _gate_pivot: Node3D = null
var _hanging_lamp: Node3D = null
var _creak_boards: Array[Node3D] = []
var _spark_particles: CPUParticles3D = null
var _spark_light: OmniLight3D = null
var _anim_t: float = 0.0
var _spark_timer: float = 1.8


func _ready() -> void:
	_build_outdoor_ground_and_treeline()
	_build_interior_props()
	_build_yard_farm_clutter()
	_build_phase13_props_and_animated()
	_build_story_signs()


func _process(delta: float) -> void:
	_anim_t += delta
	if _gate_pivot != null:
		_gate_pivot.rotation.y = sin(_anim_t * 0.85) * 0.14 + 0.18
	if _hanging_lamp != null:
		_hanging_lamp.rotation.z = sin(_anim_t * 1.35) * 0.07
		_hanging_lamp.rotation.x = cos(_anim_t * 0.95) * 0.03
	for i: int in range(_creak_boards.size()):
		var b: Node3D = _creak_boards[i]
		if is_instance_valid(b):
			b.rotation.z = sin(_anim_t * (1.7 + float(i) * 0.4)) * 0.025
	if _car_headlight != null and _car_headlight_mat != null:
		var pulse: float = sin(_anim_t * 17.0) * sin(_anim_t * 5.3)
		var on_now: bool = pulse > -0.25
		_car_headlight.light_energy = 1.35 if on_now else 0.15
		_car_headlight_mat.emission_energy_multiplier = 2.4 if on_now else 0.2
	_spark_timer -= delta
	if _spark_timer <= 0.0:
		_spark_timer = 2.4 + fmod(_anim_t * 1.37, 1.8)
		if _spark_particles != null:
			_spark_particles.restart()
			_spark_particles.emitting = true
		if _spark_light != null:
			_spark_light.light_energy = 2.0
	elif _spark_light != null and _spark_light.light_energy > 0.0:
		_spark_light.light_energy = maxf(_spark_light.light_energy - delta * 14.0, 0.0)


func _add_collider_box(parent: Node3D, body_name: String, pos: Vector3, sz: Vector3, surface: String, rot_y: float = 0.0) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.name = body_name
	sb.collision_layer = 1
	sb.collision_mask = 0
	sb.position = pos
	sb.rotation.y = rot_y
	sb.set_meta("surface", surface)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = sz
	cs.shape = shape
	sb.add_child(cs)
	parent.add_child(sb)
	return sb


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


func _build_phase13_props_and_animated() -> void:
	# 1. Crashed Car in west courtyard (clear of SpawnYardLeft at -11,-15 and center lane)
	var car := Node3D.new()
	car.name = "CrashedCar"
	car.position = Vector3(-7.6, 0.0, -15.4)
	car.rotation.y = 0.42
	add_child(car)
	var car_mat := StandardMaterial3D.new()
	car_mat.albedo_color = Color(0.22, 0.27, 0.32, 1.0)
	car_mat.roughness = 0.55
	car_mat.metallic = 0.45
	_add_box(car, Vector3(0.0, 0.55, 0.0), Vector3(1.8, 0.65, 3.8), car_mat)
	_add_box(car, Vector3(0.0, 1.12, -0.2), Vector3(1.55, 0.52, 1.9), car_mat)
	for wx: float in [-0.92, 0.92]:
		for wz: float in [-1.15, 1.15]:
			_add_cyl(car, Vector3(wx, 0.34, wz), 0.34, 0.24, MAT_CONCRETE, Vector3(0.0, 0.0, PI * 0.5))
	_add_collider_box(car, "CrashedCarBody", Vector3(0.0, 0.7, 0.0), Vector3(1.9, 1.4, 3.9), "metal")
	_car_headlight_mat = StandardMaterial3D.new()
	_car_headlight_mat.albedo_color = Color(1.0, 0.92, 0.7)
	_car_headlight_mat.emission_enabled = true
	_car_headlight_mat.emission = Color(1.0, 0.88, 0.55)
	_car_headlight_mat.emission_energy_multiplier = 2.0
	_add_box(car, Vector3(-0.6, 0.58, 1.92), Vector3(0.28, 0.16, 0.06), _car_headlight_mat)
	_add_box(car, Vector3(0.6, 0.58, 1.92), Vector3(0.28, 0.16, 0.06), _car_headlight_mat)
	_car_headlight = OmniLight3D.new()
	_car_headlight.position = Vector3(0.0, 0.65, 2.3)
	_car_headlight.light_color = Color(1.0, 0.9, 0.65)
	_car_headlight.omni_range = 6.5
	_car_headlight.shadow_enabled = false
	car.add_child(_car_headlight)

	# 2. Broken-down Truck in east outer yard (away from spawns/barricades)
	var truck := Node3D.new()
	truck.name = "BrokenTruck"
	truck.position = Vector3(14.5, 0.0, 9.2)
	truck.rotation.y = -0.35
	add_child(truck)
	_add_box(truck, Vector3(0.0, 0.95, 1.2), Vector3(2.0, 1.3, 1.6), MAT_METAL)
	_add_box(truck, Vector3(0.0, 0.75, -1.0), Vector3(2.05, 0.8, 2.8), MAT_WOOD)
	for twx: float in [-1.02, 1.02]:
		for twz: float in [-1.6, 1.2]:
			_add_cyl(truck, Vector3(twx, 0.44, twz), 0.44, 0.28, MAT_CONCRETE, Vector3(0.0, 0.0, PI * 0.5))
	_add_collider_box(truck, "BrokenTruckBody", Vector3(0.0, 0.9, 0.0), Vector3(2.1, 1.8, 4.6), "metal")

	# 3. Concrete Barriers & Sandbag Walls
	for bx: float in [-3.8, 3.8]:
		var bar := Node3D.new()
		bar.name = "ConcreteBarrier"
		bar.position = Vector3(bx, 0.0, -15.6)
		add_child(bar)
		_add_box(bar, Vector3(0.0, 0.45, 0.0), Vector3(2.2, 0.9, 0.55), MAT_CONCRETE)
		_add_collider_box(bar, "ConcreteBarrierCol", Vector3(0.0, 0.45, 0.0), Vector3(2.2, 0.9, 0.55), "concrete")

	for sz_pos: Vector3 in [Vector3(-14.2, 0.0, 8.5), Vector3(-14.2, 0.0, -8.5)]:
		var sb_wall := Node3D.new()
		sb_wall.name = "SandbagWall"
		sb_wall.position = sz_pos
		add_child(sb_wall)
		for row: int in range(3):
			for col: int in range(3):
				_add_box(sb_wall, Vector3(float(col - 1) * 0.65, 0.16 + float(row) * 0.28, 0.0), Vector3(0.6, 0.26, 0.42), MAT_FABRIC, 0.04 * float(row))
		_add_collider_box(sb_wall, "SandbagWallCol", Vector3(0.0, 0.45, 0.0), Vector3(2.0, 0.9, 0.5), "dirt")

	# 4. Yard Wall Segments with Doorway (north-east courtyard)
	var wall_door := Node3D.new()
	wall_door.name = "YardWallDoorway"
	wall_door.position = Vector3(8.5, 0.0, -16.6)
	add_child(wall_door)
	_add_box(wall_door, Vector3(-1.35, 1.2, 0.0), Vector3(1.5, 2.4, 0.35), MAT_CONCRETE)
	_add_box(wall_door, Vector3(1.35, 1.2, 0.0), Vector3(1.5, 2.4, 0.35), MAT_CONCRETE)
	_add_box(wall_door, Vector3(0.0, 2.15, 0.0), Vector3(1.2, 0.5, 0.35), MAT_CONCRETE)
	_add_collider_box(wall_door, "YardWallLeftCol", Vector3(-1.35, 1.2, 0.0), Vector3(1.5, 2.4, 0.35), "concrete")
	_add_collider_box(wall_door, "YardWallRightCol", Vector3(1.35, 1.2, 0.0), Vector3(1.5, 2.4, 0.35), "concrete")

	# 5. Fence with Animated Swinging Gate (north center courtyard edge)
	var fence_gate := Node3D.new()
	fence_gate.name = "YardFenceGate"
	fence_gate.position = Vector3(0.0, 0.0, -16.8)
	add_child(fence_gate)
	_add_box(fence_gate, Vector3(-1.2, 0.6, 0.0), Vector3(0.16, 1.2, 0.16), MAT_WOOD)
	_add_box(fence_gate, Vector3(1.2, 0.6, 0.0), Vector3(0.16, 1.2, 0.16), MAT_WOOD)
	_add_collider_box(fence_gate, "GatePostLeftCol", Vector3(-1.2, 0.6, 0.0), Vector3(0.2, 1.2, 0.2), "wood")
	_add_collider_box(fence_gate, "GatePostRightCol", Vector3(1.2, 0.6, 0.0), Vector3(0.2, 1.2, 0.2), "wood")
	_gate_pivot = Node3D.new()
	_gate_pivot.name = "SwingingGatePivot"
	_gate_pivot.position = Vector3(-1.12, 0.0, 0.0)
	fence_gate.add_child(_gate_pivot)
	_add_box(_gate_pivot, Vector3(1.05, 0.6, 0.0), Vector3(2.1, 0.95, 0.08), MAT_METAL)

	# 6. Creaking loose boards on exterior fence/shed
	for cb_pos: Vector3 in [Vector3(-13.8, 0.9, -16.7), Vector3(13.8, 0.9, -16.7)]:
		var cb := Node3D.new()
		cb.name = "CreakingBoard"
		cb.position = cb_pos
		add_child(cb)
		_add_box(cb, Vector3(0.0, -0.25, 0.0), Vector3(0.18, 0.7, 0.05), MAT_WOOD)
		_creak_boards.append(cb)

	# 7. Sparking Electric Box on StartRoom west wall
	var ebox := Node3D.new()
	ebox.name = "ElectricBox"
	ebox.position = Vector3(-5.72, 1.5, 2.2)
	add_child(ebox)
	_add_box(ebox, Vector3(0.0, 0.0, 0.0), Vector3(0.18, 0.55, 0.42), MAT_METAL)
	_add_collider_box(ebox, "ElectricBoxCol", Vector3(0.0, 0.0, 0.0), Vector3(0.2, 0.55, 0.42), "metal")
	_spark_particles = CPUParticles3D.new()
	_spark_particles.emitting = false
	_spark_particles.one_shot = true
	_spark_particles.explosiveness = 1.0
	_spark_particles.amount = 6
	_spark_particles.lifetime = 0.25
	_spark_particles.direction = Vector3(1.0, 0.2, 0.0)
	_spark_particles.spread = 50.0
	_spark_particles.initial_velocity_min = 1.5
	_spark_particles.initial_velocity_max = 3.5
	var sp_mat := StandardMaterial3D.new()
	sp_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sp_mat.albedo_color = Color(1.0, 0.85, 0.3)
	var sp_mesh := SphereMesh.new()
	sp_mesh.radius = 0.02
	sp_mesh.height = 0.04
	sp_mesh.material = sp_mat
	_spark_particles.mesh = sp_mesh
	ebox.add_child(_spark_particles)
	_spark_light = OmniLight3D.new()
	_spark_light.light_color = Color(0.75, 0.88, 1.0)
	_spark_light.light_energy = 0.0
	_spark_light.omni_range = 3.5
	_spark_light.shadow_enabled = false
	ebox.add_child(_spark_light)

	# 8. Swaying Hanging Lamp in HallRoom
	_hanging_lamp = Node3D.new()
	_hanging_lamp.name = "HangingLamp"
	_hanging_lamp.position = Vector3(0.0, 3.5, -6.0)
	add_child(_hanging_lamp)
	_add_cyl(_hanging_lamp, Vector3(0.0, -0.35, 0.0), 0.02, 0.7, MAT_METAL)
	_add_cyl(_hanging_lamp, Vector3(0.0, -0.75, 0.0), 0.22, 0.18, MAT_METAL)
	var bulb_mat := StandardMaterial3D.new()
	bulb_mat.albedo_color = Color(1.0, 0.92, 0.72)
	bulb_mat.emission_enabled = true
	bulb_mat.emission = Color(1.0, 0.88, 0.62)
	bulb_mat.emission_energy_multiplier = 2.0
	_add_cyl(_hanging_lamp, Vector3(0.0, -0.84, 0.0), 0.08, 0.1, bulb_mat)


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
