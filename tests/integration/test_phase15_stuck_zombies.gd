extends RefCounted
## Phase 15 integration test: spawns a crowd of zombies in every zone
## (start_room, hall_room, courtyard) near walls/corners so separation pushes
## them against geometry, and asserts no zombie remains non-progressing toward
## the player for > 5.0 seconds while a round is active.

const CompoundScene := preload("res://scenes/environment/greybox_compound.tscn")
const ZombieScene := preload("res://scenes/enemies/zombie_standard.tscn")

var passed: int = 0
var failed: int = 0


func run_all(tree: SceneTree) -> Dictionary:
	passed = 0
	failed = 0
	await _run_test(tree, "crowd_in_every_zone_no_zombie_stuck_over_5s", _test_crowd_every_zone)
	return {"passed": passed, "failed": failed}


func _run_test(tree: SceneTree, test_name: String, fn: Callable) -> void:
	var err: String = await fn.call(tree)
	if err.is_empty():
		print("  [PASS] ", test_name)
		passed += 1
	else:
		print("  [FAIL] ", test_name, ": ", err)
		failed += 1


func _test_crowd_every_zone(tree: SceneTree) -> String:
	var compound := CompoundScene.instantiate() as Node3D
	tree.root.add_child(compound)
	var nav_region := compound.get_node("NavRegion") as NavigationRegion3D
	var nav_map: RID = compound.get_world_3d().navigation_map
	for _w: int in range(60):
		await tree.physics_frame
		if not nav_region.is_baking() and nav_region.navigation_mesh != null and nav_region.navigation_mesh.get_polygon_count() > 0:
			NavigationServer3D.map_force_update(nav_map)
			if NavigationServer3D.map_get_iteration_id(nav_map) > 0:
				break

	var rm := compound.get_node("RoundManager") as RoundManager
	var pm := compound.get_node("PointsManager") as PointsManager
	var player := compound.get_node("Player") as PlayerController
	var door_hall := compound.get_node("NavRegion/DoorToHall") as Door
	var door_yard := compound.get_node("NavRegion/DoorToCourtyard") as Door

	# Open all doors so every zone is active and connected on the navmesh
	pm.add_points(5000, "test")
	door_hall.purchase(player, pm)
	door_yard.purchase(player, pm)
	for _f: int in range(15):
		await tree.physics_frame

	rm.stop_and_cleanup()
	player.player_health.health_component.max_health = 99999.0
	player.player_health.health_component.restore_full_health()

	# Per-zone crowd scenarios: spawn 10 zombies tightly clustered near walls/corners
	# while the player stands across the room/doorway so separation pushes them into walls.
	var zone_scenarios := [
		{
			"zone": "start_room",
			"player_pos": Vector3(0.0, 0.1, 1.5),
			"spawn_center": Vector3(-5.1, 0.1, 9.2),
		},
		{
			"zone": "hall_room",
			"player_pos": Vector3(0.0, 0.1, -1.2),
			"spawn_center": Vector3(5.1, 0.1, -9.2),
		},
		{
			"zone": "courtyard",
			"player_pos": Vector3(0.0, 0.1, -13.5),
			"spawn_center": Vector3(-11.5, 0.1, -15.0),
		},
	]

	var max_stall_observed: float = 0.0
	var total_stuck_over_5s: int = 0
	var failure_details: Array[String] = []
	var total_recoveries: int = 0

	for sc: Dictionary in zone_scenarios:
		var z_name: String = str(sc["zone"])
		player.global_position = sc["player_pos"]
		player.velocity = Vector3.ZERO

		var crowd: Array[ZombieAI] = []
		var best_dist: Array[float] = []
		var stall_time: Array[float] = []
		var max_z_stall: Array[float] = []
		var center: Vector3 = sc["spawn_center"]

		for i: int in range(10):
			var z := ZombieScene.instantiate() as ZombieAI
			compound.add_child(z)
			var offset := Vector3(float(i % 3 - 1) * 0.55, 0.0, float(i / 3 - 1) * 0.55)
			var raw_pos: Vector3 = center + offset
			var nav_pt: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, raw_pos)
			z.global_position = nav_pt if nav_pt != Vector3.ZERO else raw_pos
			z.target_player = player
			z.transition_to(ZombieAI.State.CHASE)
			crowd.append(z)
			var d0: float = z.global_position.distance_to(player.global_position)
			best_dist.append(d0)
			stall_time.append(0.0)
			max_z_stall.append(0.0)

		var dt: float = 1.0 / 60.0
		# Simulate 12 seconds (720 physics frames)
		for _step: int in range(720):
			await tree.physics_frame
			for idx: int in range(crowd.size()):
				var z: ZombieAI = crowd[idx]
				if not is_instance_valid(z) or z.current_state == ZombieAI.State.DEAD:
					continue
				var d: float = z.global_position.distance_to(player.global_position)
				if z.data != null and d <= z.data.attack_range * 1.5:
					stall_time[idx] = 0.0
					best_dist[idx] = d
				elif d < best_dist[idx] - 0.35:
					best_dist[idx] = d
					stall_time[idx] = 0.0
				else:
					stall_time[idx] += dt
					if stall_time[idx] > max_z_stall[idx]:
						max_z_stall[idx] = stall_time[idx]
					if stall_time[idx] > max_stall_observed:
						max_stall_observed = stall_time[idx]

		var zone_stuck: int = 0
		for idx: int in range(crowd.size()):
			var z: ZombieAI = crowd[idx]
			total_recoveries += z.stuck_recovery_count
			if max_z_stall[idx] > 5.0:
				zone_stuck += 1
				total_stuck_over_5s += 1
				failure_details.append("%s#z%d(stall=%.2fs,pos=%s,dist=%.2fm)" % [
					z_name, idx, max_z_stall[idx], str(z.global_position),
					z.global_position.distance_to(player.global_position)
				])
			z.queue_free()
		await tree.process_frame
		print("    [INFO] Zone %s: stuck>5s=%d/10" % [z_name, zone_stuck])

	print("    [INFO] Phase15 reproduction summary: stuck_over_5s=%d/30 | max_stall=%.2fs | recoveries=%d" % [
		total_stuck_over_5s, max_stall_observed, total_recoveries
	])

	door_yard.reset_door()
	door_hall.reset_door()
	compound.queue_free()
	await tree.process_frame

	if total_stuck_over_5s > 0:
		return "%d/30 zombies stalled >5.0s (max=%.2fs): %s" % [
			total_stuck_over_5s, max_stall_observed, ", ".join(failure_details.slice(0, 4))
		]
	return ""
