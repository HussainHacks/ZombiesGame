extends SceneTree
## Phase 12 Step 0.2: Measures frame pacing (avg/p95/p99 frame time, avg/min FPS)
## across VSYNC_ENABLED, VSYNC_ADAPTIVE, VSYNC_MAILBOX, and VSYNC_DISABLED + 60 FPS cap
## for Low and High with 20 zombies + flashlight ON at 1152x648, and diagnoses unit/hitches.

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

	var zombies: Array[ZombieAI] = []
	for i: int in range(20):
		var z := ZombieScene.instantiate() as ZombieAI
		compound.add_child(z)
		z.global_position = Vector3(float(i % 5 - 2) * 1.6, 0.0, 4.0 - float(i / 5) * 1.4)
		z.transition_to(ZombieAI.State.CHASE)
		zombies.append(z)
	ImpactEffect.spawn(compound, Vector3(0.0, 1.0, 4.0), Vector3.UP, true)

	print("ADAPTER=%s | RES=%s" % [RenderingServer.get_video_adapter_name(), DisplayServer.window_get_size()])

	var modes: Array[Dictionary] = [
		{"name": "VSYNC_ENABLED", "mode": DisplayServer.VSYNC_ENABLED, "cap": 0},
		{"name": "VSYNC_ADAPTIVE", "mode": DisplayServer.VSYNC_ADAPTIVE, "cap": 0},
		{"name": "VSYNC_MAILBOX", "mode": DisplayServer.VSYNC_MAILBOX, "cap": 0},
		{"name": "VSYNC_OFF_CAP60", "mode": DisplayServer.VSYNC_DISABLED, "cap": 60},
		{"name": "VSYNC_OFF_UNCAP", "mode": DisplayServer.VSYNC_DISABLED, "cap": 0},
	]

	for preset: String in ["low", "high"]:
		if setm != null:
			setm.call("set_quality_preset", preset)
		for m: Dictionary in modes:
			DisplayServer.window_set_vsync_mode(int(m["mode"]))
			Engine.max_fps = int(m["cap"])
			await _measure("%s_%s" % [preset.to_upper(), str(m["name"])], 180)

	# Restore defaults
	Engine.max_fps = 0
	if setm != null:
		setm.call("apply_all")

	for z: ZombieAI in zombies:
		if is_instance_valid(z):
			z.queue_free()
	ImpactEffect.clear_all()
	compound.queue_free()
	await process_frame
	quit(0)


func _measure(label: String, frames: int) -> void:
	for _w: int in range(20):
		await process_frame
	var dts_ms: Array[float] = []
	var sum_proc_raw: float = 0.0
	var sum_phys_raw: float = 0.0
	var sum_nav_raw: float = 0.0
	var prev_us: int = Time.get_ticks_usec()
	var worst_frames: Array[String] = []
	for f: int in range(frames):
		await process_frame
		var now_us: int = Time.get_ticks_usec()
		var dt_ms: float = float(now_us - prev_us) / 1000.0
		prev_us = now_us
		dts_ms.append(dt_ms)
		var p_raw: float = Performance.get_monitor(Performance.TIME_PROCESS)
		var ph_raw: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		var nv_raw: float = Performance.get_monitor(Performance.TIME_NAVIGATION_PROCESS)
		sum_proc_raw += p_raw
		sum_phys_raw += ph_raw
		sum_nav_raw += nv_raw
		if dt_ms > 22.0 and worst_frames.size() < 5:
			worst_frames.append("f%d:%.2fms(p=%.4f,ph=%.4f,nv=%.4f,dr=%d)" % [
				f, dt_ms, p_raw, ph_raw, nv_raw,
				int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
			])

	var sorted: Array[float] = dts_ms.duplicate()
	sorted.sort()
	var sum_ms: float = 0.0
	for v: float in sorted:
		sum_ms += v
	var avg_ms: float = sum_ms / float(frames)
	var p95_ms: float = sorted[mini(int(floor(float(frames) * 0.95)), frames - 1)]
	var p99_ms: float = sorted[mini(int(floor(float(frames) * 0.99)), frames - 1)]
	var max_ms: float = sorted[frames - 1]
	var avg_fps: float = 1000.0 / maxf(avg_ms, 0.001)
	var min_fps: float = 1000.0 / maxf(max_ms, 0.001)
	var actual_vsync: int = DisplayServer.window_get_vsync_mode()
	print("PACE | %-22s | vsync=%d | avg_ms=%.2f | p95=%.2f | p99=%.2f | max=%.2f | avg_fps=%.1f | min_fps=%.1f | raw_proc=%.5f | raw_phys=%.5f | raw_nav=%.5f" % [
		label, actual_vsync, avg_ms, p95_ms, p99_ms, max_ms, avg_fps, min_fps,
		sum_proc_raw / float(frames), sum_phys_raw / float(frames), sum_nav_raw / float(frames)
	])
	if not worst_frames.is_empty():
		print("  HITCHES(%s): %s" % [label, ", ".join(worst_frames)])
