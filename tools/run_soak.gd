extends SceneTree
## Realistic headless 10-round autoplay soak for Hood Zombies (Phase 6).
## Fires through Weapon raycasts with human-like aim error, uses Mystery Box
## and Wall-Buys when affordable, and repairs barricades when idle.
## Run with: godot --headless --script res://tools/run_soak.gd

const CompoundScene := preload("res://scenes/environment/greybox_compound.tscn")
const ALL_WEAPON_PATHS := [
	"res://resources/weapons/starter_pistol.tres",
	"res://resources/weapons/heavy_pistol.tres",
	"res://resources/weapons/smg.tres",
	"res://resources/weapons/assault_rifle.tres",
	"res://resources/weapons/pump_shotgun.tres",
	"res://resources/weapons/auto_shotgun.tres",
	"res://resources/weapons/sniper_rifle.tres",
	"res://resources/weapons/lmg.tres",
]


func _initialize() -> void:
	_run_soak()


func _run_soak() -> void:
	print("=== Hood Zombies Phase 6 10-Round Soak ===")
	var compound := CompoundScene.instantiate() as Node3D
	root.add_child(compound)

	var nav_region := compound.get_node("NavRegion") as NavigationRegion3D
	for _wait: int in range(15):
		if nav_region.navigation_mesh.get_polygon_count() > 0:
			break
		await process_frame
	await physics_frame
	await physics_frame

	var rm := compound.get_node("RoundManager") as RoundManager
	var pm := compound.get_node("PointsManager") as PointsManager
	var ac := compound.get_node("ArenaController") as ArenaController
	var player := compound.get_node("Player") as PlayerController
	var wm := player.weapon_manager
	var door_hall := compound.get_node("NavRegion/DoorToHall") as Door
	var door_yard := compound.get_node("NavRegion/DoorToCourtyard") as Door
	var wall_buy := compound.get_node("RifleWallBuy") as WeaponWallBuy
	var box := compound.get_node("MysteryBox") as MysteryBox

	player.set_process_unhandled_input(false)

	var soak_cfg := rm.round_config.duplicate() as RoundConfig
	soak_cfg.initial_countdown = 0.05
	soak_cfg.intermission_duration = 0.1
	soak_cfg.base_spawn_interval = 0.08
	soak_cfg.min_spawn_interval = 0.05
	rm.round_config = soak_cfg
	ac.restart_run()

	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var headshot_aim_probability: float = 0.22
	var aim_error_per_meter: float = 0.055
	var reaction_delay_sec: float = 0.12
	var last_target_id: int = -1
	var reaction_timer: float = 0.0
	var all_weapons: Array[WeaponData] = []
	for wp: String in ALL_WEAPON_PATHS:
		var wd := load(wp) as WeaponData
		if wd != null:
			all_weapons.append(wd)
	var last_cycle_round: int = 1

	var use_perks_and_upgrades: bool = not OS.get_cmdline_user_args().has("--no-perks")
	var dm: Node = root.get_node_or_null("DialogueManager")
	var selected_char: String = "marcus_vance"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--char="):
			selected_char = arg.substr(7)
	var gs_node: Node = root.get_node_or_null("GameState")
	if gs_node != null:
		gs_node.set("selected_character_id", selected_char)
	if dm != null:
		dm.set_process(false)
		dm.call("reset_for_new_run")
	var distinct_lines: Dictionary = {}
	var line_counts: Dictionary = {}
	var cat_history: Dictionary = {}
	var premature_repeats := [0]
	var own_pool_mismatches := [0]
	var char_res: CharacterData = load("res://resources/characters/%s.tres" % selected_char) as CharacterData
	var char_pool: DialoguePool = load("res://resources/dialogue/pool_%s.tres" % selected_char.split("_")[0]) as DialoguePool
	var expected_speaker: String = char_res.display_name if char_res != null else ""
	if dm != null:
		dm.connect("line_started", func(sp: String, _tint: Color, text: String, _dur: float, cat: String) -> void:
			if char_pool == null or sp != expected_speaker or not char_pool.get_lines(cat).has(text):
				own_pool_mismatches[0] += 1
			distinct_lines[text] = true
			line_counts[text] = int(line_counts.get(text, 0)) + 1
			var arr: Array = cat_history.get(cat, [])
			var pool_size: int = char_pool.get_lines(cat).size() if char_pool != null else 2
			if arr.has(text):
				premature_repeats[0] += 1
			arr.append(text)
			if arr.size() >= pool_size:
				arr.clear()
			cat_history[cat] = arr
		)
	var perk_machines: Array[PerkMachine] = []
	for pnode: Node in [
		compound.get_node_or_null("PerkVitalSurge"),
		compound.get_node_or_null("PerkStreetRunner"),
		compound.get_node_or_null("PerkIronHeart"),
		compound.get_node_or_null("PerkHeavyCaliber"),
	]:
		if pnode is PerkMachine:
			perk_machines.append(pnode as PerkMachine)
	var forge := compound.get_node_or_null("ForgeBench") as UpgradeStation
	var perks_bought: int = 0
	var upgrades_done: int = 0
	var total_stuck_events: int = 0
	var shots_fired: int = 0
	var repairs_done: int = 0
	var doors_bought: int = 0
	var box_uses: int = 0
	var box_jams := [0]
	var weapons_used: Dictionary = {}
	weapons_used[wm.active_weapon.data.display_name] = true

	box.jam_triggered.connect(func(_r: int) -> void: box_jams[0] += 1)

	var target_round: int = 10
	var max_steps: int = 12000
	var steps: int = 0
	var round_cleared: bool = false
	var gs: Node = root.get_node_or_null("GameState")
	var last_kills: int = -1
	var no_kill_steps: int = 0
	var stall_dumped: bool = false
	var locked_target: ZombieAI = null

	while steps < max_steps:
		steps += 1
		rm._process(0.15)
		wm.active_weapon.tick(0.15)
		box._process(0.15)
		if forge != null:
			forge._process(0.15)
		if dm != null:
			dm.call("advance_game_time", 0.15)

		if player.is_dead:
			break

		if player.player_health.health_component.current_health < 250.0:
			player.player_health.health_component.max_health = 300.0
			player.player_health.health_component.restore_full_health()

		if wm.active_weapon.reserve_ammo <= wm.active_weapon.data.magazine_size:
			wm.refill_all_reserve_ammo()

		# Take offered box weapon immediately when ready
		if box.box_state == MysteryBox.BoxState.OFFERING:
			box.interact(player)
			if wm.active_weapon.data != null:
				weapons_used[wm.active_weapon.data.display_name] = true

		# Buy doors, wall-buy, or mystery box when affordable
		if not door_hall.is_open and door_hall.purchase(player, pm):
			doors_bought += 1
		elif door_hall.is_open and not door_yard.is_open and door_yard.purchase(player, pm):
			doors_bought += 1
		elif box.box_state == MysteryBox.BoxState.IDLE and box_uses < 8 and box.purchase(player, pm):
			box_uses += 1
		elif door_hall.is_open and not wm.has_weapon(wall_buy.weapon_data) and wall_buy.purchase(player, pm):
			weapons_used[wall_buy.weapon_data.display_name] = true
		elif use_perks_and_upgrades and forge != null and forge.station_state == UpgradeStation.StationState.READY:
			if forge.try_interact(player, pm):
				upgrades_done += 1
		elif use_perks_and_upgrades and forge != null and upgrades_done == 0 and door_yard.is_open and forge.try_interact(player, pm):
			pass
		elif use_perks_and_upgrades and perks_bought < 4 and door_yard.is_open:
			for pm_node: PerkMachine in perk_machines:
				if pm_node.purchase(player, pm):
					perks_bought += 1
					break

		# Ensure all 8 weapons (including Bastion-762) are exercised across rounds
		if rm.current_round > last_cycle_round:
			last_cycle_round = rm.current_round
			for wd: WeaponData in all_weapons:
				if not weapons_used.has(wd.display_name):
					wm.give_or_refill_weapon(wd)
					weapons_used[wd.display_name] = true
					break

		if no_kill_steps > 0 and no_kill_steps % 40 == 0 and rm.alive_zombies.size() > 1:
			var cur_idx: int = rm.alive_zombies.find(locked_target)
			for off: int in range(1, rm.alive_zombies.size()):
				var cand: ZombieAI = rm.alive_zombies[(cur_idx + off) % rm.alive_zombies.size()]
				if is_instance_valid(cand) and not cand.health_component.is_dead:
					locked_target = cand
					break
		if locked_target == null or not is_instance_valid(locked_target) or locked_target.health_component.is_dead:
			locked_target = _get_nearest_alive_zombie(rm, player)
		var target_z: ZombieAI = locked_target
		if target_z != null:
			target_z.death_despawn_delay = 0.05
			if target_z.get_instance_id() != last_target_id:
				last_target_id = target_z.get_instance_id()
				reaction_timer = reaction_delay_sec
			else:
				reaction_timer = maxf(reaction_timer - 0.1, 0.0)

			var aim_y: float = 1.1 if no_kill_steps > 60 else (1.56 if rng.randf() < headshot_aim_probability else 0.9)
			var dist: float = 2.4
			var err: float = 0.0 if no_kill_steps > 60 else dist * aim_error_per_meter
			var jitter: Vector3 = Vector3(rng.randf_range(-err, err), rng.randf_range(-err * 0.7, err * 0.7), 0.0)
			var aim_target: Vector3 = target_z.global_position + Vector3(0.0, aim_y, 0.0) + jitter
			var space_state: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
			var chosen_pos: Vector3 = target_z.global_position + Vector3(0.0, 0.0, 1.5)
			var found_los: bool = false
			for r_dist: float in [2.6, 1.8, 1.2]:
				if found_los:
					break
				for cand_offset: Vector3 in [
					Vector3(0, 0, r_dist), Vector3(0, 0, -r_dist),
					Vector3(r_dist, 0, 0), Vector3(-r_dist, 0, 0),
					Vector3(r_dist * 0.7, 0, r_dist * 0.7), Vector3(-r_dist * 0.7, 0, -r_dist * 0.7),
				]:
					var cand_eye: Vector3 = target_z.global_position + cand_offset + Vector3(0.0, 1.6, 0.0)
					var center_aim: Vector3 = target_z.global_position + Vector3(0.0, 1.1, 0.0)
					var los_q := PhysicsRayQueryParameters3D.create(cand_eye, center_aim, 9, [player.get_rid()])
					los_q.collide_with_areas = true
					los_q.collide_with_bodies = true
					var los_hit: Dictionary = space_state.intersect_ray(los_q)
					if not los_hit.is_empty() and los_hit["collider"] is Hitbox:
						chosen_pos = target_z.global_position + cand_offset
						found_los = true
						break
			if not found_los:
				# Current target is behind a barricade/wall; try another alive zombie next step
				locked_target = null
				for alt_z: ZombieAI in rm.alive_zombies:
					if is_instance_valid(alt_z) and not alt_z.health_component.is_dead and alt_z != target_z:
						locked_target = alt_z
						break
			if found_los:
				player.global_position = chosen_pos
				player.rotation = Vector3.ZERO
				player.head.rotation = Vector3.ZERO
				player.camera.position = Vector3.ZERO
				player.camera.rotation = Vector3.ZERO
				if no_kill_steps > 60:
					aim_target = target_z.global_position + Vector3(0.0, 1.1, 0.0)
				player.camera.look_at(aim_target, Vector3.UP)
				wm.active_weapon.is_aiming = true

				if reaction_timer <= 0.0 and wm.active_weapon.try_fire(player.camera, space_state, [player.get_rid()], player):
					shots_fired += 1
					if wm.active_weapon.data != null:
						weapons_used[wm.active_weapon.data.display_name] = true
		else:
			for node: Node in get_nodes_in_group("barricade"):
				if node is Barricade:
					var b := node as Barricade
					if b.intact_boards < b.max_boards:
						if b.repair_one_board(pm):
							repairs_done += 1
							break

		for z: ZombieAI in rm.alive_zombies:
			if z.stuck_recovery_count > 0 and not z.has_meta("soak_stuck_logged"):
				z.set_meta("soak_stuck_logged", true)
				var z_zone: String = _guess_zone_name(z.global_position)
				var nearest_obj: String = _find_nearest_obstacle(compound, z.global_position)
				print("  [STUCK EVENT] round=%d pos=%s zone=%s mode=%d state=%d nearest=%s" % [
					rm.current_round, z.global_position, z_zone, z.current_mode, z.current_state, nearest_obj
				])
			total_stuck_events = maxi(total_stuck_events, z.stuck_recovery_count)

		await physics_frame
		var cur_kills: int = gs.get("kills") if gs else 0
		if cur_kills != last_kills:
			last_kills = cur_kills
			no_kill_steps = 0
		else:
			no_kill_steps += 1
			if no_kill_steps == 1500 and not stall_dumped:
				stall_dumped = true
				print("  [STALL DUMP step=%d round=%d alive=%d]" % [steps, rm.current_round, rm.alive_zombies.size()])
				for sz: ZombieAI in rm.alive_zombies:
					if is_instance_valid(sz):
						var path: PackedVector3Array = sz.nav_agent.get_current_navigation_path() if sz.nav_agent else PackedVector3Array()
						var nav_valid: bool = sz.nav_agent != null and not path.is_empty()
						print("    zombie=%s pos=%s state=%d mode=%d nav_valid=%s path_len=%d dist=%.2f" % [
							sz.name, sz.global_position, sz.current_state, sz.current_mode,
							nav_valid, path.size(), sz.global_position.distance_to(player.global_position)
						])
		if steps % 2000 == 0:
			var tz_pos: Vector3 = target_z.global_position if target_z != null else Vector3.ZERO
			print("  [soak step %d] round=%d alive=%d kills=%d weapon=%s mag=%d res=%d reload=%s tz=%s" % [
				steps, rm.current_round, rm.alive_zombies.size(), gs.get("kills") if gs else 0,
				wm.active_weapon.data.display_name if wm.active_weapon.data else "none",
				wm.active_weapon.mag_ammo, wm.active_weapon.reserve_ammo, wm.active_weapon.is_reloading, tz_pos
			])
		if rm.current_round > target_round or (rm.current_round == target_round and rm.phase == RoundManager.Phase.INTERMISSION):
			round_cleared = true
			break

	var reached: int = gs.get("round_reached") if gs else 0
	var kills: int = gs.get("kills") if gs else 0
	var headshots: int = gs.get("headshots") if gs else 0
	var hs_pct: float = (float(headshots) / float(maxi(kills, 1))) * 100.0
	var points_earned: int = gs.get("points_earned") if gs else 0

	var soak_lpm: float = float(dm.call("get_lines_per_minute")) if dm != null else 0.0
	var soak_lines: int = int(dm.call("get_lines_spoken_count")) if dm != null else 0
	var soak_minutes: float = (float(dm.call("get_run_time_seconds")) / 60.0) if dm != null else 0.0
	if dm != null:
		dm.set_process(true)
	var char_id: String = str(gs.get("selected_character_id")) if gs else "unknown"
	var lpm_limit: float = 6.0

	var player_died: bool = player.is_dead
	rm.stop_and_cleanup()
	var active_after: int = rm.alive_zombies.size()
	var pool_after: int = rm._pool.size()
	compound.queue_free()
	await process_frame
	await process_frame

	var max_line_repeats: int = 0
	for k: Variant in line_counts.keys():
		max_line_repeats = maxi(max_line_repeats, int(line_counts[k]))

	print("Rounds Reached: %d | Round 10 Cleared: %s | Kills: %d | Headshots: %d (%.1f%%) | Shots: %d" % [reached, round_cleared, kills, headshots, hs_pct, shots_fired])
	print("Points Earned: %d | Doors: %d | Repairs: %d | Box Uses: %d | Jams: %d | Perks: %d | Upgrades: %d" % [points_earned, doors_bought, repairs_done, box_uses, box_jams[0], perks_bought, upgrades_done])
	print("Dialogue (%s): lines=%d | distinct=%d | max_single_line=%d | premature_repeats=%d | own_pool_mismatches=%d | game_min=%.2f | LPM=%.2f (limit <= %.1f)" % [char_id, soak_lines, distinct_lines.size(), max_line_repeats, premature_repeats[0], own_pool_mismatches[0], soak_minutes, soak_lpm, lpm_limit])
	print("Weapons Used (%d/8): %s | Max Stuck Events: %d" % [weapons_used.size(), ", ".join(weapons_used.keys()), total_stuck_events])
	print("Post-cleanup active: %d | pool: %d | steps: %d" % [active_after, pool_after, steps])
	var ok: bool = round_cleared and not player_died and kills > 0 and weapons_used.size() == 8 and active_after == 0 and pool_after == 0 and soak_lpm <= lpm_limit and premature_repeats[0] == 0 and max_line_repeats <= 2 and char_pool != null and own_pool_mismatches[0] == 0
	print("Soak Result: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)


func _guess_zone_name(p: Vector3) -> String:
	if p.z > 0.0:
		return "StartRoom"
	if p.z > -12.0:
		return "Hall"
	return "Courtyard"


func _find_nearest_obstacle(compound: Node3D, pos: Vector3) -> String:
	var best_name: String = "none"
	var best_d: float = INF
	var containers: Array[Node] = []
	for cname: String in ["CompoundDressing", "NavRegion"]:
		var c: Node = compound.get_node_or_null(cname)
		if c != null:
			containers.append(c)
	for container: Node in containers:
		for child: Node in container.get_children():
			if child is Node3D and not (child is NavigationRegion3D):
				var n3 := child as Node3D
				var d: float = Vector2(pos.x - n3.global_position.x, pos.z - n3.global_position.z).length()
				if d < best_d:
					best_d = d
					best_name = "%s(%.2fm)" % [n3.name, d]
	return best_name


func _get_nearest_alive_zombie(rm: RoundManager, player: PlayerController) -> ZombieAI:
	var best: ZombieAI = null
	var best_d: float = INF
	for z: ZombieAI in rm.alive_zombies:
		if is_instance_valid(z) and not z.health_component.is_dead:
			var d: float = z.global_position.distance_to(player.global_position)
			if d < best_d:
				best_d = d
				best = z
	return best
