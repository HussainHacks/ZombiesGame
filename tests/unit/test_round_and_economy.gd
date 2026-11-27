extends RefCounted
## Unit tests for RoundConfig curves (rounds 1-50), PointsManager atomic
## spending, Purchasable validation/debounce, and reward-once guard.

const RoundConfigPath := "res://resources/rounds/default_rounds.tres"
const EconomyConfigPath := "res://resources/configuration/economy_config.tres"
const ZombieScene := preload("res://scenes/enemies/zombie_standard.tscn")


func run_all() -> Dictionary:
	var results := {
		"passed": 0,
		"failed": 0,
		"failures": [] as Array[String],
	}

	_run_test("round_config_curves_bounded_and_monotonic_1_to_50", _test_round_config_curves, results)
	_run_test("points_manager_atomic_and_rejects_invalid_costs", _test_points_manager, results)
	_run_test("purchasable_validation_and_same_frame_debounce", _test_purchasable_debounce, results)
	_run_test("reward_once_guard_on_zombie_kill", _test_reward_once_guard, results)

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


func _test_round_config_curves() -> String:
	var rc := load(RoundConfigPath) as RoundConfig
	if rc == null:
		return "Failed to load default_rounds.tres"

	var prev_count: int = 0
	var prev_hp: float = 0.0
	var prev_speed: float = 0.0
	var prev_interval: float = 999.0

	for r: int in range(1, 51):
		var c: int = rc.get_zombie_count(r)
		var hp: float = rc.get_health_multiplier(r)
		var spd: float = rc.get_speed_multiplier(r)
		var iv: float = rc.get_spawn_interval(r)

		if c < prev_count or c > rc.max_zombies_per_round:
			return "Count out of bounds or decreased at round %d: %d" % [r, c]
		if hp < prev_hp or hp > rc.max_health_multiplier:
			return "Health mult out of bounds or decreased at round %d: %s" % [r, hp]
		if spd < prev_speed or spd > rc.max_speed_multiplier:
			return "Speed mult out of bounds or decreased at round %d: %s" % [r, spd]
		if iv > prev_interval or iv < rc.min_spawn_interval:
			return "Spawn interval out of bounds or increased at round %d: %s" % [r, iv]

		prev_count = c
		prev_hp = hp
		prev_speed = spd
		prev_interval = iv

	return ""


func _test_points_manager() -> String:
	var ec := load(EconomyConfigPath) as EconomyConfig
	var pm := PointsManager.new()
	pm.config = ec
	pm.reset_balance()

	var gs: Node = Engine.get_main_loop().root.get_node_or_null("GameState") if Engine.get_main_loop() else null
	if gs != null:
		gs.call("start_run")

	if pm.balance != ec.starting_points:
		pm.free()
		return "Expected starting balance %d, got %d" % [ec.starting_points, pm.balance]

	if pm.try_spend(0) or pm.try_spend(-100) or pm.try_spend(NAN) or pm.try_spend(INF):
		pm.free()
		return "PointsManager must reject 0, negative, NAN, and INF costs"

	if pm.try_spend(pm.balance + 1):
		pm.free()
		return "PointsManager must reject spend exceeding balance"

	if not pm.try_spend(200) or pm.balance != ec.starting_points - 200:
		pm.free()
		return "Atomic spend of 200 failed"

	pm.free()
	return ""


func _test_purchasable_debounce() -> String:
	var ec := load(EconomyConfigPath) as EconomyConfig
	var pm := PointsManager.new()
	pm.config = ec
	pm.reset_balance()

	var item := Purchasable.new()
	item.cost = 200

	var fake_player := Node.new()
	var gs: Node = Engine.get_main_loop().root.get_node_or_null("GameState") if Engine.get_main_loop() else null
	if gs != null:
		gs.call("start_run")

	var first: bool = item.purchase(fake_player, pm)
	var second_same_frame: bool = item.purchase(fake_player, pm)

	var bal: int = pm.balance
	fake_player.free()
	item.free()
	pm.free()

	if not first:
		return "First purchase should succeed"
	if second_same_frame:
		return "Second purchase in same frame must be debounced"
	if bal != ec.starting_points - 200:
		return "Expected balance %d, got %d" % [ec.starting_points - 200, bal]
	return ""


func _test_reward_once_guard() -> String:
	var ec := load(EconomyConfigPath) as EconomyConfig
	var pm := PointsManager.new()
	pm.config = ec
	pm.reset_balance()

	var gs: Node = Engine.get_main_loop().root.get_node_or_null("GameState") if Engine.get_main_loop() else null
	if gs != null:
		gs.call("start_run")

	var z := ZombieScene.instantiate() as ZombieAI
	var r1: int = pm.reward_zombie_kill(z, true)
	var r2: int = pm.reward_zombie_kill(z, true)

	z.free()
	pm.free()

	if r1 <= 0 or r2 != 0:
		return "Expected reward once (r1=%d, r2=%d)" % [r1, r2]
	return ""
