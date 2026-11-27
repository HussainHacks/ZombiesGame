extends SceneTree
## Generates pre-baked NavigationMesh .tres files for all 4 door combinations
## under res://resources/navmeshes/ so standalone exports have a verified fallback.

const CompoundScene := preload("res://scenes/environment/greybox_compound.tscn")


func _initialize() -> void:
	_run()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://resources/navmeshes"))
	var compound := CompoundScene.instantiate() as Node3D
	root.add_child(compound)
	var nav_region := compound.get_node("NavRegion") as NavigationRegion3D
	for _w: int in range(20):
		if nav_region.navigation_mesh.get_polygon_count() > 0:
			break
		await process_frame
	await physics_frame

	var door_hall := compound.find_child("DoorToHall", true, false) as Door
	var door_yard := compound.find_child("DoorToCourtyard", true, false) as Door
	if door_hall == null or door_yard == null:
		printerr("Missing doors")
		quit(1)
		return

	# 1. Closed
	_save_mesh(nav_region, "res://resources/navmeshes/nav_closed.tres")

	# 2. Hall open
	door_hall.collision_shape.disabled = true
	door_hall.collision_layer = 0
	await physics_frame
	nav_region.bake_navigation_mesh(false)
	_save_mesh(nav_region, "res://resources/navmeshes/nav_hall_open.tres")

	# 3. Both open
	door_yard.collision_shape.disabled = true
	door_yard.collision_layer = 0
	await physics_frame
	nav_region.bake_navigation_mesh(false)
	_save_mesh(nav_region, "res://resources/navmeshes/nav_both_open.tres")

	# 4. Yard open only
	door_hall.collision_shape.disabled = false
	door_hall.collision_layer = 17
	await physics_frame
	nav_region.bake_navigation_mesh(false)
	_save_mesh(nav_region, "res://resources/navmeshes/nav_yard_open.tres")

	compound.queue_free()
	await process_frame
	quit(0)


func _save_mesh(nav_region: NavigationRegion3D, path: String) -> void:
	var copy := nav_region.navigation_mesh.duplicate() as NavigationMesh
	var err: Error = ResourceSaver.save(copy, path)
	print("PREBAKE | %s | polys=%d | err=%d" % [path, copy.get_polygon_count(), err])
