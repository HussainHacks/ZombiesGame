extends RefCounted
## Unit tests verifying all required Phase 1 input actions exist in InputMap.

const REQUIRED_ACTIONS := [
	"move_forward",
	"move_back",
	"move_left",
	"move_right",
	"sprint",
	"jump",
	"crouch",
	"fire",
	"aim",
	"reload",
	"interact",
	"weapon_1",
	"weapon_2",
	"weapon_3",
	"weapon_4",
	"weapon_5",
	"pause",
]


func run_all() -> Dictionary:
	var results := {
		"passed": 0,
		"failed": 0,
		"failures": [] as Array[String],
	}

	_run_test("all_required_input_actions_exist", _test_all_required_input_actions_exist, results)
	_run_test("all_required_input_actions_have_events", _test_all_required_input_actions_have_events, results)

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


func _test_all_required_input_actions_exist() -> String:
	var missing: Array[String] = []
	for action: String in REQUIRED_ACTIONS:
		if not InputMap.has_action(action):
			missing.append(action)
	if not missing.is_empty():
		return "Missing InputMap actions: %s" % ", ".join(missing)
	return ""


func _test_all_required_input_actions_have_events() -> String:
	var empty_actions: Array[String] = []
	for action: String in REQUIRED_ACTIONS:
		if InputMap.has_action(action) and InputMap.action_get_events(action).is_empty():
			empty_actions.append(action)
	if not empty_actions.is_empty():
		return "InputMap actions with no bound events: %s" % ", ".join(empty_actions)
	return ""
