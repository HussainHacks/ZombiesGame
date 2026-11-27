extends RefCounted
## Unit tests for Barricade state machine & repair cap, Door purchase
## validation, Zone gating, and barricade slot claim/release.

const BarricadeScene := preload("res://scenes/interactables/barricade.tscn")
const DoorScene := preload("res://scenes/interactables/door.tscn")
const EconomyConfigPath := "res://resources/configuration/economy_config.tres"


func run_all() -> Dictionary:
	var results := {
		"passed": 0,
		"failed": 0,
		"failures": [] as Array[String],
	}

	_run_test("barricade_state_bounds_and_repair_cap", _test_barricade_state_and_cap, results)
	_run_test("barricade_slot_claim_and_release", _test_slot_claim_release, results)
	_run_test("door_purchase_validation_and_debounce", _test_door_validation, results)
	_run_test("zone_gating_of_spawn_markers", _test_zone_gating, results)

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


func _test_barricade_state_and_cap() -> String:
	var b := BarricadeScene.instantiate() as Barricade
	b.max_boards = 5
	b.max_repair_rewards_per_round = 3
	b.repair_reward = 10
	b._ready()

	var pm := PointsManager.new()
	pm.config = load(EconomyConfigPath) as EconomyConfig
	pm.reset_balance()
	var start_pts: int = pm.balance

	# Cannot repair when intact
	if b.repair_one_board(pm) or pm.balance != start_pts:
		b.free()
		pm.free()
		return "Should not repair or award points when already intact"

	# Break all 5 + 1 extra (bounds check)
	for _i: int in range(6):
		b.damage_board()
	if b.intact_boards != 0 or not b.is_open():
		b.free()
		pm.free()
		return "Expected 0 boards and is_open()==true, got %d" % b.intact_boards

	# Repair 5 boards; cap is 3 rewards
	for _i: int in range(5):
		b.repair_one_board(pm)
	var gained: int = pm.balance - start_pts
	var boards: int = b.intact_boards

	b.free()
	pm.free()

	if boards != 5:
		return "Expected 5 boards after repair, got %d" % boards
	if gained != 30:
		return "Expected 30 points (capped at 3 rewards), got %d" % gained
	return ""


func _test_slot_claim_release() -> String:
	var b := BarricadeScene.instantiate() as Barricade
	b._ready()

	var z1 := Node.new()
	var z2 := Node.new()
	var z3 := Node.new()
	var z4 := Node.new()

	var s1: Marker3D = b.claim_slot(z1)
	var s2: Marker3D = b.claim_slot(z2)
	var s3: Marker3D = b.claim_slot(z3)
	var s4: Marker3D = b.claim_slot(z4)

	if s1 == null or s2 == null or s3 == null or s1 == s2 or s2 == s3:
		b.free(); z1.free(); z2.free(); z3.free(); z4.free()
		return "Expected 3 distinct slots claimed"
	if s4 != null:
		b.free(); z1.free(); z2.free(); z3.free(); z4.free()
		return "4th zombie should not claim a slot when all 3 are taken"

	b.release_slot(z2)
	var s4_after: Marker3D = b.claim_slot(z4)
	var s4_ok: bool = s4_after != null
	b.release_all_slots()
	var remaining: int = b.get_claimed_slot_count()

	b.free(); z1.free(); z2.free(); z3.free(); z4.free()
	if not s4_ok or remaining != 0:
		return "Expected slot release and release_all_slots to free claims (s4_ok=%s, remaining=%d)" % [s4_ok, remaining]
	return ""


func _test_door_validation() -> String:
	var door := DoorScene.instantiate() as Door
	door.cost = 750
	door._ready()

	var pm := PointsManager.new()
	pm.config = load(EconomyConfigPath) as EconomyConfig
	pm.reset_balance() # 500 pts

	var fake_player := Node.new()

	# Insufficient points
	if door.purchase(fake_player, pm):
		door.free(); pm.free(); fake_player.free()
		return "Door purchase should fail with 500 < 750"

	pm.add_points(500, "test") # 1000 pts

	# Dead player blocked
	var dead_player := CharacterBody3D.new()
	dead_player.set_script(load("res://scripts/player/player_controller.gd"))
	dead_player.set("is_dead", true)
	if door.can_purchase(dead_player, pm):
		door.free(); pm.free(); fake_player.free(); dead_player.free()
		return "Dead player must not be able to buy door"
	dead_player.free()

	# Same-frame double purchase
	var ok1: bool = door.purchase(fake_player, pm)
	var ok2: bool = door.purchase(fake_player, pm)
	var bal: int = pm.balance

	door.free(); pm.free(); fake_player.free()
	if not ok1 or ok2 or bal != 250:
		return "Expected single atomic purchase (ok1=%s, ok2=%s, bal=%d)" % [ok1, ok2, bal]
	return ""


func _test_zone_gating() -> String:
	var zm := ZoneManager.new()
	var z1 := Zone.new()
	z1.zone_id = "start"
	z1.starts_unlocked = true
	var m1 := Marker3D.new()
	m1.add_to_group("zombie_spawn")
	z1.add_child(m1)

	var z2 := Zone.new()
	z2.zone_id = "locked_room"
	z2.starts_unlocked = false
	var m2 := Marker3D.new()
	m2.add_to_group("zombie_spawn")
	z2.add_child(m2)

	zm.add_child(z1)
	zm.add_child(z2)
	z1.is_unlocked = true
	z2.is_unlocked = false
	z1._collect_children_recursive(z1)
	z2._collect_children_recursive(z2)
	zm.zones = {"start": z1, "locked_room": z2}

	var locked_entries: Array[Dictionary] = zm.get_eligible_spawn_entries(Vector3.ZERO)
	z2.unlock()
	var unlocked_entries: Array[Dictionary] = zm.get_eligible_spawn_entries(Vector3.ZERO)

	zm.free()
	if locked_entries.size() != 1 or unlocked_entries.size() != 2:
		return "Expected 1 eligible marker before unlock and 2 after (got %d, %d)" % [locked_entries.size(), unlocked_entries.size()]
	return ""
