class_name MysteryBoxManager
extends Node
## Manages active MysteryBox placement across unlocked zone locations and
## handles relocation on box jams and run resets.

@export var mystery_box_path: NodePath
@export var start_location_index: int = 0

var active_box: MysteryBox = null
var locations: Array[Marker3D] = []
var current_location_index: int = 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group("mystery_box_manager")
	_rng.randomize()
	active_box = get_node_or_null(mystery_box_path) as MysteryBox
	if active_box == null:
		active_box = get_tree().get_first_node_in_group("mystery_box") as MysteryBox

	for node: Node in get_tree().get_nodes_in_group("mystery_box_location"):
		if node is Marker3D:
			locations.append(node as Marker3D)

	if active_box != null and not active_box.relocation_requested.is_connected(_on_relocation_requested):
		active_box.relocation_requested.connect(_on_relocation_requested)

	reset_manager()


func reset_manager() -> void:
	if active_box != null:
		active_box.reset_box()
	if not locations.is_empty():
		current_location_index = clampi(start_location_index, 0, locations.size() - 1)
		_move_box_to(locations[current_location_index])


func get_unlocked_other_locations() -> Array[Marker3D]:
	var zm: ZoneManager = get_tree().get_first_node_in_group("zone_manager") as ZoneManager
	var candidates: Array[Marker3D] = []
	for i: int in range(locations.size()):
		if i == current_location_index:
			continue
		var loc: Marker3D = locations[i]
		if zm != null and loc.has_meta("zone_id"):
			var zid: String = str(loc.get_meta("zone_id"))
			if not zm.is_zone_unlocked(zid):
				continue
		candidates.append(loc)
	return candidates


func _on_relocation_requested() -> void:
	var candidates: Array[Marker3D] = get_unlocked_other_locations()
	if candidates.is_empty():
		return

	var old_loc: Marker3D = locations[current_location_index] if current_location_index < locations.size() else null
	var next_loc: Marker3D = candidates[_rng.randi_range(0, candidates.size() - 1)]
	current_location_index = locations.find(next_loc)
	_move_box_to(next_loc)

	if is_inside_tree():
		var ge: Node = get_node_or_null("/root/GameEvents")
		if ge != null:
			ge.emit_signal("box_relocated", old_loc, next_loc)


func _move_box_to(loc: Marker3D) -> void:
	if active_box != null and loc != null:
		active_box.global_transform = loc.global_transform
