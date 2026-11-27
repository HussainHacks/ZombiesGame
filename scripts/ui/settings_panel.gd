class_name SettingsPanel
extends PanelContainer
## Shared Settings UI panel used by both Main Menu and Pause Menu.
## Features General and Controls tabs (including Controller Test diagnostics).

const UiFocusHelper := preload("res://scripts/ui/ui_focus_helper.gd")
const InputDeviceManagerScript := preload("res://scripts/core/input_device_manager.gd")

signal closed

const FPS_CAP_OPTIONS := [60, 120, 144, 0]

@onready var master_slider: HSlider = $VBox/MasterRow/Slider
@onready var music_slider: HSlider = $VBox/MusicRow/Slider
@onready var sfx_slider: HSlider = $VBox/SfxRow/Slider
@onready var ambience_slider: HSlider = get_node_or_null("VBox/AmbienceRow/Slider") as HSlider
@onready var quality_btn: Button = get_node_or_null("VBox/QualityRow/ToggleButton") as Button
@onready var sens_slider: HSlider = $VBox/SensRow/Slider
@onready var fov_slider: HSlider = $VBox/FovRow/Slider
@onready var fullscreen_check: CheckButton = $VBox/TogglesRow/FullscreenCheck
@onready var vsync_check: CheckButton = $VBox/TogglesRow/VsyncCheck
@onready var subtitles_check: CheckButton = $VBox/TogglesRow/SubtitlesCheck
@onready var reset_btn: Button = $VBox/ButtonsRow/ResetButton
@onready var back_btn: Button = $VBox/ButtonsRow/BackButton

var general_tab_btn: Button = null
var gameplay_tab_btn: Button = null
var controls_tab_btn: Button = null
var fps_cap_btn: Button = null
var gameplay_box: VBoxContainer = null
var move_profile_btn: Button = null
var cam_bob_slider: HSlider = null
var wpn_bob_slider: HSlider = null
var cam_shake_slider: HSlider = null
var land_dip_slider: HSlider = null
var controls_box: VBoxContainer = null
var ctrl_sens_slider: HSlider = null
var ctrl_dz_slider: HSlider = null
var ctrl_invert_check: CheckButton = null
var vib_enable_check: CheckButton = null
var vib_int_slider: HSlider = null
var test_device_label: Label = null
var test_ls_x_bar: ProgressBar = null
var test_ls_y_bar: ProgressBar = null
var test_rs_x_bar: ProgressBar = null
var test_rs_y_bar: ProgressBar = null
var test_lt_bar: ProgressBar = null
var test_rt_bar: ProgressBar = null
var test_btn_labels: Dictionary = {}

var _general_rows: Array[Control] = []
var _active_tab: String = "general"
var _syncing: bool = false


func _ready() -> void:
	UiFocusHelper.apply_focus_theme(self)
	_build_tabs_and_controls_ui()
	sync_from_manager()

	master_slider.value_changed.connect(func(v: float) -> void:
		if not _syncing: _sm().call("set_master_volume", v))
	music_slider.value_changed.connect(func(v: float) -> void:
		if not _syncing: _sm().call("set_music_volume", v))
	sfx_slider.value_changed.connect(func(v: float) -> void:
		if not _syncing: _sm().call("set_sfx_volume", v))
	if ambience_slider != null:
		ambience_slider.value_changed.connect(func(v: float) -> void:
			if not _syncing: _sm().call("set_ambience_volume", v))
	if quality_btn != null:
		quality_btn.pressed.connect(func() -> void:
			var sm: Node = _sm()
			if sm == null:
				return
			var cur: String = str(sm.get("quality_preset"))
			var nxt: String = "low" if cur == "high" else "high"
			sm.call("set_quality_preset", nxt)
			sync_from_manager())
	sens_slider.value_changed.connect(func(v: float) -> void:
		if not _syncing: _sm().call("set_mouse_sensitivity", v))
	fov_slider.value_changed.connect(func(v: float) -> void:
		if not _syncing: _sm().call("set_fov", v))
	fullscreen_check.toggled.connect(func(b: bool) -> void:
		if not _syncing: _sm().call("set_fullscreen", b))
	vsync_check.toggled.connect(func(b: bool) -> void:
		if not _syncing: _sm().call("set_vsync", b))
	subtitles_check.toggled.connect(func(b: bool) -> void:
		if not _syncing: _sm().call("set_subtitles", b))
	reset_btn.pressed.connect(_on_reset_pressed)
	back_btn.pressed.connect(func() -> void: closed.emit())
	_set_tab("general")


func _build_tabs_and_controls_ui() -> void:
	var vbox := get_node_or_null("VBox") as VBoxContainer
	if vbox == null:
		return

	# Collect existing General rows (everything except TitleLabel and ButtonsRow)
	for child: Node in vbox.get_children():
		if child is Control:
			var cname: String = child.name
			if cname != "TitleLabel" and cname != "ButtonsRow":
				_general_rows.append(child as Control)

	# Tab bar at top (right after TitleLabel)
	var tab_row := HBoxContainer.new()
	tab_row.name = "TabRow"
	tab_row.add_theme_constant_override("separation", 10)
	general_tab_btn = Button.new()
	general_tab_btn.text = "General"
	general_tab_btn.pressed.connect(func() -> void: _set_tab("general"))
	gameplay_tab_btn = Button.new()
	gameplay_tab_btn.text = "Gameplay"
	gameplay_tab_btn.pressed.connect(func() -> void: _set_tab("gameplay"))
	controls_tab_btn = Button.new()
	controls_tab_btn.text = "Controls"
	controls_tab_btn.pressed.connect(func() -> void: _set_tab("controls"))
	tab_row.add_child(general_tab_btn)
	tab_row.add_child(gameplay_tab_btn)
	tab_row.add_child(controls_tab_btn)
	vbox.add_child(tab_row)
	vbox.move_child(tab_row, 1)

	# FPS Cap row in General
	var fps_row := HBoxContainer.new()
	fps_row.name = "FpsCapRow"
	var fps_lbl := Label.new()
	fps_lbl.text = "FPS Cap"
	fps_lbl.custom_minimum_size = Vector2(180, 0)
	fps_cap_btn = Button.new()
	fps_cap_btn.custom_minimum_size = Vector2(120, 0)
	fps_cap_btn.pressed.connect(_cycle_fps_cap)
	fps_row.add_child(fps_lbl)
	fps_row.add_child(fps_cap_btn)
	vbox.add_child(fps_row)
	var btn_idx: int = vbox.get_node("ButtonsRow").get_index()
	vbox.move_child(fps_row, btn_idx)
	_general_rows.append(fps_row)

	# Gameplay tab container
	gameplay_box = VBoxContainer.new()
	gameplay_box.name = "GameplayTab"
	gameplay_box.add_theme_constant_override("separation", 6)
	gameplay_box.visible = false
	vbox.add_child(gameplay_box)
	vbox.move_child(gameplay_box, btn_idx)

	var mp_row := HBoxContainer.new()
	var mp_lbl := Label.new()
	mp_lbl.text = "Movement Profile"
	mp_lbl.custom_minimum_size = Vector2(180, 0)
	move_profile_btn = Button.new()
	move_profile_btn.custom_minimum_size = Vector2(160, 0)
	move_profile_btn.pressed.connect(func() -> void:
		var sm: Node = _sm()
		if sm == null:
			return
		var cur: String = str(sm.get("movement_profile"))
		sm.call("set_movement_profile", "classic" if cur == "riposte" else "riposte")
		sync_from_manager())
	mp_row.add_child(mp_lbl)
	mp_row.add_child(move_profile_btn)
	gameplay_box.add_child(mp_row)

	cam_bob_slider = _add_slider_row(gameplay_box, "Camera Bob", 0.0, 1.0, 0.05, func(v: float) -> void:
		if not _syncing: _sm().call("set_camera_bob_intensity", v))
	wpn_bob_slider = _add_slider_row(gameplay_box, "Weapon Bob/Sway", 0.0, 1.0, 0.05, func(v: float) -> void:
		if not _syncing: _sm().call("set_weapon_bob_intensity", v))
	cam_shake_slider = _add_slider_row(gameplay_box, "Camera Shake", 0.0, 1.0, 0.05, func(v: float) -> void:
		if not _syncing: _sm().call("set_camera_shake_intensity", v))
	land_dip_slider = _add_slider_row(gameplay_box, "Landing Dip", 0.0, 1.0, 0.05, func(v: float) -> void:
		if not _syncing: _sm().call("set_landing_dip_intensity", v))

	# Controls tab container
	controls_box = VBoxContainer.new()
	controls_box.name = "ControlsTab"
	controls_box.add_theme_constant_override("separation", 6)
	controls_box.visible = false
	vbox.add_child(controls_box)
	vbox.move_child(controls_box, btn_idx)

	ctrl_sens_slider = _add_slider_row(controls_box, "Controller Sens", 40.0, 400.0, 10.0, func(v: float) -> void:
		if not _syncing: _sm().call("set_controller_sensitivity", v))
	ctrl_dz_slider = _add_slider_row(controls_box, "Stick Deadzone", 0.05, 0.50, 0.01, func(v: float) -> void:
		if not _syncing: _sm().call("set_controller_deadzone", v))

	var ctrl_toggles := HBoxContainer.new()
	ctrl_toggles.add_theme_constant_override("separation", 12)
	ctrl_invert_check = CheckButton.new()
	ctrl_invert_check.text = "Invert Y"
	ctrl_invert_check.toggled.connect(func(b: bool) -> void:
		if not _syncing: _sm().call("set_controller_invert_y", b))
	vib_enable_check = CheckButton.new()
	vib_enable_check.text = "Vibration"
	vib_enable_check.toggled.connect(func(b: bool) -> void:
		if not _syncing: _sm().call("set_vibration_enabled", b))
	ctrl_toggles.add_child(ctrl_invert_check)
	ctrl_toggles.add_child(vib_enable_check)
	controls_box.add_child(ctrl_toggles)

	vib_int_slider = _add_slider_row(controls_box, "Vibration Strength", 0.0, 1.0, 0.05, func(v: float) -> void:
		if not _syncing: _sm().call("set_vibration_intensity", v))

	# Read-only Controller Test diagnostic panel (available in release builds)
	var test_panel := PanelContainer.new()
	test_panel.name = "ControllerTestPanel"
	var tvbox := VBoxContainer.new()
	tvbox.add_theme_constant_override("separation", 4)
	test_panel.add_child(tvbox)

	var test_title := Label.new()
	test_title.text = "Controller Test (Read-Only)"
	test_title.add_theme_font_size_override("font_size", 14)
	tvbox.add_child(test_title)

	test_device_label = Label.new()
	test_device_label.text = "Detected: None"
	test_device_label.add_theme_font_size_override("font_size", 12)
	tvbox.add_child(test_device_label)

	test_ls_x_bar = _add_diag_bar(tvbox, "LS X", -1.0, 1.0)
	test_ls_y_bar = _add_diag_bar(tvbox, "LS Y", -1.0, 1.0)
	test_rs_x_bar = _add_diag_bar(tvbox, "RS X", -1.0, 1.0)
	test_rs_y_bar = _add_diag_bar(tvbox, "RS Y", -1.0, 1.0)
	test_lt_bar = _add_diag_bar(tvbox, "LT/L2", 0.0, 1.0)
	test_rt_bar = _add_diag_bar(tvbox, "RT/R2", 0.0, 1.0)

	var btn_grid := HFlowContainer.new()
	btn_grid.add_theme_constant_override("h_separation", 8)
	var diag_buttons := [
		[JOY_BUTTON_A, "A/X"],
		[JOY_BUTTON_B, "B/O"],
		[JOY_BUTTON_X, "X/Sq"],
		[JOY_BUTTON_Y, "Y/Tri"],
		[JOY_BUTTON_LEFT_SHOULDER, "LB/L1"],
		[JOY_BUTTON_RIGHT_SHOULDER, "RB/R1"],
		[JOY_BUTTON_LEFT_STICK, "L3"],
		[JOY_BUTTON_START, "Start"],
		[JOY_BUTTON_DPAD_UP, "D-Up"],
	]
	for item: Array in diag_buttons:
		var lbl := Label.new()
		lbl.text = "[%s]" % str(item[1])
		lbl.add_theme_font_size_override("font_size", 12)
		btn_grid.add_child(lbl)
		test_btn_labels[int(item[0])] = lbl
	tvbox.add_child(btn_grid)
	controls_box.add_child(test_panel)

	UiFocusHelper.wire_horizontal([general_tab_btn, gameplay_tab_btn, controls_tab_btn])
	UiFocusHelper.wire_horizontal([reset_btn, back_btn])


func _add_slider_row(parent: Control, label_text: String, min_v: float, max_v: float, step_v: float, on_changed: Callable) -> HSlider:
	var row := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(180, 0)
	var sl := HSlider.new()
	sl.min_value = min_v
	sl.max_value = max_v
	sl.step = step_v
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.value_changed.connect(on_changed)
	row.add_child(lbl)
	row.add_child(sl)
	parent.add_child(row)
	return sl


func _add_diag_bar(parent: Control, label_text: String, min_v: float, max_v: float) -> ProgressBar:
	var row := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(65, 0)
	lbl.add_theme_font_size_override("font_size", 12)
	var bar := ProgressBar.new()
	bar.min_value = min_v
	bar.max_value = max_v
	bar.value = 0.0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(180, 12)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	row.add_child(bar)
	parent.add_child(row)
	return bar


func _set_tab(tab_name: String) -> void:
	_active_tab = tab_name
	var is_ctrl: bool = (tab_name == "controls")
	var is_gp: bool = (tab_name == "gameplay")
	for r: Control in _general_rows:
		r.visible = (not is_ctrl and not is_gp)
	if gameplay_box != null:
		gameplay_box.visible = is_gp
	if controls_box != null:
		controls_box.visible = is_ctrl
	_wire_tab_focus()
	if is_ctrl:
		UiFocusHelper.grab_safe(ctrl_sens_slider)
	elif is_gp:
		UiFocusHelper.grab_safe(move_profile_btn)
	else:
		UiFocusHelper.grab_safe(general_tab_btn)


func _wire_tab_focus() -> void:
	if _active_tab == "gameplay":
		UiFocusHelper.wire_vertical([
			gameplay_tab_btn,
			move_profile_btn,
			cam_bob_slider,
			wpn_bob_slider,
			cam_shake_slider,
			land_dip_slider,
			back_btn,
		])
	elif _active_tab == "controls":
		UiFocusHelper.wire_vertical([
			controls_tab_btn,
			ctrl_sens_slider,
			ctrl_dz_slider,
			ctrl_invert_check,
			vib_int_slider,
			back_btn,
		])
		UiFocusHelper.wire_horizontal([ctrl_invert_check, vib_enable_check])
	else:
		var order: Array[Control] = [
			general_tab_btn,
			master_slider,
			music_slider,
			sfx_slider,
		]
		if ambience_slider != null:
			order.append(ambience_slider)
		if quality_btn != null:
			order.append(quality_btn)
		if fps_cap_btn != null:
			order.append(fps_cap_btn)
		order.append_array([sens_slider, fov_slider, fullscreen_check, back_btn])
		UiFocusHelper.wire_vertical(order)
		UiFocusHelper.wire_horizontal([fullscreen_check, vsync_check, subtitles_check])


func grab_initial_focus() -> void:
	UiFocusHelper.grab_safe(general_tab_btn if _active_tab == "general" else controls_tab_btn)


func _process(_delta: float) -> void:
	if not visible or controls_box == null or not controls_box.visible:
		return
	var idm: Node = get_node_or_null("/root/InputDeviceManager")
	var dev: int = int(idm.get("active_joypad_id")) if (idm != null and int(idm.get("active_joypad_id")) >= 0) else 0
	var pads: PackedInt32Array = Input.get_connected_joypads()
	var jname: String = str(idm.call("get_joy_name_for_device", dev)) if idm != null else Input.get_joy_name(dev)
	if pads.is_empty() and jname.is_empty():
		test_device_label.text = "Detected: None (connect Xbox or PS5 controller)"
	else:
		var dtype: int = InputDeviceManagerScript.classify_joypad(jname, Input.get_joy_guid(dev) if Input.get_connected_joypads().has(dev) else "")
		var tname: String = "Xbox" if dtype == 1 else ("PlayStation" if dtype == 2 else "Generic")
		test_device_label.text = "Detected: %s (%s)" % [jname if not jname.is_empty() else "Simulated", tname]

	test_ls_x_bar.value = Input.get_joy_axis(dev, JOY_AXIS_LEFT_X)
	test_ls_y_bar.value = Input.get_joy_axis(dev, JOY_AXIS_LEFT_Y)
	test_rs_x_bar.value = Input.get_joy_axis(dev, JOY_AXIS_RIGHT_X)
	test_rs_y_bar.value = Input.get_joy_axis(dev, JOY_AXIS_RIGHT_Y)
	test_lt_bar.value = Input.get_joy_axis(dev, JOY_AXIS_TRIGGER_LEFT)
	test_rt_bar.value = Input.get_joy_axis(dev, JOY_AXIS_TRIGGER_RIGHT)
	for btn_id: Variant in test_btn_labels.keys():
		var lbl := test_btn_labels[btn_id] as Label
		var down: bool = Input.is_joy_button_pressed(dev, int(btn_id) as JoyButton)
		lbl.modulate = Color(1.0, 0.85, 0.25, 1.0) if down else Color(0.55, 0.58, 0.65, 1.0)


func _cycle_fps_cap() -> void:
	var sm: Node = _sm()
	if sm == null:
		return
	var cur: int = int(sm.get("fps_cap"))
	var idx: int = FPS_CAP_OPTIONS.find(cur)
	var nxt: int = FPS_CAP_OPTIONS[(idx + 1) % FPS_CAP_OPTIONS.size()]
	sm.call("set_fps_cap", nxt)
	sync_from_manager()


func _sm() -> Node:
	return get_node_or_null("/root/SettingsManager")


func sync_from_manager() -> void:
	var sm: Node = _sm()
	if sm == null:
		return
	_syncing = true
	master_slider.value = float(sm.get("master_volume"))
	music_slider.value = float(sm.get("music_volume"))
	sfx_slider.value = float(sm.get("sfx_volume"))
	if ambience_slider != null:
		ambience_slider.value = float(sm.get("ambience_volume"))
	if quality_btn != null:
		quality_btn.text = "Low" if str(sm.get("quality_preset")) == "low" else "High"
	if fps_cap_btn != null:
		var cap: int = int(sm.get("fps_cap"))
		fps_cap_btn.text = "Uncapped" if cap <= 0 else "%d FPS" % cap
	sens_slider.value = float(sm.get("mouse_sensitivity"))
	fov_slider.value = float(sm.get("fov"))
	fullscreen_check.button_pressed = bool(sm.get("fullscreen"))
	vsync_check.button_pressed = bool(sm.get("vsync"))
	subtitles_check.button_pressed = bool(sm.get("subtitles"))
	if ctrl_sens_slider != null:
		ctrl_sens_slider.value = float(sm.get("controller_sensitivity"))
	if ctrl_dz_slider != null:
		ctrl_dz_slider.value = float(sm.get("controller_deadzone"))
	if ctrl_invert_check != null:
		ctrl_invert_check.button_pressed = bool(sm.get("controller_invert_y"))
	if vib_enable_check != null:
		vib_enable_check.button_pressed = bool(sm.get("vibration_enabled"))
	if vib_int_slider != null:
		vib_int_slider.value = float(sm.get("vibration_intensity"))
	if move_profile_btn != null:
		move_profile_btn.text = "Classic" if str(sm.get("movement_profile")) == "classic" else "Riposte-style"
	if cam_bob_slider != null:
		cam_bob_slider.value = float(sm.get("camera_bob_intensity"))
	if wpn_bob_slider != null:
		wpn_bob_slider.value = float(sm.get("weapon_bob_intensity"))
	if cam_shake_slider != null:
		cam_shake_slider.value = float(sm.get("camera_shake_intensity"))
	if land_dip_slider != null:
		land_dip_slider.value = float(sm.get("landing_dip_intensity"))
	_syncing = false


func _on_reset_pressed() -> void:
	var sm: Node = _sm()
	if sm != null:
		sm.call("reset_to_defaults")
	sync_from_manager()
