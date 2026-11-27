class_name ImpactEffect
extends CPUParticles3D
## Self-freeing surface-aware hit impact particle burst with hard caps on
## active bursts, surface/blood decals (recycled at cap), and procedural SFX.

const MAX_BURSTS_HIGH: int = 16
const MAX_BURSTS_LOW: int = 8
const MAX_SPLATS_HIGH: int = 40
const MAX_SPLATS_LOW: int = 20

const SURFACES := ["concrete", "wood", "metal", "dirt", "flesh"]
const SURFACE_PROFILES := {
	"concrete": {"color": Color(0.74, 0.72, 0.68), "decal": Color(0.14, 0.14, 0.14, 0.85), "size": 0.025, "count": 6, "life": 0.24, "vmin": 1.8, "vmax": 4.2, "grav": -9.8, "freq": 280.0, "noise": 0.75},
	"wood": {"color": Color(0.62, 0.43, 0.22), "decal": Color(0.22, 0.13, 0.06, 0.88), "size": 0.030, "count": 7, "life": 0.28, "vmin": 2.0, "vmax": 4.8, "grav": -11.0, "freq": 190.0, "noise": 0.55},
	"metal": {"color": Color(1.0, 0.76, 0.25), "decal": Color(0.08, 0.08, 0.10, 0.90), "size": 0.020, "count": 9, "life": 0.20, "vmin": 3.5, "vmax": 7.5, "grav": -6.5, "freq": 1180.0, "noise": 0.20},
	"dirt": {"color": Color(0.36, 0.28, 0.18), "decal": Color(0.16, 0.12, 0.08, 0.82), "size": 0.032, "count": 7, "life": 0.30, "vmin": 1.6, "vmax": 3.8, "grav": -12.0, "freq": 135.0, "noise": 0.85},
	"flesh": {"color": Color(0.55, 0.04, 0.04), "decal": Color(0.28, 0.02, 0.02, 0.90), "size": 0.038, "count": 10, "life": 0.28, "vmin": 1.8, "vmax": 4.6, "grav": -9.8, "freq": 160.0, "noise": 0.65},
}

static var _active_bursts: Array[ImpactEffect] = []
static var _floor_splats: Array[MeshInstance3D] = []
static var _low_quality: bool = false
static var _rng := RandomNumberGenerator.new()
static var _surface_sounds: Dictionary = {}

var surface_type: String = "concrete"


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
	_surface_sounds.clear()


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


static func classify_surface(collider: Object) -> String:
	if collider == null:
		return "concrete"
	if collider is Hitbox:
		return "flesh"
	if collider is Node:
		var n := collider as Node
		if n.has_meta("surface"):
			var ms: String = str(n.get_meta("surface")).to_lower()
			if SURFACES.has(ms):
				return ms
		var cur: Node = n
		for _depth: int in range(3):
			if cur == null:
				break
			var nm: String = cur.name.to_lower()
			if nm.contains("car") or nm.contains("truck") or nm.contains("metal") or nm.contains("gate") or nm.contains("door") or nm.contains("box") or nm.contains("perk") or nm.contains("forge") or nm.contains("electric") or nm.contains("lamp"):
				return "metal"
			if nm.contains("wood") or nm.contains("barricade") or nm.contains("crate") or nm.contains("fence") or nm.contains("board") or nm.contains("table"):
				return "wood"
			if nm.contains("dirt") or nm.contains("sandbag") or nm.contains("yard") or nm.contains("grass") or nm.contains("tree"):
				return "dirt"
			cur = cur.get_parent()
	return "concrete"


static func spawn(parent: Node, world_pos: Vector3, normal: Vector3, is_target_hit: bool) -> ImpactEffect:
	return spawn_surface(parent, world_pos, normal, "flesh" if is_target_hit else "concrete")


static func spawn_surface(parent: Node, world_pos: Vector3, normal: Vector3, surface: String) -> ImpactEffect:
	var surf: String = surface.to_lower()
	if not SURFACE_PROFILES.has(surf):
		surf = "concrete"
	var prof: Dictionary = SURFACE_PROFILES[surf]

	_prune_invalid_bursts()
	var burst_cap: int = get_burst_cap()
	while _active_bursts.size() >= burst_cap:
		var oldest: ImpactEffect = _active_bursts.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()

	var fx := ImpactEffect.new()
	fx.surface_type = surf
	parent.add_child(fx)
	fx.global_position = world_pos + normal * 0.02
	_active_bursts.append(fx)

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = prof["color"]

	var quad := SphereMesh.new()
	quad.radius = float(prof["size"])
	quad.height = quad.radius * 2.0
	quad.material = mat

	fx.mesh = quad
	var base_amt: int = int(prof["count"])
	fx.amount = maxi(base_amt / 2, 2) if _low_quality else base_amt
	fx.lifetime = float(prof["life"])
	fx.one_shot = true
	fx.explosiveness = 1.0
	fx.direction = normal if normal.length_squared() > 0.001 else Vector3.UP
	fx.spread = 55.0 if surf == "metal" else 45.0
	fx.initial_velocity_min = float(prof["vmin"])
	fx.initial_velocity_max = float(prof["vmax"])
	fx.gravity = Vector3(0.0, float(prof["grav"]), 0.0)
	fx.finished.connect(func() -> void:
		_active_bursts.erase(fx)
		if is_instance_valid(fx):
			fx.queue_free()
	)
	fx.emitting = true

	if surf == "flesh":
		_spawn_floor_splat(parent, world_pos, prof["decal"])
	else:
		_spawn_surface_decal(parent, world_pos, normal, prof["decal"], surf)

	if DisplayServer.get_name() != "headless":
		_play_surface_sound(parent, world_pos, surf)

	return fx


static func get_surface_sound(surface: String) -> AudioStreamWAV:
	var surf: String = surface.to_lower()
	if not SURFACE_PROFILES.has(surf):
		surf = "concrete"
	if _surface_sounds.has(surf):
		return _surface_sounds[surf] as AudioStreamWAV
	var prof: Dictionary = SURFACE_PROFILES[surf]
	var freq: float = float(prof["freq"])
	var noise_mix: float = float(prof["noise"])
	var sample_rate: int = 22050
	var dur: float = 0.09 if surf != "metal" else 0.14
	var samples: int = int(float(sample_rate) * dur)
	var buf := PackedByteArray()
	buf.resize(samples * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = surf.hash()
	for i: int in range(samples):
		var t: float = float(i) / float(sample_rate)
		var env: float = exp(-t * (28.0 if surf == "metal" else 42.0))
		var tone: float = sin(TAU * freq * t) * (1.0 - noise_mix)
		var nz: float = rng.randf_range(-1.0, 1.0) * noise_mix
		var s: int = clampi(int((tone + nz) * env * 0.45 * 32767.0), -32768, 32767)
		buf.encode_s16(i * 2, s)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sample_rate
	wav.data = buf
	_surface_sounds[surf] = wav
	return wav


static func _play_surface_sound(parent: Node, world_pos: Vector3, surf: String) -> void:
	var asp := AudioStreamPlayer3D.new()
	asp.bus = &"SFX"
	asp.max_distance = 18.0
	asp.unit_size = 2.0
	asp.volume_db = -8.0
	asp.stream = get_surface_sound(surf)
	parent.add_child(asp)
	asp.global_position = world_pos
	asp.finished.connect(func() -> void:
		if is_instance_valid(asp):
			asp.queue_free()
	)
	asp.play()


static func _spawn_floor_splat(parent: Node, world_pos: Vector3, col: Color = Color(0.28, 0.02, 0.02, 0.9)) -> void:
	var splat := _acquire_decal_node(parent)
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.26
	mesh.bottom_radius = 0.26
	mesh.height = 0.012
	mesh.radial_segments = 8
	mesh.rings = 1
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 0.35
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = mat
	splat.mesh = mesh

	var jitter_x: float = _rng.randf_range(-0.22, 0.22)
	var jitter_z: float = _rng.randf_range(-0.22, 0.22)
	var s_scale: float = _rng.randf_range(0.75, 1.35)
	splat.global_position = Vector3(world_pos.x + jitter_x, 0.012, world_pos.z + jitter_z)
	splat.rotation = Vector3(0.0, _rng.randf_range(0.0, TAU), 0.0)
	splat.scale = Vector3(s_scale, 1.0, s_scale * _rng.randf_range(0.8, 1.25))
	_floor_splats.append(splat)


static func _spawn_surface_decal(parent: Node, world_pos: Vector3, normal: Vector3, col: Color, surf: String) -> void:
	var decal := _acquire_decal_node(parent)
	var mesh := CylinderMesh.new()
	var rad: float = 0.055 if surf == "wood" else (0.045 if surf == "metal" else 0.06)
	mesh.top_radius = rad
	mesh.bottom_radius = rad
	mesh.height = 0.008
	mesh.radial_segments = 6
	mesh.rings = 1
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 0.85
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = mat
	decal.mesh = mesh

	var n: Vector3 = normal.normalized() if normal.length_squared() > 0.001 else Vector3.UP
	decal.global_position = world_pos + n * 0.008
	if absf(n.dot(Vector3.UP)) < 0.99:
		decal.look_at(world_pos + n + Vector3.UP * 0.001, Vector3.UP)
		decal.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	else:
		decal.rotation = Vector3.ZERO
	decal.scale = Vector3.ONE
	_floor_splats.append(decal)


static func _acquire_decal_node(parent: Node) -> MeshInstance3D:
	_prune_invalid_splats()
	var splat_cap: int = get_splat_cap()
	var splat: MeshInstance3D = null
	if _floor_splats.size() >= splat_cap:
		splat = _floor_splats.pop_front()
		if not is_instance_valid(splat):
			splat = null
	if splat == null:
		splat = MeshInstance3D.new()
		splat.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(splat)
	return splat
