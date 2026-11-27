extends SceneTree
## Step 5 & Step 6: Benchmarks Low vs High quality in windowed mode with ~20
## active zombies + flashlight ON, logs Performance monitors, and captures
## screenshots of each room and the yard for visual inspection.

const CompoundScene := preload("res://scenes/environment/greybox_compound.tscn")
const ZombieScene := preload("res://scenes/enemies/zombie_standard.tscn")


func _initialize() -> void:
	_run()


func _run() -> void:
	var out_dir: String = "C:/Users/syedhuss/.gemini/antigravity/brain/ef4eeff1-5b63-4109-b244-397d620e3288/scratch"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.substr(6)

	var compound := CompoundScene.instantiate() as Node3D
	root.add_child(compound)
	var nav_region := compound.get_node("NavRegion") as NavigationRegion3D
	for _w: int in range(20):
		if nav_region.navigation_mesh.get_polygon_count() > 0:
			break
		await process_frame
	await physics_frame
	await physics_frame

	var player := compound.get_node("Player") as PlayerController
	var rm := compound.get_node("RoundManager") as RoundManager
	var ac := compound.get_node("ArenaController") as ArenaController
	var setm: Node = root.get_node_or_null("SettingsManager")
	var gs: Node = root.get_node_or_null("GameState")

	player.set_process_unhandled_input(false)
	ac.restart_run()
	rm.stop_and_cleanup()
	player.player_health.health_component.max_health = 99999.0
	player.player_health.health_component.restore_full_health()
	if gs != null:
		gs.call("start_run")

	# Ensure flashlight ON
	if not player.is_flashlight_on():
		player.toggle_flashlight()

	# Spawn 20 active zombies in StartRoom / Hall / Yard
	var zombies: Array[ZombieAI] = []
	for i: int in range(20):
		var z := ZombieScene.instantiate() as ZombieAI
		compound.add_child(z)
		z.global_position = Vector3(float(i % 5 - 2) * 1.6, 0.0, 4.0 - float(i / 5) * 1.4)
		z.transition_to(ZombieAI.State.CHASE)
		zombies.append(z)

	# Trigger 1 blood burst so particle count is visible
	ImpactEffect.spawn(compound, Vector3(0.0, 1.0, 4.0), Vector3.UP, true)

	var gpu_name: String = RenderingServer.get_video_adapter_name()
	var win_size: Vector2i = DisplayServer.window_get_size()
	var lights_count: int = compound.find_children("*", "Light3D", true, false).size()
	var particles_count: int = compound.find_children("*", "CPUParticles3D", true, false).size()

	# Benchmark High
	if setm != null:
		setm.call("set_quality_preset", "high")
	var high_stats: Dictionary = await _measure_frames(90)

	# Benchmark Low
	if setm != null:
		setm.call("set_quality_preset", "low")
	var low_stats: Dictionary = await _measure_frames(90)

	# Restore High for screenshots
	if setm != null:
		setm.call("set_quality_preset", "high")
	for _f: int in range(10):
		await process_frame

	print("PERF_BENCH | GPU=%s | Res=%dx%d | Lights=%d | Particles=%d" % [
		gpu_name, win_size.x, win_size.y, lights_count, particles_count
	])
	print("PERF_HIGH | avg_fps=%.1f | min_fps=%.1f | draw_calls=%d | objects=%d" % [
		high_stats["avg_fps"], high_stats["min_fps"], high_stats["draw_calls"], high_stats["objects"]
	])
	print("PERF_LOW  | avg_fps=%.1f | min_fps=%.1f | draw_calls=%d | objects=%d" % [
		low_stats["avg_fps"], low_stats["min_fps"], low_stats["draw_calls"], low_stats["objects"]
	])

	# Capture 4 screenshots using a dedicated Camera3D
	var shot_cam := Camera3D.new()
	shot_cam.fov = 80.0
	compound.add_child(shot_cam)
	shot_cam.current = true
	# Attach a temporary flashlight to shot_cam so rooms show real flashlight illumination
	var shot_light := SpotLight3D.new()
	shot_light.light_color = Color(1.0, 0.95, 0.84)
	shot_light.light_energy = 2.4
	shot_light.spot_range = 18.0
	shot_light.spot_angle = 32.0
	shot_cam.add_child(shot_light)

	await _snap(shot_cam, Vector3(0.0, 1.6, 9.8), Vector3(0.0, 1.1, 1.0), "%s/shot_start_room.png" % out_dir)
	await _snap(shot_cam, Vector3(0.0, 1.6, -1.5), Vector3(0.0, 1.1, -10.0), "%s/shot_hall_room.png" % out_dir)
	await _snap(shot_cam, Vector3(0.0, 1.6, -12.6), Vector3(1.5, 1.0, -17.0), "%s/shot_courtyard.png" % out_dir)
	await _snap(shot_cam, Vector3(-4.5, 2.2, -14.8), Vector3(11.5, 1.0, -15.5), "%s/shot_yard_trees.png" % out_dir)

	for z: ZombieAI in zombies:
		if is_instance_valid(z):
			z.queue_free()
	ImpactEffect.clear_all()
	compound.queue_free()
	await process_frame
	quit(0)


func _measure_frames(count: int) -> Dictionary:
	for _w: int in range(15):
		await process_frame
	var total_dt: float = 0.0
	var max_dt: float = 0.0
	var prev_us: int = Time.get_ticks_usec()
	for _i: int in range(count):
		await process_frame
		var now_us: int = Time.get_ticks_usec()
		var dt: float = float(now_us - prev_us) / 1000000.0
		prev_us = now_us
		total_dt += dt
		max_dt = maxf(max_dt, dt)
	var avg_fps: float = float(count) / maxf(total_dt, 0.001)
	var min_fps: float = 1.0 / maxf(max_dt, 0.0001)
	var draws: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var objs: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	return {
		"avg_fps": avg_fps,
		"min_fps": min_fps,
		"draw_calls": draws,
		"objects": objs,
	}


func _snap(cam: Camera3D, pos: Vector3, look_at_pt: Vector3, save_path: String) -> void:
	cam.global_position = pos
	cam.look_at(look_at_pt, Vector3.UP)
	await process_frame
	await process_frame
	var img: Image = root.get_texture().get_image()
	var err: Error = img.save_png(save_path)
	print("SCREENSHOT | path=%s | err=%d" % [save_path, err])
