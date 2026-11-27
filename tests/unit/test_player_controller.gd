extends RefCounted
## Unit tests for PlayerController movement constants, pitch clamping, and crouch state logic.

const PlayerControllerScript := preload("res://scripts/player/player_controller.gd")


func run_all() -> Dictionary:
	var results := {
		"passed": 0,
		"failed": 0,
		"failures": [] as Array[String],
	}

	_run_test("movement_speed_constants_valid", _test_movement_speed_constants_valid, results)
	_run_test("pitch_clamping_logic", _test_pitch_clamping_logic, results)
	_run_test("crouch_state_toggling", _test_crouch_state_toggling, results)

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


func _test_movement_speed_constants_valid() -> String:
	var player := PlayerControllerScript.new()
	var walk: float = player.walk_speed
	var sprint: float = player.sprint_speed
	var crouch: float = player.crouch_speed
	var jump_vel: float = player.jump_velocity
	var grav: float = player.gravity
	var stand_h: float = player.standing_height
	var crouch_h: float = player.crouch_height
	player.free()

	if crouch <= 0.0 or walk <= 0.0 or sprint <= 0.0:
		return "Speeds must be positive (crouch=%s, walk=%s, sprint=%s)" % [crouch, walk, sprint]
	if not (crouch < walk and walk < sprint):
		return "Expected crouch < walk < sprint, got (%s, %s, %s)" % [crouch, walk, sprint]
	if jump_vel <= 0.0 or grav <= 0.0:
		return "Jump velocity and gravity must be positive"
	if not (crouch_h > 0.0 and crouch_h < stand_h):
		return "Expected 0 < crouch_height < standing_height, got (%s, %s)" % [crouch_h, stand_h]
	return ""


func _test_pitch_clamping_logic() -> String:
	var low: float = PlayerControllerScript.clamp_pitch_degrees(-120.0, -89.0, 89.0)
	if not is_equal_approx(low, -89.0):
		return "Expected -120 clamped to -89.0, got %s" % low

	var high: float = PlayerControllerScript.clamp_pitch_degrees(95.5, -89.0, 89.0)
	if not is_equal_approx(high, 89.0):
		return "Expected 95.5 clamped to 89.0, got %s" % high

	var mid: float = PlayerControllerScript.clamp_pitch_degrees(25.0, -89.0, 89.0)
	if not is_equal_approx(mid, 25.0):
		return "Expected 25.0 preserved, got %s" % mid

	return ""


func _test_crouch_state_toggling() -> String:
	# Enter crouch when requested
	if not PlayerControllerScript.resolve_crouch_state(false, true, false):
		return "Should enter crouch when wants_crouch is true"

	# Stand up when not requested and ceiling is clear
	if PlayerControllerScript.resolve_crouch_state(true, false, false):
		return "Should stand up when wants_crouch is false and ceiling is clear"

	# Remain crouched when not requested but ceiling is blocked
	if not PlayerControllerScript.resolve_crouch_state(true, false, true):
		return "Should remain crouched when ceiling is blocked"

	# Remain standing when not requested even if ceiling_blocked flag is true
	if PlayerControllerScript.resolve_crouch_state(false, false, true):
		return "Should not force crouch when not currently crouching"

	return ""
