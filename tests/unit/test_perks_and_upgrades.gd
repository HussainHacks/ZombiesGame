extends RefCounted
## Unit tests for Phase 7: PlayerStats stacking & caps, PerkData resources,
## PerkManager cap/duplicates/health rule, and WeaponManager per-slot upgrades.

const ALL_PERK_PATHS := [
	"res://resources/perks/iron_heart.tres",
	"res://resources/perks/quick_hands.tres",
	"res://resources/perks/street_runner.tres",
	"res://resources/perks/heavy_caliber.tres",
	"res://resources/perks/deadeye_tonic.tres",
	"res://resources/perks/vital_surge.tres",
]
const PistolPath := "res://resources/weapons/starter_pistol.tres"
const EconomyPath := "res://resources/configuration/economy_config.tres"
const UpgradePath := "res://resources/configuration/default_weapon_upgrade.tres"


func run_all() -> Dictionary:
	var results := {
		"passed": 0,
		"failed": 0,
		"failures": [] as Array[String],
	}

	_run_test("player_stats_additive_then_multiplicative_and_caps", _test_player_stats_stacking_and_caps, results)
	_run_test("all_6_perk_resources_valid", _test_all_6_perks_valid, results)
	_run_test("perk_manager_cap_no_duplicates_and_health_rule", _test_perk_manager_rules, results)
	_run_test("weapon_upgrade_preserves_shared_weapon_data", _test_weapon_upgrade_non_mutating, results)
	_run_test("upgrade_ammo_cost_and_box_refill_compatibility", _test_upgrade_ammo_and_refill, results)

	return results


func _run_test(test_name: String, fn: Callable, results: Dictionary) -> void:
	var err: String = fn.call()
	if err.is_empty():
		results["passed"] += 1
		print("  [PASS] ", test_name)
	else:
		results["failed"] += 1
		results["failures"].append("%s: %s" % [test_name, err])
		print("  [FAIL] ", test_name, ": ", err)


func _test_player_stats_stacking_and_caps() -> String:
	var ps := PlayerStats.new()
	ps._ready()

	# Additive then multiplicative: (100 + 50) * 1.2 = 180
	ps.add_modifier(&"src_a", &"max_health", PlayerStats.ModifierOp.ADD, 50.0)
	ps.add_modifier(&"src_b", &"max_health", PlayerStats.ModifierOp.MULTIPLY, 1.2)
	if not is_equal_approx(ps.get_stat(&"max_health"), 180.0):
		ps.free()
		return "Expected (100+50)*1.2 = 180.0, got %s" % ps.get_stat(&"max_health")

	# Hard cap check: max_health cap = 300.0, reload_speed cap = 2.5
	ps.add_modifier(&"src_c", &"max_health", PlayerStats.ModifierOp.ADD, 500.0)
	ps.add_modifier(&"src_c", &"reload_speed", PlayerStats.ModifierOp.MULTIPLY, 5.0)
	if not is_equal_approx(ps.get_stat(&"max_health"), 300.0):
		ps.free()
		return "Expected max_health clamped to 300.0, got %s" % ps.get_stat(&"max_health")
	if not is_equal_approx(ps.get_stat(&"reload_speed"), 2.5):
		ps.free()
		return "Expected reload_speed clamped to 2.5, got %s" % ps.get_stat(&"reload_speed")

	# Source removal restores cleanly
	ps.remove_source(&"src_c")
	ps.remove_source(&"src_b")
	if not is_equal_approx(ps.get_stat(&"max_health"), 150.0) or not is_equal_approx(ps.get_stat(&"reload_speed"), 1.0):
		ps.free()
		return "Removing sources failed to restore expected values"

	ps.clear_all()
	if not is_equal_approx(ps.get_stat(&"max_health"), 100.0):
		ps.free()
		return "clear_all failed to restore baseline 100.0"

	ps.free()
	return ""


func _test_all_6_perks_valid() -> String:
	var seen_ids := {}
	for path: String in ALL_PERK_PATHS:
		var pd := load(path) as PerkData
		if pd == null or pd.perk_id == &"" or pd.display_name.is_empty():
			return "Invalid PerkData at %s" % path
		if seen_ids.has(pd.perk_id):
			return "Duplicate perk_id %s" % pd.perk_id
		seen_ids[pd.perk_id] = true
		if pd.cost <= 0 or pd.stat_modifiers.is_empty():
			return "Missing cost or modifiers on %s" % pd.display_name
	return ""


func _test_perk_manager_rules() -> String:
	var ps := PlayerStats.new()
	ps._ready()
	var hc := HealthComponent.new()
	hc.max_health = 100.0
	hc.current_health = 100.0
	var ph := PlayerHealth.new()
	ph.health_component = hc
	ph.player_stats = ps
	ps.stats_changed.connect(ph._on_stats_changed)

	var pkm := PerkManager.new()
	pkm.player_stats = ps
	pkm.player_health = ph

	var iron := load(ALL_PERK_PATHS[0]) as PerkData
	var quick := load(ALL_PERK_PATHS[1]) as PerkData
	var runner := load(ALL_PERK_PATHS[2]) as PerkData
	var heavy := load(ALL_PERK_PATHS[3]) as PerkData
	var deadeye := load(ALL_PERK_PATHS[4]) as PerkData

	if not pkm.acquire_perk(iron):
		pkm.free(); ph.free(); hc.free(); ps.free()
		return "Failed to acquire first perk"
	if not is_equal_approx(hc.max_health, 150.0) or not is_equal_approx(hc.current_health, 150.0):
		pkm.free(); ph.free(); hc.free(); ps.free()
		return "Iron Heart health rule failed (max=%s, cur=%s)" % [hc.max_health, hc.current_health]

	# Reject duplicate
	if pkm.acquire_perk(iron):
		pkm.free(); ph.free(); hc.free(); ps.free()
		return "Duplicate perk should be rejected"

	pkm.acquire_perk(quick)
	pkm.acquire_perk(runner)
	pkm.acquire_perk(heavy)
	if pkm.active_perks.size() != 4:
		pkm.free(); ph.free(); hc.free(); ps.free()
		return "Expected 4 active perks"

	# Enforce cap of 4
	if pkm.acquire_perk(deadeye):
		pkm.free(); ph.free(); hc.free(); ps.free()
		return "5th perk should be rejected at cap 4"

	pkm.clear_perks()
	if not pkm.active_perks.is_empty() or not is_equal_approx(hc.max_health, 100.0):
		pkm.free(); ph.free(); hc.free(); ps.free()
		return "clear_perks failed to restore baseline"

	pkm.free()
	ph.free()
	hc.free()
	ps.free()
	return ""


func _test_weapon_upgrade_non_mutating() -> String:
	var pistol := load(PistolPath) as WeaponData
	var upg := load(UpgradePath) as WeaponUpgradeData
	var orig_dmg: float = pistol.damage
	var orig_mag: int = pistol.magazine_size

	var wm := WeaponManager.new()
	wm.starting_weapons = [pistol]
	wm._ready()

	if not wm.upgrade_slot(0, upg):
		wm.free()
		return "upgrade_slot(0) failed"

	if wm.get_active_tier() != 1 or wm.get_active_display_name() != "Forged Street-9":
		wm.free()
		return "Expected tier 1 and Forged Street-9, got tier=%d name=%s" % [wm.get_active_tier(), wm.get_active_display_name()]

	if wm.active_weapon.mag_ammo != roundi(float(orig_mag) * upg.mag_size_multiplier):
		wm.free()
		return "Upgraded mag size mismatch"

	# Shared WeaponData resource MUST remain unmutated
	if not is_equal_approx(pistol.damage, orig_dmg) or pistol.magazine_size != orig_mag:
		wm.free()
		return "Shared WeaponData was mutated!"

	wm.free()
	return ""


func _test_upgrade_ammo_and_refill() -> String:
	var pistol := load(PistolPath) as WeaponData
	var ec := load(EconomyPath) as EconomyConfig
	var upg := load(UpgradePath) as WeaponUpgradeData

	if ec.get_ammo_price(pistol, 0) != 150 or ec.get_ammo_price(pistol, 1) != 2500:
		return "Expected tier 0 ammo=150 and tier 1 ammo=2500"

	var wm := WeaponManager.new()
	wm.starting_weapons = [pistol]
	wm._ready()
	wm.upgrade_slot(0, upg)
	wm.active_weapon.mag_ammo = 1
	wm.active_weapon.reserve_ammo = 0
	wm.give_or_refill_weapon(pistol)

	if wm.get_active_tier() != 1 or wm.active_weapon.mag_ammo != roundi(float(pistol.magazine_size) * upg.mag_size_multiplier):
		wm.free()
		return "Refilling owned upgraded weapon failed to preserve tier or upgraded mag capacity"

	wm.free()
	return ""
