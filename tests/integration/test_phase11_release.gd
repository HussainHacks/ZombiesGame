extends RefCounted
## Integration tests for Phase 11 release hygiene:
## verifies all debug cheat keys (F4, F9-F12) do nothing when DebugGate is off.

const CompoundScene := preload("res://scenes/environment/greybox_compound.tscn")
const DebugGateScript := preload("res://scripts/core/debug_gate.gd")


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

	await _run_test("debug_keys_blocked_when_gate_off", _test_debug_gate.bind(compound), results)

	var rm := compound.get_node_or_null("RoundManager") as RoundManager
	if rm != null:
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


func _test_debug_gate(compound: Node3D) -> String:
	var rm := compound.get_node("RoundManager") as RoundManager
	var nav_dbg := compound.get_node_or_null("NavDebugOverlay") as NavDebugOverlay
	var spawner := compound.get_node_or_null("DevSpawner") as DevSpawner
	rm.stop_and_cleanup()
	rm.current_round = 1
	rm.phase = RoundManager.Phase.ACTIVE

	DebugGateScript.force_disabled_for_test = true
	for keycode: int in [KEY_F4, KEY_F9, KEY_F10, KEY_F11, KEY_F12]:
		var ev := InputEventKey.new()
		ev.pressed = true
		ev.echo = false
		ev.keycode = keycode as Key
		if nav_dbg != null:
			nav_dbg._unhandled_input(ev)
		if spawner != null:
			spawner._unhandled_input(ev)
		rm._unhandled_input(ev)
	DebugGateScript.force_disabled_for_test = false

	var round_after: int = rm.current_round
	var zombies_after: int = rm.alive_zombies.size()
	var nav_dbg_on: bool = nav_dbg != null and nav_dbg.debug_enabled
	if nav_dbg != null:
		nav_dbg.set_debug_enabled(false)

	if round_after != 1 or zombies_after != 0 or nav_dbg_on:
		return "Debug keys leaked when gate off (round=%d, zombies=%d, nav_dbg=%s)" % [round_after, zombies_after, nav_dbg_on]
	return ""
