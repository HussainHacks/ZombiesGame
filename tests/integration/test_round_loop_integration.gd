extends RefCounted
## Integration tests for Phase 4 survival loop: round progression, max-concurrent,
## non-mutation of EnemyData, out-of-sight spawn waiting, reward-once on
## simultaneous kills, purchase blocking/debounce, game-over/restart, pause,
## and pooled zombie reset.

const ArenaScene := preload("res://scenes/environment/test_arena.tscn")
const EnemyDataRes := preload("res://resources/enemies/standard_zombie.tres")


func run_all(tree: SceneTree) -> Dictionary:
	var results := {
		"passed": 0,
		"failed": 0,
		"failures": [] as Array[String],
	}

	var arena := ArenaScene.instantiate() as Node3D
	tree.root.add_child(arena)
	var nav_region := arena.get_node("Geometry") as NavigationRegion3D
	for _wait: int in range(10):
		if nav_region.navigation_mesh.get_polygon_count() > 0:
			break
		await tree.process_frame
	await tree.physics_frame
	await tree.physics_frame

	var player := arena.get_node("Player") as PlayerController
	var rm := arena.get_node("RoundManager") as RoundManager
	var pm := arena.get_node("PointsManager") as PointsManager
	var ac := arena.get_node("ArenaController") as ArenaController
	var wall_buy := arena.get_node("RifleWallBuy") as WeaponWallBuy

	player.set_process_unhandled_input(false)

	await _run_test("round_1_spawns_and_advances_to_round_2", _test_round_1_to_2.bind(tree, rm, ac), results)
	await _run_test("later_round_scales_health_without_mutating_resource", _test_later_round_scaling.bind(tree, rm, ac), results)
	await _run_test("spawning_waits_when_all_markers_visible_or_close", _test_spawn_waits_no_fallback.bind(tree, rm, player, ac), results)
	await _run_test("simultaneous_kill_awards_points_once", _test_simultaneous_kill_reward_once.bind(tree, rm, pm, ac), results)
	await _run_test("purchase_blocked_when_poor_and_debounced_when_affordable", _test_purchase_flow.bind(player, pm, wall_buy, ac), results)
	await _run_test("game_over_cleans_up_and_restart_is_clean", _test_game_over_and_restart.bind(tree, player, rm, pm, ac), results)
	await _run_test("pause_freezes_spawning_and_zombies", _test_pause_freezes.bind(tree, rm, ac), results)
	await _run_test("pooled_zombie_reuse_resets_state", _test_pooled_reuse.bind(tree, rm, ac), results)

	ac.restart_run()
	rm.stop_and_cleanup()
	arena.queue_free()
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


func _test_round_1_to_2(tree: SceneTree, rm: RoundManager, ac: ArenaController) -> String:
	var orig_cfg: RoundConfig = rm.round_config
	var test_cfg := RoundConfig.new()
	test_cfg.base_zombie_count = 4
	test_cfg.count_growth_per_round = 2.0
	test_cfg.max_concurrent_zombies = 2
	test_cfg.base_spawn_interval = 0.05
	test_cfg.min_spawn_interval = 0.05
	test_cfg.initial_countdown = 0.05
	test_cfg.intermission_duration = 0.1
	rm.round_config = test_cfg

	ac.restart_run()
	var spawned_r1: int = 0
	var max_seen_alive: int = 0

	for _step: int in range(60):
		rm._process(0.05)
		max_seen_alive = maxi(max_seen_alive, rm.alive_zombies.size())
		if rm.phase == RoundManager.Phase.ACTIVE and not rm.alive_zombies.is_empty():
			var z: ZombieAI = rm.alive_zombies[0]
			z.health_component.take_damage(999.0)
			spawned_r1 += 1
		if rm.current_round == 2 and rm.phase == RoundManager.Phase.ACTIVE:
			break
		await tree.process_frame

	var final_round: int = rm.current_round
	rm.round_config = orig_cfg
	if max_seen_alive > 2:
		return "max_concurrent_zombies=2 exceeded (%d)" % max_seen_alive
	if spawned_r1 != 4:
		return "Expected 4 zombies in round 1, killed %d" % spawned_r1
	if final_round != 2:
		return "Expected transition to round 2, got round %d" % final_round
	return ""


func _test_later_round_scaling(tree: SceneTree, rm: RoundManager, ac: ArenaController) -> String:
	ac.restart_run()
	rm.jump_to_round(1)
	rm._process(0.05)
	if rm.alive_zombies.is_empty():
		return "Failed to spawn round 1 zombie"
	var r1_hp: float = rm.alive_zombies[0].health_component.max_health

	rm.jump_to_round(3)
	rm._process(0.05)
	if rm.alive_zombies.is_empty():
		return "Failed to spawn round 3 zombie"
	var r3_hp: float = rm.alive_zombies[0].health_component.max_health

	await tree.process_frame
	if r3_hp <= r1_hp:
		return "Expected round 3 HP (%s) > round 1 HP (%s)" % [r3_hp, r1_hp]
	if not is_equal_approx(EnemyDataRes.base_health, 100.0):
		return "Shared EnemyData.base_health was mutated to %s" % EnemyDataRes.base_health
	return ""


func _test_spawn_waits_no_fallback(tree: SceneTree, rm: RoundManager, player: PlayerController, ac: ArenaController) -> String:
	ac.restart_run()
	rm.jump_to_round(1)
	var orig_min_dist: float = rm.min_spawn_distance
	rm.min_spawn_distance = 200.0 # Make every marker "too close"
	rm._process(0.1)
	rm._process(0.3)
	await tree.process_frame
	var count_alive: int = rm.alive_zombies.size()
	rm.min_spawn_distance = orig_min_dist
	if count_alive != 0:
		return "Expected 0 zombies spawned when all markers invalid, got %d" % count_alive
	return ""


func _test_simultaneous_kill_reward_once(tree: SceneTree, rm: RoundManager, pm: PointsManager, ac: ArenaController) -> String:
	ac.restart_run()
	rm.jump_to_round(1)
	rm._process(0.05)
	if rm.alive_zombies.is_empty():
		return "No zombie spawned"
	var z: ZombieAI = rm.alive_zombies[0]
	var start_bal: int = pm.balance

	# Simultaneous lethal hits in same frame
	z.health_component.take_damage(80.0, false)
	z.health_component.take_damage(80.0, true)
	z.health_component.take_damage(80.0, true)

	await tree.process_frame
	var gained: int = pm.balance - start_bal
	# 10 (hit1) + 10 (hit2) + 60 (kill) + 40 (headshot bonus) = 120; must NOT have 2x kill reward
	if gained > 120:
		return "Simultaneous hits awarded too many points: %d" % gained
	return ""


func _test_purchase_flow(player: PlayerController, pm: PointsManager, wall_buy: WeaponWallBuy, ac: ArenaController) -> String:
	ac.restart_run()
	# Starting points = 500, rifle cost = 1200 -> should be blocked
	if wall_buy.purchase(player, pm):
		return "Purchase should be blocked when balance < cost"

	pm.add_points(1000, "test") # balance = 1500
	var ok1: bool = wall_buy.purchase(player, pm)
	var ok2: bool = wall_buy.purchase(player, pm) # same frame debounce
	if not ok1 or ok2:
		return "Expected first purchase true and second same-frame false (ok1=%s, ok2=%s)" % [ok1, ok2]
	if pm.balance != 300:
		return "Expected balance 300 after 1200 spend, got %d" % pm.balance
	return ""


func _test_game_over_and_restart(tree: SceneTree, player: PlayerController, rm: RoundManager, pm: PointsManager, ac: ArenaController) -> String:
	ac.restart_run()
	rm.jump_to_round(2)
	rm._process(0.05)
	pm.add_points(1000, "test")
	player.weapon_manager.give_or_refill_weapon(load("res://resources/weapons/assault_rifle.tres"))

	# Kill player -> triggers GAME_OVER + cleanup
	player.take_damage(200.0, null)
	await tree.process_frame

	if GameState.current_state != GameState.State.GAME_OVER:
		return "Expected GAME_OVER state after player death"
	if not rm.alive_zombies.is_empty():
		return "Expected all active zombies cleaned up on game over"

	# Restart run -> clean state
	ac.restart_run()
	await tree.process_frame
	if GameState.current_state != GameState.State.PLAYING:
		return "Expected PLAYING state after restart"
	if rm.current_round != 1 or pm.balance != pm.config.starting_points:
		return "Expected round 1 and starting points after restart (round=%d, pts=%d)" % [rm.current_round, pm.balance]
	if player.weapon_manager.slots.size() != 1:
		return "Expected pistol-only (1 slot) after restart, got %d" % player.weapon_manager.slots.size()
	return ""


func _test_pause_freezes(tree: SceneTree, rm: RoundManager, ac: ArenaController) -> String:
	ac.restart_run()
	rm.jump_to_round(1)
	rm._process(0.05)
	var z: ZombieAI = rm.alive_zombies[0]
	var pos_before: Vector3 = z.global_position

	GameState.set_paused(true)
	for _i: int in range(10):
		await tree.physics_frame
	var pos_after: Vector3 = z.global_position
	var alive_after: int = rm.alive_zombies.size()
	GameState.set_paused(false)

	if pos_before.distance_to(pos_after) > 0.001:
		return "Zombie moved while paused!"
	if alive_after != 1:
		return "Spawning occurred while paused!"
	return ""


func _test_pooled_reuse(tree: SceneTree, rm: RoundManager, ac: ArenaController) -> String:
	ac.restart_run()
	rm.jump_to_round(1)
	rm._process(0.05)
	var z: ZombieAI = rm.alive_zombies[0]
	z.death_despawn_delay = 0.01
	z.health_component.take_damage(999.0)
	await tree.physics_frame
	await tree.physics_frame

	if rm._pool.is_empty():
		return "Expected dead zombie to return to pool"

	rm._process(2.0) # spawn next zombie from pool
	var recycled: ZombieAI = rm.alive_zombies.back()
	if recycled != z:
		return "Expected pooled zombie instance to be reused"
	if recycled.current_state != ZombieAI.State.CHASE or recycled.health_component.is_dead or recycled.kill_rewarded:
		return "Recycled zombie state was not cleanly reset"
	if recycled.body_collision.disabled or not recycled.body_hitbox.monitorable:
		return "Recycled zombie collision/hitbox was not re-enabled"
	return ""
