extends RefCounted
## Phase 13 tests: MovementConfig profiles & persistence, ViewmodelRig FP arms &
## animation timing, surface-aware impacts, and procedural/animated props + navmesh.

const CompoundScene := preload("res://scenes/environment/greybox_compound.tscn")
const PlayerScene := preload("res://scenes/player/player.tscn")
const PistolRigScene := preload("res://scenes/weapons/viewmodel_pistol.tscn")
const MovementConfigScript := preload("res://scripts/core/movement_config.gd")


func run_all(tree: SceneTree) -> Dictionary:
	var results := {"passed": 0, "failed": 0, "failures": []}
	await _run_test("movement_profiles_and_effect_intensities_persist", _test_movement_profiles.bind(tree), results)
	await _run_test("fp_arms_character_colors_and_anim_timings", _test_fp_arms_and_anims.bind(tree), results)
	await _run_test("surface_aware_impacts_and_sounds_distinct", _test_surface_impacts.bind(tree), results)
	await _run_test("phase13_props_and_all_spawn_markers_navmesh_valid", _test_props_and_spawns.bind(tree), results)
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


func _test_movement_profiles(tree: SceneTree) -> String:
	var cfg := load("res://resources/configuration/movement_config.tres") as MovementConfigScript
	if cfg == null:
		return "Missing movement_config.tres"
	var rip: Dictionary = cfg.get_profile("riposte")
	var cls: Dictionary = cfg.get_profile("classic")
	if not is_equal_approx(float(rip["walk_speed"]), 4.75) or not bool(rip["slide_enabled"]):
		return "Riposte profile values mismatch"
	if not is_equal_approx(float(cls["walk_speed"]), 5.0) or bool(cls["slide_enabled"]):
		return "Classic profile values mismatch"

	var player := PlayerScene.instantiate() as PlayerController
	tree.root.add_child(player)
	await tree.process_frame
	player.apply_movement_profile("riposte")
	if not is_equal_approx(player.walk_speed, 4.75) or not is_equal_approx(player.gravity, 19.0):
		player.queue_free()
		await tree.process_frame
		return "PlayerController did not apply riposte profile"
	player.apply_movement_profile("classic")
	if not is_equal_approx(player.walk_speed, 5.0) or not is_equal_approx(player.gravity, 14.0):
		player.queue_free()
		await tree.process_frame
		return "PlayerController did not apply classic profile"
	player.queue_free()
	await tree.process_frame

	# Persistence & clamping
	var tmp := "res://.tmp_phase13_save.json"
	var abs_tmp := ProjectSettings.globalize_path(tmp)
	if FileAccess.file_exists(abs_tmp):
		DirAccess.remove_absolute(abs_tmp)
	var sm: Node = load("res://scripts/core/save_manager.gd").new()
	sm.set("save_path", tmp)
	sm.call("load_save")
	var s: Dictionary = sm.call("get_settings")
	s["movement_profile"] = "classic"
	s["camera_bob_intensity"] = 2.5
	s["landing_dip_intensity"] = -0.5
	sm.call("save_to_disk")
	sm.call("load_save")
	var s2: Dictionary = sm.call("get_settings")
	DirAccess.remove_absolute(abs_tmp)
	if str(s2["movement_profile"]) != "classic" or not is_equal_approx(float(s2["camera_bob_intensity"]), 1.0) or not is_equal_approx(float(s2["landing_dip_intensity"]), 0.0):
		return "Movement/intensity settings did not persist/clamp: %s" % s2
	return ""


func _test_fp_arms_and_anims(tree: SceneTree) -> String:
	var skins := {}
	var sleeves := {}
	for cid: String in ["marcus_vance", "simone_brooks", "devon_carter", "tasha_monroe"]:
		var cd := load("res://resources/characters/%s.tres" % cid) as CharacterData
		if cd == null:
			return "Missing CharacterData: %s" % cid
		skins[cd.skin_tone] = true
		sleeves[cd.sleeve_color] = true
	if skins.size() < 4 or sleeves.size() < 4:
		return "Expected 4 distinct skin_tone and sleeve_color values"

	var rig := PistolRigScene.instantiate() as ViewmodelRig
	tree.root.add_child(rig)
	await tree.process_frame
	if rig.left_arm_root == null or rig.right_arm_root == null or rig.anim_player == null or rig.muzzle_smoke == null:
		rig.queue_free()
		await tree.process_frame
		return "ViewmodelRig missing FP arms, anim_player, or muzzle_smoke"

	rig.configure_character_and_weapon(Color(0.5, 0.3, 0.2), Color(0.2, 0.4, 0.6), "shotgun")
	rig.trigger_reload(2.0)
	if not is_equal_approx(rig.anim_player.speed_scale, 0.5) or rig.anim_player.current_animation != "reload_shotgun":
		rig.queue_free()
		await tree.process_frame
		return "Reload animation speed_scale/clip mismatch: %s @ %.2f" % [rig.anim_player.current_animation, rig.anim_player.speed_scale]

	rig.set_reloading(false)
	rig.trigger_empty_fire()
	if rig.anim_player.current_animation != "empty_fire":
		rig.queue_free()
		await tree.process_frame
		return "empty_fire animation did not play"

	rig.queue_free()
	await tree.process_frame
	return ""


func _test_surface_impacts(tree: SceneTree) -> String:
	ImpactEffect.clear_all()
	var holder := Node3D.new()
	tree.root.add_child(holder)

	var metal_body := StaticBody3D.new()
	metal_body.set_meta("surface", "metal")
	if ImpactEffect.classify_surface(metal_body) != "metal":
		metal_body.free()
		holder.queue_free()
		await tree.process_frame
		return "classify_surface did not read meta surface=metal"
	metal_body.free()

	for surf: String in ImpactEffect.SURFACES:
		var fx: ImpactEffect = ImpactEffect.spawn_surface(holder, Vector3(0, 0.2, 0), Vector3.UP, surf)
		if fx == null or fx.surface_type != surf:
			ImpactEffect.clear_all()
			holder.queue_free()
			await tree.process_frame
			return "Failed spawning surface impact for %s" % surf
		var wav: AudioStreamWAV = ImpactEffect.get_surface_sound(surf)
		if wav == null or wav.data.is_empty():
			ImpactEffect.clear_all()
			holder.queue_free()
			await tree.process_frame
			return "Missing impact sound for %s" % surf

	ImpactEffect.clear_all()
	holder.queue_free()
	await tree.process_frame
	return ""


func _test_props_and_spawns(tree: SceneTree) -> String:
	var compound := CompoundScene.instantiate() as Node3D
	tree.root.add_child(compound)
	var nav_region := compound.get_node("NavRegion") as NavigationRegion3D
	var nav_map: RID = compound.get_world_3d().navigation_map
	for _w: int in range(60):
		await tree.physics_frame
		if not nav_region.is_baking() and nav_region.navigation_mesh != null and nav_region.navigation_mesh.get_polygon_count() > 0:
			NavigationServer3D.map_force_update(nav_map)
			if NavigationServer3D.map_get_closest_point(nav_map, Vector3(-11.0, 0.0, 6.0)) != Vector3.ZERO:
				break
	await tree.physics_frame

	var dressing := compound.get_node("CompoundDressing") as Node3D
	for req_name: String in ["CrashedCar", "BrokenTruck", "ConcreteBarrier", "SandbagWall", "YardWallDoorway", "YardFenceGate", "ElectricBox", "HangingLamp"]:
		if dressing.find_child(req_name, true, false) == null:
			compound.queue_free()
			await tree.process_frame
			return "Missing Phase 13 prop: %s" % req_name

	for m: Node in tree.get_nodes_in_group("zombie_spawn"):
		if is_instance_valid(m) and not m.is_queued_for_deletion() and m is Marker3D and compound.is_ancestor_of(m):
			var mp: Vector3 = (m as Marker3D).global_position
			var closest: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, mp)
			var dist: float = Vector2(mp.x - closest.x, mp.z - closest.z).length()
			if dist > 1.0:
				var m_name: String = m.name
				compound.queue_free()
				await tree.process_frame
				return "Spawn marker %s too far from navmesh: %.2fm (mp=%s closest=%s)" % [m_name, dist, str(mp), str(closest)]

	compound.queue_free()
	await tree.process_frame
	return ""
