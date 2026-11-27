extends RefCounted
## Unit tests for WeaponData resources (loading, sanity bounds, distinct roles).

const WEAPON_PATHS := [
	"res://resources/weapons/starter_pistol.tres",
	"res://resources/weapons/assault_rifle.tres",
	"res://resources/weapons/pump_shotgun.tres",
]


func run_all() -> Dictionary:
	var results := {
		"passed": 0,
		"failed": 0,
		"failures": [] as Array[String],
	}

	_run_test("weapon_resources_load_and_valid", _test_weapon_resources_load_and_valid, results)
	_run_test("weapons_have_distinct_profiles", _test_weapons_have_distinct_profiles, results)

	return results


func _run_test(test_name: String, fn: Callable, results: Dictionary) -> void:
	var err: String = fn.call()
	if err.is_empty():
		results["passed"] += 1
		print("  [PASS] ", test_name)
	else:
		results["failed"] += 1
		var msg := "%s: %s" % [test_name, err]
		results["failures"].append(msg)
		print("  [FAIL] ", msg)


func _test_weapon_resources_load_and_valid() -> String:
	for path: String in WEAPON_PATHS:
		var res: Resource = load(path)
		if not (res is WeaponData):
			return "Failed to load WeaponData at %s" % path
		var wd := res as WeaponData
		if wd.display_name.is_empty():
			return "Empty display_name in %s" % path
		if wd.damage <= 0.0 or wd.headshot_multiplier < 1.0:
			return "Invalid damage/headshot_multiplier in %s" % path
		if wd.pellet_count < 1 or wd.fire_rate <= 0.0:
			return "Invalid pellet_count/fire_rate in %s" % path
		if wd.magazine_size <= 0 or wd.reserve_ammo_max < wd.magazine_size:
			return "Invalid ammo capacities in %s" % path
		if wd.reload_time <= 0.0 or wd.range <= 0.0:
			return "Invalid reload_time/range in %s" % path
		if wd.move_speed_multiplier <= 0.0 or wd.move_speed_multiplier > 1.0:
			return "Invalid move_speed_multiplier in %s" % path
		if wd.aim_fov_multiplier <= 0.0 or wd.aim_fov_multiplier > 1.0:
			return "Invalid aim_fov_multiplier in %s" % path
		if wd.viewmodel_scene == null:
			return "Missing viewmodel_scene in %s" % path
	return ""


func _test_weapons_have_distinct_profiles() -> String:
	var pistol := load(WEAPON_PATHS[0]) as WeaponData
	var rifle := load(WEAPON_PATHS[1]) as WeaponData
	var shotgun := load(WEAPON_PATHS[2]) as WeaponData

	if pistol.fire_mode != WeaponData.FireMode.SEMI:
		return "Starter pistol should be SEMI"
	if rifle.fire_mode != WeaponData.FireMode.AUTO:
		return "Assault rifle should be AUTO"
	if shotgun.fire_mode != WeaponData.FireMode.PUMP:
		return "Pump shotgun should be PUMP"
	if shotgun.pellet_count <= 1 or shotgun.pump_cycle_delay <= 0.0:
		return "Shotgun must have multiple pellets and pump_cycle_delay > 0"
	return ""
