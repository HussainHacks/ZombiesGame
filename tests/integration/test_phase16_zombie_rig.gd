extends RefCounted
## Phase 16 integration tests (Issue #1):
## (a) A spawned crowd contains both male and female variants from data.
## (b) Both variants share the humanoid skeleton & AnimationTree, scale walk
##     speed, reach "attack" when in range, and reach "death" on lethal damage.

const CompoundScene := preload("res://scenes/environment/greybox_compound.tscn")
const ZombieScene := preload("res://scenes/enemies/zombie_standard.tscn")

var passed: int = 0
var failed: int = 0


func run_all(tree: SceneTree) -> Dictionary:
	passed = 0
	failed = 0
	await _run_test(tree, "spawned_crowd_contains_both_male_and_female_variants", _test_crowd_both_variants)
	await _run_test(tree, "both_variants_reach_attack_and_death_states", _test_both_variants_states)
	return {"passed": passed, "failed": failed}


func _run_test(tree: SceneTree, test_name: String, fn: Callable) -> void:
	var err: String = await fn.call(tree)
	if err.is_empty():
		print("  [PASS] ", test_name)
		passed += 1
	else:
		print("  [FAIL] ", test_name, ": ", err)
		failed += 1


func _test_crowd_both_variants(tree: SceneTree) -> String:
	var counts := {"male": 0, "female": 0}
	var shared_mats := {}
	var spawned: Array[ZombieAI] = []

	for i: int in range(24):
		var z := ZombieScene.instantiate() as ZombieAI
		tree.root.add_child(z)
		spawned.append(z)
		var vid: String = z.visual.get_variant_id()
		counts[vid] = int(counts.get(vid, 0)) + 1
		var mi := z.visual.mesh_inst
		if mi != null and mi.material_override != null:
			shared_mats[mi.material_override.get_instance_id()] = true

	await tree.process_frame
	for z: ZombieAI in spawned:
		z.queue_free()
	await tree.process_frame

	if int(counts.get("male", 0)) == 0 or int(counts.get("female", 0)) == 0:
		return "Spawned crowd missing a variant (male=%d, female=%d)" % [counts["male"], counts["female"]]
	if shared_mats.size() != 1:
		return "Expected 1 shared material across all variants, got %d" % shared_mats.size()
	return ""


func _test_both_variants_states(tree: SceneTree) -> String:
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
	rm.stop_and_cleanup()
	var player := compound.get_node("Player") as PlayerController
	player.player_health.health_component.max_health = 99999.0
	player.player_health.health_component.restore_full_health()
	player.global_position = Vector3(0.0, 0.1, 6.0)

	for vid: String in ["male", "female"]:
		var z := ZombieScene.instantiate() as ZombieAI
		compound.add_child(z)
		z.global_position = Vector3(0.0, 0.1, 2.0)
		z.target_player = player
		z.apply_round_scaling(1.0, 1.5)
		if not z.visual.set_variant(vid):
			compound.queue_free()
			await tree.process_frame
			return "Failed to select variant '%s'" % vid
		await tree.physics_frame

		var rig := z.visual.get_node_or_null("ZombieRig") as Node3D
		var skel := rig.find_child("Skeleton3D", true, false) as Skeleton3D if rig != null else null
		var skinned_meshes := rig.find_children("*", "MeshInstance3D", true, false) if rig != null else []
		if skel == null or skel.get_bone_count() < 12 or skinned_meshes.size() != 1:
			compound.queue_free()
			await tree.process_frame
			return "Variant '%s' rig invalid (skel=%s, meshes=%d)" % [vid, str(skel != null), skinned_meshes.size()]

		z.transition_to(ZombieAI.State.CHASE)
		var saw_walk: bool = false
		var walk_scale: float = 0.0
		var saw_attack: bool = false
		for _f: int in range(180):
			await tree.physics_frame
			await tree.process_frame
			var cur: StringName = z.visual.get_current_anim_state()
			if cur == &"walk":
				saw_walk = true
				walk_scale = z.visual.get_walk_time_scale()
			if cur == &"attack":
				saw_attack = true
				break

		if not saw_walk or walk_scale <= 1.2:
			compound.queue_free()
			await tree.process_frame
			return "Variant '%s' did not reach walk with scaled rate (saw_walk=%s, scale=%.2f)" % [vid, saw_walk, walk_scale]
		if not saw_attack:
			compound.queue_free()
			await tree.process_frame
			return "Variant '%s' did not reach attack in range" % vid

		z.health_component.take_damage(9999.0, false, player)
		var saw_death: bool = false
		for _f: int in range(30):
			await tree.physics_frame
			await tree.process_frame
			if is_instance_valid(z) and z.visual.get_current_anim_state() == &"death":
				saw_death = true
				break

		if is_instance_valid(z):
			z.queue_free()
		await tree.process_frame
		if not saw_death:
			compound.queue_free()
			await tree.process_frame
			return "Variant '%s' did not reach death on lethal damage" % vid

	compound.queue_free()
	await tree.process_frame
	return ""
