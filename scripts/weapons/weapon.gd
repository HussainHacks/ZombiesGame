class_name Weapon
extends Node
## Handles firing cadence, hitscan raycasting with spread/bloom, range cutoff,
## pellet handling, reload state machine, and ADS state for the active weapon.

signal fired(recoil_pitch: float, recoil_yaw: float)
signal hit_landed(is_headshot: bool, is_kill: bool)
signal ammo_changed(mag_ammo: int, reserve_ammo: int)
signal reload_started(duration: float)
signal reload_finished
signal reload_cancelled

var data: WeaponData
var mag_ammo: int = 0
var reserve_ammo: int = 0
var player_stats: PlayerStats = null
var damage_bonus_mult: float = 1.0
var headshot_bonus_mult: float = 1.0
var mag_size_mult: float = 1.0
var reserve_size_mult: float = 1.0
var fire_rate_mult: float = 1.0

var is_reloading: bool = false
var is_aiming: bool = false

var _fire_cooldown: float = 0.0
var _reload_timer: float = 0.0
var _current_bloom: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()


func setup(weapon_data: WeaponData, initial_mag: int, initial_reserve: int) -> void:
	data = weapon_data
	mag_ammo = clampi(initial_mag, 0, get_effective_magazine_size())
	reserve_ammo = clampi(initial_reserve, 0, get_effective_reserve_max())
	is_reloading = false
	is_aiming = false
	_fire_cooldown = 0.0
	_reload_timer = 0.0
	_current_bloom = 0.0
	ammo_changed.emit(mag_ammo, reserve_ammo)


func get_effective_magazine_size() -> int:
	if data == null:
		return 0
	return maxi(roundi(float(data.magazine_size) * mag_size_mult), 1)


func get_effective_reserve_max() -> int:
	if data == null:
		return 0
	return maxi(roundi(float(data.reserve_ammo_max) * reserve_size_mult), 0)


func tick(delta: float) -> void:
	if _fire_cooldown > 0.0:
		_fire_cooldown = maxf(_fire_cooldown - delta, 0.0)

	if data != null and _current_bloom > 0.0:
		var handling: float = player_stats.get_stat(&"weapon_handling") if player_stats != null else 1.0
		_current_bloom = maxf(_current_bloom - data.spread_recovery_rate * handling * delta, 0.0)

	if is_reloading:
		_reload_timer -= delta
		if _reload_timer <= 0.0:
			_complete_reload()


func can_fire() -> bool:
	if data == null or is_reloading:
		return false
	return _fire_cooldown <= 0.0 and mag_ammo > 0


func get_current_spread_degrees() -> float:
	if data == null:
		return 0.0
	var handling: float = player_stats.get_stat(&"weapon_handling") if player_stats != null else 1.0
	var base: float = data.spread_aim if is_aiming else data.spread_hip
	return minf(base + _current_bloom, data.spread_max) / maxf(handling, 0.1)


func try_fire(camera: Camera3D, space_state: PhysicsDirectSpaceState3D, exclude_rids: Array[RID], owner_node: Node, fx_parent: Node = null) -> bool:
	if data == null or is_reloading:
		return false
	if _fire_cooldown > 0.0:
		return false

	if mag_ammo <= 0:
		if reserve_ammo > 0:
			start_reload()
		elif is_inside_tree():
			var ge: Node = get_node_or_null("/root/GameEvents")
			if ge != null:
				ge.emit_signal("out_of_ammo", data)
		return false

	mag_ammo -= 1
	_fire_cooldown = data.get_shot_interval() / maxf(fire_rate_mult, 0.1)
	ammo_changed.emit(mag_ammo, reserve_ammo)

	var spread_deg: float = get_current_spread_degrees()
	_current_bloom = minf(_current_bloom + data.spread_per_shot, data.spread_max)

	var any_headshot: bool = false
	var any_kill: bool = false
	var any_hit: bool = false

	if camera != null and space_state != null:
		var origin: Vector3 = camera.global_position
		var forward: Vector3 = -camera.global_transform.basis.z
		var right: Vector3 = camera.global_transform.basis.x
		var up: Vector3 = camera.global_transform.basis.y

		for _i: int in range(maxi(data.pellet_count, 1)):
			var ray_dir: Vector3 = _apply_spread(forward, right, up, spread_deg)
			var max_hits: int = 1 + maxi(data.pierce_count, 0)
			var ray_origin: Vector3 = origin
			var ray_end: Vector3 = origin + ray_dir * data.range
			var ray_excludes: Array[RID] = exclude_rids.duplicate()
			var hit_targets: Array[HealthComponent] = []
			var pierce_idx: int = 0

			for _h: int in range(max_hits):
				if ray_origin.distance_to(origin) >= data.range:
					break
				var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end, 9, ray_excludes)
				query.collide_with_areas = true
				query.collide_with_bodies = true
				var result: Dictionary = space_state.intersect_ray(query)
				if result.is_empty():
					break

				var collider: Object = result["collider"]
				var hit_pos: Vector3 = result["position"]
				var hit_normal: Vector3 = result["normal"]
				var is_target: bool = collider is Hitbox
				if fx_parent != null:
					var surf: String = ImpactEffect.classify_surface(collider)
					ImpactEffect.spawn_surface(fx_parent, hit_pos, hit_normal, surf)

				if not is_target:
					break

				var hitbox := collider as Hitbox
				ray_excludes.append(hitbox.get_rid())
				var hc: HealthComponent = hitbox.health_component
				if hc != null and not hit_targets.has(hc):
					hit_targets.append(hc)
					var dmg_mult: float = pow(data.pierce_damage_falloff, pierce_idx) * damage_bonus_mult * (player_stats.get_stat(&"damage_multiplier") if player_stats != null else 1.0)
					var eff_hs_mult: float = data.headshot_multiplier * headshot_bonus_mult * (player_stats.get_stat(&"headshot_bonus") if player_stats != null else 1.0)
					var hit_res: Dictionary = hitbox.apply_hit(data.damage * dmg_mult, eff_hs_mult, owner_node)
					if hit_res.get("applied", 0.0) > 0.0:
						any_hit = true
						if hit_res.get("is_headshot", false):
							any_headshot = true
						if hit_res.get("killed", false):
							any_kill = true
					pierce_idx += 1

				ray_origin = hit_pos + ray_dir * 0.04

	if any_hit:
		hit_landed.emit(any_headshot, any_kill)

	var handling: float = maxf(player_stats.get_stat(&"weapon_handling") if player_stats != null else 1.0, 0.1)
	var yaw_kick: float = _rng.randf_range(-data.recoil_yaw_range, data.recoil_yaw_range) / handling
	fired.emit(data.recoil_pitch / handling, yaw_kick)
	return true


func start_reload() -> bool:
	if data == null or is_reloading:
		return false
	if mag_ammo >= get_effective_magazine_size() or reserve_ammo <= 0:
		return false
	is_reloading = true
	is_aiming = false
	var reload_spd: float = maxf(player_stats.get_stat(&"reload_speed") if player_stats != null else 1.0, 0.1)
	var eff_reload_time: float = data.reload_time / reload_spd
	_reload_timer = eff_reload_time
	reload_started.emit(eff_reload_time)
	return true


func cancel_reload() -> void:
	if not is_reloading:
		return
	is_reloading = false
	_reload_timer = 0.0
	reload_cancelled.emit()


func _complete_reload() -> void:
	is_reloading = false
	_reload_timer = 0.0
	var updated: Vector2i = compute_reload_transfer(mag_ammo, get_effective_magazine_size(), reserve_ammo)
	mag_ammo = updated.x
	reserve_ammo = updated.y
	ammo_changed.emit(mag_ammo, reserve_ammo)
	reload_finished.emit()


func _apply_spread(forward: Vector3, right: Vector3, up: Vector3, spread_deg: float) -> Vector3:
	if spread_deg <= 0.001:
		return forward.normalized()
	var spread_rad: float = deg_to_rad(spread_deg)
	var angle: float = _rng.randf_range(0.0, TAU)
	var radius: float = sqrt(_rng.randf()) * tan(spread_rad)
	return (forward + right * (cos(angle) * radius) + up * (sin(angle) * radius)).normalized()


static func compute_reload_transfer(current_mag: int, mag_capacity: int, current_reserve: int) -> Vector2i:
	var safe_mag: int = maxi(current_mag, 0)
	var safe_reserve: int = maxi(current_reserve, 0)
	var needed: int = maxi(mag_capacity - safe_mag, 0)
	var transfer: int = mini(needed, safe_reserve)
	return Vector2i(safe_mag + transfer, safe_reserve - transfer)
