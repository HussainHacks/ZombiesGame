extends RefCounted
## Unit tests for Phase 9: DialogueManager cooldowns, priority/interruption,
## shuffle-bag anti-repeat over 1000 draws, trigger chance bounds, pool
## completeness (>=2 lines x 15 categories x 4 characters, no duplicates),
## and subtitle duration scaling.

const DialogueMgrScript := preload("res://scripts/dialogue/dialogue_manager.gd")
const POOL_PATHS := [
	"res://resources/dialogue/pool_marcus.tres",
	"res://resources/dialogue/pool_simone.tres",
	"res://resources/dialogue/pool_devon.tres",
	"res://resources/dialogue/pool_tasha.tres",
]


func run_all() -> Dictionary:
	var results := {
		"passed": 0,
		"failed": 0,
		"failures": [] as Array[String],
	}

	_run_test("cooldown_enforcement", _test_cooldowns, results)
	_run_test("priority_and_interruption_rules", _test_priority_interruption, results)
	_run_test("shuffle_bag_anti_repeat_1000_draws", _test_shuffle_bag_1000, results)
	_run_test("trigger_chance_bounds", _test_trigger_chances, results)
	_run_test("pool_completeness_and_no_duplicates", _test_pool_completeness, results)
	_run_test("subtitle_duration_logic", _test_subtitle_duration, results)

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


func _test_cooldowns() -> String:
	var dm: Node = Engine.get_main_loop().root.get_node_or_null("DialogueManager") if Engine.get_main_loop() else null
	var gs: Node = Engine.get_main_loop().root.get_node_or_null("GameState") if Engine.get_main_loop() else null
	if dm == null or gs == null:
		return "Autoloads missing"

	gs.call("start_run")
	dm.call("reset_for_new_run")
	if not dm.call("request_line", "round_start", true):
		return "First line should succeed"

	# Advance past active timer (5.5s) only if global_cooldown is 4.5s -> test global cooldown at 1.0s
	dm.set("_active_timer", 0.0)
	dm.set("_active_priority", 0)
	if dm.call("request_line", "door_opened", true):
		return "Global cooldown should block immediate second line"

	# Advance past global cooldown: round_start category cooldown (10.0s) check -> wait 8.0s if global is 11.0s, or test category cooldown
	dm.call("tick_timers", float(dm.get("global_cooldown")) + 0.2)
	if not dm.call("request_line", "door_opened", true):
		return "Different category should succeed after global cooldown expires"

	dm.call("reset_for_new_run")
	return ""


func _test_priority_interruption() -> String:
	var dm: Node = Engine.get_main_loop().root.get_node_or_null("DialogueManager") if Engine.get_main_loop() else null
	var gs: Node = Engine.get_main_loop().root.get_node_or_null("GameState") if Engine.get_main_loop() else null
	if dm == null or gs == null:
		return "Autoloads missing"

	gs.call("start_run")
	dm.call("reset_for_new_run")

	# Normal priority (1) active
	if not dm.call("request_line", "round_start", true):
		return "Initial normal line failed"
	# Equal priority (1) cannot interrupt
	if dm.call("request_line", "bought_weapon", true):
		return "Equal priority should not interrupt active line"
	# Higher priority low_health (2) CAN interrupt normal (1) even during global cooldown if we clear global_cd
	dm.set("_global_cd_timer", 0.0)
	if not dm.call("request_line", "low_health", true):
		return "low_health (prio 2) should interrupt normal (prio 1)"
	# Lower priority (1) cannot interrupt low_health (2)
	dm.set("_global_cd_timer", 0.0)
	if dm.call("request_line", "bought_perk", true):
		return "Normal (prio 1) must not interrupt low_health (prio 2)"
	# Death (3) interrupts low_health (2)
	if not dm.call("request_line", "player_died", true):
		return "player_died (prio 3) should interrupt low_health (prio 2)"

	dm.call("reset_for_new_run")
	return ""


func _test_shuffle_bag_1000() -> String:
	var dm: Node = DialogueMgrScript.new()
	var pool := DialoguePool.new()
	pool.pool_id = "test_bag"
	pool.categories = {"test_cat": ["L1", "L2", "L3", "L4"]}

	var counts := {"L1": 0, "L2": 0, "L3": 0, "L4": 0}
	var prev: String = ""
	for _i: int in range(1000):
		var chosen: String = dm.draw_next_line(pool, "test_cat")
		if chosen == prev:
			dm.free()
			return "Immediate repeat detected on %s" % chosen
		counts[chosen] = int(counts.get(chosen, 0)) + 1
		prev = chosen
	dm.free()

	for k: String in counts.keys():
		if int(counts[k]) != 250:
			return "Expected 250 draws each over 1000 triggers, got %s" % counts
	return ""


func _test_trigger_chances() -> String:
	for cat: String in DialogueMgrScript.CATEGORIES:
		if not DialogueMgrScript.CATEGORY_CHANCES.has(cat):
			return "Missing trigger chance for %s" % cat
		var ch: float = float(DialogueMgrScript.CATEGORY_CHANCES[cat])
		if ch < 0.0 or ch > 1.0:
			return "Trigger chance out of bounds for %s: %s" % [cat, ch]
	return ""


func _test_pool_completeness() -> String:
	var min5 := ["round_start", "round_end", "kill_streak", "took_damage", "reloading", "zombie_spotted", "bought_weapon"]
	for path: String in POOL_PATHS:
		var pool := load(path) as DialoguePool
		if pool == null:
			return "Failed to load %s" % path
		var seen_in_pool := {}
		for cat: String in DialogueMgrScript.CATEGORIES:
			var lines: Array[String] = pool.get_lines(cat)
			var req_min: int = 5 if min5.has(cat) else 3
			if lines.size() < req_min:
				return "%s category %s has < %d lines (%d)" % [path, cat, req_min, lines.size()]
			for line: String in lines:
				if line.is_empty():
					return "%s has empty line in %s" % [path, cat]
				if seen_in_pool.has(line):
					return "%s has duplicate line: %s" % [path, line]
				seen_in_pool[line] = true
	return ""


func _test_subtitle_duration() -> String:
	var short_d: float = DialogueMgrScript.compute_duration("Hi.")
	var long_d: float = DialogueMgrScript.compute_duration("This is a much longer line to verify duration scales cleanly.")
	var max_d: float = DialogueMgrScript.compute_duration("A".repeat(300))
	if not is_equal_approx(short_d, 2.0):
		return "Expected min duration 2.0s, got %s" % short_d
	if long_d <= short_d:
		return "Expected longer line to have longer duration (%s <= %s)" % [long_d, short_d]
	if not is_equal_approx(max_d, 5.5):
		return "Expected max duration cap 5.5s, got %s" % max_d
	return ""
