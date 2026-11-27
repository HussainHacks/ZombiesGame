extends RefCounted
## Integration tests for Phase 5 greybox compound: barricade breaking/entering,
## mid-assault repair, distinct attack slots, closed/open door navmesh gating,
## 20-zombie stress test, round completion, and game-over/pool reset.

const CompoundScene := preload("res://scenes/environment/greybox_compound.tscn")
const ZombieScene := preload("res://scenes/enemies/zombie_standard.tscn")


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
	var door_hall := compound.get_node("NavRegion/DoorToHall") as Door
	var barricade_w := compound.get_node("NavRegion/ZoneManager/StartRoom/BarricadeStartWest") as Barricade

	player.set_process_unhandled_input(false)
	rm.stop_and_cleanup()

	await _run_test("zombie_breaks_barricade_enters_and_reaches_player", _test_barricade_break_and_enter.bind(tree, compound, player, barricade_w), results)
	await _run_test("repairing_mid_assault_forces_zombie_to_rebreak", _test_repair_mid_assault.bind(tree, compound, player, barricade_w), results)
	await _run_test("multiple_zombies_use_distinct_barricade_slots", _test_distinct_slots.bind(tree, compound, barricade_w), results)
	await _run_test("closed_door_blocks_path_and_open_unlocks_zone", _test_door_nav_and_unlock.bind(tree, compound, player, pm, zm, door_hall), results)
	await _run_test("chasing_zombies_keep_valid_paths_when_door_opens", _test_chasing_zombies_when_door_opens.bind(tree, compound, player, pm, door_hall), results)
	await _run_test("stress_20_zombies_through_door_and_window", _test_stress_20_zombies.bind(tree, compound, player, pm, door_hall, barricade_w), results)
	await _run_test("round_completes_with_barricade_zombies", _test_round_completes_with_barricades.bind(tree, rm, ac), results)
	await _run_test("stall_watchdog_relocates_stuck_zombie_without_killing", _test_stall_watchdog.bind(tree, rm, ac, player), results)
	await _run_test("stall_watchdog_ignores_barricade_assault", _test_watchdog_ignores_barricade.bind(tree, rm, ac, player, barricade_w), results)
	await _run_test("async_door_rebake_gates_spawn_and_handles_second_door", _test_async_door_rebake_and_second_door.bind(tree, compound, player, pm, zm, ac), results)
	await _run_test("restart_resets_barricades_doors_zones_and_pool", _test_restart_resets_compound.bind(tree, rm, pm, zm, ac, door_hall, barricade_w), results)

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


func _test_barricade_break_and_enter(tree: SceneTree, compound: Node3D, player: PlayerController, barricade: Barricade) -> String:
	barricade.reset_barricade()
	barricade.board_break_interval = 0.08
	player.global_position = Vector3(0.0, 0.1, 6.0)

	var z := ZombieScene.instantiate() as ZombieAI
	compound.add_child(z)
	z.global_position = Vector3(-9.5, 0.0, 6.0)
	z.assign_barricade(barricade)
	z.transition_to(ZombieAI.State.CHASE)

	var reached: bool = false
	for _step: int in range(720):
		await tree.physics_frame
		if z.global_position.x > -4.5 and z.global_position.distance_to(player.global_position) <= 2.5:
			reached = true
			break

	var boards_left: int = barricade.intact_boards
	var z_pos: Vector3 = z.global_position
	var z_mode: int = z.current_mode
	var z_path: PackedVector3Array = z.nav_agent.get_current_navigation_path()
	z.queue_free()
	await tree.process_frame
	barricade.board_break_interval = 1.4
	barricade.reset_barricade()
	return "" if reached and boards_left == 0 else "Zombie failed (reached=%s, boards=%d, pos=%s, mode=%d, path=%s)" % [reached, boards_left, z_pos, z_mode, z_path]


func _test_repair_mid_assault(tree: SceneTree, compound: Node3D, player: PlayerController, barricade: Barricade) -> String:
	barricade.reset_barricade()
	barricade.board_break_interval = 0.06
	player.global_position = Vector3(0.0, 0.1, 6.0)

	var z := ZombieScene.instantiate() as ZombieAI
	compound.add_child(z)
	z.global_position = Vector3(-7.5, 0.0, 6.0)
	z.assign_barricade(barricade)
	z.transition_to(ZombieAI.State.CHASE)

	# Wait until 3 boards broken (2 left)
	for _step: int in range(120):
		await tree.physics_frame
		if barricade.intact_boards <= 2:
			break

	# Repair 2 boards mid-assault
	barricade.repair_one_board(null)
	barricade.repair_one_board(null)
	var after_repair: int = barricade.intact_boards

	# Let zombie break them again
	for _step: int in range(180):
		await tree.physics_frame
		if barricade.is_open():
			break

	var reopened: bool = barricade.is_open()
	z.queue_free()
	await tree.process_frame
	barricade.board_break_interval = 1.4
	barricade.reset_barricade()
	if after_repair <= 2 or not reopened:
		return "Mid-assault repair failed to force re-breaking (after_repair=%d, reopened=%s)" % [after_repair, reopened]
	return ""


func _test_distinct_slots(tree: SceneTree, compound: Node3D, barricade: Barricade) -> String:
	barricade.reset_barricade()
	barricade.board_break_interval = 5.0
	var zombies: Array[ZombieAI] = []
	for i: int in range(4):
		var z := ZombieScene.instantiate() as ZombieAI
		compound.add_child(z)
		z.global_position = Vector3(-8.5 - float(i) * 0.8, 0.0, 5.0 + float(i) * 0.5)
		z.assign_barricade(barricade)
		z.transition_to(ZombieAI.State.CHASE)
		zombies.append(z)

	for _step: int in range(90):
		await tree.physics_frame

	var claimed: int = barricade.get_claimed_slot_count()
	var min_sep: float = 999.0
	for i: int in range(zombies.size()):
		for j: int in range(i + 1, zombies.size()):
			min_sep = minf(min_sep, zombies[i].global_position.distance_to(zombies[j].global_position))

	for z: ZombieAI in zombies:
		z.queue_free()
	await tree.process_frame
	barricade.board_break_interval = 1.4
	barricade.reset_barricade()

	if claimed > 3:
		return "More than 3 slots claimed: %d" % claimed
	if min_sep < 0.35:
		return "Zombies stacked on top of each other (min_sep=%s)" % min_sep
	return ""


func _test_door_nav_and_unlock(tree: SceneTree, compound: Node3D, player: PlayerController, pm: PointsManager, zm: ZoneManager, door: Door) -> String:
	door.reset_door()
	zm.reset_all_zones()
	player.global_position = Vector3(0.0, 0.1, 6.0)
	player.player_health.health_component.max_health = 99999.0
	player.player_health.health_component.restore_full_health()
	player.is_dead = false
	await tree.physics_frame

	var nav_map: RID = compound.get_world_3d().navigation_map
	var path_closed: PackedVector3Array = NavigationServer3D.map_get_path(nav_map, Vector3(0.0, 0.1, -6.0), Vector3(0.0, 0.1, 6.0), true)
	var crossed_while_closed: bool = not path_closed.is_empty() and path_closed[path_closed.size() - 1].z > 1.0
	var hall_unlocked_before: bool = zm.is_zone_unlocked("hall_room")

	# Buy the door
	pm.add_points(1000, "test")
	var bought: bool = door.purchase(player, pm)
	var nav_region := compound.get_node("NavRegion") as NavigationRegion3D
	await tree.physics_frame
	await tree.physics_frame
	if nav_region.is_baking():
		await nav_region.bake_finished
	var path_open: PackedVector3Array = PackedVector3Array()
	var crossed_when_open: bool = false
	for _pf: int in range(15):
		await tree.process_frame
		await tree.physics_frame
		NavigationServer3D.map_force_update(nav_map)
		path_open = NavigationServer3D.map_get_path(nav_map, Vector3(0.0, 0.1, -6.0), Vector3(0.0, 0.1, 6.0), true)
		crossed_when_open = not path_open.is_empty() and path_open[path_open.size() - 1].z > 1.0
		if crossed_when_open:
			break
	var hall_unlocked_after: bool = zm.is_zone_unlocked("hall_room")
	var door_center_closest: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, door.global_position)
	var door_gap_dist: float = Vector2(door.global_position.x - door_center_closest.x, door.global_position.z - door_center_closest.z).length()

	# Also verify DoorToCourtyard rebakes continuous navmesh when opened
	var door_yard := compound.get_node_or_null("NavRegion/DoorToCourtyard") as Door
	var yard_gap_dist: float = 0.0
	if door_yard != null:
		door_yard.reset_door()
		pm.add_points(1000, "test")
		door_yard.purchase(player, pm)
		await tree.physics_frame
		await tree.physics_frame
		if nav_region.is_baking():
			await nav_region.bake_finished
		for _pf in range(15):
			await tree.process_frame
			await tree.physics_frame
			NavigationServer3D.map_force_update(nav_map)
			var yard_closest: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, door_yard.global_position)
			yard_gap_dist = Vector2(door_yard.global_position.x - yard_closest.x, door_yard.global_position.z - yard_closest.z).length()
			if yard_gap_dist < 0.35:
				break
		door_yard.reset_door()

	door.reset_door()
	zm.reset_all_zones()

	if crossed_while_closed or hall_unlocked_before:
		return "Closed door/locked zone allowed path or unlock prematurely"
	if not bought or not crossed_when_open or not hall_unlocked_after:
		return "Opening door failed to connect path or unlock hall_room (bought=%s, path=%s, unlocked=%s)" % [bought, crossed_when_open, hall_unlocked_after]
	if door_gap_dist >= 0.35 or yard_gap_dist >= 0.35:
		return "Open door left unbaked navmesh gap (hall=%.3fm, yard=%.3fm)" % [door_gap_dist, yard_gap_dist]
	return ""


func _test_chasing_zombies_when_door_opens(tree: SceneTree, compound: Node3D, player: PlayerController, pm: PointsManager, door: Door) -> String:
	door.reset_door()
	player.global_position = Vector3(0.0, 0.1, 6.0)
	var z := ZombieScene.instantiate() as ZombieAI
	compound.add_child(z)
	z.global_position = Vector3(3.0, 0.0, 9.0)
	z.transition_to(ZombieAI.State.CHASE)

	for _i: int in range(15):
		await tree.physics_frame

	pm.add_points(1000, "test")
	door.purchase(player, pm)

	var reached: bool = false
	for _i: int in range(180):
		await tree.physics_frame
		if z.global_position.distance_to(player.global_position) <= z.data.attack_range + 0.2:
			reached = true
			break

	z.queue_free()
	await tree.process_frame
	door.reset_door()
	return "" if reached else "Chasing zombie lost path when door opened"


func _test_stress_20_zombies(tree: SceneTree, compound: Node3D, player: PlayerController, pm: PointsManager, door: Door, barricade: Barricade) -> String:
	door.reset_door()
	pm.add_points(1000, "test")
	door.purchase(player, pm)
	var nav_region := compound.get_node("NavRegion") as NavigationRegion3D
	await tree.physics_frame
	await tree.physics_frame
	if nav_region.is_baking():
		await nav_region.bake_finished
	await tree.process_frame
	NavigationServer3D.map_force_update(nav_region.get_navigation_map())
	await tree.physics_frame

	# Open west barricade
	barricade.reset_barricade()
	for _i: int in range(5):
		barricade.damage_board()

	player.global_position = Vector3(0.0, 0.1, 6.0)
	player.player_health.health_component.max_health = 99999.0
	player.player_health.health_component.restore_full_health()
	player.is_dead = false
	await tree.physics_frame

	var zombies: Array[ZombieAI] = []
	for i: int in range(10):
		var zd := ZombieScene.instantiate() as ZombieAI
		compound.add_child(zd)
		zd.global_position = Vector3(float(i % 3 - 1) * 1.2, 0.0, -4.0 - float(i / 3) * 1.2)
		zd.transition_to(ZombieAI.State.CHASE)
		zombies.append(zd)

		var zw := ZombieScene.instantiate() as ZombieAI
		compound.add_child(zw)
		zw.global_position = Vector3(-9.5 - float(i % 2) * 1.2, 0.0, 5.0 + float(i / 2) * 0.8)
		zw.assign_barricade(barricade)
		zw.transition_to(ZombieAI.State.CHASE)
		zombies.append(zw)

	var nav_map: RID = compound.get_world_3d().navigation_map
	var max_off_nav_dist: float = 0.0
	var max_off_nav_enter_barricade: float = 0.0
	var worst_off_info: String = ""
	var arrival_frames: Dictionary = {}
	for step: int in range(900):
		await tree.physics_frame
		for idx: int in range(zombies.size()):
			var z: ZombieAI = zombies[idx]
			if not arrival_frames.has(idx) and z.global_position.distance_to(player.global_position) <= z.data.attack_range + 0.5:
				arrival_frames[idx] = step + 1
			var closest: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, z.global_position)
			var off_dist: float = Vector2(z.global_position.x - closest.x, z.global_position.z - closest.z).length()
			if z.current_mode == ZombieAI.Mode.ENTER_BARRICADE:
				max_off_nav_enter_barricade = maxf(max_off_nav_enter_barricade, off_dist)
			elif off_dist > max_off_nav_dist:
				max_off_nav_dist = off_dist
				worst_off_info = "pos=%s closest=%s mode=%d step=%d" % [z.global_position, closest, z.current_mode, step]

	var arrived: int = 0
	var total_recoveries: int = 0
	var stragglers: Array[String] = []
	for z: ZombieAI in zombies:
		total_recoveries += z.stuck_recovery_count
		if z.global_position.distance_to(player.global_position) <= z.data.attack_range + 0.5:
			arrived += 1
		else:
			stragglers.append("(pos=%s, dist=%.2f, mode=%d)" % [z.global_position, z.global_position.distance_to(player.global_position), z.current_mode])
		z.queue_free()
	await tree.process_frame

	var times: Array[int] = []
	for k: Variant in arrival_frames.keys():
		times.append(int(arrival_frames[k]))
	times.sort()
	var t_min: int = times[0] if not times.is_empty() else -1
	var t_med: int = times[times.size() / 2] if not times.is_empty() else -1
	var t_max: int = times[times.size() - 1] if not times.is_empty() else -1

	barricade.reset_barricade()
	door.reset_door()
	player.player_health.health_component.max_health = 100.0
	player.player_health.health_component.restore_full_health()
	player.is_dead = false
	print("    [INFO] 20-zombie stress: arrived=%d/20, total_stuck_recoveries=%d, max_off_nav=%.3fm (enter_barricade=%.3fm), arrival_frames(min/med/max)=%d/%d/%d" % [arrived, total_recoveries, max_off_nav_dist, max_off_nav_enter_barricade, t_min, t_med, t_max])
	if arrived < 20:
		return "Too few zombies arrived (%d/20). Stragglers: %s" % [arrived, ", ".join(stragglers)]
	if total_recoveries > 3:
		return "Too many stuck recoveries (%d > 3)" % total_recoveries
	if max_off_nav_dist >= 0.35:
		return "Zombie left navmesh while not on a link (max_off_nav=%.3fm >= 0.35m, %s)" % [max_off_nav_dist, worst_off_info]
	return ""


func _test_round_completes_with_barricades(tree: SceneTree, rm: RoundManager, ac: ArenaController) -> String:
	var orig_cfg: RoundConfig = rm.round_config
	var cfg := RoundConfig.new()
	cfg.base_zombie_count = 3
	cfg.max_concurrent_zombies = 3
	cfg.base_spawn_interval = 0.05
	cfg.min_spawn_interval = 0.05
	cfg.initial_countdown = 0.05
	cfg.intermission_duration = 0.1
	rm.round_config = cfg

	ac.restart_run()
	for _step: int in range(60):
		rm._process(0.05)
		for z: ZombieAI in rm.alive_zombies.duplicate():
			z.health_component.take_damage(999.0)
		if rm.current_round == 2 and rm.phase == RoundManager.Phase.ACTIVE:
			break
		await tree.process_frame

	var r: int = rm.current_round
	rm.round_config = orig_cfg
	return "" if r == 2 else "Expected round 2 after barricade round completion, got %d" % r


func _test_stall_watchdog(tree: SceneTree, rm: RoundManager, ac: ArenaController, player: PlayerController) -> String:
	ac.restart_run()
	player.global_position = Vector3(0.0, 0.1, 6.0)
	var z: ZombieAI = rm._spawn_at(Vector3(0.0, 0.0, -9.0), null)
	if z == null:
		return "Failed to spawn zombie for watchdog test"
	z.watchdog_timeout = 0.25
	z.reset_watchdog()
	var start_pos: Vector3 = Vector3(0.0, 0.0, -9.0)
	# Hold zombie in place so it makes zero progress toward player
	for _i: int in range(25):
		z.global_position = start_pos
		await tree.physics_frame
		if z.global_position.distance_to(start_pos) > 0.5:
			break
	var relocated: bool = z.global_position.distance_to(start_pos) > 0.5
	var alive: bool = not z.health_component.is_dead and z.current_state != ZombieAI.State.DEAD
	rm.stop_and_cleanup()
	if not relocated or not alive:
		return "Watchdog failed (relocated=%s, alive=%s, pos=%s)" % [relocated, alive, z.global_position]
	return ""


func _test_watchdog_ignores_barricade(tree: SceneTree, rm: RoundManager, ac: ArenaController, player: PlayerController, barricade: Barricade) -> String:
	ac.restart_run()
	barricade.reset_barricade()
	player.global_position = Vector3(0.0, 0.1, 6.0)
	var z: ZombieAI = rm._spawn_at(Vector3(-8.5, 0.0, 6.0), barricade)
	if z == null:
		return "Failed to spawn zombie for barricade watchdog test"
	z.watchdog_timeout = 0.25
	z.reset_watchdog()
	var triggered := [false]
	z.stall_watchdog_triggered.connect(func(_zb: ZombieAI) -> void: triggered[0] = true)
	for _i: int in range(30):
		await tree.physics_frame
	rm.stop_and_cleanup()
	await tree.process_frame
	barricade.reset_barricade()
	return "Watchdog falsely triggered during barricade assault!" if triggered[0] else ""


func _test_async_door_rebake_and_second_door(tree: SceneTree, compound: Node3D, player: PlayerController, pm: PointsManager, zm: ZoneManager, ac: ArenaController) -> String:
	ac.restart_run()
	await tree.process_frame
	var nav_region := compound.get_node("NavRegion") as NavigationRegion3D
	var door_hall := compound.get_node("NavRegion/DoorToHall") as Door
	var door_yard := compound.get_node("NavRegion/DoorToCourtyard") as Door
	var nav_map: RID = compound.get_world_3d().navigation_map

	var zombies: Array[ZombieAI] = []
	for i: int in range(20):
		var z := ZombieScene.instantiate() as ZombieAI
		compound.add_child(z)
		z.global_position = Vector3(float(i % 5 - 2) * 1.4, 0.0, 4.0 + float(i / 5) * 1.2)
		z.transition_to(ZombieAI.State.CHASE)
		zombies.append(z)

	pm.add_points(3000, "test")
	var t0_us: int = Time.get_ticks_usec()
	door_hall.purchase(player, pm)
	var unlocked_immediately: bool = zm.is_zone_unlocked("hall_room")
	if unlocked_immediately:
		for z: ZombieAI in zombies:
			z.queue_free()
		return "hall_room unlocked before async door rebake finished!"

	# Buy second door immediately while first door is mid-bake
	await tree.physics_frame
	door_yard.purchase(player, pm)

	var hall_traversable_ms: float = -1.0
	var both_ready: bool = false
	for _f: int in range(60):
		await tree.process_frame
		await tree.physics_frame
		NavigationServer3D.map_force_update(nav_map)
		if hall_traversable_ms < 0.0:
			var p_hall: PackedVector3Array = NavigationServer3D.map_get_path(nav_map, Vector3(0, 0.1, 3.0), Vector3(0, 0.1, -3.0), true)
			if p_hall.size() >= 2 and p_hall[p_hall.size() - 1].z < -2.0:
				hall_traversable_ms = float(Time.get_ticks_usec() - t0_us) / 1000.0
		if zm.is_zone_unlocked("hall_room") and zm.is_zone_unlocked("courtyard"):
			var p_yard: PackedVector3Array = NavigationServer3D.map_get_path(nav_map, Vector3(0, 0.1, 3.0), Vector3(0, 0.1, -15.0), true)
			if p_yard.size() >= 2 and p_yard[p_yard.size() - 1].z < -13.5:
				both_ready = true
				break

	for z: ZombieAI in zombies:
		z.queue_free()
	await tree.process_frame
	print("    [INFO] Async door rebake (20 zombies): hall_traversable=%.2fms | both_doors_ready=%s" % [hall_traversable_ms, both_ready])
	if not both_ready:
		return "Buying second door mid-bake failed to bake both doorways or unlock zones"
	return ""


func _test_restart_resets_compound(tree: SceneTree, rm: RoundManager, pm: PointsManager, zm: ZoneManager, ac: ArenaController, door: Door, barricade: Barricade) -> String:
	ac.restart_run()
	pm.add_points(1000, "test")
	door.purchase(ac._player, pm)
	barricade.damage_board()
	barricade.damage_board()

	ac.restart_run()
	await tree.process_frame

	if barricade.intact_boards != barricade.max_boards or barricade.get_claimed_slot_count() != 0:
		return "Barricade not reset on restart"
	if door.is_open:
		return "Door not closed on restart"
	if zm.is_zone_unlocked("hall_room") or not zm.is_zone_unlocked("start_room"):
		return "Zones not reset on restart"
	if not rm._pool.is_empty() or not rm.alive_zombies.is_empty():
		return "RoundManager pool/active zombies not cleared on restart"
	return ""
