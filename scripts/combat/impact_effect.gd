class_name ImpactEffect
extends CPUParticles3D
## Self-freeing hit impact particle burst with hard caps on active bursts
## and persistent floor blood splats (recycles oldest at cap).

const MAX_BURSTS_HIGH: int = 16
const MAX_BURSTS_LOW: int = 8
const MAX_SPLATS_HIGH: int = 40
const MAX_SPLATS_LOW: int = 20

static var _active_bursts: Array[ImpactEffect] = []
static var _floor_splats: Array[MeshInstance3D] = []
static var _low_quality: bool = false
static var _rng := RandomNumberGenerator.new()


static func set_low_quality(low: bool) -> void:
	_low_quality = low
	var splat_cap: int = get_splat_cap()
	while _floor_splats.size() > splat_cap:
		var old: MeshInstance3D = _floor_splats.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	var burst_cap: int = get_burst_cap()
	while _active_bursts.size() > burst_cap:
		var old_b: ImpactEffect = _active_bursts.pop_front()
		if is_instance_valid(old_b):
			old_b.queue_free()


static func get_burst_cap() -> int:
	return MAX_BURSTS_LOW if _low_quality else MAX_BURSTS_HIGH


static func get_splat_cap() -> int:
	return MAX_SPLATS_LOW if _low_quality else MAX_SPLATS_HIGH


static func get_active_burst_count() -> int:
	_prune_invalid_bursts()
	return _active_bursts.size()


static func get_active_splat_count() -> int:
	_prune_invalid_splats()
	return _floor_splats.size()


static func clear_all() -> void:
	for b: ImpactEffect in _active_bursts:
		if is_instance_valid(b):
			b.queue_free()
	_active_bursts.clear()
	for s: MeshInstance3D in _floor_splats:
		if is_instance_valid(s):
			s.queue_free()
	_floor_splats.clear()


static func _prune_invalid_bursts() -> void:
	var valid: Array[ImpactEffect] = []
	for b: ImpactEffect in _active_bursts:
		if is_instance_valid(b) and not b.is_queued_for_deletion():
			valid.append(b)
	_active_bursts = valid


static func _prune_invalid_splats() -> void:
	var valid: Array[MeshInstance3D] = []
	for s: MeshInstance3D in _floor_splats:
		if is_instance_valid(s) and not s.is_queued_for_deletion():
			valid.append(s)
	_floor_splats = valid


static func spawn(parent: Node, world_pos: Vector3, normal: Vector3, is_target_hit: bool) -> ImpactEffect:
	_prune_invalid_bursts()
	var burst_cap: int = get_burst_cap()
	while _active_bursts.size() >= burst_cap:
		var oldest: ImpactEffect = _active_bursts.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()

	var fx := ImpactEffect.new()
	parent.add_child(fx)
	fx.global_position = world_pos + normal * 0.02
	_active_bursts.append(fx)

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.55, 0.04, 0.04) if is_target_hit else Color(0.75, 0.72, 0.65)

	var quad := SphereMesh.new()
	quad.radius = 0.038 if is_target_hit else 0.025
	quad.height = quad.radius * 2.0
	quad.material = mat

	fx.mesh = quad
	var base_amt: int = 10 if is_target_hit else 6
	fx.amount = maxi(base_amt / 2, 2) if _low_quality else base_amt
	fx.lifetime = 0.28 if is_target_hit else 0.24
	fx.one_shot = true
	fx.explosiveness = 1.0
	fx.direction = normal if normal.length_squared() > 0.001 else Vector3.UP
	fx.spread = 48.0
	fx.initial_velocity_min = 1.8
	fx.initial_velocity_max = 4.6
	fx.gravity = Vector3(0.0, -9.8, 0.0)
	fx.finished.connect(func() -> void:
		_active_bursts.erase(fx)
		if is_instance_valid(fx):
			fx.queue_free()
	)
	fx.emitting = true

	if is_target_hit:
		_spawn_floor_splat(parent, world_pos)

	return fx


static func _spawn_floor_splat(parent: Node, world_pos: Vector3) -> void:
	_prune_invalid_splats()
	var splat_cap: int = get_splat_cap()
	var splat: MeshInstance3D = null
	if _floor_splats.size() >= splat_cap:
		splat = _floor_splats.pop_front()
		if not is_instance_valid(splat):
			splat = null

	if splat == null:
		splat = MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.26
		mesh.bottom_radius = 0.26
		mesh.height = 0.012
		mesh.radial_segments = 8
		mesh.rings = 1
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.28, 0.02, 0.02, 0.9)
		mat.roughness = 0.35
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mesh.material = mat
		splat.mesh = mesh
		splat.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(splat)

	var jitter_x: float = _rng.randf_range(-0.22, 0.22)
	var jitter_z: float = _rng.randf_range(-0.22, 0.22)
	var s_scale: float = _rng.randf_range(0.75, 1.35)
	splat.global_position = Vector3(world_pos.x + jitter_x, 0.012, world_pos.z + jitter_z)
	splat.scale = Vector3(s_scale, 1.0, s_scale * _rng.randf_range(0.8, 1.25))
	splat.rotation.y = _rng.randf_range(0.0, TAU)
	_floor_splats.append(splat)
