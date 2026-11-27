extends RefCounted
## Integration tests for Phase 9: GameEvents -> DialogueManager -> HUD subtitles,
## character pool selection, pause/death suppression, restart reset, and subtitles toggle.

const CompoundScene := preload("res://scenes/environment/greybox_compound.tscn")


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

	var rm := compound.get_node("RoundManager") as RoundManager
	var hud := compound.get_node("HUD")
	var dm: Node = tree.root.get_node_or_null("DialogueManager")
	var gs: Node = tree.root.get_node_or_null("GameState")
	var ge: Node = tree.root.get_node_or_null("GameEvents")
	var set_m: Node = tree.root.get_node_or_null("SettingsManager")

	rm.stop_and_cleanup()

	await _run_test("game_events_trigger_categories_and_selected_character", _test_events_and_character.bind(dm, gs, ge, hud), results)
	await _run_test("no_dialogue_while_paused_or_dead_except_death", _test_pause_and_death.bind(dm, gs, ge), results)
	await _run_test("restart_resets_cooldowns_and_bags", _test_restart_resets.bind(dm, gs), results)
	await _run_test("subtitles_off_suppresses_hud_display", _test_subtitles_off.bind(dm, gs, set_m, hud), results)

	if set_m != null:
		set_m.call("set_subtitles", true)
	if gs != null:
		gs.call("set_selected_character_id", "marcus_vance")
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


func _test_events_and_character(dm: Node, gs: Node, ge: Node, hud: Node) -> String:
	gs.call("set_selected_character_id", "simone_brooks")
	gs.call("start_run")
	dm.call("reset_for_new_run")

	var orig_chances: Dictionary = {}
	# Force deterministic trigger via direct GameEvents with clear cooldowns between
	var spoken := []
	var cb := func(speaker: String, _tint: Color, _txt: String, _dur: float, cat: String) -> void:
		spoken.append([speaker, cat])
	dm.connect("line_started", cb)

	# Test high_round (chance = 1.0) at round 5
	ge.emit_signal("round_started", 5, 18)
	# Test player_died (chance = 1.0, bypasses cooldowns)
	ge.emit_signal("player_died")

	dm.disconnect("line_started", cb)

	if spoken.size() < 2:
		return "Expected high_round and player_died to speak, got %s" % [spoken]
	if spoken[0][0] != "Simone Brooks" or spoken[0][1] != "high_round":
		return "Expected Simone Brooks high_round, got %s" % [spoken[0]]
	if spoken[1][0] != "Simone Brooks" or spoken[1][1] != "player_died":
		return "Expected Simone Brooks player_died, got %s" % [spoken[1]]

	var sub_panel := hud.get_node_or_null("SubtitlePanel") as PanelContainer
	if sub_panel == null or not sub_panel.visible:
		return "Expected HUD SubtitlePanel visible after line"
	var _unused = orig_chances
	return ""


func _test_pause_and_death(dm: Node, gs: Node, ge: Node) -> String:
	gs.call("start_run")
	dm.call("reset_for_new_run")

	gs.call("set_paused", true)
	if dm.call("request_line", "round_start", true):
		gs.call("set_paused", false)
		return "Dialogue should be suppressed while paused"
	gs.call("set_paused", false)

	gs.call("end_run")
	if dm.call("request_line", "round_start", true):
		return "Non-death dialogue should be suppressed after death"
	ge.emit_signal("player_died")
	if dm.call("get_lines_spoken_count") != 1:
		return "player_died should still trigger once at death"
	return ""


func _test_restart_resets(dm: Node, gs: Node) -> String:
	gs.call("start_run")
	dm.call("request_line", "round_start", true)
	if dm.call("get_lines_spoken_count") != 1:
		return "Expected 1 spoken line before reset"
	gs.call("start_run")
	if dm.call("get_lines_spoken_count") != 0:
		return "Expected lines_spoken_in_run reset to 0 on new run"
	if not dm.call("request_line", "round_start", true):
		return "Expected cooldowns reset on new run"
	return ""


func _test_subtitles_off(dm: Node, gs: Node, set_m: Node, hud: Node) -> String:
	gs.call("start_run")
	dm.call("reset_for_new_run")
	set_m.call("set_subtitles", false)
	dm.call("request_line", "round_start", true)
	var sub_panel := hud.get_node_or_null("SubtitlePanel") as PanelContainer
	if sub_panel != null and sub_panel.visible:
		return "SubtitlePanel should remain hidden when subtitles setting is false"
	return ""
