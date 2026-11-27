extends RefCounted
## Integration tests for Phase 8: MainMenu -> Play -> Return to Menu -> Play again,
## Pause/Resume + no pause on GameOver, Settings persistence across reload,
## Corrupt save boot notice, Character selection persistence + viewmodel sleeve tint.

const MainMenuScene := preload("res://scenes/ui/main_menu.tscn")
const CompoundScene := preload("res://scenes/environment/greybox_compound.tscn")


func run_all(tree: SceneTree) -> Dictionary:
	var results := {
		"passed": 0,
		"failed": 0,
		"failures": [] as Array[String],
	}

	var sm: Node = tree.root.get_node_or_null("SaveManager")
	var set_m: Node = tree.root.get_node_or_null("SettingsManager")
	var orig_save_path: String = sm.save_path if sm != null else "user://save_data.json"
	var test_save_path := "res://.tmp_phase8_integ_save.json"
	_cleanup(test_save_path)
	if sm != null:
		sm.save_path = test_save_path
		sm.reset_save()
	if set_m != null:
		set_m.call("reset_to_defaults")

	await _run_test("menu_play_return_to_menu_play_again_clean", _test_menu_play_loop.bind(tree), results)
	await _run_test("pause_freezes_and_no_pause_on_game_over", _test_pause_and_game_over.bind(tree), results)
	await _run_test("settings_persist_across_simulated_restart", _test_settings_persist.bind(sm, set_m), results)
	await _run_test("corrupt_save_boots_to_menu_with_defaults", _test_corrupt_save_menu.bind(tree, sm, test_save_path), results)
	await _run_test("character_selection_persists_and_tints_sleeves", _test_character_persist_and_sleeves.bind(tree, sm), results)

	if sm != null:
		sm.save_path = orig_save_path
		sm.load_save()
	if set_m != null:
		set_m.call("load_from_save")
		set_m.call("apply_all")
	_cleanup(test_save_path)
	return results


func _cleanup(p: String) -> void:
	for s: String in ["", ".tmp", ".corrupt"]:
		var ap: String = ProjectSettings.globalize_path(p + s)
		if FileAccess.file_exists(ap):
			DirAccess.remove_absolute(ap)


func _run_test(test_name: String, fn: Callable, results: Dictionary) -> void:
	var err: String = await fn.call()
	if err.is_empty():
		results["passed"] += 1
		print("  [PASS] ", test_name)
	else:
		results["failed"] += 1
		results["failures"].append("%s: %s" % [test_name, err])
		print("  [FAIL] ", test_name, ": ", err)


func _test_menu_play_loop(tree: SceneTree) -> String:
	var gs: Node = tree.root.get_node_or_null("GameState")
	var menu := MainMenuScene.instantiate() as MainMenu
	tree.root.add_child(menu)
	await tree.process_frame

	if int(gs.get("current_state")) != 0: # MENU
		menu.queue_free()
		await tree.process_frame
		return "Expected MENU state on MainMenu"
	menu.queue_free()
	await tree.process_frame

	# Run 1
	var c1 := CompoundScene.instantiate() as Node3D
	tree.root.add_child(c1)
	await tree.process_frame
	await tree.process_frame
	await tree.physics_frame
	var rm1 := c1.get_node("RoundManager") as RoundManager
	var pause1 := c1.get_node("PauseMenu") as PauseMenu
	if not gs.call("is_playing"):
		rm1.stop_and_cleanup()
		c1.queue_free()
		await tree.process_frame
		return "Expected PLAYING state in Run 1"

	# Return to Menu cleanly
	rm1.stop_and_cleanup()
	gs.call("abandon_run_to_menu")
	var z_count_after_stop: int = rm1.alive_zombies.size()
	c1.queue_free()
	await tree.process_frame
	await tree.process_frame
	if int(gs.get("current_state")) != 0 or z_count_after_stop != 0 or is_instance_valid(pause1):
		return "Return to menu failed (state=%s, z=%d, pause_valid=%s)" % [gs.get("current_state"), z_count_after_stop, is_instance_valid(pause1)]

	# Run 2 starts clean
	var c2 := CompoundScene.instantiate() as Node3D
	tree.root.add_child(c2)
	await tree.process_frame
	await tree.process_frame
	await tree.physics_frame
	var rm2 := c2.get_node("RoundManager") as RoundManager
	var ok2: bool = gs.call("is_playing") and int(gs.get("kills")) == 0
	rm2.stop_and_cleanup()
	c2.queue_free()
	await tree.process_frame
	await tree.process_frame
	return "" if ok2 else "Second run did not start clean"


func _test_pause_and_game_over(tree: SceneTree) -> String:
	var gs: Node = tree.root.get_node_or_null("GameState")
	var c := CompoundScene.instantiate() as Node3D
	tree.root.add_child(c)
	await tree.process_frame
	await tree.physics_frame

	var player := c.get_node("Player") as PlayerController
	var rm := c.get_node("RoundManager") as RoundManager
	var pause_menu := c.get_node("PauseMenu") as PauseMenu

	player.toggle_pause()
	await tree.process_frame
	if not tree.paused or not pause_menu.backdrop.visible:
		rm.stop_and_cleanup(); c.queue_free(); await tree.process_frame
		return "Pause did not pause SceneTree or show PauseMenu"

	player.toggle_pause()
	await tree.process_frame
	if tree.paused or pause_menu.backdrop.visible:
		rm.stop_and_cleanup(); c.queue_free(); await tree.process_frame
		return "Resume did not unpause SceneTree or hide PauseMenu"

	# Esc must not open pause during game over
	gs.call("end_run")
	player.set_dead(true)
	player.toggle_pause()
	await tree.process_frame
	var paused_in_go: bool = tree.paused or pause_menu.backdrop.visible

	rm.stop_and_cleanup()
	c.queue_free()
	await tree.process_frame
	await tree.process_frame
	return "Pause opened during Game Over!" if paused_in_go else ""


func _test_settings_persist(sm: Node, set_m: Node) -> String:
	set_m.call("set_fov", 95.0)
	set_m.call("set_master_volume", 0.45)

	# Simulate restart by reloading SaveManager & SettingsManager
	sm.call("load_save")
	set_m.call("load_from_save")

	var fov_val: float = float(set_m.get("fov"))
	var vol_val: float = float(set_m.get("master_volume"))
	if not is_equal_approx(fov_val, 95.0) or not is_equal_approx(vol_val, 0.45):
		return "Settings did not persist (fov=%s, vol=%s)" % [fov_val, vol_val]
	return ""


func _test_corrupt_save_menu(tree: SceneTree, sm: Node, save_path: String) -> String:
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	f.store_string("corrupt{{{")
	f.close()

	sm.call("load_save")
	var menu := MainMenuScene.instantiate() as MainMenu
	tree.root.add_child(menu)
	await tree.process_frame
	var notice_vis: bool = menu.notice_label.visible
	menu.queue_free()
	await tree.process_frame
	if not sm.last_load_was_corrupt or not notice_vis:
		return "Corrupt save did not show menu notice"
	return ""


func _test_character_persist_and_sleeves(tree: SceneTree, sm: Node) -> String:
	var menu := MainMenuScene.instantiate() as MainMenu
	tree.root.add_child(menu)
	await tree.process_frame
	menu.select_character("simone_brooks")
	menu.queue_free()
	await tree.process_frame

	sm.call("load_save")
	var persisted_id: String = str(sm.call("get_selected_character_id"))
	if persisted_id != "simone_brooks":
		return "Character selection did not persist (got %s)" % persisted_id

	var c := CompoundScene.instantiate() as Node3D
	tree.root.add_child(c)
	await tree.process_frame
	await tree.physics_frame

	var player := c.get_node("Player") as PlayerController
	var rm := c.get_node("RoundManager") as RoundManager
	var rig: ViewmodelRig = player.weapon_manager.active_viewmodel
	var sleeve: MeshInstance3D = rig.find_child("Sleeve", true, false) as MeshInstance3D if rig != null else null
	var simone := load("res://resources/characters/simone_brooks.tres") as CharacterData
	var color_ok: bool = false
	if sleeve != null and sleeve.material_override is StandardMaterial3D and simone != null:
		var mat := sleeve.material_override as StandardMaterial3D
		color_ok = mat.albedo_color.is_equal_approx(simone.sleeve_color)

	rm.stop_and_cleanup()
	c.queue_free()
	await tree.process_frame
	await tree.process_frame
	return "" if color_ok else "Viewmodel sleeve color did not match selected character"
