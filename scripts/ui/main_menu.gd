class_name MainMenu
extends Control
## Main menu screen (Phase 8): Play, Character Select, Settings, Credits, Exit.

const UiFocusHelper := preload("res://scripts/ui/ui_focus_helper.gd")

const COMPOUND_SCENE_PATH := "res://scenes/environment/greybox_compound.tscn"
const CHARACTER_PATHS := [
	"res://resources/characters/marcus_vance.tres",
	"res://resources/characters/simone_brooks.tres",
	"res://resources/characters/devon_carter.tres",
	"res://resources/characters/tasha_monroe.tres",
]

@onready var main_panel: PanelContainer = $CenterContainer/MainPanel
@onready var stats_label: Label = $CenterContainer/MainPanel/VBox/StatsLabel
@onready var notice_label: Label = $CenterContainer/MainPanel/VBox/NoticeLabel
@onready var play_btn: Button = $CenterContainer/MainPanel/VBox/PlayButton
@onready var char_btn: Button = $CenterContainer/MainPanel/VBox/CharacterButton
@onready var settings_btn: Button = $CenterContainer/MainPanel/VBox/SettingsButton
@onready var credits_btn: Button = $CenterContainer/MainPanel/VBox/CreditsButton
@onready var exit_btn: Button = $CenterContainer/MainPanel/VBox/ExitButton

@onready var char_panel: PanelContainer = $CenterContainer/CharacterPanel
@onready var char_cards_row: HBoxContainer = $CenterContainer/CharacterPanel/VBox/CardsRow
@onready var char_back_btn: Button = $CenterContainer/CharacterPanel/VBox/BackButton

@onready var settings_panel: SettingsPanel = $CenterContainer/SettingsPanel
@onready var credits_panel: PanelContainer = $CenterContainer/CreditsPanel
@onready var credits_back_btn: Button = $CenterContainer/CreditsPanel/VBox/BackButton

var _characters: Array[CharacterData] = []
var _card_panels: Dictionary = {}
var _card_buttons: Array[Control] = []
var _last_main_focus: Control = null


func _ready() -> void:
	UiFocusHelper.apply_focus_theme(self)
	if get_tree() != null:
		get_tree().paused = false
	if DisplayServer.get_name() != "headless":
		var idm: Node = get_node_or_null("/root/InputDeviceManager")
		if idm != null and int(idm.get("current_device")) != 0:
			Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null and gs.has_method("abandon_run_to_menu"):
		gs.call("abandon_run_to_menu")

	play_btn.pressed.connect(_on_play_pressed)
	char_btn.pressed.connect(func() -> void:
		_last_main_focus = char_btn
		_show_panel(char_panel))
	settings_btn.pressed.connect(func() -> void:
		_last_main_focus = settings_btn
		settings_panel.sync_from_manager()
		_show_panel(settings_panel))
	credits_btn.pressed.connect(func() -> void:
		_last_main_focus = credits_btn
		_show_panel(credits_panel))
	exit_btn.pressed.connect(func() -> void:
		if get_tree() != null: get_tree().quit())

	char_back_btn.pressed.connect(func() -> void: _show_panel(main_panel))
	settings_panel.closed.connect(func() -> void: _show_panel(main_panel))
	credits_back_btn.pressed.connect(func() -> void: _show_panel(main_panel))

	UiFocusHelper.wire_vertical([play_btn, char_btn, settings_btn, credits_btn, exit_btn])
	_last_main_focus = play_btn
	_build_character_cards()
	_refresh_summary()
	_show_panel(main_panel)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if char_panel.visible or settings_panel.visible or credits_panel.visible:
			_show_panel(main_panel)
			get_viewport().set_input_as_handled()


func _show_panel(target: Control) -> void:
	main_panel.visible = (target == main_panel)
	char_panel.visible = (target == char_panel)
	settings_panel.visible = (target == settings_panel)
	credits_panel.visible = (target == credits_panel)
	if target == main_panel:
		UiFocusHelper.grab_safe(_last_main_focus if _last_main_focus != null else play_btn)
	elif target == char_panel:
		if not _card_buttons.is_empty():
			UiFocusHelper.grab_safe(_card_buttons[0])
		else:
			UiFocusHelper.grab_safe(char_back_btn)
	elif target == settings_panel:
		settings_panel.grab_initial_focus()
	elif target == credits_panel:
		UiFocusHelper.grab_safe(credits_back_btn)


func _refresh_summary() -> void:
	var sm: Node = get_node_or_null("/root/SaveManager")
	if sm == null:
		return
	var prog: Dictionary = sm.call("get_progression")
	if stats_label:
		stats_label.text = "Best Round: %d  |  High Score: %d  |  Total Kills: %d" % [
			int(prog.get("best_round", 0)),
			int(prog.get("highest_score", 0)),
			int(prog.get("total_kills", 0)),
		]
	if notice_label:
		var was_corrupt: bool = bool(sm.get("last_load_was_corrupt"))
		notice_label.visible = was_corrupt
		if was_corrupt:
			notice_label.text = "Corrupt save detected; defaults restored."


func _build_character_cards() -> void:
	_characters.clear()
	_card_panels.clear()
	_card_buttons.clear()
	for child: Node in char_cards_row.get_children():
		child.queue_free()

	for path: String in CHARACTER_PATHS:
		var cd := load(path) as CharacterData
		if cd != null:
			_characters.append(cd)
			var card := _create_character_card(cd)
			char_cards_row.add_child(card)
			_card_panels[cd.id] = card

	UiFocusHelper.wire_horizontal(_card_buttons)
	for btn: Control in _card_buttons:
		btn.focus_neighbor_bottom = btn.get_path_to(char_back_btn)
	if not _card_buttons.is_empty():
		char_back_btn.focus_neighbor_top = char_back_btn.get_path_to(_card_buttons[0])
	_refresh_character_highlights()


func _create_character_card(cd: CharacterData) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(210, 240)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	var name_lbl := Label.new()
	name_lbl.text = cd.display_name
	name_lbl.add_theme_font_size_override("font_size", 18)
	name_lbl.modulate = cd.ui_tint
	vbox.add_child(name_lbl)

	var arch_lbl := Label.new()
	arch_lbl.text = cd.archetype
	arch_lbl.add_theme_font_size_override("font_size", 13)
	arch_lbl.modulate = Color(0.75, 0.78, 0.85, 1.0)
	vbox.add_child(arch_lbl)

	var bio_lbl := Label.new()
	bio_lbl.text = cd.short_bio
	bio_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bio_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bio_lbl.add_theme_font_size_override("font_size", 13)
	vbox.add_child(bio_lbl)

	var select_btn := Button.new()
	select_btn.text = "Select"
	select_btn.focus_mode = Control.FOCUS_ALL
	select_btn.pressed.connect(func() -> void: select_character(cd.id))
	vbox.add_child(select_btn)
	_card_buttons.append(select_btn)

	return panel


func select_character(char_id: String) -> void:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null:
		gs.call("set_selected_character_id", char_id)
	_refresh_character_highlights()


func _refresh_character_highlights() -> void:
	var gs: Node = get_node_or_null("/root/GameState")
	var selected_id: String = str(gs.get("selected_character_id")) if gs != null else "marcus_vance"
	for cd: CharacterData in _characters:
		var panel := _card_panels.get(cd.id) as PanelContainer
		if panel == null:
			continue
		var sb := StyleBoxFlat.new()
		sb.set_content_margin_all(12)
		sb.set_corner_radius_all(6)
		if cd.id == selected_id:
			sb.bg_color = cd.ui_tint.darkened(0.72)
			sb.border_color = cd.ui_tint
			sb.set_border_width_all(3)
		else:
			sb.bg_color = Color(0.1, 0.11, 0.15, 0.95)
			sb.border_color = Color(0.24, 0.27, 0.35, 1.0)
			sb.set_border_width_all(1)
		panel.add_theme_stylebox_override("panel", sb)


func _on_play_pressed() -> void:
	if get_tree() != null:
		get_tree().change_scene_to_file(COMPOUND_SCENE_PATH)
