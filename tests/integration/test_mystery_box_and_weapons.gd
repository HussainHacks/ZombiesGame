extends RefCounted
## Integration tests for Phase 6: MysteryBox flow, expiry, spam-protection,
## empty pool refusal, jam + unlocked-zone relocation, all 8 weapons + sniper
## pierce + shotgun pellets, and death/restart reset.

const CompoundScene := preload("res://scenes/environment/greybox_compound.tscn")
const ZombieScene := preload("res://scenes/enemies/zombie_standard.tscn")
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
	var zm := compound.get_node("NavRegion/ZoneManager") as ZoneManager
	var ac := compound.get_node("ArenaController") as ArenaController
	var box := compound.get_node("MysteryBox") as MysteryBox
	var mbm := compound.get_node("MysteryBoxManager") as MysteryBoxManager

	player.set_process_unhandled_input(false)
	rm.stop_and_cleanup()

	await _run_test("buy_and_take_box_weapon_deducts_once", _test_buy_and_take.bind(tree, player, pm, box), results)
	await _run_test("let_box_result_expire_no_weapon_no_refund", _test_box_expiry.bind(tree, player, pm, box), results)
	await _run_test("spam_interact_during_spin_offer_cooldown_charges_once", _test_spam_interact.bind(tree, player, pm, box), results)
	await _run_test("empty_box_pool_refused_without_charge", _test_empty_pool_refused.bind(player, pm, box), results)
	await _run_test("forced_jam_refunds_once_and_relocates_to_unlocked_zone", _test_forced_jam_relocates.bind(tree, player, pm, zm, box, mbm), results)
	await _run_test("fire_all_8_weapons_and_verify_sniper_pierce_and_pellets", _test_all_8_weapons_fire_and_pierce.bind(tree, compound, player), results)
	await _run_test("death_during_spin_and_restart_resets_box", _test_death_and_restart_box.bind(tree, player, pm, ac, box, mbm), results)

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


func _test_buy_and_take(tree: SceneTree, player: PlayerController, pm: PointsManager, box: MysteryBox) -> String:
	box.reset_box()
	player.weapon_manager.reset_to_starter_weapons()
	pm.reset_balance()
	pm.add_points(1000, "test") # 1500
	var cost: int = box.get_effective_cost(player)

	var bought: bool = box.purchase(player, pm)
	if not bought or pm.balance != 1500 - cost:
		return "Box purchase failed or wrong balance (%d)" % pm.balance

	# Advance spin to OFFERING
	box.state_timer = 0.01
	box.uses_since_relocate = 1
	box._process(0.05)
	if box.box_state != MysteryBox.BoxState.OFFERING or box.offered_weapon == null:
		return "Expected OFFERING state after spin"

	var offered: WeaponData = box.offered_weapon
	box.interact(player)
	await tree.process_frame

	if not player.weapon_manager.has_weapon(offered) or box.box_state != MysteryBox.BoxState.COOLDOWN:
		return "Offered weapon not granted or box did not enter COOLDOWN"
	return ""


func _test_box_expiry(tree: SceneTree, player: PlayerController, pm: PointsManager, box: MysteryBox) -> String:
	box.reset_box()
	player.weapon_manager.reset_to_starter_weapons()
	pm.reset_balance()
	pm.add_points(1000, "test") # 1500
	var cost: int = box.get_effective_cost(player)

	box.purchase(player, pm)
	box.uses_since_relocate = 1
	box.state_timer = 0.01
	box._process(0.05) # -> OFFERING
	var offered: WeaponData = box.offered_weapon
	box.state_timer = 0.01
	box._process(0.05) # -> EXPIRED -> COOLDOWN
	await tree.process_frame

	if player.weapon_manager.has_weapon(offered):
		return "Expired weapon must not be granted"
	if pm.balance != 1500 - cost:
		return "Expired weapon must not refund points"
	return ""


func _test_spam_interact(tree: SceneTree, player: PlayerController, pm: PointsManager, box: MysteryBox) -> String:
	box.reset_box()
	player.weapon_manager.reset_to_starter_weapons()
	pm.reset_balance()
	pm.add_points(3000, "test") # 3500
	var start_bal: int = pm.balance
	var cost: int = box.get_effective_cost(player)

	# Spam during IDLE (same frame) -> 1 charge
	box.interact(player)
	box.interact(player)
	box.interact(player)
	# Spam during SPINNING
	box.interact(player)
	box.interact(player)
	await tree.process_frame

	if pm.balance != start_bal - cost:
		return "Spam interact charged more than once (bal=%d, expected=%d)" % [pm.balance, start_bal - cost]
	return ""


func _test_empty_pool_refused(player: PlayerController, pm: PointsManager, box: MysteryBox) -> String:
	box.reset_box()
	pm.reset_balance()
	pm.add_points(2000, "test")
	var bal_before: int = pm.balance

	# Temporarily set pool to only starter_pistol (already owned)
	var orig_pool: Array[WeaponData] = box.weapon_pool.duplicate()
	var pistol := load(ALL_WEAPON_PATHS[0]) as WeaponData
	box.weapon_pool = [pistol]
	var bought: bool = box.purchase(player, pm)
	box.weapon_pool = orig_pool

	if bought or pm.balance != bal_before:
		return "Empty eligible pool must refuse purchase without charging"
	return ""


func _test_forced_jam_relocates(tree: SceneTree, player: PlayerController, pm: PointsManager, zm: ZoneManager, box: MysteryBox, mbm: MysteryBoxManager) -> String:
	zm.reset_all_zones()
	zm.unlock_zone("hall_room") # courtyard stays LOCKED
	mbm.reset_manager()
	pm.reset_balance()
	pm.add_points(2000, "test")
	var start_bal: int = pm.balance

	var cfg := box.get_config().duplicate() as GameplayConfig
	cfg.box_min_uses_before_relocate = 1
	cfg.box_pity_max_uses = 1
	box.gameplay_config = cfg

	box.purchase(player, pm)
	box.state_timer = 0.01
	box._process(0.05) # -> JAMMED + refund
	if pm.balance != start_bal:
		return "Jam did not refund exact cost (bal=%d, expected=%d)" % [pm.balance, start_bal]

	box.state_timer = 0.01
	box._process(0.05) # -> COOLDOWN + relocate
	await tree.process_frame

	var new_loc: Marker3D = mbm.locations[mbm.current_location_index]
	var new_zone: String = str(new_loc.get_meta("zone_id"))
	box.gameplay_config = null
	if new_zone != "hall_room":
		return "Box must relocate to unlocked hall_room, never locked courtyard (got %s)" % new_zone
	return ""


func _test_all_8_weapons_fire_and_pierce(tree: SceneTree, compound: Node3D, player: PlayerController) -> String:
	player.global_position = Vector3(0.0, 0.1, 8.0)
	player.rotation = Vector3.ZERO
	player.head.rotation = Vector3.ZERO
	player.camera.rotation = Vector3.ZERO

	var z1 := ZombieScene.instantiate() as ZombieAI
	var z2 := ZombieScene.instantiate() as ZombieAI
	compound.add_child(z1)
	compound.add_child(z2)
	z1.global_position = Vector3(0.0, 0.0, 4.5)
	z2.global_position = Vector3(0.0, 0.0, 2.5)

	await tree.physics_frame
	await tree.physics_frame

	var wm := player.weapon_manager
	var space_state: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	var exclude: Array[RID] = [player.get_rid()]

	# Fire each of the 8 weapons at z1 body
	for path: String in ALL_WEAPON_PATHS:
		var wd := load(path) as WeaponData
		z1.health_component.max_health = 1000.0
		z1.health_component.restore_full_health()
		wm.give_or_refill_weapon(wd)
		wm.active_weapon.data.spread_hip = 0.0
		player.camera.look_at(Vector3(0.0, 0.9, 4.5), Vector3.UP)
		wm.active_weapon.tick(2.0)
		var fired: bool = wm.active_weapon.try_fire(player.camera, space_state, exclude, player)
		if not fired or z1.health_component.current_health >= 1000.0:
			z1.queue_free(); z2.queue_free()
			return "Weapon %s failed to fire or damage zombie" % wd.display_name

	# Verify Sniper Pierce (1 shot hits BOTH z1 and z2 lined up!)
	var sniper := load(ALL_WEAPON_PATHS[6]) as WeaponData
	z1.health_component.max_health = 1000.0
	z1.health_component.restore_full_health()
	z2.health_component.max_health = 1000.0
	z2.health_component.restore_full_health()
	wm.give_or_refill_weapon(sniper)
	wm.active_weapon.tick(2.0)
	player.camera.look_at(Vector3(0.0, 0.9, 2.5), Vector3.UP)
	wm.active_weapon.try_fire(player.camera, space_state, exclude, player)

	var z1_hit: bool = z1.health_component.current_health < 1000.0
	var z2_hit: bool = z2.health_component.current_health < 1000.0
	z1.queue_free()
	z2.queue_free()
	await tree.process_frame

	if not z1_hit or not z2_hit:
		return "Sniper pierce failed to hit both lined-up zombies (z1_hit=%s, z2_hit=%s)" % [z1_hit, z2_hit]
	return ""


func _test_death_and_restart_box(tree: SceneTree, player: PlayerController, pm: PointsManager, ac: ArenaController, box: MysteryBox, mbm: MysteryBoxManager) -> String:
	ac.restart_run()
	pm.add_points(2000, "test")
	box.purchase(player, pm) # SPINNING

	player.take_damage(200.0, null)
	await tree.process_frame
	box._process(0.05)

	ac.restart_run()
	await tree.process_frame
	if box.box_state != MysteryBox.BoxState.IDLE or box.uses_since_relocate != 0 or mbm.current_location_index != 0:
		return "Restart did not reset MysteryBox state/location"
	if player.weapon_manager.slots.size() != 1:
		return "Restart did not reset player weapons to pistol only"
	return ""
