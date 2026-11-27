extends CanvasLayer
## Combat & survival HUD: dynamic spread crosshair, weapon/ammo readout,
## hit/headshot markers, health/damage feedback, round/points, and interact prompt.

@export var player_path: NodePath
@export var round_manager_path: NodePath
@export var points_manager_path: NodePath

@onready var weapon_label: Label = $AmmoPanel/VBoxContainer/WeaponNameLabel
@onready var ammo_label: Label = $AmmoPanel/VBoxContainer/AmmoLabel
@onready var health_label: Label = $HealthPanel/MarginContainer/HealthLabel
@onready var round_label: Label = $RoundPanel/VBoxContainer/RoundLabel
@onready var remaining_label: Label = $RoundPanel/VBoxContainer/RemainingLabel
@onready var points_label: Label = $PointsPanel/VBoxContainer/PointsLabel
@onready var points_popup_label: Label = $PointsPanel/VBoxContainer/PointsPopupLabel
@onready var announcement_label: Label = $AnnouncementLabel
@onready var prompt_label: Label = $PromptLabel
@onready var interact_progress_bar: ProgressBar = $InteractProgressBar
@onready var perk_bar: HBoxContainer = get_node_or_null("PerkBar") as HBoxContainer
@onready var subtitle_panel: PanelContainer = get_node_or_null("SubtitlePanel") as PanelContainer
@onready var subtitle_label: RichTextLabel = get_node_or_null("SubtitlePanel/SubtitleLabel") as RichTextLabel
@onready var damage_vignette: TextureRect = $DamageVignette
@onready var scope_overlay: Control = get_node_or_null("ScopeOverlay") as Control
@onready var damage_indicator: Control = $CenterContainer/DamageIndicatorPivot
@onready var hit_marker: Control = $CenterContainer/HitMarker
@onready var cross_top: ColorRect = $CenterContainer/Crosshair/Top
@onready var cross_bottom: ColorRect = $CenterContainer/Crosshair/Bottom
@onready var cross_left: ColorRect = $CenterContainer/Crosshair/Left
@onready var cross_right: ColorRect = $CenterContainer/Crosshair/Right

var _hit_timer: float = 0.0
var _recent_damage_flash: float = 0.0
var _low_health_alpha: float = 0.0
var _indicator_timer: float = 0.0
var _announcement_timer: float = 0.0
var _popup_timer: float = 0.0
var _attacker_world_pos: Vector3 = Vector3.ZERO
var _has_attacker_pos: bool = false

var _player: PlayerController = null
var _weapon_manager: WeaponManager = null
var _player_health: PlayerHealth = null
var _perk_manager: PerkManager = null
var _round_manager: RoundManager = null
var _points_manager: PointsManager = null
var _dialogue_blip_player: AudioStreamPlayer = null
var _dialogue_blip_stream: AudioStreamWAV = null


func _ready() -> void:
	if hit_marker:
		hit_marker.visible = false
	if damage_indicator:
		damage_indicator.visible = false
	if damage_vignette:
		damage_vignette.modulate.a = 0.0
	if announcement_label:
		announcement_label.visible = false
	if points_popup_label:
		points_popup_label.visible = false
	if prompt_label:
		prompt_label.visible = false
	if interact_progress_bar:
		interact_progress_bar.visible = false

	var player: Node = get_node_or_null(player_path) if player_path != NodePath() else get_tree().get_first_node_in_group("player")
	if player is PlayerController:
		_player = player as PlayerController
		_weapon_manager = player.get_node_or_null("WeaponManager") as WeaponManager
		_player_health = player.get_node_or_null("PlayerHealth") as PlayerHealth
		_perk_manager = player.get_node_or_null("PerkManager") as PerkManager

	if _perk_manager != null:
		_perk_manager.perk_added.connect(_on_perk_added)
		_perk_manager.perks_changed.connect(_on_perks_changed)
		_on_perks_changed(_perk_manager.active_perks)

	if _weapon_manager != null:
		_weapon_manager.weapon_switched.connect(_on_weapon_switched)
		_weapon_manager.ammo_changed.connect(_on_ammo_changed)
		_weapon_manager.hit_confirmed.connect(_on_hit_confirmed)
		_weapon_manager.spread_changed.connect(_on_spread_changed)
		if _weapon_manager.active_weapon and _weapon_manager.active_weapon.data:
			_on_weapon_switched(_weapon_manager.active_weapon.data)
			_on_ammo_changed(_weapon_manager.active_weapon.mag_ammo, _weapon_manager.active_weapon.reserve_ammo)

	if _player_health != null:
		_player_health.health_changed.connect(_on_health_changed)
		_player_health.damage_taken.connect(_on_damage_taken)
		if _player_health.health_component != null:
			_on_health_changed(_player_health.health_component.current_health, _player_health.health_component.max_health)

	_round_manager = (
		get_node_or_null(round_manager_path) as RoundManager
		if round_manager_path != NodePath()
		else get_tree().get_first_node_in_group("round_manager") as RoundManager
	)
	if _round_manager != null:
		_round_manager.round_started.connect(_on_round_started)
		_round_manager.round_ended.connect(_on_round_ended)
		_round_manager.zombies_remaining_changed.connect(_on_zombies_remaining_changed)

	_points_manager = (
		get_node_or_null(points_manager_path) as PointsManager
		if points_manager_path != NodePath()
		else get_tree().get_first_node_in_group("points_manager") as PointsManager
	)
	if _points_manager != null:
		_points_manager.balance_changed.connect(_on_balance_changed)
		_on_balance_changed(_points_manager.balance, 0, "init")

	var dm: Node = get_node_or_null("/root/DialogueManager")
	if dm != null:
		dm.connect("line_started", _on_dialogue_line_started)
		dm.connect("line_cleared", _on_dialogue_line_cleared)
	_setup_dialogue_blip()


func _process(delta: float) -> void:
	if _hit_timer > 0.0:
		_hit_timer -= delta
		if _hit_timer <= 0.0 and hit_marker:
			hit_marker.visible = false

	if _recent_damage_flash > 0.0:
		_recent_damage_flash = maxf(_recent_damage_flash - 1.8 * delta, 0.0)

	if damage_vignette:
		damage_vignette.modulate.a = clampf(maxf(_recent_damage_flash, _low_health_alpha), 0.0, 0.9)

	if _announcement_timer > 0.0:
		_announcement_timer -= delta
		if _announcement_timer <= 0.0 and announcement_label:
			announcement_label.visible = false

	if _popup_timer > 0.0:
		_popup_timer -= delta
		if _popup_timer <= 0.0 and points_popup_label:
			points_popup_label.visible = false

	if _indicator_timer > 0.0:
		_indicator_timer -= delta
		if _indicator_timer <= 0.0 and damage_indicator:
			damage_indicator.visible = false
		elif damage_indicator and _has_attacker_pos and _player != null:
			var to_attacker: Vector3 = _attacker_world_pos - _player.global_position
			to_attacker.y = 0.0
			if to_attacker.length_squared() > 0.001:
				to_attacker = to_attacker.normalized()
				var forward: Vector3 = -_player.global_transform.basis.z
				forward.y = 0.0
				forward = forward.normalized()
				var right: Vector3 = _player.global_transform.basis.x
				right.y = 0.0
				right = right.normalized()
				var angle: float = atan2(to_attacker.dot(right), to_attacker.dot(forward))
				damage_indicator.rotation = angle
				damage_indicator.modulate.a = clampf(_indicator_timer / 0.5, 0.0, 1.0)

	_update_interact_prompt()
	_update_scope_overlay()


func _update_scope_overlay() -> void:
	if scope_overlay == null or _weapon_manager == null or _weapon_manager.active_weapon == null:
		return
	var w: Weapon = _weapon_manager.active_weapon
	var show_scope: bool = w.is_aiming and w.data != null and w.data.has_scope_overlay and not w.is_reloading
	scope_overlay.visible = show_scope
	if _weapon_manager.active_viewmodel != null:
		_weapon_manager.active_viewmodel.visible = not show_scope and (_player == null or not _player.is_dead)


func _update_interact_prompt() -> void:
	if prompt_label == null or _player == null:
		if prompt_label:
			prompt_label.visible = false
		if interact_progress_bar:
			interact_progress_bar.visible = false
		return

	var ui_state: Dictionary = _player.get_interact_ui_state()
	if not ui_state.get("visible", false):
		prompt_label.visible = false
		if interact_progress_bar:
			interact_progress_bar.visible = false
		return

	prompt_label.text = ui_state.get("text", "")
	var affordable: bool = ui_state.get("affordable", true)
	prompt_label.modulate = Color(1.0, 1.0, 1.0, 1.0) if affordable else Color(1.0, 0.35, 0.35, 1.0)
	prompt_label.visible = true

	if interact_progress_bar != null:
		var is_hold: bool = ui_state.get("is_hold", false)
		var prog: float = float(ui_state.get("progress", 0.0))
		interact_progress_bar.visible = is_hold and prog > 0.0
		interact_progress_bar.value = prog * 100.0


func _on_round_started(round_num: int, total_zombies: int) -> void:
	if round_label:
		round_label.text = "ROUND %d" % round_num
	_on_zombies_remaining_changed(total_zombies)
	_show_announcement("ROUND %d" % round_num)


func _on_round_ended(round_num: int) -> void:
	_show_announcement("ROUND %d COMPLETE" % round_num)


func _show_announcement(text: String) -> void:
	if announcement_label:
		announcement_label.text = text
		announcement_label.visible = true
		_announcement_timer = 2.4


func _on_zombies_remaining_changed(remaining: int) -> void:
	if remaining_label:
		remaining_label.text = "Zombies: %d" % remaining


func _on_balance_changed(new_balance: int, delta_pts: int, _reason: String) -> void:
	if points_label:
		points_label.text = "%d PTS" % new_balance
	if delta_pts > 0 and points_popup_label:
		points_popup_label.text = "+%d" % delta_pts
		points_popup_label.visible = true
		_popup_timer = 0.9


func _on_weapon_switched(weapon_data: WeaponData) -> void:
	if weapon_label and weapon_data:
		if _weapon_manager != null and _weapon_manager.has_method("get_active_display_name"):
			weapon_label.text = _weapon_manager.call("get_active_display_name")
		else:
			weapon_label.text = weapon_data.display_name


func _on_perk_added(perk: PerkData) -> void:
	if perk != null:
		_show_announcement("PERK ACQUIRED: %s" % perk.display_name.to_upper())
		var idm: Node = get_node_or_null("/root/InputDeviceManager")
		if idm != null:
			idm.call("play_vibration", 0.25, 0.15, 0.12, false)


func _on_perks_changed(perks: Array[PerkData]) -> void:
	if perk_bar == null:
		return
	for child: Node in perk_bar.get_children():
		child.queue_free()
	for perk: PerkData in perks:
		if perk == null:
			continue
		var badge := PanelContainer.new()
		badge.custom_minimum_size = Vector2(44, 34)
		var sb := StyleBoxFlat.new()
		sb.bg_color = perk.accent_color.darkened(0.45)
		sb.border_color = perk.accent_color
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(4)
		badge.add_theme_stylebox_override("panel", sb)
		var lbl := Label.new()
		lbl.text = perk.short_label if not perk.short_label.is_empty() else perk.display_name.left(3).to_upper()
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 13)
		badge.add_child(lbl)
		perk_bar.add_child(badge)


func _setup_dialogue_blip() -> void:
	var sample_rate: int = 22050
	var duration: float = 0.06
	var total: int = int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(total * 2)
	for i: int in range(total):
		var t: float = float(i) / float(sample_rate)
		var env: float = exp(-t * 45.0)
		var s: float = sin(TAU * 620.0 * t) * 0.18 * env
		var sample_i: int = clampi(int(s * 32767.0), -32768, 32767)
		data[i * 2] = sample_i & 0xFF
		data[i * 2 + 1] = (sample_i >> 8) & 0xFF
	_dialogue_blip_stream = AudioStreamWAV.new()
	_dialogue_blip_stream.format = AudioStreamWAV.FORMAT_16_BITS
	_dialogue_blip_stream.mix_rate = sample_rate
	_dialogue_blip_stream.data = data

	_dialogue_blip_player = AudioStreamPlayer.new()
	_dialogue_blip_player.name = "DialogueBlipAudio"
	_dialogue_blip_player.bus = &"Dialogue"
	_dialogue_blip_player.stream = _dialogue_blip_stream
	add_child(_dialogue_blip_player)


func _exit_tree() -> void:
	if _dialogue_blip_player != null:
		_dialogue_blip_player.stop()
		_dialogue_blip_player.stream = null
	_dialogue_blip_stream = null


func _on_dialogue_line_started(speaker_name: String, speaker_tint: Color, text: String, _duration: float, _category: String) -> void:
	var set_m: Node = get_node_or_null("/root/SettingsManager")
	var subs_on: bool = bool(set_m.get("subtitles")) if set_m != null else true
	if not subs_on:
		if subtitle_panel != null:
			subtitle_panel.visible = false
		return
	if subtitle_panel != null and subtitle_label != null:
		var hex: String = speaker_tint.to_html(false)
		subtitle_label.text = "[center][color=#%s][b]%s:[/b][/color] %s[/center]" % [hex, speaker_name, text]
		subtitle_panel.visible = true
	if _dialogue_blip_player != null:
		_dialogue_blip_player.play()


func _on_dialogue_line_cleared() -> void:
	if subtitle_panel != null:
		subtitle_panel.visible = false


func _on_ammo_changed(mag: int, reserve: int) -> void:
	if ammo_label:
		ammo_label.text = "%d / %d" % [mag, reserve]


func _on_health_changed(current_hp: float, max_hp: float) -> void:
	if health_label:
		health_label.text = "HP: %d / %d" % [ceili(current_hp), ceili(max_hp)]
	var ratio: float = clampf(current_hp / maxf(max_hp, 1.0), 0.0, 1.0)
	_low_health_alpha = clampf((0.5 - ratio) * 1.4, 0.0, 0.7) if ratio < 0.5 else 0.0


func _on_damage_taken(amount: float, attacker_world_pos: Vector3, has_attacker_pos: bool) -> void:
	_recent_damage_flash = clampf(_recent_damage_flash + clampf(amount / 40.0, 0.25, 0.75), 0.0, 0.85)
	if has_attacker_pos and damage_indicator:
		_attacker_world_pos = attacker_world_pos
		_has_attacker_pos = true
		_indicator_timer = 1.2
		damage_indicator.visible = true


func _on_hit_confirmed(is_headshot: bool, _is_kill: bool) -> void:
	if hit_marker == null:
		return
	hit_marker.visible = true
	hit_marker.modulate = Color(1.0, 0.25, 0.2, 1.0) if is_headshot else Color(1.0, 1.0, 1.0, 0.95)
	_hit_timer = 0.18 if is_headshot else 0.12


func _on_spread_changed(spread_degrees: float) -> void:
	var gap: float = 6.0 + spread_degrees * 6.0
	if cross_top:
		cross_top.position = Vector2(-1.0, -gap - 8.0)
	if cross_bottom:
		cross_bottom.position = Vector2(-1.0, gap)
	if cross_left:
		cross_left.position = Vector2(-gap - 8.0, -1.0)
	if cross_right:
		cross_right.position = Vector2(gap, -1.0)
