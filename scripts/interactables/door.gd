class_name Door
extends Purchasable
## Purchasable zone-gating door. Disables collision, enables NavigationLink3D,
## unlocks target zones, and slides open with placeholder 3D audio.

signal door_opened(door: Door)

@export var unlock_zone_ids: Array[String] = []
@export var slide_offset: Vector3 = Vector3(0.0, 3.0, 0.0)
@export var open_duration: float = 0.45

@onready var door_mesh: MeshInstance3D = $DoorMesh
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var nav_link: NavigationLink3D = $NavLink
@onready var nav_link_left: NavigationLink3D = get_node_or_null("NavLinkLeft") as NavigationLink3D
@onready var nav_link_right: NavigationLink3D = get_node_or_null("NavLinkRight") as NavigationLink3D
@onready var audio_player: AudioStreamPlayer3D = $AudioStreamPlayer3D

var is_open: bool = false
var _closed_mesh_pos: Vector3 = Vector3.ZERO
var _tween: Tween = null
var _open_stream: AudioStreamWAV = null


func _ready() -> void:
	super._ready()
	add_to_group("door")
	item_name = "Door"
	if door_mesh != null:
		_closed_mesh_pos = door_mesh.position
	_set_nav_links_enabled(false)
	_open_stream = BarricadeAudio.create_door_open_sound()


func _set_nav_links_enabled(enabled_val: bool) -> void:
	if nav_link != null:
		nav_link.enabled = enabled_val
	if nav_link_left != null:
		nav_link_left.enabled = enabled_val
	if nav_link_right != null:
		nav_link_right.enabled = enabled_val


func _exit_tree() -> void:
	if audio_player:
		audio_player.stop()
		audio_player.stream = null
	_open_stream = null


func can_purchase(player: Node, points_manager: PointsManager) -> bool:
	if is_open:
		return false
	return super.can_purchase(player, points_manager)


func get_prompt_text(player: Node) -> String:
	if is_open:
		return ""
	return "Press E - Buy door [%d]" % get_effective_cost(player)


func _apply_purchase(_player: Node) -> void:
	is_open = true
	collision_layer = 0
	if collision_shape != null:
		collision_shape.disabled = true
	_set_nav_links_enabled(false)

	if audio_player != null and _open_stream != null and is_inside_tree():
		audio_player.stream = _open_stream
		audio_player.play()

	if door_mesh != null and is_inside_tree():
		if _tween != null and _tween.is_valid():
			_tween.kill()
		_tween = create_tween()
		_tween.tween_property(door_mesh, "position", _closed_mesh_pos + slide_offset, open_duration)

	door_opened.emit(self)
	if is_inside_tree():
		var ge: Node = get_node_or_null("/root/GameEvents")
		if ge != null:
			ge.emit_signal("door_opened", self)

	_rebake_and_unlock_zones(true)


func _unlock_target_zones() -> void:
	if not is_inside_tree():
		return
	var zm: ZoneManager = get_tree().get_first_node_in_group("zone_manager") as ZoneManager
	if zm != null:
		for zid: String in unlock_zone_ids:
			zm.unlock_zone(zid)


func reset_door() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	var was_open: bool = is_open
	is_open = false
	collision_layer = 17
	if collision_shape != null:
		collision_shape.disabled = false
	_set_nav_links_enabled(false)
	if was_open:
		_rebake_parent_nav_region(false)
	if door_mesh != null:
		door_mesh.position = _closed_mesh_pos


func _rebake_parent_nav_region(async_bake: bool) -> void:
	if not is_inside_tree():
		return
	var nav_region := get_parent() as NavigationRegion3D
	if nav_region == null or nav_region.navigation_mesh == null:
		return
	if async_bake:
		await get_tree().physics_frame
		if not is_inside_tree():
			return
		while nav_region.is_baking():
			await nav_region.bake_finished
			if not is_inside_tree():
				return
		nav_region.bake_navigation_mesh(true)
		await nav_region.bake_finished
		if is_inside_tree():
			var nav_map: RID = nav_region.get_navigation_map()
			if nav_map.is_valid():
				NavigationServer3D.map_force_update(nav_map)
	else:
		if not nav_region.is_baking():
			nav_region.bake_navigation_mesh(false)
			var nav_map: RID = nav_region.get_navigation_map()
			if nav_map.is_valid():
				NavigationServer3D.map_force_update(nav_map)


func _rebake_and_unlock_zones(async_bake: bool) -> void:
	await _rebake_parent_nav_region(async_bake)
	if not is_inside_tree() or not is_open:
		return
	var nav_region := get_parent() as NavigationRegion3D
	if nav_region != null and nav_region.has_method("apply_prebaked_fallback_if_empty"):
		nav_region.call("apply_prebaked_fallback_if_empty")
	_unlock_target_zones()
