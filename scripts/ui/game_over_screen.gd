class_name GameOverScreen
extends CanvasLayer
## Minimal Phase 4 Game Over screen showing run summary with Restart and
## Return to Menu (stub) actions.

const UiFocusHelper := preload("res://scripts/ui/ui_focus_helper.gd")

signal restart_requested
signal menu_requested

@onready var root_panel: Control = $CenterContainer
@onready var stats_label: Label = $CenterContainer/PanelContainer/VBoxContainer/StatsLabel
@onready var restart_button: Button = $CenterContainer/PanelContainer/VBoxContainer/Buttons/RestartButton
@onready var menu_button: Button = $CenterContainer/PanelContainer/VBoxContainer/Buttons/MenuButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if root_panel:
		UiFocusHelper.apply_focus_theme(root_panel)
		root_panel.visible = false

	if restart_button:
		restart_button.pressed.connect(_on_restart_pressed)
	if menu_button:
		menu_button.pressed.connect(_on_menu_pressed)
	UiFocusHelper.wire_horizontal([restart_button, menu_button])

	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null:
		gs.connect("run_started", _on_run_started)
		gs.connect("run_ended", _on_run_ended)


func _on_run_started() -> void:
	if root_panel:
		root_panel.visible = false


func _on_run_ended(stats: Dictionary) -> void:
	if root_panel:
		root_panel.visible = true
	UiFocusHelper.grab_safe(restart_button)
	if DisplayServer.get_name() != "headless":
		var idm: Node = get_node_or_null("/root/InputDeviceManager")
		if idm != null and int(idm.get("current_device")) != 0:
			Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	var total_sec: int = int(stats.get("time_survived", 0.0))
	@warning_ignore("integer_division")
	var mins: int = total_sec / 60
	var secs: int = total_sec % 60
	var gs: Node = get_node_or_null("/root/GameState")
	var is_new_best: bool = bool(gs.get("last_run_is_new_best")) if gs != null else false
	var best_line: String = "NEW BEST ROUND!\n" if is_new_best else ""
	if stats_label:
		stats_label.text = (
			best_line
			+ "Round Reached: %d\n" % stats.get("round_reached", 1)
			+ "Kills: %d\n" % stats.get("kills", 0)
			+ "Headshots: %d\n" % stats.get("headshots", 0)
			+ "Points Earned: %d\n" % stats.get("points_earned", 0)
			+ "Time Survived: %02d:%02d" % [mins, secs]
		)


func _on_restart_pressed() -> void:
	restart_requested.emit()


func _on_menu_pressed() -> void:
	menu_requested.emit()
	if get_tree() != null:
		var rm := get_tree().get_first_node_in_group("round_manager") as RoundManager
		if rm != null:
			rm.stop_and_cleanup()
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null and gs.has_method("abandon_run_to_menu"):
		gs.call("abandon_run_to_menu")
	if DisplayServer.get_name() != "headless":
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if get_tree() != null:
		get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
