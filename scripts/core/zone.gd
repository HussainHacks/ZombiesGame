class_name Zone
extends Node3D
## Represents a playable map zone that owns spawn markers and barricades.
## Starts locked unless starts_unlocked is true.

signal zone_unlocked(zone: Zone)

@export var zone_id: String = "zone"
@export var starts_unlocked: bool = false
@export var adjacent_zone_ids: Array[String] = []
@export var bounds_size: Vector3 = Vector3(12.0, 5.0, 12.0)

var is_unlocked: bool = false
var spawn_markers: Array[Marker3D] = []
var barricades: Array[Node] = []


func _ready() -> void:
	add_to_group("zone")
	is_unlocked = starts_unlocked
	_collect_children_recursive(self)


func _collect_children_recursive(node: Node) -> void:
	for child: Node in node.get_children():
		if child is Marker3D and child.is_in_group("zombie_spawn"):
			spawn_markers.append(child as Marker3D)
		elif child.is_in_group("barricade"):
			barricades.append(child)
		_collect_children_recursive(child)


func unlock() -> void:
	if is_unlocked:
		return
	is_unlocked = true
	zone_unlocked.emit(self)


func reset_zone() -> void:
	is_unlocked = starts_unlocked


func contains_point(world_pos: Vector3) -> bool:
	var local_pos: Vector3 = to_local(world_pos) if is_inside_tree() else (world_pos - position)
	return (
		absf(local_pos.x) <= bounds_size.x * 0.5
		and absf(local_pos.y) <= bounds_size.y * 0.5
		and absf(local_pos.z) <= bounds_size.z * 0.5
	)
