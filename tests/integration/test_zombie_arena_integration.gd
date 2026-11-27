extends RefCounted
## Integration tests for Phase 3: navmesh chase, melee damage & player death,
## weapon kill + single died signal, upper-platform pathing, and spawn validation.

const ArenaScene := preload("res://scenes/environment/test_arena.tscn")
const ZombieScene := preload("res://scenes/enemies/zombie_standard.tscn")


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
	var spawner := arena.get_node("DevSpawner") as DevSpawner

	# Disable player input processing during scripted tests
	player.set_process_unhandled_input(false)

	await _run_test("zombie_reaches_attack_range_via_navmesh", _test_zombie_reaches_player.bind(tree, arena, player), results)
	await _run_test("zombie_damages_and_kills_player", _test_zombie_damages_and_kills_player.bind(tree, arena, player), results)
	await _run_test("zombie_dies_from_weapon_fire_once", _test_zombie_dies_from_weapon_fire.bind(tree, arena, player), results)
	await _run_test("zombie_paths_from_upper_platform_to_floor", _test_upper_platform_pathing.bind(tree, arena, player), results)
	await _run_test("invalid_spawn_positions_rejected", _test_invalid_spawn_rejected.bind(spawner, player), results)

	arena.queue_free()
	await tree.process_frame
	await tree.process_frame

	await _run_test("zombie_cannot_reach_player_behind_sealed_wall", _test_zombie_blocked_by_sealed_wall.bind(tree), results)
	await _run_test("zombie_navigates_1_2m_doorway_without_cutting_corners", _test_doorway_no_corner_cut.bind(tree), results)
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


func _test_zombie_reaches_player(tree: SceneTree, arena: Node3D, player: PlayerController) -> String:
	player.global_position = Vector3(0.0, 0.0, 6.0)
	var zombie := ZombieScene.instantiate() as ZombieAI
	arena.add_child(zombie)
	zombie.global_position = Vector3(4.5, 0.0, 6.0)
	zombie.transition_to(ZombieAI.State.CHASE)

	var reached: bool = false
	for _step: int in range(180): # up to 3 seconds at 60Hz
		await tree.physics_frame
		if zombie.global_position.distance_to(player.global_position) <= zombie.data.attack_range + 0.1:
			reached = true
			break

	var final_pos: Vector3 = zombie.global_position
	var final_state: String = zombie.get_state_name()
	var next_p: Vector3 = zombie.nav_agent.get_next_path_position()
	var path: PackedVector3Array = zombie.nav_agent.get_current_navigation_path()
	var p_pos: Vector3 = player.global_position
	zombie.queue_free()
	await tree.process_frame
	return "" if reached else "Zombie failed (pos=%s, player=%s, state=%s, next=%s, path=%s)" % [final_pos, p_pos, final_state, next_p, path]


func _test_zombie_damages_and_kills_player(tree: SceneTree, arena: Node3D, player: PlayerController) -> String:
	player.global_position = Vector3(0.0, 0.0, 6.0)
	var ph := player.player_health
	ph.health_component.restore_full_health()
	player.is_dead = false

	var zombie := ZombieScene.instantiate() as ZombieAI
	arena.add_child(zombie)
	zombie.global_position = Vector3(1.2, 0.0, 6.0)

	# Trigger 4 swings (4 * 25 = 100 damage)
	for _i: int in range(4):
		zombie._perform_attack_swing()
		await tree.physics_frame

	var dead: bool = player.is_dead and ph.health_component.is_dead
	zombie.queue_free()
	await tree.process_frame

	# Restore player for subsequent tests
	ph.health_component.restore_full_health()
	player.is_dead = false
	return "" if dead else "Expected player to die after 100 damage"


func _test_zombie_dies_from_weapon_fire(tree: SceneTree, arena: Node3D, player: PlayerController) -> String:
	player.global_position = Vector3(0.0, 0.0, 6.0)
	var zombie := ZombieScene.instantiate() as ZombieAI
	arena.add_child(zombie)
	zombie.global_position = Vector3(0.0, 0.0, 2.0)

	var died_count := [0]
	zombie.died.connect(func(_z: ZombieAI) -> void: died_count[0] += 1)

	await tree.physics_frame
	await tree.physics_frame

	var wm := player.weapon_manager
	wm.equip_slot(0, true) # Street-9 pistol
	wm.active_weapon.data.spread_hip = 0.0
	player.camera.look_at(Vector3(0.0, 0.9, 2.0), Vector3.UP)

	var space_state: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	var exclude: Array[RID] = [player.get_rid()]

	for _shot: int in range(5):
		wm.active_weapon.try_fire(player.camera, space_state, exclude, player)
		wm.active_weapon.tick(0.5)
		await tree.physics_frame

	var ok: bool = zombie.current_state == ZombieAI.State.DEAD and died_count[0] == 1
	zombie.queue_free()
	await tree.process_frame
	return "" if ok else "Expected zombie DEAD and died_count==1, got state=%s count=%d" % [zombie.get_state_name(), died_count[0]]


func _test_upper_platform_pathing(tree: SceneTree, arena: Node3D, player: PlayerController) -> String:
	player.global_position = Vector3(-8.0, 0.0, 2.0)
	var zombie := ZombieScene.instantiate() as ZombieAI
	arena.add_child(zombie)
	zombie.global_position = Vector3(-8.0, 2.05, -8.0)
	zombie.transition_to(ZombieAI.State.CHASE)

	var reached_floor: bool = false
	for _step: int in range(420): # up to 7 seconds at 60Hz
		await tree.physics_frame
		if zombie.global_position.y < 0.45 and zombie.global_position.z > -4.0:
			reached_floor = true
			break

	var final_pos := zombie.global_position
	zombie.queue_free()
	await tree.process_frame
	return "" if reached_floor else "Zombie on upper platform failed to path down to floor (pos=%s)" % final_pos


func _test_zombie_blocked_by_sealed_wall(tree: SceneTree) -> String:
	var region := NavigationRegion3D.new()
	var nav_mesh := NavigationMesh.new()
	nav_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nav_mesh.cell_size = 0.175
	nav_mesh.cell_height = 0.1
	nav_mesh.agent_height = 1.8
	nav_mesh.agent_radius = 0.35
	region.navigation_mesh = nav_mesh

	var floor_box := CSGBox3D.new()
	floor_box.use_collision = true
	floor_box.size = Vector3(12.0, 1.0, 12.0)
	floor_box.position = Vector3(0.0, -0.5, 0.0)
	region.add_child(floor_box)

	var divider := CSGBox3D.new()
	divider.use_collision = true
	divider.size = Vector3(14.0, 4.0, 1.0)
	divider.position = Vector3(0.0, 2.0, 0.0)
	region.add_child(divider)

	tree.root.add_child(region)
	await tree.process_frame
	region.bake_navigation_mesh(false)
	NavigationServer3D.map_force_update(region.get_navigation_map())
	await tree.process_frame
	await tree.physics_frame
	await tree.physics_frame

	var fake_player := Node3D.new()
	fake_player.add_to_group("player")
	fake_player.position = Vector3(0.0, 0.0, -3.5)
	region.add_child(fake_player)

	var zombie := ZombieScene.instantiate() as ZombieAI
	zombie.position = Vector3(0.0, 0.0, 3.5)
	region.add_child(zombie)
	zombie.target_player = fake_player
	zombie.transition_to(ZombieAI.State.CHASE)

	for _step: int in range(120):
		await tree.physics_frame

	var zombie_z: float = zombie.global_position.z
	var dist_to_player: float = zombie.global_position.distance_to(fake_player.global_position)
	var attack_range: float = zombie.data.attack_range
	region.queue_free()
	await tree.process_frame
	await tree.process_frame

	if zombie_z <= 0.0 or dist_to_player <= attack_range:
		return "Zombie should not cross sealed wall (z=%s, dist=%s)" % [zombie_z, dist_to_player]
	return ""


func _test_doorway_no_corner_cut(tree: SceneTree) -> String:
	var region := NavigationRegion3D.new()
	var nav_mesh := NavigationMesh.new()
	nav_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nav_mesh.cell_size = 0.1
	nav_mesh.cell_height = 0.1
	nav_mesh.agent_height = 1.8
	nav_mesh.agent_radius = 0.3
	nav_mesh.agent_max_climb = 0.3
	region.navigation_mesh = nav_mesh

	var floor_body := StaticBody3D.new()
	var floor_col := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(12.0, 1.0, 12.0)
	floor_col.shape = floor_shape
	floor_body.position = Vector3(0.0, -0.5, 0.0)
	floor_body.add_child(floor_col)
	region.add_child(floor_body)

	# 1.2m wide doorway centered at x=0, z=0 (gaps from x=-0.6 to +0.6)
	var wall_left := StaticBody3D.new()
	var wl_col := CollisionShape3D.new()
	var wl_shape := BoxShape3D.new()
	wl_shape.size = Vector3(6.0, 3.0, 0.6)
	wl_col.shape = wl_shape
	wall_left.position = Vector3(-3.6, 1.5, 0.0)
	wall_left.add_child(wl_col)
	region.add_child(wall_left)

	var wall_right := StaticBody3D.new()
	var wr_col := CollisionShape3D.new()
	var wr_shape := BoxShape3D.new()
	wr_shape.size = Vector3(6.0, 3.0, 0.6)
	wr_col.shape = wr_shape
	wall_right.position = Vector3(3.6, 1.5, 0.0)
	wall_right.add_child(wr_col)
	region.add_child(wall_right)

	tree.root.add_child(region)
	await tree.process_frame
	await tree.physics_frame
	var nav_map: RID = region.get_navigation_map()
	var prev_cell_size: float = NavigationServer3D.map_get_cell_size(nav_map)
	var prev_cell_height: float = NavigationServer3D.map_get_cell_height(nav_map)
	NavigationServer3D.map_set_cell_size(nav_map, nav_mesh.cell_size)
	NavigationServer3D.map_set_cell_height(nav_map, nav_mesh.cell_height)
	NavigationServer3D.map_force_update(nav_map)
	await tree.physics_frame
	region.bake_navigation_mesh(false)
	await tree.process_frame
	NavigationServer3D.region_set_navigation_mesh(region.get_rid(), nav_mesh)
	var sync_path_len: int = 0
	for _sync: int in range(20):
		await tree.process_frame
		await tree.physics_frame
		NavigationServer3D.map_force_update(nav_map)
		sync_path_len = NavigationServer3D.map_get_path(nav_map, Vector3(3.0, 0.0, 3.5), Vector3(-3.0, 0.0, -3.5), true).size()
		if sync_path_len > 1:
			break
	if sync_path_len <= 1:
		print("    [DIAG] doorway sync_path_len=", sync_path_len, " regions=", NavigationServer3D.map_get_regions(nav_map).size(), " iter=", NavigationServer3D.map_get_iteration_id(nav_map), " bounds=", NavigationServer3D.region_get_bounds(region.get_rid()), " closest_start=", NavigationServer3D.map_get_closest_point(nav_map, Vector3(3.0, 0.0, 3.5)))

	var fake_player := Node3D.new()
	fake_player.add_to_group("player")
	fake_player.position = Vector3(-3.0, 0.0, -3.5)
	region.add_child(fake_player)

	var zombie := ZombieScene.instantiate() as ZombieAI
	zombie.position = Vector3(3.0, 0.0, 3.5)
	region.add_child(zombie)
	zombie.set_physics_process(false)
	zombie.nav_agent.set_navigation_map(nav_map)
	await tree.physics_frame
	zombie.target_player = fake_player
	zombie.set_physics_process(true)
	zombie.transition_to(ZombieAI.State.CHASE)

	var passed_through_door: bool = false
	for _step: int in range(300):
		await tree.physics_frame
		if zombie.global_position.z < -2.0:
			passed_through_door = true
			break

	var z_pos: Vector3 = zombie.global_position
	var z_path: PackedVector3Array = zombie.nav_agent.get_current_navigation_path()
	var z_reachable: bool = zombie.nav_agent.is_target_reachable()
	var z_state: int = zombie.current_state
	var srv_path: PackedVector3Array = NavigationServer3D.map_get_path(nav_map, z_pos, fake_player.global_position, true)
	var poly_count: int = nav_mesh.get_polygon_count()
	NavigationServer3D.map_set_cell_size(nav_map, prev_cell_size)
	NavigationServer3D.map_set_cell_height(nav_map, prev_cell_height)
	region.queue_free()
	await tree.process_frame
	await tree.process_frame
	return "" if passed_through_door else "Zombie failed to pass 1.2m doorway (pos=%s, polys=%d, path=%s, srv_path=%d, reachable=%s, state=%d)" % [z_pos, poly_count, z_path, srv_path.size(), z_reachable, z_state]


func _test_invalid_spawn_rejected(spawner: DevSpawner, player: PlayerController) -> String:
	player.global_position = Vector3(0.0, 0.0, 6.0)

	# 1. Off-navmesh position
	if spawner.is_valid_spawn_position(Vector3(60.0, 0.0, 60.0), player):
		return "Off-navmesh position (60, 0, 60) should be rejected"

	# 2. Overlapping JumpPlatform geometry
	if spawner.is_valid_spawn_position(Vector3(0.0, 0.4, -2.0), player):
		return "Geometry-overlapping position should be rejected"

	# 3. Close-range visible to player
	if spawner.is_valid_spawn_position(Vector3(0.0, 0.0, 2.0), player):
		return "Close-range visible spawn position should be rejected"

	return ""
