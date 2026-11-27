extends RefCounted
## Phase 14 integration tests: every solid compound mesh/prop has a fitted
## collision body unless explicitly listed in CompoundDressing.NON_SOLID_DECORATION_REASONS,
## and the player is physically stopped by representative props.

const CompoundScene := preload("res://scenes/environment/greybox_compound.tscn")

var passed: int = 0
var failed: int = 0


func run_all(tree: SceneTree) -> Dictionary:
	passed = 0
	failed = 0
	await _run_test(tree, "all_compound_meshes_covered_by_collision_unless_excepted", _test_all_meshes_covered)
	await _run_test(tree, "player_stopped_by_three_representative_props", _test_player_stopped_by_props)
	return {"passed": passed, "failed": failed}


func _run_test(tree: SceneTree, test_name: String, fn: Callable) -> void:
	var err: String = await fn.call(tree)
	if err.is_empty():
		print("  [PASS] ", test_name)
		passed += 1
	else:
		print("  [FAIL] ", test_name, ": ", err)
		failed += 1


func _collect_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for child: Node in node.get_children():
		_collect_meshes(child, out)


func _has_active_collision_shape(body: Node) -> bool:
	for child: Node in body.get_children():
		if child is CollisionShape3D:
			var cs := child as CollisionShape3D
			if not cs.disabled and cs.shape != null:
				return true
	return false


func _find_covering_body(mi: MeshInstance3D, compound: Node) -> CollisionObject3D:
	# Check children first (automatic prop colliders attached to MeshInstance3D)
	for child: Node in mi.get_children():
		if child is CollisionObject3D and _has_active_collision_shape(child):
			return child as CollisionObject3D
	# Check ancestors up to compound root (e.g., StaticBody3D walls, doors, machines)
	var cur: Node = mi.get_parent()
	while cur != null and cur != compound:
		if cur is CollisionObject3D and _has_active_collision_shape(cur):
			return cur as CollisionObject3D
		cur = cur.get_parent()
	return null


func _is_scene_overhead_or_actor_mesh(mi: MeshInstance3D, player: Node) -> bool:
	if player != null and (mi == player or player.is_ancestor_of(mi)):
		return true
	# Ceiling light bulb meshes in InteriorLights (y >= 3.5m)
	if mi.get_parent() != null and mi.get_parent().get_parent() != null and mi.get_parent().get_parent().name == "InteriorLights":
		return true
	# Barricade visual frames/boards sit inside the window opening covered by BlockerBody/InteractCollider
	var cur: Node = mi.get_parent()
	while cur != null:
		if cur is Barricade:
			return true
		cur = cur.get_parent()
	return false


func _test_all_meshes_covered(tree: SceneTree) -> String:
	var compound := CompoundScene.instantiate() as Node3D
	tree.root.add_child(compound)
	await tree.physics_frame
	await tree.physics_frame

	var player := compound.get_node_or_null("Player")
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(compound, meshes)
	if meshes.is_empty():
		compound.queue_free()
		await tree.process_frame
		return "No MeshInstance3D nodes found in compound"

	var uncovered: Array[String] = []
	var bad_exceptions: Array[String] = []
	var solid_checked: int = 0
	var exception_checked: int = 0

	for mi: MeshInstance3D in meshes:
		if _is_scene_overhead_or_actor_mesh(mi, player):
			continue
		if mi.has_meta("non_solid_exception"):
			var tag: String = str(mi.get_meta("non_solid_exception"))
			if not CompoundDressing.NON_SOLID_DECORATION_REASONS.has(tag):
				bad_exceptions.append("%s (unknown tag '%s')" % [str(mi.get_path()), tag])
			else:
				exception_checked += 1
			continue
		var body: CollisionObject3D = _find_covering_body(mi, compound)
		if body == null:
			uncovered.append("%s at %s" % [mi.name, str(mi.global_position)])
		else:
			solid_checked += 1

	compound.queue_free()
	await tree.process_frame

	if not bad_exceptions.is_empty():
		return "Invalid non_solid_exception tags: %s" % ", ".join(bad_exceptions)
	if not uncovered.is_empty():
		return "Uncovered MeshInstance3D without collision (%d): %s" % [uncovered.size(), ", ".join(uncovered.slice(0, 5))]
	if solid_checked < 30 or exception_checked < 10:
		return "Unexpected mesh counts (solid=%d, exceptions=%d)" % [solid_checked, exception_checked]
	return ""


func _test_player_stopped_by_props(tree: SceneTree) -> String:
	var compound := CompoundScene.instantiate() as Node3D
	tree.root.add_child(compound)
	await tree.physics_frame
	await tree.physics_frame

	var rm := compound.get_node_or_null("RoundManager") as RoundManager
	if rm != null:
		rm.stop_and_cleanup()
	var player := compound.get_node("Player") as PlayerController
	player.player_health.health_component.max_health = 99999.0
	player.player_health.health_component.restore_full_health()

	# Three representative CompoundDressing props that previously had no collision:
	# 1) StartRoom wooden crate (-4.9, 0.4, 10.8)
	# 2) StartRoom metal barrel (4.9, 0.5, 10.9)
	# 3) Courtyard hay bale (-13.5, 0.45, -15.5)
	var probes := [
		{"name": "StartRoomCrate", "start": Vector3(-3.0, 0.1, 10.8), "target": Vector3(-4.9, 0.1, 10.8), "min_stop_dist": 0.45},
		{"name": "StartRoomBarrel", "start": Vector3(3.0, 0.1, 10.9), "target": Vector3(4.9, 0.1, 10.9), "min_stop_dist": 0.35},
		{"name": "CourtyardHayBale", "start": Vector3(-11.2, 0.1, -15.5), "target": Vector3(-13.5, 0.1, -15.5), "min_stop_dist": 0.55},
	]

	for p: Dictionary in probes:
		var start_pos: Vector3 = p["start"]
		var target_pos: Vector3 = p["target"]
		var min_dist: float = float(p["min_stop_dist"])
		var dir: Vector3 = (target_pos - start_pos)
		dir.y = 0.0
		dir = dir.normalized()

		player.global_position = start_pos
		player.velocity = Vector3.ZERO
		await tree.physics_frame

		for _f: int in range(60):
			player.velocity = dir * 5.0
			player.move_and_slide()
			await tree.physics_frame

		var end_xz := Vector2(player.global_position.x, player.global_position.z)
		var target_xz := Vector2(target_pos.x, target_pos.z)
		var dist_to_center: float = end_xz.distance_to(target_xz)
		if dist_to_center < min_dist:
			compound.queue_free()
			await tree.process_frame
			return "Player walked through %s (dist_to_center=%.2fm < %.2fm, end=%s)" % [
				str(p["name"]), dist_to_center, min_dist, str(player.global_position)
			]

	compound.queue_free()
	await tree.process_frame
	return ""
