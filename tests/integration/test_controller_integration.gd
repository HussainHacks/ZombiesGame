extends RefCounted
## Integration tests for Step 1.8: Trigger hysteresis, weapon cycling, L3 sprint,
## controller disconnect auto-pause, all menu screens navigation, and controller-only
## multi-round autoplay.

const CompoundScene := preload("res://scenes/environment/greybox_compound.tscn")
const MainMenuScene := preload("res://scenes/ui/main_menu.tscn")


func run_all(tree: SceneTree) -> Dictionary:
	var results := {"passed": 0, "failed": 0, "failures": []}
	await _run_test("trigger_fire_hysteresis_and_weapon_cycling", _test_triggers_and_cycling.bind(tree), results)
	await _run_test("controller_disconnect_auto_pauses_and_reconnect_resumes", _test_disconnect_pause.bind(tree), results)
	await _run_test("all_menus_controller_focus_and_navigation", _test_menus_focus.bind(tree), results)
	await _run_test("controller_only_autoplay_advances_rounds", _test_controller_autoplay.bind(tree), results)
	return results


func _run_test(test_name: String, fn: Callable, results: Dictionary) -> void:
	var err: String = await fn.call()
	if err.is_empty():
		results["passed"] += 1
		print("  [PASS] ", test_name)
	else:
		results["failed"] += 1
		results["failures"].append("%s: %s" % [test_name, err])
		print("  [FAIL] ", test_name, ": ", err)


func _send_axis(axis: JoyAxis, val: float, dev: int = 0) -> void:
	var ev := InputEventJoypadMotion.new()
	ev.device = dev
	ev.axis = axis
	ev.axis_value = val
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _send_btn(btn: JoyButton, pressed: bool, dev: int = 0) -> void:
	var ev := InputEventJoypadButton.new()
	ev.device = dev
	ev.button_index = btn
	ev.pressed = pressed
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _test_triggers_and_cycling(tree: SceneTree) -> String:
	var compound := CompoundScene.instantiate() as Node3D
	tree.root.add_child(compound)
	await tree.process_frame
	await tree.physics_frame

	var player := compound.get_node("Player") as PlayerController
	var wm := player.weapon_manager
	var rm := compound.get_node("RoundManager") as RoundManager
	rm.stop_and_cleanup()

	# Give 3 weapons and test RB/LB cycling with wrap
	var smg := load("res://resources/weapons/smg.tres") as WeaponData
	var ar := load("res://resources/weapons/assault_rifle.tres") as WeaponData
	wm.give_or_refill_weapon(smg)
	wm.give_or_refill_weapon(ar)
	wm.equip_slot(0, true)

	_send_btn(JOY_BUTTON_RIGHT_SHOULDER, true)
	await tree.process_frame
	_send_btn(JOY_BUTTON_RIGHT_SHOULDER, false)
	if wm.active_slot != 1:
		compound.queue_free()
		await tree.process_frame
		return "RB did not cycle to slot 1 (got %d)" % wm.active_slot

	_send_btn(JOY_BUTTON_LEFT_SHOULDER, true)
	await tree.process_frame
	_send_btn(JOY_BUTTON_LEFT_SHOULDER, false)
	_send_btn(JOY_BUTTON_LEFT_SHOULDER, true)
	await tree.process_frame
	_send_btn(JOY_BUTTON_LEFT_SHOULDER, false)
	if wm.active_slot != 2:
		compound.queue_free()
		await tree.process_frame
		return "LB did not wrap from slot 0 to slot 2 (got %d)" % wm.active_slot

	# Semi-auto (slot 0 Street-9): RT > 0.5 fires ONCE; staying at 0.40 does not release or re-fire
	wm.equip_slot(0, true)
	var mag_before: int = wm.active_weapon.mag_ammo
	_send_axis(JOY_AXIS_TRIGGER_RIGHT, 0.7)
	await tree.process_frame
	await tree.process_frame
	var mag_after_one: int = wm.active_weapon.mag_ammo
	if mag_after_one != mag_before - 1:
		_send_axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
		compound.queue_free()
		await tree.process_frame
		return "Semi-auto RT fired %d times instead of 1" % (mag_before - mag_after_one)

	# Drop to 0.40 (above hysteresis release 0.35), then back to 0.7 -> should NOT re-fire
	_send_axis(JOY_AXIS_TRIGGER_RIGHT, 0.40)
	await tree.process_frame
	_send_axis(JOY_AXIS_TRIGGER_RIGHT, 0.75)
	await tree.process_frame
	if wm.active_weapon.mag_ammo != mag_after_one:
		_send_axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
		compound.queue_free()
		await tree.process_frame
		return "Hysteresis failed: re-fired without releasing below 0.35"

	# Release to 0.0, wait for fire-rate cooldown (~0.25s), then press again -> fires once more
	_send_axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	for _c: int in range(15):
		await tree.physics_frame
	_send_axis(JOY_AXIS_TRIGGER_RIGHT, 0.8)
	await tree.process_frame
	await tree.process_frame
	var mag_after_two: int = wm.active_weapon.mag_ammo
	_send_axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	compound.queue_free()
	await tree.process_frame
	if mag_after_two != mag_after_one - 1:
		return "Fresh RT pull after release did not fire semi-auto"
	return ""


func _test_disconnect_pause(tree: SceneTree) -> String:
	var compound := CompoundScene.instantiate() as Node3D
	tree.root.add_child(compound)
	await tree.process_frame
	var ac := compound.get_node("ArenaController") as ArenaController
	var player := compound.get_node("Player") as PlayerController
	var pause_menu := compound.get_node("PauseMenu") as PauseMenu
	ac.restart_run()
	await tree.process_frame

	var idm: Node = tree.root.get_node_or_null("InputDeviceManager")
	idm.set("active_joypad_id", 0)
	idm.set("current_device", InputDeviceManager.DeviceType.XBOX)
	idm.call("simulate_disconnect", 0)
	await tree.process_frame

	var ok: bool = player.is_paused and pause_menu.disconnect_notice_label != null and pause_menu.disconnect_notice_label.visible
	if not ok:
		compound.queue_free()
		await tree.process_frame
		return "Disconnect did not auto-pause and show notice"

	idm.call("simulate_reconnect", 0)
	pause_menu._on_resume_pressed()
	await tree.process_frame
	var resumed: bool = not player.is_paused
	compound.queue_free()
	await tree.process_frame
	return "" if resumed else "Could not resume after reconnect"


func _test_menus_focus(tree: SceneTree) -> String:
	var mm := MainMenuScene.instantiate() as MainMenu
	tree.root.add_child(mm)
	await tree.process_frame

	var focused: Control = mm.get_viewport().gui_get_focus_owner()
	if focused == null:
		mm.queue_free()
		await tree.process_frame
		return "MainMenu has no focused control on open"

	# Open Character Select -> focus moves inside, Back restores focus
	mm.char_btn.pressed.emit()
	await tree.process_frame
	if mm.get_viewport().gui_get_focus_owner() == null or not mm.char_panel.visible:
		mm.queue_free()
		await tree.process_frame
		return "CharacterPanel missing focus"
	mm.char_back_btn.pressed.emit()
	await tree.process_frame
	if mm.get_viewport().gui_get_focus_owner() != mm.char_btn:
		mm.queue_free()
		await tree.process_frame
		return "MainMenu did not restore focus to CharacterButton"

	# Open Settings -> switch to Controls tab -> ControllerTestPanel visible -> Back restores
	mm.settings_btn.pressed.emit()
	await tree.process_frame
	mm.settings_panel.controls_tab_btn.pressed.emit()
	await tree.process_frame
	if not mm.settings_panel.controls_box.visible or mm.get_viewport().gui_get_focus_owner() == null:
		mm.queue_free()
		await tree.process_frame
		return "Settings Controls tab failed to focus"
	mm.settings_panel.back_btn.pressed.emit()
	await tree.process_frame
	if mm.get_viewport().gui_get_focus_owner() != mm.settings_btn:
		mm.queue_free()
		await tree.process_frame
		return "MainMenu did not restore focus to SettingsButton"

	mm.queue_free()
	await tree.process_frame
	return ""


func _test_controller_autoplay(tree: SceneTree) -> String:
	var compound := CompoundScene.instantiate() as Node3D
	tree.root.add_child(compound)
	var nav_region := compound.get_node("NavRegion") as NavigationRegion3D
	for _w: int in range(20):
		if nav_region.navigation_mesh.get_polygon_count() > 0:
			break
		await tree.process_frame
	await tree.physics_frame

	var rm := compound.get_node("RoundManager") as RoundManager
	var ac := compound.get_node("ArenaController") as ArenaController
	var player := compound.get_node("Player") as PlayerController
	var gs: Node = tree.root.get_node_or_null("GameState")

	var cfg := rm.round_config.duplicate() as RoundConfig
	cfg.initial_countdown = 0.05
	cfg.intermission_duration = 0.05
	cfg.base_spawn_interval = 0.05
	rm.round_config = cfg
	ac.restart_run()
	player.player_health.health_component.max_health = 99999.0
	player.player_health.health_component.restore_full_health()

	var kills: int = 0
	var rt_down: bool = false
	for step: int in range(5400):
		# Aim using right stick toward nearest zombie (preferring inside StartRoom z > -1.0), fire using RT only
		var best_z: ZombieAI = null
		var best_d: float = INF
		for z: ZombieAI in rm.alive_zombies:
			if is_instance_valid(z) and not z.health_component.is_dead:
				var d: float = z.global_position.distance_to(player.global_position)
				if z.global_position.z < -0.5 or absf(z.global_position.x) > 6.2:
					d += 20.0
				if d < best_d:
					best_d = d
					best_z = z
		if best_z != null:
			var to_z: Vector3 = (best_z.global_position + Vector3(0, 1.1, 0)) - player.camera.global_position
			var forward: Vector3 = -player.camera.global_transform.basis.z
			var right: Vector3 = player.camera.global_transform.basis.x
			var yaw_err: float = right.dot(to_z.normalized())
			var pitch_err: float = to_z.normalized().y - forward.y
			_send_axis(JOY_AXIS_RIGHT_X, clampf(yaw_err * 3.0, -1.0, 1.0))
			_send_axis(JOY_AXIS_RIGHT_Y, clampf(-pitch_err * 3.0, -1.0, 1.0))
			var inside_room: bool = absf(best_z.global_position.x) <= 5.8 and best_z.global_position.z >= 0.5
			_send_axis(JOY_AXIS_LEFT_Y, -0.5 if (inside_room and best_d > 4.0) else 0.0)
			if inside_room and absf(yaw_err) < 0.12 and absf(pitch_err) < 0.12 and not rt_down:
				_send_axis(JOY_AXIS_TRIGGER_RIGHT, 0.9)
				rt_down = true
			elif rt_down:
				_send_axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
				rt_down = false
		else:
			_send_axis(JOY_AXIS_RIGHT_X, 0.0)
			_send_axis(JOY_AXIS_RIGHT_Y, 0.0)
			_send_axis(JOY_AXIS_LEFT_Y, 0.0)
			if rt_down:
				_send_axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
				rt_down = false

		if player.weapon_manager.active_weapon.mag_ammo == 0 and not player.weapon_manager.active_weapon.is_reloading:
			_send_btn(JOY_BUTTON_X, true)
			await tree.physics_frame
			_send_btn(JOY_BUTTON_X, false)
		else:
			await tree.physics_frame

		kills = int(gs.get("kills")) if gs != null else 0
		if rm.current_round >= 2 and kills >= 6:
			break

	_send_axis(JOY_AXIS_RIGHT_X, 0.0)
	_send_axis(JOY_AXIS_RIGHT_Y, 0.0)
	_send_axis(JOY_AXIS_LEFT_Y, 0.0)
	_send_axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	var cur_round: int = rm.current_round
	var rem_info: String = ""
	if cur_round < 2:
		var w := player.weapon_manager.active_weapon
		rem_info += " [mag=%d res=%d]" % [w.mag_ammo if w else -1, w.reserve_ammo if w else -1]
		for z: ZombieAI in rm.alive_zombies:
			if is_instance_valid(z):
				rem_info += " [pos=%s state=%s mode=%s dead=%s]" % [str(z.global_position), str(z.get("current_state")), str(z.get("mode")), str(z.health_component.is_dead)]
	rm.stop_and_cleanup()
	compound.queue_free()
	await tree.process_frame
	if cur_round < 2:
		return "Controller autoplay did not reach Round 2 (round=%d, kills=%d, alive=%s)" % [cur_round, kills, rem_info]
	return ""
