extends RefCounted
## Unit tests for all 8 WeaponData resources, DPS/TTK sanity table vs R10 zombie,
## WeaponManager ownership/replacement rules, and MysteryBox pool/weights/pity/refund.

const ALL_WEAPON_PATHS := [
	"res://resources/weapons/starter_pistol.tres",
	"res://resources/weapons/heavy_pistol.tres",
	"res://resources/weapons/smg.tres",
	"res://resources/weapons/assault_rifle.tres",
	"res://resources/weapons/pump_shotgun.tres",
	"res://resources/weapons/auto_shotgun.tres",
	"res://resources/weapons/sniper_rifle.tres",
	"res://resources/weapons/lmg.tres",
]
const BoxScene := preload("res://scenes/interactables/mystery_box.tscn")
const RoundConfigPath := "res://resources/rounds/default_rounds.tres"
const EconomyConfigPath := "res://resources/configuration/economy_config.tres"


func run_all() -> Dictionary:
	var results := {
		"passed": 0,
		"failed": 0,
		"failures": [] as Array[String],
	}

	_run_test("all_8_weapon_resources_valid_and_dps_table", _test_all_8_weapons_and_dps, results)
	_run_test("weapon_ownership_replace_and_refill_rules", _test_weapon_ownership_rules, results)
	_run_test("box_pool_excludes_owned_and_weighted_distribution", _test_box_pool_and_weights, results)
	_run_test("box_pity_rule_and_refund_once", _test_box_pity_and_refund, results)

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


func _test_all_8_weapons_and_dps() -> String:
	var rc := load(RoundConfigPath) as RoundConfig
	var r10_hp: float = 100.0 * rc.get_health_multiplier(10) # 325.0 HP
	print("    --- Weapon DPS / TTK vs Round-10 Zombie (%.0f HP) ---" % r10_hp)
	print("    Weapon         | Burst | BodyDPS | HeadDPS | SustBody | SustHead | BodyTTK | HeadTTK")

	for path: String in ALL_WEAPON_PATHS:
		var wd := load(path) as WeaponData
		if wd == null or wd.viewmodel_scene == null:
			return "Invalid WeaponData or missing viewmodel at %s" % path
		if wd.damage <= 0.0 or wd.fire_rate <= 0.0 or wd.magazine_size <= 0:
			return "Invalid stats on %s" % wd.display_name

		var burst: float = wd.damage * float(maxi(wd.pellet_count, 1))
		var interval: float = wd.get_shot_interval()
		var body_dps: float = burst / interval
		var head_dps: float = (burst * wd.headshot_multiplier) / interval
		var mag_cycle: float = float(wd.magazine_size) * interval + wd.reload_time
		var sust_body_dps: float = (burst * float(wd.magazine_size)) / mag_cycle
		var sust_head_dps: float = (burst * wd.headshot_multiplier * float(wd.magazine_size)) / mag_cycle
		var shots_body: int = ceili(r10_hp / burst)
		var shots_head: int = ceili(r10_hp / (burst * wd.headshot_multiplier))
		var ttk_body: float = float(maxi(shots_body - 1, 0)) * interval
		var ttk_head: float = float(maxi(shots_head - 1, 0)) * interval
		var body_ttk_str: String = " 1 shot" if shots_body <= 1 else "%6.2fs" % ttk_body
		var head_ttk_str: String = " 1 shot" if shots_head <= 1 else "%6.2fs" % ttk_head

		print("    %-14s | %5.1f | %7.1f | %7.1f | %8.1f | %8.1f | %s | %s" % [
			wd.display_name, burst, body_dps, head_dps, sust_body_dps, sust_head_dps, body_ttk_str, head_ttk_str
		])
		if body_dps <= 0.0 or head_dps <= body_dps or sust_body_dps <= 0.0:
			return "Invalid DPS ordering on %s" % wd.display_name
	return ""


func _test_weapon_ownership_rules() -> String:
	var pistol := load(ALL_WEAPON_PATHS[0]) as WeaponData
	var hpistol := load(ALL_WEAPON_PATHS[1]) as WeaponData
	var smg := load(ALL_WEAPON_PATHS[2]) as WeaponData
	var rifle := load(ALL_WEAPON_PATHS[3]) as WeaponData

	var wm := WeaponManager.new()
	wm.starting_weapons = [pistol]
	wm._ready()

	if wm.get_max_weapons() != 3:
		wm.free(); return "Expected max_weapons = 3"

	wm.give_or_refill_weapon(hpistol)
	wm.give_or_refill_weapon(smg)
	if wm.slots.size() != 3:
		wm.free(); return "Expected 3 slots filled, got %d" % wm.slots.size()

	# Refill owned weapon without duplicating
	wm.active_weapon.mag_ammo = 1
	wm.give_or_refill_weapon(smg)
	if wm.slots.size() != 3 or wm.active_weapon.mag_ammo != smg.magazine_size:
		wm.free(); return "Refill owned weapon failed or duplicated slot"

	# Buying 4th weapon replaces active slot (slot 2: smg -> rifle)
	wm.equip_slot(2, true)
	wm.give_or_refill_weapon(rifle)
	if wm.slots.size() != 3 or wm.has_weapon(smg) or not wm.has_weapon(rifle):
		wm.free(); return "Full inventory replacement failed"

	wm.free()
	return ""


func _test_box_pool_and_weights() -> String:
	var box := BoxScene.instantiate() as MysteryBox
	var smg := load(ALL_WEAPON_PATHS[2]) as WeaponData
	var sniper := load(ALL_WEAPON_PATHS[6]) as WeaponData

	var fake_player := Node3D.new()
	var wm := WeaponManager.new()
	wm.name = "WeaponManager"
	wm.starting_weapons = [smg]
	fake_player.add_child(wm)
	wm._init_slots()

	var eligible: Array[WeaponData] = box.get_eligible_weapons(fake_player)
	if eligible.has(smg):
		box.free(); fake_player.free(); return "Eligible pool must exclude owned weapon (smg)"

	# Weighted distribution over 1000 rolls: smg (1.5) > sniper (0.7)
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var counts := {smg: 0, sniper: 0}
	var pool: Array[WeaponData] = [smg, sniper]
	for _i: int in range(1000):
		var pick: WeaponData = MysteryBox.pick_weighted_weapon(pool, rng)
		counts[pick] += 1

	box.free()
	fake_player.free()
	if counts[smg] <= counts[sniper]:
		return "Weighted distribution failed (smg=%d, sniper=%d)" % [counts[smg], counts[sniper]]
	return ""


func _test_box_pity_and_refund() -> String:
	var box := BoxScene.instantiate() as MysteryBox
	box._ready()
	var cfg := box.get_config().duplicate() as GameplayConfig
	cfg.box_min_uses_before_relocate = 3
	cfg.box_pity_max_uses = 4
	cfg.box_jam_chance = 0.0
	box.gameplay_config = cfg

	var pm := PointsManager.new()
	pm.config = load(EconomyConfigPath) as EconomyConfig
	pm.reset_balance()

	var jam_count := [0]
	box.jam_triggered.connect(func(_r: int) -> void: jam_count[0] += 1)

	box.uses_since_relocate = 4
	box._trigger_jam()
	box._trigger_jam() # second call must NOT double-refund

	var count: int = jam_count[0]
	box.free()
	pm.free()
	if count != 1:
		return "Expected jam_triggered/refund exactly once, got %d" % count
	return ""
