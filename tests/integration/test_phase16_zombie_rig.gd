extends RefCounted
## Phase 16 integration test: rigged humanoid zombie has 1 skinned mesh + Skeleton3D,
## AnimationTree state machine scales walk rate, reaches "attack" in range, and
## reaches "death" on lethal damage before cleanup.

const CompoundScene := preload("res://scenes/environment/greybox_compound.tscn")
const ZombieScene := preload("res://scenes/enemies/zombie_standard.tscn")

var passed: int = 0
var failed: int = 0


func run_all(tree: SceneTree) -> Dictionary:
	passed = 0
	failed = 0
	await _run_test(tree, "zombie_rig_state_machine_walk_attack_and_death", _test_zombie_rig_states)
	return {"passed": passed, "failed": failed}


func _run_test(tree: SceneTree, test_name: String, fn: Callable) -> void:
	var err: String = await fn.call(tree)
	if err.is_empty():
		print("  [PASS] ", test_name)
		passed += 1
	else:
		print("  [FAIL] ", test_name, ": ", err)
		failed += 1


func _test_zombie_rig_states(tree: SceneTree) -> String:
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

	var z := ZombieScene.instantiate() as ZombieAI
	compound.add_child(z)
	z.global_position = Vector3(0.0, 0.1, 2.0)
	z.target_player = player
	z.apply_round_scaling(1.0, 1.5)
	await tree.physics_frame

	# Verify single skinned MeshInstance3D + Skeleton3D + active AnimationTree
	var rig := z.visual.get_node_or_null("ZombieRig") as Node3D
	if rig == null:
		compound.queue_free()
		await tree.process_frame
		return "ZombieRig missing under VisualRoot"
	var skel := rig.find_child("Skeleton3D", true, false) as Skeleton3D
	var skinned_meshes := rig.find_children("*", "MeshInstance3D", true, false)
	if skel == null or skel.get_bone_count() < 10:
		compound.queue_free()
		await tree.process_frame
		return "Skeleton3D missing or insufficient bones"
	if skinned_meshes.size() != 1:
		compound.queue_free()
		await tree.process_frame
		return "Expected exactly 1 skinned MeshInstance3D, got %d" % skinned_meshes.size()
	if z.visual.anim_tree == null or not z.visual.anim_tree.active:
		compound.queue_free()
		await tree.process_frame
		return "AnimationTree missing or inactive"

	# 1. Chase -> walk state with scaled TimeScale
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
		return "Zombie did not reach walk with scaled rate (saw_walk=%s, walk_scale=%.2f)" % [saw_walk, walk_scale]
	if not saw_attack:
		compound.queue_free()
		await tree.process_frame
		return "Zombie AnimationTree did not reach attack when in range (cur=%s)" % str(z.visual.get_current_anim_state())

	# 2. Lethal damage -> death state before cleanup
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
	compound.queue_free()
	await tree.process_frame

	if not saw_death:
		return "Zombie AnimationTree did not reach death on lethal damage"
	return ""
