class_name PauseMenu
extends CanvasLayer
## In-run pause menu (Esc): Resume, Settings, Restart Run, Return to Main Menu, Quit.

const UiFocusHelper := preload("res://scripts/ui/ui_focus_helper.gd")
const InputDeviceManagerScript := preload("res://scripts/core/input_device_manager.gd")

const MAIN_MENU_PATH := "res://scenes/ui/main_menu.tscn"

@export var player_path: NodePath
@export var arena_controller_path: NodePath

@onready var backdrop: Control = $CenterContainer
@onready var main_panel: PanelContainer = $CenterContainer/MainPanel
@onready var settings_panel: SettingsPanel = $CenterContainer/SettingsPanel
@onready var resume_btn: Button = $CenterContainer/MainPanel/VBox/ResumeButton
@onready var settings_btn: Button = $CenterContainer/MainPanel/VBox/SettingsButton
@onready var restart_btn: Button = $CenterContainer/MainPanel/VBox/RestartButton
@onready var menu_btn: Button = $CenterContainer/MainPanel/VBox/MenuButton
@onready var quit_btn: Button = $CenterContainer/MainPanel/VBox/QuitButton

var disconnect_notice_label: Label = null
var _disconnect_paused: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if backdrop is Control:
		UiFocusHelper.apply_focus_theme(backdrop)
	if backdrop:
		backdrop.visible = false
	if settings_panel:
		settings_panel.visible = false
		settings_panel.closed.connect(_on_settings_closed)

	var vbox: Node = main_panel.get_node_or_null("VBox")
	if vbox != null:
		disconnect_notice_label = Label.new()
		disconnect_notice_label.name = "DisconnectNoticeLabel"
		disconnect_notice_label.text = InputDeviceManagerScript.DISCONNECT_NOTICE_TEXT
		disconnect_notice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		disconnect_notice_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		disconnect_notice_label.modulate = Color(1.0, 0.72, 0.25, 1.0)
		disconnect_notice_label.visible = false
		vbox.add_child(disconnect_notice_label)
		vbox.move_child(disconnect_notice_label, 0)

	resume_btn.pressed.connect(_on_resume_pressed)
	settings_btn.pressed.connect(_on_settings_pressed)
	restart_btn.pressed.connect(_on_restart_pressed)
	menu_btn.pressed.connect(_on_menu_pressed)
	quit_btn.pressed.connect(_on_quit_pressed)
	UiFocusHelper.wire_vertical([resume_btn, settings_btn, restart_btn, menu_btn, quit_btn])

	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null:
		gs.connect("state_changed", _on_game_state_changed)

	var idm: Node = get_node_or_null("/root/InputDeviceManager")
	if idm != null:
		idm.connect("controller_disconnected", _on_controller_disconnected)
		idm.connect("controller_reconnected", _on_controller_reconnected)


func _unhandled_input(event: InputEvent) -> void:
	if backdrop == null or not backdrop.visible:
		return
	if _disconnect_paused and event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and not ke.echo and not event.is_action("pause"):
			_clear_disconnect_notice()
			_on_resume_pressed()
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("ui_cancel"):
		if settings_panel.visible:
			_on_settings_closed()
		else:
			_on_resume_pressed()
		get_viewport().set_input_as_handled()


func _on_controller_disconnected(_device_id: int) -> void:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs == null or not bool(gs.call("is_playing")):
		return
	var player := get_node_or_null(player_path) as PlayerController
	if player != null and not player.is_dead:
		_disconnect_paused = true
		if disconnect_notice_label != null:
			disconnect_notice_label.text = InputDeviceManagerScript.DISCONNECT_NOTICE_TEXT
			disconnect_notice_label.visible = true
		if not player.is_paused:
			player.toggle_pause()


func _on_controller_reconnected(_device_id: int) -> void:
	if _disconnect_paused and disconnect_notice_label != null:
		disconnect_notice_label.text = "Controller reconnected - press Start or Resume"


func _clear_disconnect_notice() -> void:
	_disconnect_paused = false
	if disconnect_notice_label != null:
		disconnect_notice_label.visible = false


func _on_game_state_changed(new_state: int, _old_state: int) -> void:
	var is_paused_state: bool = new_state == 2 # GameState.State.PAUSED
	if backdrop:
		backdrop.visible = is_paused_state
	if is_paused_state:
		main_panel.visible = true
		settings_panel.visible = false
		UiFocusHelper.grab_safe(resume_btn)
		if DisplayServer.get_name() != "headless":
			var idm: Node = get_node_or_null("/root/InputDeviceManager")
			if idm != null and int(idm.get("current_device")) != 0:
				Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
			else:
				Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		_clear_disconnect_notice()


func _on_resume_pressed() -> void:
	_clear_disconnect_notice()
	var player := get_node_or_null(player_path) as PlayerController
	if player != null and player.is_paused:
		player.toggle_pause()


func _on_settings_pressed() -> void:
	main_panel.visible = false
	settings_panel.sync_from_manager()
	settings_panel.visible = true
	settings_panel.grab_initial_focus()


func _on_settings_closed() -> void:
	settings_panel.visible = false
	main_panel.visible = true
	UiFocusHelper.grab_safe(settings_btn)


func _on_restart_pressed() -> void:
	var player := get_node_or_null(player_path) as PlayerController
	if player != null and player.is_paused:
		player.toggle_pause()
	var ac := get_node_or_null(arena_controller_path) as ArenaController
	if ac != null:
		ac.restart_run()


func _on_menu_pressed() -> void:
	var idm: Node = get_node_or_null("/root/InputDeviceManager")
	if idm != null:
		idm.call("stop_all_vibration")
	var rm := get_tree().get_first_node_in_group("round_manager") as RoundManager
	if rm != null:
		rm.stop_and_cleanup()
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null:
		gs.call("abandon_run_to_menu")
	if DisplayServer.get_name() != "headless":
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if get_tree() != null:
		get_tree().change_scene_to_file(MAIN_MENU_PATH)


func _on_quit_pressed() -> void:
	if get_tree() != null:
		get_tree().quit()
