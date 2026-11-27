extends RefCounted
## Integration tests for Phase 7: PerkMachine purchases, 4-perk cap, HUD perk bar,
## Forge Bench (only-weapon rule, PROCESSING -> READY -> collect, ready_timeout
## auto-return, upgraded wall-buy ammo cost), GameEvents, and full restart reset.

const CompoundScene := preload("res://scenes/environment/greybox_compound.tscn")
const RiflePath := "res://resources/weapons/assault_rifle.tres"


func run_all(tree: SceneTree) -> Dictionary:
	var results := {
		"passed": 0,
		"failed": 0,
		"failures": [] as Array[String],
	}

	var compound := CompoundScene.instantiate() as Node3D
	tree.root.add_child(compound)
	var nav_region := compound.get_node("NavRegion") as NavigationRegion3D
	for _wait: int in range(15):
		if nav_region.navigation_mesh.get_polygon_count() > 0:
			break
		await tree.process_frame
	await tree.physics_frame
	await tree.physics_frame

	var player := compound.get_node("Player") as PlayerController
	var rm := compound.get_node("RoundManager") as RoundManager
	var pm := compound.get_node("PointsManager") as PointsManager
	var ac := compound.get_node("ArenaController") as ArenaController
	var hud := compound.get_node("HUD")
	var forge := compound.get_node("ForgeBench") as UpgradeStation

	player.set_process_unhandled_input(false)
	rm.stop_and_cleanup()

	await _run_test("buy_perk_updates_stats_health_hud_and_events", _test_buy_perk.bind(tree, compound, player, pm, hud), results)
	await tree.physics_frame
	await _run_test("perk_machine_rejects_duplicate_and_enforces_4_cap", _test_perk_cap_and_dup.bind(compound, player, pm), results)
	await tree.physics_frame
	await _run_test("forge_bench_only_weapon_rule_and_upgrade_flow", _test_forge_flow.bind(tree, compound, player, pm, forge), results)
	await tree.physics_frame
	await _run_test("forge_bench_auto_returns_on_ready_timeout", _test_forge_timeout.bind(player, pm, forge), results)
	await tree.physics_frame
	await _run_test("restart_resets_perks_stats_slot_tiers_and_forge", _test_restart_reset.bind(tree, player, pm, ac, forge), results)

	rm.stop_and_cleanup()
	compound.queue_free()
	await tree.process_frame
	await tree.process_frame
	return results


func _run_test(test_name: String, fn: Callable, results: Dictionary) -> void:
	var err: String = await fn.call()
	if err.is_empty():
		results["passed"] += 1
		print("  [PASS] ", test_name)
	else:
		results["failed"] += 1
		results["failures"].append("%s: %s" % [test_name, err])
		print("  [FAIL] ", test_name, ": ", err)


func _test_buy_perk(tree: SceneTree, compound: Node3D, player: PlayerController, pm: PointsManager, hud: Node) -> String:
	player.perk_manager.clear_perks()
	player.player_stats.clear_all()
	player.player_health.health_component.restore_full_health()
	pm.reset_balance()
	pm.add_points(5000, "test")

	var perk_events := [0]
	var ge: Node = tree.root.get_node_or_null("GameEvents")
	var cb := func(_p: PerkData) -> void: perk_events[0] += 1
	if ge != null:
		ge.connect("perk_purchased", cb)

	var iron_machine := compound.get_node("PerkIronHeart") as PerkMachine
	var start_pts: int = pm.balance
	var cost: int = iron_machine.get_effective_cost(player)
	var bought: bool = iron_machine.purchase(player, pm)

	if ge != null:
		ge.disconnect("perk_purchased", cb)

	if not bought or pm.balance != start_pts - cost:
		return "Iron Heart purchase failed or wrong point deduction"
	if not is_equal_approx(player.player_health.health_component.max_health, 150.0):
		return "Expected max_health 150.0 after Iron Heart"
	if not is_equal_approx(player.player_health.health_component.current_health, 150.0):
		return "Expected current_health 150.0 after Iron Heart"
	var perk_bar := hud.get_node_or_null("PerkBar") as HBoxContainer
	if perk_bar == null or perk_bar.get_child_count() != 1:
		return "Expected HUD PerkBar to display 1 badge"
	if perk_events[0] != 1:
		return "Expected GameEvents.perk_purchased to fire once"
	return ""


func _test_perk_cap_and_dup(compound: Node3D, player: PlayerController, pm: PointsManager) -> String:
	player.perk_manager.clear_perks()
	player.player_stats.clear_all()
	pm.reset_balance()
	pm.add_points(20000, "test")

	var m_vital := compound.get_node("PerkVitalSurge") as PerkMachine
	var m_run := compound.get_node("PerkStreetRunner") as PerkMachine
	var m_iron := compound.get_node("PerkIronHeart") as PerkMachine
	m_iron._last_purchase_usec = -1000000
	m_iron._last_purchase_frame = -1
	var m_dead := compound.get_node("PerkDeadeyeTonic") as PerkMachine
	var m_quick := compound.get_node("PerkQuickHands") as PerkMachine

	m_vital.purchase(player, pm)
	var pts_before_dup: int = pm.balance
	if m_vital.purchase(player, pm) or pm.balance != pts_before_dup:
		return "Duplicate perk purchase should fail without charging"

	m_run.purchase(player, pm)
	m_iron.purchase(player, pm)
	m_dead.purchase(player, pm)

	var pts_before_5th: int = pm.balance
	if m_quick.purchase(player, pm) or pm.balance != pts_before_5th:
		return "5th perk purchase should fail at cap 4 without charging"
	if player.perk_manager.active_perks.size() != 4:
		return "Expected 4 active perks"
	return ""


func _test_forge_flow(tree: SceneTree, compound: Node3D, player: PlayerController, pm: PointsManager, forge: UpgradeStation) -> String:
	forge.reset_station()
	player.weapon_manager.reset_to_starter_weapons()
	pm.reset_balance()
	pm.add_points(15000, "test")

	# Only-weapon rule: 1 weapon cannot be deposited
	if forge.can_purchase(player, pm) or forge.try_interact(player, pm):
		return "Forge Bench should refuse deposit when player has only 1 weapon"

	# Acquire 2nd weapon (Strider-556) and equip it
	var rifle := load(RiflePath) as WeaponData
	player.weapon_manager.give_or_refill_weapon(rifle)
	var wall_buy := compound.get_node("HeavyPistolWallBuy") as WeaponWallBuy
	var rifle_wb := WeaponWallBuy.new()
	rifle_wb.weapon_data = rifle
	rifle_wb.economy_config = wall_buy.economy_config
	var base_ammo_cost: int = rifle_wb.get_effective_cost(player)

	var upg_events := [0]
	var ge: Node = tree.root.get_node_or_null("GameEvents")
	var cb := func(_wd: WeaponData, _tier: int, _c: int) -> void: upg_events[0] += 1
	if ge != null:
		ge.connect("weapon_upgraded", cb)

	var pts_before: int = pm.balance
	if not forge.try_interact(player, pm):
		if ge != null: ge.disconnect("weapon_upgraded", cb)
		rifle_wb.free()
		return "Forge Bench deposit failed with 2 weapons"
	if forge.station_state != UpgradeStation.StationState.PROCESSING:
		if ge != null: ge.disconnect("weapon_upgraded", cb)
		rifle_wb.free()
		return "Expected PROCESSING state after deposit"
	if pm.balance != pts_before - forge.get_effective_cost(player):
		if ge != null: ge.disconnect("weapon_upgraded", cb)
		rifle_wb.free()
		return "Incorrect upgrade cost deduction"

	# Spam interact during PROCESSING should not charge
	if forge.try_interact(player, pm):
		if ge != null: ge.disconnect("weapon_upgraded", cb)
		rifle_wb.free()
		return "Spam interact during PROCESSING should be refused"

	forge._process(3.1)
	if forge.station_state != UpgradeStation.StationState.READY:
		if ge != null: ge.disconnect("weapon_upgraded", cb)
		rifle_wb.free()
		return "Expected READY state after processing duration"

	if not forge.try_interact(player, pm):
		if ge != null: ge.disconnect("weapon_upgraded", cb)
		rifle_wb.free()
		return "Failed to collect forged weapon in READY state"

	if ge != null:
		ge.disconnect("weapon_upgraded", cb)

	if player.weapon_manager.get_active_tier() != 1 or player.weapon_manager.get_active_display_name() != "Forged Strider-556":
		rifle_wb.free()
		return "Expected active weapon to be Forged Strider-556 tier 1"
	if upg_events[0] != 1:
		rifle_wb.free()
		return "Expected GameEvents.weapon_upgraded to fire once"

	var upg_ammo_cost: int = rifle_wb.get_effective_cost(player)
	rifle_wb.free()
	if base_ammo_cost != 600 or upg_ammo_cost != 2500:
		return "Expected base ammo=600 and upgraded ammo=2500, got %d / %d" % [base_ammo_cost, upg_ammo_cost]
	return ""


func _test_forge_timeout(player: PlayerController, pm: PointsManager, forge: UpgradeStation) -> String:
	forge.reset_station()
	forge._last_purchase_usec = -1000000
	forge._last_purchase_frame = -1
	player.weapon_manager.reset_to_starter_weapons()
	var rifle := load(RiflePath) as WeaponData
	player.weapon_manager.give_or_refill_weapon(rifle)
	pm.reset_balance()
	pm.add_points(10000, "test")

	if not forge.try_interact(player, pm):
		return "Forge deposit failed in timeout test"
	forge._process(3.1)
	if forge.station_state != UpgradeStation.StationState.READY:
		return "Expected READY state"
	forge._process(10.5)
	if forge.station_state != UpgradeStation.StationState.IDLE:
		return "Expected Forge Bench to auto-return and reset to IDLE on timeout"
	if player.weapon_manager.get_weapon_tier(rifle) != 1:
		return "Expected auto-returned weapon to have tier 1"
	return ""


func _test_restart_reset(tree: SceneTree, player: PlayerController, pm: PointsManager, ac: ArenaController, forge: UpgradeStation) -> String:
	ac.restart_run()
	await tree.process_frame

	if not player.perk_manager.active_perks.is_empty():
		return "Perks not cleared on restart"
	if not is_equal_approx(player.player_stats.get_stat(&"max_health"), 100.0):
		return "PlayerStats not reset on restart"
	if not is_equal_approx(player.player_health.health_component.max_health, 100.0):
		return "PlayerHealth max_health not reset on restart"
	if player.weapon_manager.get_active_tier() != 0:
		return "Weapon slot tier not reset on restart"
	if forge.station_state != UpgradeStation.StationState.IDLE:
		return "Forge Bench not reset to IDLE on restart"
	if pm.balance != 500:
		return "PointsManager not reset to 500 on restart"
	return ""
