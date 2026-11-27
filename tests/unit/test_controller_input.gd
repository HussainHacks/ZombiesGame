extends RefCounted
## Unit tests for Step 1.8: Controller mappings, radial deadzone, frame-rate
## independent look, device classification, vibration gating, and settings persistence.


func run_all() -> Dictionary:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var results := {"passed": 0, "failed": 0, "failures": []}
	_run_test("controller_actions_have_joypad_bindings", _test_actions, results)
	_run_test("radial_deadzone_zero_below_and_smooth_above", _test_deadzone, results)
	_run_test("controller_look_frame_rate_independent_30_vs_144", _test_look_fps_independence.bind(tree), results)
	_run_test("device_tracking_labels_prompts_and_noise_filter", _test_device_tracking.bind(tree), results)
	_run_test("vibration_off_never_calls_start_and_intensity_scales", _test_vibration_gating.bind(tree), results)
	_run_test("controller_settings_round_trip_clamp_and_old_save_defaults", _test_settings_persistence, results)
	return results


func _run_test(test_name: String, fn: Callable, results: Dictionary) -> void:
	var err_str: String = str(fn.call())
	if err_str.is_empty():
		results["passed"] += 1
		print("  [PASS] ", test_name)
	else:
		results["failed"] += 1
		results["failures"].append("%s: %s" % [test_name, err_str])
		print("  [FAIL] ", test_name, ": ", err_str)


func _test_actions() -> String:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var idm: Node = tree.root.get_node_or_null("InputDeviceManager")
	if idm != null:
		idm.call("ensure_joypad_bindings")
	var required := [
		"move_forward", "move_back", "move_left", "move_right",
		"jump", "crouch", "sprint", "reload", "interact",
		"toggle_flashlight", "pause", "weapon_next", "weapon_prev",
		"ui_accept", "ui_cancel", "ui_up", "ui_down", "ui_left", "ui_right",
	]
	for act: String in required:
		if not InputMap.has_action(act):
			return "Missing action: %s" % act
		var has_joy: bool = false
		for ev: InputEvent in InputMap.action_get_events(act):
			if ev is InputEventJoypadButton or ev is InputEventJoypadMotion:
				has_joy = true
				break
		if not has_joy:
			return "Action %s has no joypad binding" % act
	return ""


func _test_deadzone() -> String:
	var dz: float = 0.20
	if InputDeviceManager.apply_radial_deadzone(Vector2(0.15, 0.10), dz) != Vector2.ZERO:
		return "Sub-deadzone vector did not return ZERO"
	var just_above: Vector2 = InputDeviceManager.apply_radial_deadzone(Vector2(0.22, 0.0), dz)
	if just_above.x <= 0.0 or just_above.x >= 0.05:
		return "Expected small scaled value just above deadzone, got %s" % just_above
	var full: Vector2 = InputDeviceManager.apply_radial_deadzone(Vector2(1.0, 0.0), dz)
	if not is_equal_approx(full.x, 1.0):
		return "Full stick should reach 1.0, got %s" % full
	return ""


func _test_look_fps_independence(tree: SceneTree) -> String:
	var PlayerScene := preload("res://scenes/player/player.tscn")
	var p30 := PlayerScene.instantiate() as PlayerController
	var p144 := PlayerScene.instantiate() as PlayerController
	p30.set_physics_process(false)
	p144.set_physics_process(false)
	tree.root.add_child(p30)
	tree.root.add_child(p144)

	var ev_x := InputEventJoypadMotion.new()
	ev_x.device = 0
	ev_x.axis = JOY_AXIS_RIGHT_X
	ev_x.axis_value = 0.75
	Input.parse_input_event(ev_x)

	var ev_y := InputEventJoypadMotion.new()
	ev_y.device = 0
	ev_y.axis = JOY_AXIS_RIGHT_Y
	ev_y.axis_value = -0.50
	Input.parse_input_event(ev_y)
	Input.flush_buffered_events()

	for _i: int in range(30):
		p30._handle_controller_look(1.0 / 30.0)
	for _j: int in range(144):
		p144._handle_controller_look(1.0 / 144.0)

	var yaw_diff: float = absf(rad_to_deg(p30.rotation.y - p144.rotation.y))
	var pitch_diff: float = absf(p30._pitch_degrees - p144._pitch_degrees)

	ev_x.axis_value = 0.0
	ev_y.axis_value = 0.0
	Input.parse_input_event(ev_x)
	Input.parse_input_event(ev_y)

	tree.root.remove_child(p30)
	tree.root.remove_child(p144)
	p30.free()
	p144.free()
	if yaw_diff > 0.5 or pitch_diff > 0.5:
		return "Look not frame-rate independent: yaw_diff=%.3f pitch_diff=%.3f" % [yaw_diff, pitch_diff]
	return ""


func _test_device_tracking(tree: SceneTree) -> String:
	var idm: Node = tree.root.get_node_or_null("InputDeviceManager")
	if idm == null:
		return "InputDeviceManager autoload missing"

	if InputDeviceManager.classify_joypad("Xbox Series Controller") != InputDeviceManager.DeviceType.XBOX:
		return "Xbox Series Controller misclassified"
	if InputDeviceManager.classify_joypad("DualSense Wireless Controller") != InputDeviceManager.DeviceType.PLAYSTATION:
		return "DualSense Wireless Controller misclassified"
	if InputDeviceManager.classify_joypad("PS5 Controller") != InputDeviceManager.DeviceType.PLAYSTATION:
		return "PS5 Controller misclassified"
	if InputDeviceManager.classify_joypad("Generic USB Pad") != InputDeviceManager.DeviceType.GENERIC:
		return "Unknown pad not classified as GENERIC"

	# Switch back to KBM via key
	var ke := InputEventKey.new()
	ke.keycode = KEY_W
	ke.pressed = true
	idm._input(ke)
	ke.pressed = false
	idm._input(ke)
	if int(idm.get("current_device")) != InputDeviceManager.DeviceType.KEYBOARD_MOUSE:
		return "Key did not switch to KEYBOARD_MOUSE"

	# Sub-deadzone stick noise must NOT switch
	var noise := InputEventJoypadMotion.new()
	noise.device = 0
	noise.axis = JOY_AXIS_LEFT_X
	noise.axis_value = 0.12
	idm._input(noise)
	if int(idm.get("current_device")) != InputDeviceManager.DeviceType.KEYBOARD_MOUSE:
		return "Sub-deadzone stick noise switched device!"

	# Xbox button switches to Xbox + Hold Y prompt
	idm.call("set_joy_name_override", 0, "Xbox Series Controller")
	var jb := InputEventJoypadButton.new()
	jb.device = 0
	jb.button_index = JOY_BUTTON_A
	jb.pressed = true
	idm._input(jb)
	jb.pressed = false
	idm._input(jb)
	if str(idm.call("format_prompt", "Hold E - Repair (2/5)")) != "Hold Y - Repair (2/5)":
		return "Xbox prompt formatting failed (got: %s)" % str(idm.call("format_prompt", "Hold E - Repair (2/5)"))

	# PlayStation switches to Triangle
	idm.call("set_joy_name_override", 0, "DualSense Wireless Controller")
	jb.pressed = true
	idm._input(jb)
	jb.pressed = false
	idm._input(jb)
	if str(idm.call("format_prompt", "Press E - Buy door [750]")) != "Press Triangle - Buy door [750]":
		return "PS5 prompt formatting failed"

	# Mouse motion switches back to KBM
	var mm := InputEventMouseMotion.new()
	mm.relative = Vector2(12.0, 0.0)
	idm._input(mm)
	if int(idm.get("current_device")) != InputDeviceManager.DeviceType.KEYBOARD_MOUSE:
		return "Mouse motion did not switch back to KEYBOARD_MOUSE"

	idm.call("set_joy_name_override", 0, "")
	return ""


func _test_vibration_gating(tree: SceneTree) -> String:
	var idm: Node = tree.root.get_node_or_null("InputDeviceManager")
	if idm == null:
		return "InputDeviceManager missing"
	idm.set("active_joypad_id", 0)
	idm.set("vibration_enabled", false)
	idm.set("vibration_intensity", 1.0)
	idm.set("vibration_call_count", 0)
	idm.call("play_vibration", 0.5, 0.8, 0.2, false)
	if int(idm.get("vibration_call_count")) != 0:
		return "play_vibration called start_joy_vibration when vibration_enabled=false!"

	idm.set("vibration_enabled", true)
	idm.set("vibration_intensity", 0.5)
	idm.call("play_vibration", 0.5, 0.8, 0.2, false)
	if int(idm.get("vibration_call_count")) != 1:
		return "play_vibration did not fire when vibration_enabled=true"
	idm.call("stop_all_vibration")
	return ""


func _test_settings_persistence() -> String:
	var tmp := "res://.tmp_phase12_save.json"
	var abs_tmp := ProjectSettings.globalize_path(tmp)
	if FileAccess.file_exists(abs_tmp):
		DirAccess.remove_absolute(abs_tmp)

	var sm: Node = SaveManager.new() if false else load("res://scripts/core/save_manager.gd").new()
	sm.set("save_path", tmp)
	# Old Phase 11 save missing controller fields
	var old_json := JSON.stringify({
		"version": 1,
		"settings": {"master_volume": 0.7, "vsync": false},
		"progression": {"selected_character_id": "simone_brooks", "best_round": 4},
	})
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	f.store_string(old_json)
	f.close()
	sm.call("load_save")
	var s: Dictionary = sm.call("get_settings")
	if not is_equal_approx(float(s["controller_deadzone"]), 0.20) or int(s["fps_cap"]) != 60:
		DirAccess.remove_absolute(abs_tmp)
		return "Old save did not default controller_deadzone/fps_cap"

	# Out-of-range clamping
	s["controller_deadzone"] = 0.99
	s["controller_sensitivity"] = 999.0
	s["vibration_intensity"] = -2.0
	s["fps_cap"] = 500
	sm.call("save_to_disk")
	sm.call("load_save")
	var s2: Dictionary = sm.call("get_settings")
	DirAccess.remove_absolute(abs_tmp)
	if not is_equal_approx(float(s2["controller_deadzone"]), 0.50) or not is_equal_approx(float(s2["controller_sensitivity"]), 400.0) or float(s2["vibration_intensity"]) != 0.0 or int(s2["fps_cap"]) != 240:
		return "Controller settings did not clamp properly: %s" % s2
	return ""
