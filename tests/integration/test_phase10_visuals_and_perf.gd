extends RefCounted
## Integration tests for Phase 10: quality toggle persistence & application,
## blood/decal caps under 500 hits, flashlight toggle, ambience stopping on
## Return to Menu, and props not blocking navmesh across all unlocked-zone states.

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

	await _run_test("quality_toggle_persists_and_applies", _test_quality_toggle.bind(tree, compound), results)
	await _run_test("blood_and_decal_caps_under_500_hits", _test_blood_caps.bind(tree, compound), results)
	await _run_test("flashlight_toggles_cleanly", _test_flashlight_toggle.bind(compound), results)
	await _run_test("ambience_stops_on_return_to_menu", _test_ambience_stops_on_menu.bind(tree, compound), results)
	await _run_test("props_do_not_block_navmesh_across_zone_states", _test_props_do_not_block_navmesh.bind(tree, compound), results)
	await _run_test("damage_vignette_fades_to_zero_after_hit", _test_damage_vignette_fades.bind(tree, compound), results)

	var rm := compound.get_node_or_null("RoundManager") as RoundManager
	if rm != null:
		rm.stop_and_cleanup()
	ImpactEffect.clear_all()
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


func _test_quality_toggle(tree: SceneTree, compound: Node3D) -> String:
	var sm: Node = tree.root.get_node_or_null("SaveManager")
	var setm: Node = tree.root.get_node_or_null("SettingsManager")
	if sm == null or setm == null:
		return "SaveManager or SettingsManager missing"

	var tmp_path: String = "res://.tmp_phase10_quality.json"
	var orig_path: String = str(sm.get("save_path"))
	sm.set("save_path", tmp_path)
	sm.call("load_save")
	setm.call("load_from_save")

	setm.call("set_quality_preset", "low")
	await tree.process_frame

	var we := compound.get_node("WorldEnvironment") as WorldEnvironment
	var start_light := compound.get_node("InteriorLights/StartRoomBulbLight") as Light3D
	var low_glow: bool = we.environment.glow_enabled
	var low_shadow: bool = start_light.shadow_enabled
	var low_cap: int = ImpactEffect.get_splat_cap()

	# Simulate restart reload
	sm.call("load_save")
	setm.call("load_from_save")
	setm.call("apply_all")
	var reloaded_q: String = str(setm.get("quality_preset"))

	setm.call("set_quality_preset", "high")
	var high_shadow: bool = start_light.shadow_enabled
	var high_glow: bool = we.environment.glow_enabled

	# Cleanup temp file and restore save path
	var abs_tmp: String = ProjectSettings.globalize_path(tmp_path)
	if FileAccess.file_exists(abs_tmp):
		DirAccess.remove_absolute(abs_tmp)
	sm.set("save_path", orig_path)
	sm.call("load_save")
	setm.call("load_from_save")
	setm.call("apply_all")

	if low_glow or low_shadow or low_cap != ImpactEffect.MAX_SPLATS_LOW:
		return "Low quality did not apply (glow=%s, shadow=%s, splat_cap=%d)" % [low_glow, low_shadow, low_cap]
	if reloaded_q != "low":
		return "Low quality did not persist across reload (got=%s)" % reloaded_q
	if not high_shadow or not high_glow:
		return "High quality did not restore (glow=%s, shadow=%s)" % [high_glow, high_shadow]
	return ""


func _test_blood_caps(tree: SceneTree, compound: Node3D) -> String:
	ImpactEffect.clear_all()
	ImpactEffect.set_low_quality(false)
	for i: int in range(500):
		ImpactEffect.spawn(compound, Vector3(float(i % 5), 0.8, 5.0), Vector3.UP, true)
	var bursts_high: int = ImpactEffect.get_active_burst_count()
	var splats_high: int = ImpactEffect.get_active_splat_count()

	ImpactEffect.set_low_quality(true)
	for i: int in range(500):
		ImpactEffect.spawn(compound, Vector3(float(i % 5), 0.8, 5.0), Vector3.UP, true)
	var bursts_low: int = ImpactEffect.get_active_burst_count()
	var splats_low: int = ImpactEffect.get_active_splat_count()

	ImpactEffect.set_low_quality(false)
	ImpactEffect.clear_all()
	await tree.process_frame

	if bursts_high > ImpactEffect.MAX_BURSTS_HIGH or splats_high > ImpactEffect.MAX_SPLATS_HIGH:
		return "High caps exceeded (bursts=%d/%d, splats=%d/%d)" % [bursts_high, ImpactEffect.MAX_BURSTS_HIGH, splats_high, ImpactEffect.MAX_SPLATS_HIGH]
	if bursts_low > ImpactEffect.MAX_BURSTS_LOW or splats_low > ImpactEffect.MAX_SPLATS_LOW:
		return "Low caps exceeded (bursts=%d/%d, splats=%d/%d)" % [bursts_low, ImpactEffect.MAX_BURSTS_LOW, splats_low, ImpactEffect.MAX_SPLATS_LOW]
	return ""


func _test_flashlight_toggle(compound: Node3D) -> String:
	var player := compound.get_node("Player") as PlayerController
	var initial: bool = player.is_flashlight_on()
	player.toggle_flashlight()
	var toggled: bool = player.is_flashlight_on()
	player.toggle_flashlight()
	var restored: bool = player.is_flashlight_on()
	if toggled == initial or restored != initial:
		return "Flashlight toggle failed (initial=%s, toggled=%s, restored=%s)" % [initial, toggled, restored]
	return ""


func _test_ambience_stops_on_menu(tree: SceneTree, compound: Node3D) -> String:
	var gs: Node = tree.root.get_node_or_null("GameState")
	var amb: Node = compound.get_node_or_null("AmbienceManager")
	if gs == null or amb == null:
		return "GameState or AmbienceManager missing"
	gs.call("start_run")
	amb.call("start_ambience")
	await tree.process_frame
	var playing_in_run: bool = bool(amb.call("is_any_playing"))
	gs.call("abandon_run_to_menu")
	await tree.process_frame
	var playing_in_menu: bool = bool(amb.call("is_any_playing"))
	if not playing_in_run or playing_in_menu:
		return "Ambience state mismatch (in_run=%s, in_menu=%s)" % [playing_in_run, playing_in_menu]
	return ""


func _test_props_do_not_block_navmesh(tree: SceneTree, compound: Node3D) -> String:
	var zm := compound.get_node("NavRegion/ZoneManager") as ZoneManager
	var pm := compound.get_node("PointsManager") as PointsManager
	var player := compound.get_node("Player") as PlayerController
	var door_hall := compound.get_node("NavRegion/DoorToHall") as Door
	var door_yard := compound.get_node("NavRegion/DoorToCourtyard") as Door
	var nav_map: RID = compound.get_world_3d().navigation_map
	var player_start := Vector3(0.0, 0.1, 6.0)

	# State 0: start_room only (doors closed)
	door_hall.reset_door()
	door_yard.reset_door()
	zm.reset_all_zones()
	await tree.physics_frame
	await tree.physics_frame
	var err0: String = _check_markers_reach_player(zm, nav_map, player_start, "start_room_only")
	if not err0.is_empty():
		return err0

	# State 1: start_room + hall_room
	pm.add_points(2000, "test")
	door_hall.purchase(player, pm)
	await tree.physics_frame
	await tree.physics_frame
	await tree.physics_frame
	var err1: String = _check_markers_reach_player(zm, nav_map, player_start, "hall_unlocked")
	if not err1.is_empty():
		door_hall.reset_door()
		zm.reset_all_zones()
		return err1

	# State 2: all zones unlocked
	door_yard.purchase(player, pm)
	await tree.physics_frame
	await tree.physics_frame
	await tree.physics_frame
	var err2: String = _check_markers_reach_player(zm, nav_map, player_start, "courtyard_unlocked")

	door_yard.reset_door()
	door_hall.reset_door()
	zm.reset_all_zones()
	await tree.physics_frame
	await tree.physics_frame
	return err2


func _check_markers_reach_player(zm: ZoneManager, nav_map: RID, player_start: Vector3, label: String) -> String:
	var entries: Array[Dictionary] = zm.get_eligible_spawn_entries(player_start)
	if entries.is_empty():
		return "No eligible spawn markers in state %s" % label
	for entry: Dictionary in entries:
		var m := entry.get("marker") as Marker3D
		if m == null:
			continue
		var target_pt: Vector3 = player_start
		var start_pt: Vector3 = m.global_position
		var bar := entry.get("barricade") as Barricade
		if bar != null and bar.outside_point != null:
			target_pt = bar.outside_point.global_position
		var p: PackedVector3Array = NavigationServer3D.map_get_path(nav_map, start_pt, target_pt, true)
		if p.size() < 2 or p[p.size() - 1].distance_to(target_pt) > 1.2:
			return "Blocked navmesh path in %s from marker %s to %s (path_len=%d)" % [label, m.name, target_pt, p.size()]
	return ""


func _test_damage_vignette_fades(tree: SceneTree, compound: Node3D) -> String:
	var hud := compound.get_node_or_null("HUD")
	var player := compound.get_node("Player") as PlayerController
	if hud == null or player == null:
		return "HUD or Player missing"
	var vignette := hud.get_node_or_null("DamageVignette") as CanvasItem
	if vignette == null:
		return "DamageVignette missing"
	player.player_health.health_component.max_health = 100.0
	player.player_health.health_component.restore_full_health()
	player.is_dead = false
	hud.call("_on_damage_taken", 30.0, Vector3.ZERO, false)
	hud._process(0.016)
	var peak_alpha: float = vignette.modulate.a
	for _i: int in range(12):
		hud._process(0.1)
	var faded_alpha: float = vignette.modulate.a
	if peak_alpha <= 0.1:
		return "Damage vignette did not appear on hit (alpha=%.3f)" % peak_alpha
	if faded_alpha > 0.01:
		return "Damage vignette did not fade to zero (alpha=%.3f)" % faded_alpha
	return ""
