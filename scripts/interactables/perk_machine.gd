class_name PerkMachine
extends Purchasable
## Interactable perk vending machine extending Purchasable.
## Tints its cabinet/sign from PerkData.accent_color, enforces no-duplicate
## and max_perks rules, and plays a procedural chime on purchase.

const DEFAULT_ECONOMY := preload("res://resources/configuration/economy_config.tres")

@export var perk_data: PerkData
@export var economy_config: EconomyConfig

@onready var cabinet_mesh: MeshInstance3D = get_node_or_null("CabinetMesh") as MeshInstance3D
@onready var sign_mesh: MeshInstance3D = get_node_or_null("SignMesh") as MeshInstance3D
@onready var sign_label: Label3D = get_node_or_null("SignLabel") as Label3D

var _audio_player: AudioStreamPlayer3D = null
var _chime_stream: AudioStreamWAV = null


func _ready() -> void:
	collision_layer = 16
	collision_mask = 0
	_apply_visual_branding()
	_setup_audio()


func _exit_tree() -> void:
	if _audio_player:
		_audio_player.stop()
		_audio_player.stream = null
	_chime_stream = null


func _apply_visual_branding() -> void:
	if perk_data == null:
		return
	if sign_label != null:
		sign_label.text = perk_data.short_label if not perk_data.short_label.is_empty() else perk_data.display_name
		sign_label.modulate = perk_data.accent_color
	if sign_mesh != null:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = perk_data.accent_color
		mat.emission_enabled = true
		mat.emission = perk_data.accent_color
		mat.emission_energy_multiplier = 1.4
		sign_mesh.material_override = mat
	if cabinet_mesh != null:
		var cab_mat := StandardMaterial3D.new()
		cab_mat.albedo_color = perk_data.accent_color.darkened(0.55)
		cabinet_mesh.material_override = cab_mat


func _setup_audio() -> void:
	_chime_stream = _create_chime_stream()
	_audio_player = AudioStreamPlayer3D.new()
	_audio_player.name = "PerkChimeAudio"
	_audio_player.stream = _chime_stream
	_audio_player.bus = &"SFX"
	add_child(_audio_player)


func get_effective_cost(_player: Node = null) -> int:
	if perk_data == null:
		return cost
	var ec: EconomyConfig = economy_config if economy_config != null else DEFAULT_ECONOMY
	if ec != null:
		return ec.get_perk_price(perk_data)
	return perk_data.cost


func can_purchase(player: Node, points_manager: PointsManager) -> bool:
	if perk_data == null or player == null:
		return false
	var pm: PerkManager = player.get("perk_manager") as PerkManager
	if pm == null or not pm.can_acquire_perk(perk_data):
		return false
	return super.can_purchase(player, points_manager)


func get_prompt_text(player: Node = null) -> String:
	if perk_data == null:
		return ""
	var pm: PerkManager = player.get("perk_manager") as PerkManager if player != null else null
	if pm != null:
		if pm.has_perk(perk_data):
			return "[Owned] %s" % perk_data.display_name
		if pm.is_at_cap():
			return "[Max Perks (%d)] %s" % [pm.get_max_perks(), perk_data.display_name]
	return "[E] Buy %s (%d pts)" % [perk_data.display_name, get_effective_cost(player)]


func _apply_purchase(player: Node) -> void:
	if player == null or perk_data == null:
		return
	var pm: PerkManager = player.get("perk_manager") as PerkManager
	if pm == null:
		return
	if pm.acquire_perk(perk_data) and _audio_player != null:
		_audio_player.play()


static func _create_chime_stream() -> AudioStreamWAV:
	var sample_rate: int = 22050
	var duration: float = 0.42
	var total: int = int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(total * 2)
	for i: int in range(total):
		var t: float = float(i) / float(sample_rate)
		var env: float = exp(-t * 6.5)
		var freq: float = 523.25 if t < 0.14 else (659.25 if t < 0.28 else 783.99)
		var s: float = sin(TAU * freq * t) * 0.35 * env
		var sample_i: int = clampi(int(s * 32767.0), -32768, 32767)
		data[i * 2] = sample_i & 0xFF
		data[i * 2 + 1] = (sample_i >> 8) & 0xFF
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sample_rate
	wav.data = data
	return wav
