extends Node
## Built-in command-line smoke runner (autoload: SmokeRunner).
## Triggered via `-- --smoke` (works in both editor and exported builds).

const COMPOUND_SCENE_PATH := "res://scenes/environment/greybox_compound.tscn"


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var engine_args: PackedStringArray = OS.get_cmdline_args()
	if args.has("--smoke") or engine_args.has("--smoke"):
		call_deferred("_run_smoke")


func _run_smoke() -> void:
	print("=== Hood Zombies CLI Smoke Mode ===")
	var tree: SceneTree = get_tree()
	var err: Error = tree.change_scene_to_file(COMPOUND_SCENE_PATH)
	if err != OK:
		print("SMOKE_ERROR | failed_to_load_compound=%d" % err)
		tree.quit(1)
		return

	for _w: int in range(25):
		await tree.process_frame
		if tree.current_scene != null:
			break

	var compound: Node = tree.current_scene
	if compound == null:
		print("SMOKE_ERROR | current_scene_null")
		tree.quit(1)
		return

	var nav_region := compound.get_node_or_null("NavRegion") as NavigationRegion3D
	if nav_region != null:
		for _nw: int in range(30):
			if nav_region.navigation_mesh != null and nav_region.navigation_mesh.get_polygon_count() > 0:
				break
			await tree.process_frame
	await tree.physics_frame
	await tree.physics_frame

	var rm := compound.get_node_or_null("RoundManager") as RoundManager
	var ac := compound.get_node_or_null("ArenaController") as ArenaController
	var player := compound.get_node_or_null("Player") as PlayerController
	var gs: Node = tree.root.get_node_or_null("GameState")

	if rm == null or ac == null or player == null:
		print("SMOKE_ERROR | missing_core_nodes")
		tree.quit(1)
		return

	player.set_process_unhandled_input(false)
	var smoke_cfg := rm.round_config.duplicate() as RoundConfig
	smoke_cfg.initial_countdown = 0.05
	smoke_cfg.intermission_duration = 0.1
	smoke_cfg.base_spawn_interval = 0.12
	smoke_cfg.min_spawn_interval = 0.08
	rm.round_config = smoke_cfg
	ac.restart_run()
	player.player_health.health_component.max_health = 99999.0
	player.player_health.health_component.restore_full_health()

	var zombies_spawned := [0]
	rm.zombie_spawned.connect(func(_z: ZombieAI) -> void: zombies_spawned[0] += 1)

	var reached_player: bool = false
	var start_us: int = Time.get_ticks_usec()
	var frames: int = 0
	var steps: int = 600 # 600 * 0.15s = 90.0s in-game time

	for s: int in range(steps):
		rm._process(0.15)
		if player.weapon_manager != null and player.weapon_manager.active_weapon != null:
			player.weapon_manager.active_weapon.tick(0.15)
			if player.weapon_manager.active_weapon.reserve_ammo <= 12:
				player.weapon_manager.refill_all_reserve_ammo()

		for z: ZombieAI in rm.alive_zombies:
			if not is_instance_valid(z) or z.health_component.is_dead:
				continue
			if z.global_position.distance_to(player.global_position) <= z.data.attack_range + 0.6:
				reached_player = true
				# Aim and shoot once a zombie reaches engagement range so rounds advance
				if player.camera != null and player.weapon_manager != null and player.weapon_manager.active_weapon != null:
					player.camera.look_at(z.global_position + Vector3(0.0, 1.3, 0.0), Vector3.UP)
					player.weapon_manager.active_weapon.try_fire(
						player.camera, player.get_world_3d().direct_space_state, [player.get_rid()], player
					)
				break

		await tree.physics_frame
		frames += 1

	var elapsed_sec: float = maxf(float(Time.get_ticks_usec() - start_us) / 1000000.0, 0.001)
	var avg_fps: float = float(frames) / elapsed_sec
	var rounds_reached: int = int(gs.get("round_reached")) if gs != null else rm.current_round
	var kills: int = int(gs.get("kills")) if gs != null else 0
	var nav_polys: int = nav_region.navigation_mesh.get_polygon_count() if (nav_region != null and nav_region.navigation_mesh != null) else 0

	var passed: bool = (
		nav_polys > 0
		and zombies_spawned[0] > 0
		and kills > 0
		and reached_player
		and rounds_reached >= 2
	)
	print("SMOKE_RESULT | passed=%s | rounds=%d | spawned=%d | killed=%d | reached_player=%s | nav_polys=%d | avg_fps=%.1f | errors=0" % [
		passed, rounds_reached, zombies_spawned[0], kills, reached_player, nav_polys, avg_fps
	])
	rm.stop_and_cleanup()
	tree.quit(0 if passed else 1)
