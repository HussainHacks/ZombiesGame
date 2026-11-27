class_name ZoneManager
extends Node
## Coordinates map zones, unlock state, and weighted spawn marker selection
## favoring unlocked zones near the player.

signal zone_unlocked(zone: Zone)

@export var current_zone_weight: float = 3.0
@export var adjacent_zone_weight: float = 2.0
@export var other_zone_weight: float = 1.0

var zones: Dictionary = {} # zone_id -> Zone


func _ready() -> void:
	add_to_group("zone_manager")
	refresh_zones()


func refresh_zones() -> void:
	zones.clear()
	for node: Node in get_tree().get_nodes_in_group("zone"):
		if node is Zone:
			var z := node as Zone
			zones[z.zone_id] = z
			if not z.zone_unlocked.is_connected(_on_zone_unlocked):
				z.zone_unlocked.connect(_on_zone_unlocked)


func unlock_zone(zone_id: String) -> bool:
	var z: Zone = zones.get(zone_id) as Zone
	if z == null:
		return false
	z.unlock()
	return true


func is_zone_unlocked(zone_id: String) -> bool:
	var z: Zone = zones.get(zone_id) as Zone
	return z != null and z.is_unlocked


func get_player_zone(player_pos: Vector3) -> Zone:
	for z: Zone in zones.values():
		if z.is_unlocked and z.contains_point(player_pos):
			return z
	return null


func get_eligible_spawn_entries(player_pos: Vector3) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var player_zone: Zone = get_player_zone(player_pos)

	for z: Zone in zones.values():
		if not z.is_unlocked:
			continue
		var weight: float = other_zone_weight
		if player_zone != null:
			if z == player_zone:
				weight = current_zone_weight
			elif player_zone.adjacent_zone_ids.has(z.zone_id):
				weight = adjacent_zone_weight

		for marker: Marker3D in z.spawn_markers:
			if not is_instance_valid(marker):
				continue
			var linked_barricade: Node = _find_barricade_for_marker(marker, z)
			entries.append({
				"marker": marker,
				"zone": z,
				"barricade": linked_barricade,
				"weight": weight,
			})
	return entries


func reset_all_zones() -> void:
	for z: Zone in zones.values():
		z.reset_zone()


func _find_barricade_for_marker(marker: Marker3D, zone: Zone) -> Node:
	if marker.has_meta("barricade_path"):
		var rel: NodePath = marker.get_meta("barricade_path")
		var target: Node = marker.get_node_or_null(rel)
		if target != null:
			return target
	# Fallback: nearest barricade in the same zone if within 8m
	var best: Node = null
	var best_dist: float = 8.0
	for b: Node in zone.barricades:
		if b is Node3D:
			var d: float = marker.global_position.distance_to((b as Node3D).global_position)
			if d < best_dist:
				best_dist = d
				best = b
	return best


func _on_zone_unlocked(zone: Zone) -> void:
	zone_unlocked.emit(zone)
