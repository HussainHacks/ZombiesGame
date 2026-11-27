class_name UpgradeStation
extends Purchasable
## Forge Bench weapon upgrade station extending Purchasable.
## Flow: IDLE -> PROCESSING -> READY -> IDLE.
## Enforces the only-weapon rule (requires >= 2 weapons to deposit) and
## auto-returns the upgraded weapon if READY times out before collection.

const DEFAULT_ECONOMY := preload("res://resources/configuration/economy_config.tres")
const DEFAULT_UPGRADE := preload("res://resources/configuration/default_weapon_upgrade.tres")

enum StationState {
	IDLE,
	PROCESSING,
	READY,
}

signal state_changed(new_state: StationState)
signal weapon_upgraded(weapon_data: WeaponData, new_tier: int)

@export var upgrade_data: WeaponUpgradeData
@export var economy_config: EconomyConfig

@onready var status_label: Label3D = get_node_or_null("StatusLabel") as Label3D
@onready var bench_glow_mesh: MeshInstance3D = get_node_or_null("GlowMesh") as MeshInstance3D

var station_state: StationState = StationState.IDLE
var _state_timer: float = 0.0
var _held_weapon: WeaponData = null
var _held_tier: int = 0
var _owner_player: Node = null

var _audio_player: AudioStreamPlayer3D = null
var _forge_stream: AudioStreamWAV = null


func _ready() -> void:
	collision_layer = 16
	collision_mask = 0
	_setup_audio()
	_update_visuals()


func _exit_tree() -> void:
	if _audio_player:
		_audio_player.stop()
		_audio_player.stream = null
	_forge_stream = null


func _setup_audio() -> void:
	_forge_stream = _create_forge_sound()
	_audio_player = AudioStreamPlayer3D.new()
	_audio_player.name = "ForgeAudio"
	_audio_player.stream = _forge_stream
	_audio_player.bus = &"SFX"
	add_child(_audio_player)


func _process(delta: float) -> void:
	if station_state == StationState.PROCESSING:
		_state_timer -= delta
		if _state_timer <= 0.0:
			var upg: WeaponUpgradeData = _get_upgrade_data()
			station_state = StationState.READY
			_state_timer = upg.ready_timeout
			state_changed.emit(station_state)
			_update_visuals()
			if _audio_player != null:
				_audio_player.play()
	elif station_state == StationState.READY:
		_state_timer -= delta
		if _state_timer <= 0.0:
			_collect_or_auto_return(_owner_player)


func _get_upgrade_data() -> WeaponUpgradeData:
	return upgrade_data if upgrade_data != null else DEFAULT_UPGRADE


func get_effective_cost(_player: Node = null) -> int:
	var ec: EconomyConfig = economy_config if economy_config != null else DEFAULT_ECONOMY
	if ec != null:
		return ec.upgrade_base_cost
	return _get_upgrade_data().upgrade_cost


func can_purchase(player: Node, points_manager: PointsManager) -> bool:
	if station_state != StationState.IDLE or player == null:
		return false
	var wm: WeaponManager = player.get("weapon_manager") as WeaponManager
	if wm == null or wm.slots.size() <= 1 or not wm.can_upgrade_active():
		return false
	return super.can_purchase(player, points_manager)


func interact(player: Node) -> void:
	try_interact(player)


func try_interact(player: Node, points_manager: PointsManager = null) -> bool:
	if station_state == StationState.READY:
		return _collect_or_auto_return(player)
	if points_manager == null and is_inside_tree():
		points_manager = get_tree().get_first_node_in_group("points_manager") as PointsManager
	if points_manager == null:
		return false
	return purchase(player, points_manager)


func get_prompt_text(player: Node = null) -> String:
	var upg: WeaponUpgradeData = _get_upgrade_data()
	match station_state:
		StationState.PROCESSING:
			return "Forging %s..." % (_held_weapon.display_name if _held_weapon != null else "Weapon")
		StationState.READY:
			var wname: String = _held_weapon.display_name if _held_weapon != null else "Weapon"
			return "[E] Take %s%s" % [upg.name_prefix, wname]
		_:
			var wm: WeaponManager = player.get("weapon_manager") as WeaponManager if player != null else null
			if wm != null:
				if wm.slots.size() <= 1:
					return "[Need 2nd Weapon] Forge Bench"
				if not wm.can_upgrade_active():
					return "[Max Tier] %s" % wm.get_active_display_name()
			return "[E] Upgrade Weapon (%d pts)" % get_effective_cost(player)


func _apply_purchase(player: Node) -> void:
	if player == null:
		return
	var wm: WeaponManager = player.get("weapon_manager") as WeaponManager
	if wm == null:
		return
	var taken: Dictionary = wm.take_active_for_upgrade()
	if taken.is_empty():
		return
	_held_weapon = taken["data"] as WeaponData
	_held_tier = int(taken.get("tier", 0))
	_owner_player = player
	var upg: WeaponUpgradeData = _get_upgrade_data()
	station_state = StationState.PROCESSING
	_state_timer = upg.processing_duration
	state_changed.emit(station_state)
	_update_visuals()
	if _audio_player != null:
		_audio_player.play()


func _collect_or_auto_return(player: Node) -> bool:
	if station_state != StationState.READY or _held_weapon == null:
		return false
	var target_player: Node = player if player != null else _owner_player
	var wm: WeaponManager = target_player.get("weapon_manager") as WeaponManager if target_player != null else null
	var upg: WeaponUpgradeData = _get_upgrade_data()
	var new_tier: int = _held_tier + 1
	var wd: WeaponData = _held_weapon
	if wm != null:
		wm.receive_upgraded_weapon(wd, new_tier, upg)

	_held_weapon = null
	_held_tier = 0
	_owner_player = null
	_state_timer = 0.0
	station_state = StationState.IDLE
	state_changed.emit(station_state)
	_update_visuals()
	weapon_upgraded.emit(wd, new_tier)

	if is_inside_tree():
		var ge: Node = get_node_or_null("/root/GameEvents")
		if ge != null:
			ge.emit_signal("weapon_upgraded", wd, new_tier, get_effective_cost(target_player))
	return true


func reset_station() -> void:
	_held_weapon = null
	_held_tier = 0
	_owner_player = null
	_state_timer = 0.0
	station_state = StationState.IDLE
	state_changed.emit(station_state)
	_update_visuals()


func _update_visuals() -> void:
	var upg: WeaponUpgradeData = _get_upgrade_data()
	if status_label != null:
		match station_state:
			StationState.PROCESSING:
				status_label.text = "FORGING..."
				status_label.modulate = Color(1.0, 0.72, 0.25, 1.0)
			StationState.READY:
				status_label.text = "READY!"
				status_label.modulate = upg.emissive_tint
			_:
				status_label.text = "FORGE BENCH"
				status_label.modulate = Color(0.85, 0.92, 1.0, 1.0)
	if bench_glow_mesh != null:
		var mat := StandardMaterial3D.new()
		var col: Color = upg.emissive_tint if station_state != StationState.PROCESSING else Color(1.0, 0.55, 0.15, 1.0)
		mat.albedo_color = col
		mat.emission_enabled = true
		mat.emission = col
		mat.emission_energy_multiplier = 2.0 if station_state == StationState.READY else 0.9
		bench_glow_mesh.material_override = mat


static func _create_forge_sound() -> AudioStreamWAV:
	var sample_rate: int = 22050
	var duration: float = 0.35
	var total: int = int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(total * 2)
	for i: int in range(total):
		var t: float = float(i) / float(sample_rate)
		var env: float = exp(-t * 8.0)
		var s: float = (sin(TAU * 220.0 * t) * 0.5 + sin(TAU * 440.0 * t) * 0.35 + sin(TAU * 880.0 * t) * 0.2) * 0.35 * env
		var sample_i: int = clampi(int(s * 32767.0), -32768, 32767)
		data[i * 2] = sample_i & 0xFF
		data[i * 2 + 1] = (sample_i >> 8) & 0xFF
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sample_rate
	wav.data = data
	return wav
