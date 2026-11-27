extends SceneTree
## Step 0.2 & 0.3 profiler: measures Performance monitors (process/physics/nav ms,
## draw calls), bisects Phase 10 regression, and times door open rebake with 20 zombies.

const CompoundScene := preload("res://scenes/environment/greybox_compound.tscn")
const ZombieScene := preload("res://scenes/enemies/zombie_standard.tscn")


func _initialize() -> void:
	_run()


func _run() -> void:
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
	var pm := compound.get_node("PointsManager") as PointsManager
	var door_hall := compound.get_node("NavRegion/DoorToHall") as Door
	var setm: Node = root.get_node_or_null("SettingsManager")
	var gs: Node = root.get_node_or_null("GameState")

	player.set_process_unhandled_input(false)
	ac.restart_run()
	rm.stop_and_cleanup()
	player.player_health.health_component.max_health = 99999.0
	player.player_health.health_component.restore_full_health()
	if gs != null:
		gs.call("start_run")

	if not player.is_flashlight_on():
		player.toggle_flashlight()

	var orig_vsync: bool = bool(setm.get("vsync")) if setm != null else true
	var sm_node: Node = root.get_node_or_null("SaveManager")
	if setm != null and sm_node != null:
		setm.call("set_vsync", sm_node.call("get_default_vsync"))
	# Measure 0 zombies (Low)
	if setm != null:
		setm.call("set_quality_preset", "low")
	await _log_case("0_zombies_low", 45)

	# Spawn 20 zombies
	var zombies: Array[ZombieAI] = []
	for i: int in range(20):
		var z := ZombieScene.instantiate() as ZombieAI
		compound.add_child(z)
		z.global_position = Vector3(float(i % 5 - 2) * 1.6, 0.0, 4.0 - float(i / 5) * 1.4)
		z.transition_to(ZombieAI.State.CHASE)
		zombies.append(z)
	ImpactEffect.spawn(compound, Vector3(0.0, 1.0, 4.0), Vector3.UP, true)

	if setm != null:
		setm.call("set_quality_preset", "high")
	await _log_case("20_zombies_high", 60)

	if setm != null:
		setm.call("set_quality_preset", "low")
	await _log_case("20_zombies_low", 60)

	# Bisect on Low
	player.toggle_flashlight()
	await _log_case("bisect_flashlight_off", 45)
	player.toggle_flashlight()

	var we := compound.get_node("WorldEnvironment") as WorldEnvironment
	we.environment.fog_enabled = false
	await _log_case("bisect_fog_off", 45)
	we.environment.fog_enabled = true

	var lights_node := compound.get_node("InteriorLights") as Node3D
	lights_node.visible = false
	await _log_case("bisect_lights_off", 45)
	lights_node.visible = true

	var dressing := compound.get_node("CompoundDressing") as Node3D
	dressing.visible = false
	await _log_case("bisect_props_hidden", 45)
	dressing.visible = true

	var amb := compound.get_node("AmbienceManager") as Node
	amb.call("stop_all")
	amb.set_process(false)
	await _log_case("bisect_ambience_off", 45)

	ImpactEffect.clear_all()
	await _log_case("bisect_particles_off", 45)

	# 0.3 Door rebake timing with 20 zombies active
	pm.add_points(1000, "test")
	var t0: int = Time.get_ticks_usec()
	door_hall.purchase(player, pm)
	var worst_dt_ms: float = 0.0
	var prev_us: int = t0
	for _f: int in range(15):
		await process_frame
		var now_us: int = Time.get_ticks_usec()
		worst_dt_ms = maxf(worst_dt_ms, float(now_us - prev_us) / 1000.0)
		prev_us = now_us
	print("DOOR_REBAKE | worst_frame_ms=%.2f" % worst_dt_ms)

	if setm != null:
		setm.call("set_vsync", orig_vsync)
	for z: ZombieAI in zombies:
		if is_instance_valid(z):
			z.queue_free()
	compound.queue_free()
	await process_frame
	quit(0)


func _log_case(label: String, frames: int) -> void:
	for _w: int in range(10):
		await process_frame
	var total_dt: float = 0.0
	var max_dt: float = 0.0
	var sum_proc: float = 0.0
	var sum_phys: float = 0.0
	var sum_nav: float = 0.0
	var prev_us: int = Time.get_ticks_usec()
	for _i: int in range(frames):
		await process_frame
		var now_us: int = Time.get_ticks_usec()
		var dt: float = float(now_us - prev_us) / 1000000.0
		prev_us = now_us
		total_dt += dt
		max_dt = maxf(max_dt, dt)
		sum_proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		sum_phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		sum_nav += Performance.get_monitor(Performance.TIME_NAVIGATION_PROCESS) * 1000.0
	var avg_fps: float = float(frames) / maxf(total_dt, 0.001)
	var min_fps: float = 1.0 / maxf(max_dt, 0.0001)
	var draws: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var objs: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	print("PERF_CASE | %-22s | avg=%.1f | min=%.1f | draws=%d | objs=%d | proc=%.2fms | phys=%.2fms | nav=%.2fms" % [
		label, avg_fps, min_fps, draws, objs, sum_proc / frames, sum_phys / frames, sum_nav / frames
	])
