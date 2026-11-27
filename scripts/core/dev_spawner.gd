class_name DevSpawner
extends Node
## Temporary Phase 3 dev scaffolding for spawning/killing zombies and
## validating spawn positions against navmesh, geometry, and player LOS.

const DebugGateScript := preload("res://scripts/core/debug_gate.gd")

@export var zombie_scene: PackedScene
@export var max_navmesh_distance: float = 1.0
@export var min_visible_spawn_distance: float = 12.0

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()


func _unhandled_input(event: InputEvent) -> void:
	if not DebugGateScript.is_debug_enabled():
		return
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if not key_event.pressed or key_event.echo:
			return
		if key_event.keycode == KEY_F9:
			spawn_random_zombie()
		elif key_event.keycode == KEY_F10:
			for _i: int in range(10):
				spawn_random_zombie()
		elif key_event.keycode == KEY_F11:
			kill_all_zombies()


func spawn_random_zombie() -> ZombieAI:
	if zombie_scene == null:
		return null
	var markers: Array[Node] = get_tree().get_nodes_in_group("zombie_spawn")
	if markers.is_empty():
		return null

	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	var indices: Array[int] = []
	for i: int in range(markers.size()):
		indices.append(i)
	indices.shuffle()

	for idx: int in indices:
		var marker := markers[idx] as Node3D
		if marker == null:
			continue
		if is_valid_spawn_position(marker.global_position, player):
			return _spawn_at(marker.global_position)

	# Fallback to first marker if all are visible in small test arena
	var fallback := markers[_rng.randi_range(0, markers.size() - 1)] as Node3D
	if fallback != null and is_valid_spawn_position(fallback.global_position, null):
		return _spawn_at(fallback.global_position)
	return null


func _spawn_at(world_pos: Vector3) -> ZombieAI:
	var instance := zombie_scene.instantiate() as ZombieAI
	if instance == null:
		return null
	get_parent().add_child(instance)
	instance.global_position = world_pos
	return instance


func kill_all_zombies() -> void:
	for node: Node in get_tree().get_nodes_in_group("zombies"):
		if node is ZombieAI:
			var z := node as ZombieAI
			if z.health_component != null and not z.health_component.is_dead:
				z.health_component.take_damage(99999.0, false, null)


func is_valid_spawn_position(pos: Vector3, player: Node3D = null) -> bool:
	var world_3d: World3D = get_viewport().world_3d if get_viewport() else null
	if world_3d == null:
		return false

	# 1. Navmesh proximity check
	var nav_map: RID = world_3d.navigation_map
	if not nav_map.is_valid():
		return false
	var closest: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, pos)
	if pos.distance_to(closest) > max_navmesh_distance:
		return false

	# 2. Geometry overlap check
	var space_state: PhysicsDirectSpaceState3D = world_3d.direct_space_state
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.6
	var shape_query := PhysicsShapeQueryParameters3D.new()
	shape_query.shape = capsule
	shape_query.transform = Transform3D(Basis.IDENTITY, pos + Vector3(0.0, 0.95, 0.0))
	shape_query.collision_mask = 1
	if not space_state.intersect_shape(shape_query, 1).is_empty():
		return false

	# 3. Close-range player line-of-sight check
	if player != null and pos.distance_to(player.global_position) < min_visible_spawn_distance:
		var from_pos: Vector3 = player.global_position + Vector3(0.0, 1.5, 0.0)
		var to_pos: Vector3 = pos + Vector3(0.0, 1.5, 0.0)
		var los_query := PhysicsRayQueryParameters3D.create(from_pos, to_pos, 1, [player.get_rid()])
		var hit: Dictionary = space_state.intersect_ray(los_query)
		if hit.is_empty():
			return false

	return true
