class_name MysteryBox
extends Purchasable
## Weighted random weapon crate with spin cycle, rarity lighting, expiry,
## pity-ruled electrical jam + refund, and anti-exploit guards.

enum BoxState {
	IDLE,
	SPINNING,
	OFFERING,
	JAMMED,
	COOLDOWN,
}

signal spin_started
signal weapon_offered(weapon: WeaponData)
signal weapon_taken(weapon: WeaponData)
signal offer_expired
signal jam_triggered(refund_amount: int)
signal relocation_requested

@export var gameplay_config: GameplayConfig
@export var weapon_pool: Array[WeaponData] = []

@onready var lid_pivot: Node3D = get_node_or_null("LidPivot") as Node3D
@onready var display_anchor: Node3D = get_node_or_null("DisplayAnchor") as Node3D
@onready var rarity_light: OmniLight3D = get_node_or_null("RarityLight") as OmniLight3D
@onready var jam_sparks: CPUParticles3D = get_node_or_null("JamSparks") as CPUParticles3D
@onready var audio_player: AudioStreamPlayer3D = get_node_or_null("AudioStreamPlayer3D") as AudioStreamPlayer3D

var box_state: BoxState = BoxState.IDLE
var offered_weapon: WeaponData = null
var uses_since_relocate: int = 0
var state_timer: float = 0.0

var _tick_timer: float = 0.0
var _display_index: int = 0
var _display_node: Node3D = null
var _refund_granted: bool = false
var _weapon_taken_flag: bool = false
var _active_player: Node = null
var _rng := RandomNumberGenerator.new()

var _tick_sfx: AudioStreamWAV
var _chime_sfx: AudioStreamWAV
var _jam_sfx: AudioStreamWAV


func _ready() -> void:
	super._ready()
	add_to_group("mystery_box")
	item_name = "Mystery Box"
	_rng.randomize()
	_tick_sfx = MysteryBoxAudio.create_spin_tick()
	_chime_sfx = MysteryBoxAudio.create_result_chime()
	_jam_sfx = MysteryBoxAudio.create_jam_surge()
	_sync_visuals()


func _exit_tree() -> void:
	if audio_player:
		audio_player.stop()
		audio_player.stream = null
	_tick_sfx = null
	_chime_sfx = null
	_jam_sfx = null


func get_config() -> GameplayConfig:
	if gameplay_config != null:
		return gameplay_config
	return load("res://resources/configuration/gameplay_config.tres") as GameplayConfig


func get_effective_cost(_player: Node) -> int:
	var cfg: GameplayConfig = get_config()
	return cfg.mystery_box_cost if cfg != null else cost


func get_eligible_weapons(player: Node) -> Array[WeaponData]:
	var eligible: Array[WeaponData] = []
	var wm: WeaponManager = player.get_node_or_null("WeaponManager") as WeaponManager if player != null else null
	for wd: WeaponData in weapon_pool:
		if wd == null or wd.box_weight <= 0.0:
			continue
		if wm != null and wm.has_weapon(wd):
			continue
		eligible.append(wd)
	return eligible


func can_purchase(player: Node, points_manager: PointsManager) -> bool:
	if box_state != BoxState.IDLE:
		return false
	if get_eligible_weapons(player).is_empty():
		return false
	return super.can_purchase(player, points_manager)


func get_prompt_text(player: Node) -> String:
	match box_state:
		BoxState.IDLE:
			if get_eligible_weapons(player).is_empty():
				return "Mystery Box - No eligible weapons"
			return "Press E - Mystery Box [%d]" % get_effective_cost(player)
		BoxState.SPINNING:
			return "Mystery Box - Spinning..."
		BoxState.OFFERING:
			var wname: String = offered_weapon.display_name if offered_weapon != null else "Weapon"
			return "Press E - Take %s (%.1fs)" % [wname, maxf(state_timer, 0.0)]
		BoxState.JAMMED:
			return "Short Circuit! Refunded..."
		BoxState.COOLDOWN:
			return "Mystery Box - Cooling down..."
	return ""


func interact(player: Node) -> void:
	if player == null:
		return
	if "is_dead" in player and player.get("is_dead"):
		return
	if is_inside_tree():
		var gs: Node = get_node_or_null("/root/GameState")
		if gs != null and not gs.call("is_playing"):
			return

	if box_state == BoxState.OFFERING:
		take_offered_weapon(player)
		return

	var pm: PointsManager = get_tree().get_first_node_in_group("points_manager") as PointsManager if is_inside_tree() else null
	if pm != null:
		purchase(player, pm)


func _apply_purchase(player: Node) -> void:
	var cfg: GameplayConfig = get_config()
	_active_player = player
	offered_weapon = null
	_refund_granted = false
	_weapon_taken_flag = false
	uses_since_relocate += 1
	box_state = BoxState.SPINNING
	state_timer = cfg.box_spin_duration if cfg != null else 3.0
	_tick_timer = 0.0
	_set_lid_open(true)
	spin_started.emit()

	if is_inside_tree():
		var ge: Node = get_node_or_null("/root/GameEvents")
		if ge != null:
			ge.emit_signal("box_used", self, get_effective_cost(player))


func take_offered_weapon(player: Node) -> bool:
	if box_state != BoxState.OFFERING or offered_weapon == null or _weapon_taken_flag:
		return false
	if player == null or ("is_dead" in player and player.get("is_dead")):
		return false

	_weapon_taken_flag = true
	var granted: WeaponData = offered_weapon
	offered_weapon = null
	var wm: WeaponManager = player.get_node_or_null("WeaponManager") as WeaponManager
	if wm != null:
		wm.give_or_refill_weapon(granted)

	weapon_taken.emit(granted)
	_enter_cooldown()
	return true


func _process(delta: float) -> void:
	if is_inside_tree():
		var gs: Node = get_node_or_null("/root/GameState")
		if gs != null and not gs.call("is_playing"):
			return

	if _active_player != null and "is_dead" in _active_player and _active_player.get("is_dead"):
		if box_state == BoxState.SPINNING or box_state == BoxState.OFFERING:
			offered_weapon = null
			_enter_cooldown()
			return

	match box_state:
		BoxState.SPINNING:
			_process_spinning(delta)
		BoxState.OFFERING:
			_process_offering(delta)
		BoxState.JAMMED:
			_process_jammed(delta)
		BoxState.COOLDOWN:
			_process_cooldown(delta)


func _process_spinning(delta: float) -> void:
	state_timer -= delta
	_tick_timer -= delta
	if _tick_timer <= 0.0:
		_tick_timer = 0.16
		_cycle_spin_display()
		_play_sfx(_tick_sfx)

	if state_timer <= 0.0:
		_resolve_spin()


func _resolve_spin() -> void:
	var cfg: GameplayConfig = get_config()
	var min_uses: int = cfg.box_min_uses_before_relocate if cfg != null else 3
	var pity_max: int = cfg.box_pity_max_uses if cfg != null else 6
	var jam_chance: float = cfg.box_jam_chance if cfg != null else 0.25

	var should_jam: bool = false
	if uses_since_relocate >= pity_max:
		should_jam = true
	elif uses_since_relocate >= min_uses and _rng.randf() < jam_chance:
		should_jam = true

	if should_jam:
		_trigger_jam()
		return

	var eligible: Array[WeaponData] = get_eligible_weapons(_active_player)
	if eligible.is_empty():
		_trigger_jam()
		return

	offered_weapon = pick_weighted_weapon(eligible, _rng)
	box_state = BoxState.OFFERING
	state_timer = cfg.box_offer_duration if cfg != null else 8.0
	_show_weapon_model(offered_weapon)
	_set_rarity_light(offered_weapon.rarity)
	_play_sfx(_chime_sfx)
	weapon_offered.emit(offered_weapon)

	if is_inside_tree():
		var ge: Node = get_node_or_null("/root/GameEvents")
		if ge != null:
			ge.emit_signal("box_result", offered_weapon, offered_weapon.rarity)


func _trigger_jam() -> void:
	box_state = BoxState.JAMMED
	state_timer = 1.2
	offered_weapon = null
	_clear_display_model()
	if jam_sparks != null and is_inside_tree():
		jam_sparks.restart()
		jam_sparks.emitting = true
	if rarity_light != null:
		rarity_light.visible = true
		rarity_light.light_color = Color(1.0, 0.25, 0.05)
	_play_sfx(_jam_sfx)

	var refund: int = get_effective_cost(_active_player)
	if not _refund_granted:
		_refund_granted = true
		var pm: PointsManager = get_tree().get_first_node_in_group("points_manager") as PointsManager if is_inside_tree() else null
		if pm != null:
			pm.refund_points(refund, "box_jam_refund")
		jam_triggered.emit(refund)
	if is_inside_tree():
		var ge: Node = get_node_or_null("/root/GameEvents")
		if ge != null:
			ge.emit_signal("box_jammed", self)


func _process_offering(delta: float) -> void:
	if display_anchor != null:
		display_anchor.position.y = 1.1 + sin(Time.get_ticks_msec() * 0.005) * 0.06
	state_timer -= delta
	if state_timer <= 0.0:
		offered_weapon = null
		offer_expired.emit()
		_enter_cooldown()


func _process_jammed(delta: float) -> void:
	if rarity_light != null:
		rarity_light.light_energy = 3.0 if int(state_timer * 20.0) % 2 == 0 else 0.3
	state_timer -= delta
	if state_timer <= 0.0:
		uses_since_relocate = 0
		_enter_cooldown()
		relocation_requested.emit()


func _process_cooldown(delta: float) -> void:
	state_timer -= delta
	if state_timer <= 0.0:
		box_state = BoxState.IDLE
		_sync_visuals()


func _enter_cooldown() -> void:
	var cfg: GameplayConfig = get_config()
	box_state = BoxState.COOLDOWN
	state_timer = cfg.box_cooldown_duration if cfg != null else 2.0
	_clear_display_model()
	_set_lid_open(false)
	if rarity_light != null:
		rarity_light.visible = false


func reset_box() -> void:
	box_state = BoxState.IDLE
	offered_weapon = null
	uses_since_relocate = 0
	state_timer = 0.0
	_refund_granted = false
	_weapon_taken_flag = false
	_active_player = null
	_last_purchase_frame = -1
	_last_purchase_usec = -1000000
	_clear_display_model()
	_set_lid_open(false)
	_sync_visuals()


func _cycle_spin_display() -> void:
	if weapon_pool.is_empty():
		return
	_display_index = (_display_index + 1) % weapon_pool.size()
	var wd: WeaponData = weapon_pool[_display_index]
	_show_weapon_model(wd)


func _show_weapon_model(wd: WeaponData) -> void:
	_clear_display_model()
	if display_anchor == null or wd == null or wd.viewmodel_scene == null:
		return
	var inst := wd.viewmodel_scene.instantiate() as Node3D
	if inst != null:
		inst.set_script(null)
		_reset_visual_layers(inst)
		inst.position = Vector3.ZERO
		inst.rotation = Vector3(0.0, PI * 0.5, 0.0)
		inst.scale = Vector3.ONE * 1.4
		display_anchor.add_child(inst)
		_display_node = inst


func _reset_visual_layers(node: Node) -> void:
	if node is VisualInstance3D:
		(node as VisualInstance3D).layers = 1
	for c: Node in node.get_children():
		_reset_visual_layers(c)


func _clear_display_model() -> void:
	if _display_node != null and is_instance_valid(_display_node):
		_display_node.queue_free()
	_display_node = null


func _set_lid_open(open_lid: bool) -> void:
	if lid_pivot != null:
		lid_pivot.rotation.x = deg_to_rad(-75.0 if open_lid else 0.0)


func _set_rarity_light(rarity: WeaponData.Rarity) -> void:
	if rarity_light == null:
		return
	rarity_light.visible = true
	rarity_light.light_energy = 2.5
	match rarity:
		WeaponData.Rarity.COMMON:
			rarity_light.light_color = Color(0.95, 0.95, 1.0)
		WeaponData.Rarity.UNCOMMON:
			rarity_light.light_color = Color(0.25, 0.55, 1.0)
		WeaponData.Rarity.RARE:
			rarity_light.light_color = Color(1.0, 0.8, 0.2)


func _sync_visuals() -> void:
	if rarity_light != null:
		rarity_light.visible = false
	if jam_sparks != null:
		jam_sparks.emitting = false


func _play_sfx(stream: AudioStreamWAV) -> void:
	if audio_player != null and stream != null and is_inside_tree():
		audio_player.stream = stream
		audio_player.play()


static func pick_weighted_weapon(eligible: Array[WeaponData], rng: RandomNumberGenerator) -> WeaponData:
	if eligible.is_empty():
		return null
	var total_w: float = 0.0
	for wd: WeaponData in eligible:
		total_w += maxf(wd.box_weight, 0.0)
	if total_w <= 0.0:
		return eligible[0]
	var roll: float = rng.randf() * total_w
	var acc: float = 0.0
	for wd: WeaponData in eligible:
		acc += maxf(wd.box_weight, 0.0)
		if roll <= acc:
			return wd
	return eligible.back()
