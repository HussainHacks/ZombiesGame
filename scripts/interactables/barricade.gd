class_name Barricade
extends Node3D
## Breakable & repairable window/opening barricade with zombie attack slots,
## per-round repair reward cap, NavigationLink3D gating, and placeholder 3D SFX.

signal boards_changed(intact: int, max_count: int)
signal board_broken(intact: int)
signal board_repaired(intact: int)
signal barricade_opened
signal barricade_closed

@export var max_boards: int = 5
@export var board_break_interval: float = 1.4
@export var repair_duration: float = 0.75
@export var repair_reward: int = 10
@export var max_repair_rewards_per_round: int = 5

@onready var boards_root: Node3D = $BoardsRoot
@onready var blocker_body: StaticBody3D = $BlockerBody
@onready var blocker_collision: CollisionShape3D = $BlockerBody/CollisionShape3D
@onready var nav_link: NavigationLink3D = $NavLink
@onready var attack_slots_root: Node3D = $AttackSlots
@onready var wait_point: Marker3D = $WaitPoint
@onready var outside_point: Marker3D = $OutsidePoint
@onready var inside_point: Marker3D = $InsidePoint
@onready var audio_player: AudioStreamPlayer3D = $AudioStreamPlayer3D

var intact_boards: int = 5
var rewards_granted_this_round: int = 0

var _slot_claims: Dictionary = {} # Marker3D -> Node (zombie)
var _hit_stream: AudioStreamWAV
var _break_stream: AudioStreamWAV
var _repair_stream: AudioStreamWAV


func _ready() -> void:
	add_to_group("barricade")
	intact_boards = max_boards

	if attack_slots_root == null:
		attack_slots_root = get_node_or_null("AttackSlots") as Node3D
	if boards_root == null:
		boards_root = get_node_or_null("BoardsRoot") as Node3D
	if attack_slots_root != null:
		for child: Node in attack_slots_root.get_children():
			if child is Marker3D:
				_slot_claims[child] = null

	_hit_stream = BarricadeAudio.create_board_hit_sound()
	_break_stream = BarricadeAudio.create_board_break_sound()
	_repair_stream = BarricadeAudio.create_repair_sound()

	_sync_state(false)


func _exit_tree() -> void:
	if audio_player:
		audio_player.stop()
		audio_player.stream = null
	_hit_stream = null
	_break_stream = null
	_repair_stream = null


func is_open() -> bool:
	return intact_boards <= 0


func can_repair(player: Node) -> bool:
	if player == null or intact_boards >= max_boards:
		return false
	if "is_dead" in player and player.get("is_dead"):
		return false
	if is_inside_tree():
		var gs: Node = get_node_or_null("/root/GameState")
		if gs != null and not gs.call("is_playing"):
			return false
	return true


func get_prompt_text(player: Node) -> String:
	if intact_boards >= max_boards:
		return "Barricade intact"
	if can_repair(player):
		return "Hold E - Repair (%d/%d)" % [intact_boards, max_boards]
	return "Barricade (%d/%d)" % [intact_boards, max_boards]


func damage_board(_attacker: Node = null) -> bool:
	if intact_boards <= 0:
		return false
	intact_boards = maxi(intact_boards - 1, 0)
	_sync_state(true)
	board_broken.emit(intact_boards)
	_play_sfx(_break_stream if intact_boards == 0 else _hit_stream)
	if intact_boards == 0:
		barricade_opened.emit()
	return true


func repair_one_board(points_manager: PointsManager = null) -> bool:
	if intact_boards >= max_boards:
		return false
	var was_open: bool = intact_boards == 0
	intact_boards = mini(intact_boards + 1, max_boards)
	_sync_state(true)
	board_repaired.emit(intact_boards)
	_play_sfx(_repair_stream)
	if was_open and intact_boards > 0:
		barricade_closed.emit()

	if points_manager != null and rewards_granted_this_round < max_repair_rewards_per_round:
		if points_manager.add_points(repair_reward, "barricade_repair"):
			rewards_granted_this_round += 1

	if is_inside_tree():
		var ge: Node = get_node_or_null("/root/GameEvents")
		if ge != null:
			ge.emit_signal("barricade_repaired", self, intact_boards)

	return true


func reset_round_repair_cap() -> void:
	rewards_granted_this_round = 0


func reset_barricade() -> void:
	intact_boards = max_boards
	rewards_granted_this_round = 0
	release_all_slots()
	_sync_state(true)


func claim_slot(zombie: Node) -> Marker3D:
	if zombie == null:
		return null
	# Idempotent: return existing slot if already claimed by this zombie
	for slot: Marker3D in _slot_claims.keys():
		if _slot_claims[slot] == zombie:
			return slot
	for slot: Marker3D in _slot_claims.keys():
		var holder: Variant = _slot_claims[slot]
		if holder == null or not is_instance_valid(holder):
			_slot_claims[slot] = zombie
			return slot
	return null


func release_slot(zombie: Node) -> void:
	if zombie == null:
		return
	for slot: Marker3D in _slot_claims.keys():
		if _slot_claims[slot] == zombie:
			_slot_claims[slot] = null


func release_all_slots() -> void:
	for slot: Marker3D in _slot_claims.keys():
		_slot_claims[slot] = null


func get_claimed_slot_count() -> int:
	var count: int = 0
	for holder: Variant in _slot_claims.values():
		if holder != null and is_instance_valid(holder):
			count += 1
	return count


func get_waiting_position(offset_index: int = 0) -> Vector3:
	var base: Vector3 = wait_point.global_position if wait_point != null else global_position + global_transform.basis.z * 2.2
	var angle: float = float(offset_index % 6) * (TAU / 6.0)
	return base + Vector3(cos(angle) * 0.9, 0.0, sin(angle) * 0.9)


func get_inside_entry_point() -> Vector3:
	if inside_point != null:
		return inside_point.global_position
	return global_position - global_transform.basis.z * 1.4


func get_outside_approach_point() -> Vector3:
	if outside_point != null:
		return outside_point.global_position
	return global_position + global_transform.basis.z * 1.4


func _sync_state(emit_change: bool) -> void:
	if boards_root != null:
		var idx: int = 0
		for child: Node in boards_root.get_children():
			if child is Node3D:
				(child as Node3D).visible = idx < intact_boards
				idx += 1

	var blocked: bool = intact_boards > 0
	if blocker_collision != null:
		blocker_collision.set_deferred("disabled", not blocked)
	if blocker_body != null:
		blocker_body.collision_layer = 1 if blocked else 0
	if nav_link != null:
		nav_link.enabled = not blocked

	if emit_change:
		boards_changed.emit(intact_boards, max_boards)


func _play_sfx(stream: AudioStreamWAV) -> void:
	if audio_player != null and stream != null and is_inside_tree():
		audio_player.stream = stream
		audio_player.play()
