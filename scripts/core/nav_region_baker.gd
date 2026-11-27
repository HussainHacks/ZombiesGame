class_name NavRegionBaker
extends NavigationRegion3D
## Ensures the NavigationMesh is baked from child geometry once the scene
## tree has built CSG meshes and collisions, with pre-baked fallbacks for
## standalone/exported builds if runtime CSG baking yields 0 polygons.

const PREBAKED_PATHS := {
	"closed": "res://resources/navmeshes/nav_closed.tres",
	"hall_open": "res://resources/navmeshes/nav_hall_open.tres",
	"yard_open": "res://resources/navmeshes/nav_yard_open.tres",
	"both_open": "res://resources/navmeshes/nav_both_open.tres",
}


func _ready() -> void:
	if navigation_mesh != null and navigation_mesh.get_polygon_count() == 0:
		call_deferred("_bake_deferred")


func _bake_deferred() -> void:
	await get_tree().process_frame
	if navigation_mesh == null:
		return
	var nav_map: RID = get_navigation_map()
	if nav_map.is_valid():
		NavigationServer3D.map_set_cell_size(nav_map, navigation_mesh.cell_size)
		NavigationServer3D.map_set_cell_height(nav_map, navigation_mesh.cell_height)
	if navigation_mesh.get_polygon_count() == 0:
		bake_navigation_mesh(false)
		if navigation_mesh.get_polygon_count() == 0:
			apply_prebaked_fallback_if_empty()


func apply_prebaked_fallback_if_empty() -> void:
	if navigation_mesh != null and navigation_mesh.get_polygon_count() > 0:
		return
	var door_hall := get_node_or_null("DoorToHall")
	var door_yard := get_node_or_null("DoorToCourtyard")
	var h_open: bool = bool(door_hall.get("is_open")) if door_hall != null else false
	var y_open: bool = bool(door_yard.get("is_open")) if door_yard != null else false
	var key: String = "closed"
	if h_open and y_open:
		key = "both_open"
	elif h_open:
		key = "hall_open"
	elif y_open:
		key = "yard_open"
	var path: String = str(PREBAKED_PATHS.get(key, ""))
	if not path.is_empty() and ResourceLoader.exists(path):
		var prebaked := load(path) as NavigationMesh
		if prebaked != null and prebaked.get_polygon_count() > 0:
			navigation_mesh = prebaked.duplicate()
			var nav_map: RID = get_navigation_map()
			if nav_map.is_valid():
				NavigationServer3D.map_force_update(nav_map)
