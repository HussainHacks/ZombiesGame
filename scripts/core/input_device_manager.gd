extends Node
## Tracks last-used input device (Keyboard/Mouse, Xbox, PlayStation, Generic),
## registers built-in joypad bindings, formats device-aware prompts, handles
## controller disconnect/reconnect, and wraps joypad vibration.

enum DeviceType {
	KEYBOARD_MOUSE,
	XBOX,
	PLAYSTATION,
	GENERIC,
}

signal device_changed(new_device: DeviceType)
signal controller_disconnected(device_id: int)
signal controller_reconnected(device_id: int)

const DISCONNECT_NOTICE_TEXT := "Controller disconnected - reconnect or press any key"

var current_device: DeviceType = DeviceType.KEYBOARD_MOUSE
var active_joypad_id: int = -1
var controller_deadzone: float = 0.20
var vibration_enabled: bool = true
var vibration_intensity: float = 1.0
var vibration_call_count: int = 0
var _joy_name_overrides: Dictionary = {} # device_id -> String (for unit/integration tests)
var _sim_axes: Dictionary = {} # "dev:axis" -> float (for headless InputEventJoypadMotion simulation)
var _death_vib_timer: float = 0.0
var _bindings_initialized: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	ensure_joypad_bindings()
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	var connected: PackedInt32Array = Input.get_connected_joypads()
	if not connected.is_empty():
		active_joypad_id = connected[0]


func _process(delta: float) -> void:
	if _death_vib_timer > 0.0:
		_death_vib_timer -= delta
		if _death_vib_timer <= 0.0:
			stop_all_vibration()


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and not ke.echo:
			_switch_to_kbm()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			_switch_to_kbm()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if mm.relative.length_squared() > 4.0:
			_switch_to_kbm()
	elif event is InputEventJoypadButton:
		var jb := event as InputEventJoypadButton
		if jb.pressed:
			_switch_to_joypad(jb.device)
	elif event is InputEventJoypadMotion:
		var jm := event as InputEventJoypadMotion
		_sim_axes["%d:%d" % [jm.device, jm.axis]] = jm.axis_value
		# Sub-deadzone stick/trigger noise never switches the active device.
		var switch_thresh: float = maxf(controller_deadzone, 0.25)
		if absf(jm.axis_value) >= switch_thresh:
			_switch_to_joypad(jm.device)


func _switch_to_kbm() -> void:
	if current_device != DeviceType.KEYBOARD_MOUSE:
		current_device = DeviceType.KEYBOARD_MOUSE
		device_changed.emit(current_device)
	_sync_mouse_capture()


func _switch_to_joypad(device_id: int) -> void:
	if device_id >= 0:
		active_joypad_id = device_id
	var j_name: String = get_joy_name_for_device(active_joypad_id)
	var j_guid: String = Input.get_joy_guid(active_joypad_id) if (active_joypad_id >= 0 and Input.get_connected_joypads().has(active_joypad_id)) else ""
	var dtype: DeviceType = classify_joypad(j_name, j_guid)
	if current_device != dtype:
		current_device = dtype
		device_changed.emit(current_device)
	_sync_mouse_capture()


func _sync_mouse_capture() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var gs: Node = get_node_or_null("/root/GameState")
	var playing: bool = gs != null and bool(gs.call("is_playing"))
	if current_device == DeviceType.KEYBOARD_MOUSE:
		if playing:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)


func _on_joy_connection_changed(device_id: int, connected: bool) -> void:
	if connected:
		if active_joypad_id == -1:
			active_joypad_id = device_id
		controller_reconnected.emit(device_id)
	else:
		stop_all_vibration()
		var was_active: bool = (device_id == active_joypad_id) or (current_device != DeviceType.KEYBOARD_MOUSE and Input.get_connected_joypads().is_empty())
		if device_id == active_joypad_id:
			var pads: PackedInt32Array = Input.get_connected_joypads()
			active_joypad_id = pads[0] if not pads.is_empty() else -1
		if was_active:
			controller_disconnected.emit(device_id)


func set_joy_name_override(device_id: int, joy_name: String) -> void:
	if joy_name.is_empty():
		_joy_name_overrides.erase(device_id)
	else:
		_joy_name_overrides[device_id] = joy_name


func get_joy_name_for_device(device_id: int) -> String:
	if _joy_name_overrides.has(device_id):
		return str(_joy_name_overrides[device_id])
	if device_id < 0 or not Input.get_connected_joypads().has(device_id):
		return ""
	return Input.get_joy_name(device_id)


func get_axis_value(device_id: int, axis: JoyAxis) -> float:
	if device_id >= 0 and Input.get_connected_joypads().has(device_id):
		return Input.get_joy_axis(device_id, axis)
	return float(_sim_axes.get("%d:%d" % [device_id, axis], 0.0))


func simulate_disconnect(device_id: int = 0) -> void:
	_on_joy_connection_changed(device_id, false)


func simulate_reconnect(device_id: int = 0) -> void:
	_on_joy_connection_changed(device_id, true)


static func classify_joypad(joy_name: String, joy_guid: String = "") -> DeviceType:
	var n: String = joy_name.to_lower()
	var g: String = joy_guid.to_lower()
	if n.contains("dualsense") or n.contains("dualshock") or n.contains("ps5") or n.contains("ps4") or n.contains("playstation") or n.contains("sony") or g.contains("054c"):
		return DeviceType.PLAYSTATION
	if n.contains("xbox") or n.contains("xinput") or n.contains("microsoft") or g.contains("045e"):
		return DeviceType.XBOX
	return DeviceType.GENERIC


func get_device_label() -> String:
	match current_device:
		DeviceType.XBOX:
			return "Xbox"
		DeviceType.PLAYSTATION:
			return "PlayStation"
		DeviceType.GENERIC:
			return "Controller"
		_:
			return "Keyboard & Mouse"


func get_interact_button_label() -> String:
	match current_device:
		DeviceType.XBOX:
			return "Y"
		DeviceType.PLAYSTATION:
			return "Triangle"
		DeviceType.GENERIC:
			return "Btn4"
		_:
			return "E"


func format_prompt(raw_text: String) -> String:
	if raw_text.is_empty() or current_device == DeviceType.KEYBOARD_MOUSE:
		return raw_text
	var btn: String = get_interact_button_label()
	var out: String = raw_text
	out = out.replace("Hold E -", "Hold %s -" % btn)
	out = out.replace("Press E -", "Press %s -" % btn)
	out = out.replace("Hold [E]", "Hold [%s]" % btn)
	out = out.replace("Press [E]", "Press [%s]" % btn)
	return out


static func apply_radial_deadzone(raw: Vector2, deadzone: float) -> Vector2:
	var dz: float = clampf(deadzone, 0.0, 0.95)
	var mag: float = raw.length()
	if mag <= dz or mag <= 0.00001:
		return Vector2.ZERO
	var scaled: float = clampf((mag - dz) / (1.0 - dz), 0.0, 1.0)
	return (raw / mag) * scaled


static func apply_look_curve(stick: Vector2, exponent: float = 1.6) -> Vector2:
	var mag: float = stick.length()
	if mag <= 0.00001:
		return Vector2.ZERO
	var curved: float = pow(clampf(mag, 0.0, 1.0), exponent)
	return (stick / mag) * curved


func play_vibration(weak_mag: float, strong_mag: float, duration_sec: float, is_death: bool = false) -> void:
	if not vibration_enabled or vibration_intensity <= 0.001:
		return
	var dev: int = active_joypad_id
	if dev < 0:
		var pads: PackedInt32Array = Input.get_connected_joypads()
		if pads.is_empty():
			return
		dev = pads[0]
	var w: float = clampf(weak_mag * vibration_intensity, 0.0, 1.0)
	var s: float = clampf(strong_mag * vibration_intensity, 0.0, 1.0)
	if w <= 0.001 and s <= 0.001:
		return
	vibration_call_count += 1
	Input.start_joy_vibration(dev, w, s, duration_sec)
	if is_death:
		_death_vib_timer = duration_sec + 0.05


func stop_all_vibration() -> void:
	_death_vib_timer = 0.0
	if active_joypad_id >= 0:
		Input.stop_joy_vibration(active_joypad_id)
	for dev_id: int in Input.get_connected_joypads():
		Input.stop_joy_vibration(dev_id)


func ensure_joypad_bindings() -> void:
	if _bindings_initialized:
		return
	_bindings_initialized = true
	_add_joy_button(&"jump", JOY_BUTTON_A)
	_add_joy_button(&"crouch", JOY_BUTTON_B)
	_add_joy_button(&"reload", JOY_BUTTON_X)
	_add_joy_button(&"interact", JOY_BUTTON_Y)
	_add_joy_button(&"sprint", JOY_BUTTON_LEFT_STICK)
	_add_joy_button(&"toggle_flashlight", JOY_BUTTON_DPAD_UP)
	_add_joy_button(&"pause", JOY_BUTTON_START)
	_add_joy_button(&"weapon_next", JOY_BUTTON_RIGHT_SHOULDER)
	_add_joy_button(&"weapon_prev", JOY_BUTTON_LEFT_SHOULDER)

	_add_joy_axis(&"move_left", JOY_AXIS_LEFT_X, -1.0)
	_add_joy_axis(&"move_right", JOY_AXIS_LEFT_X, 1.0)
	_add_joy_axis(&"move_forward", JOY_AXIS_LEFT_Y, -1.0)
	_add_joy_axis(&"move_back", JOY_AXIS_LEFT_Y, 1.0)

	# Ensure UI navigation works with D-pad, Left Stick, A/Cross, and B/Circle
	_add_joy_button(&"ui_accept", JOY_BUTTON_A)
	_add_joy_button(&"ui_cancel", JOY_BUTTON_B)
	_add_joy_button(&"ui_up", JOY_BUTTON_DPAD_UP)
	_add_joy_button(&"ui_down", JOY_BUTTON_DPAD_DOWN)
	_add_joy_button(&"ui_left", JOY_BUTTON_DPAD_LEFT)
	_add_joy_button(&"ui_right", JOY_BUTTON_DPAD_RIGHT)
	_add_joy_axis(&"ui_up", JOY_AXIS_LEFT_Y, -1.0)
	_add_joy_axis(&"ui_down", JOY_AXIS_LEFT_Y, 1.0)
	_add_joy_axis(&"ui_left", JOY_AXIS_LEFT_X, -1.0)
	_add_joy_axis(&"ui_right", JOY_AXIS_LEFT_X, 1.0)


func _add_joy_button(action: StringName, btn: JoyButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for ev: InputEvent in InputMap.action_get_events(action):
		if ev is InputEventJoypadButton and (ev as InputEventJoypadButton).button_index == btn:
			return
	var jb := InputEventJoypadButton.new()
	jb.button_index = btn
	jb.device = -1
	InputMap.action_add_event(action, jb)


func _add_joy_axis(action: StringName, axis: JoyAxis, axis_value: float) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for ev: InputEvent in InputMap.action_get_events(action):
		if ev is InputEventJoypadMotion:
			var jm := ev as InputEventJoypadMotion
			if jm.axis == axis and signf(jm.axis_value) == signf(axis_value):
				return
	var jm := InputEventJoypadMotion.new()
	jm.axis = axis
	jm.axis_value = axis_value
	jm.device = -1
	InputMap.action_add_event(action, jm)
