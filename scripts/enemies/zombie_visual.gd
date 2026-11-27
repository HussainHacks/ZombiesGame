class_name ZombieVisual
extends Node3D
## Thin AnimationTree state-machine driver for male and female comedy zombie
## variants sharing one humanoid Skeleton3D, one skinned MeshInstance3D, and
## one shared material. Picks a variant from data in `variants`.

const STRIDE_METERS_PER_CYCLE: float = 1.75
const ZombieVariantDataScript := preload("res://scripts/enemies/zombie_variant_data.gd")
const DEFAULT_MALE := preload("res://resources/enemies/variant_male.tres")
const DEFAULT_FEMALE := preload("res://resources/enemies/variant_female.tres")

@export var variants: Array[Resource] = []

@onready var body_pivot: Node3D = $ZombieRig
@onready var anim_player: AnimationPlayer = $ZombieRig/AnimationPlayer
@onready var mesh_inst: MeshInstance3D = $ZombieRig/Skeleton3D/ZombieMesh

var anim_tree: AnimationTree = null
var playback: AnimationNodeStateMachinePlayback = null
var active_variant: Resource = null

var _rng := RandomNumberGenerator.new()
var _last_state: int = -1
var _idle_quirk_timer: float = 4.0
var _n_idle_quirk: AnimationNodeAnimation = null
var _n_attack: AnimationNodeAnimation = null
var _n_death: AnimationNodeAnimation = null


func _ready() -> void:
	_rng.randomize()
	var s: float = _rng.randf_range(0.95, 1.06)
	scale = Vector3(s, _rng.randf_range(0.96, 1.05), s)
	_setup_animation_tree()
	_pick_random_variant()
	_reset_idle_quirk_timer()


func _get_variant_pool() -> Array[Resource]:
	if not variants.is_empty():
		return variants
	return [DEFAULT_MALE, DEFAULT_FEMALE]


func _pick_random_variant() -> void:
	var pool: Array[Resource] = _get_variant_pool()
	var total_w: float = 0.0
	for v: Resource in pool:
		if v != null:
			total_w += maxf(float(v.get("weight")), 0.0)
	if total_w <= 0.0:
		_apply_variant(pool[0])
		return
	var roll: float = _rng.randf_range(0.0, total_w)
	var acc: float = 0.0
	for v: Resource in pool:
		if v == null:
			continue
		acc += maxf(float(v.get("weight")), 0.0)
		if roll <= acc:
			_apply_variant(v)
			return
	_apply_variant(pool[0])


func set_variant(variant_id: String) -> bool:
	for v: Resource in _get_variant_pool():
		if v != null and str(v.get("variant_id")) == variant_id:
			_apply_variant(v)
			return true
	return false


func get_variant_id() -> String:
	return str(active_variant.get("variant_id")) if active_variant != null else ""


func _apply_variant(v: Resource) -> void:
	active_variant = v
	if v == null:
		return
	var v_mesh := v.get("mesh") as Mesh
	if mesh_inst != null and v_mesh != null:
		mesh_inst.mesh = v_mesh
	if _n_idle_quirk != null:
		_n_idle_quirk.animation = v.get("idle_quirk_anim")
	if _n_attack != null:
		_n_attack.animation = v.get("attack_anim")
	if _n_death != null:
		_n_death.animation = v.get("death_anim")


func _reset_idle_quirk_timer() -> void:
	_idle_quirk_timer = _rng.randf_range(3.5, 7.5)


func _setup_animation_tree() -> void:
	if body_pivot == null or anim_player == null:
		return
	anim_tree = AnimationTree.new()
	anim_tree.name = "AnimationTree"
	body_pivot.add_child(anim_tree)
	anim_tree.anim_player = anim_tree.get_path_to(anim_player)

	var sm := AnimationNodeStateMachine.new()

	var n_idle := AnimationNodeAnimation.new()
	n_idle.animation = &"idle"
	sm.add_node(&"idle", n_idle, Vector2(120, 120))

	_n_idle_quirk = AnimationNodeAnimation.new()
	_n_idle_quirk.animation = &"idle_male_pat"
	sm.add_node(&"idle_quirk", _n_idle_quirk, Vector2(120, 260))

	var walk_bt := AnimationNodeBlendTree.new()
	var walk_anim := AnimationNodeAnimation.new()
	walk_anim.animation = &"walk"
	var walk_ts := AnimationNodeTimeScale.new()
	walk_bt.add_node(&"anim", walk_anim, Vector2(100, 100))
	walk_bt.add_node(&"TimeScale", walk_ts, Vector2(300, 100))
	walk_bt.connect_node(&"TimeScale", 0, &"anim")
	walk_bt.connect_node(&"output", 0, &"TimeScale")
	sm.add_node(&"walk", walk_bt, Vector2(320, 120))

	_n_attack = AnimationNodeAnimation.new()
	_n_attack.animation = &"attack_male_shove"
	sm.add_node(&"attack", _n_attack, Vector2(520, 40))

	var n_hit := AnimationNodeAnimation.new()
	n_hit.animation = &"hit_react"
	sm.add_node(&"hit_react", n_hit, Vector2(520, 200))

	_n_death = AnimationNodeAnimation.new()
	_n_death.animation = &"death_male_collapse"
	sm.add_node(&"death", _n_death, Vector2(720, 120))

	var t_start := AnimationNodeStateMachineTransition.new()
	t_start.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
	sm.add_transition(&"Start", &"idle", t_start)

	for pair: Array in [
		[&"idle", &"idle_quirk", 0.15],
		[&"idle_quirk", &"walk", 0.12],
		[&"idle_quirk", &"attack", 0.08],
		[&"idle_quirk", &"hit_react", 0.05],
		[&"idle_quirk", &"death", 0.08],
		[&"idle", &"walk", 0.15],
		[&"walk", &"idle", 0.15],
		[&"idle", &"attack", 0.08],
		[&"walk", &"attack", 0.08],
		[&"attack", &"idle", 0.12],
		[&"attack", &"walk", 0.12],
		[&"idle", &"hit_react", 0.05],
		[&"walk", &"hit_react", 0.05],
		[&"attack", &"hit_react", 0.05],
		[&"idle", &"death", 0.08],
		[&"walk", &"death", 0.08],
		[&"attack", &"death", 0.08],
		[&"hit_react", &"death", 0.08],
	]:
		var tr := AnimationNodeStateMachineTransition.new()
		tr.xfade_time = float(pair[2])
		sm.add_transition(pair[0], pair[1], tr)

	for end_pair: Array in [[&"idle_quirk", &"idle"], [&"hit_react", &"idle"]]:
		var tr_end := AnimationNodeStateMachineTransition.new()
		tr_end.xfade_time = 0.15
		tr_end.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_AT_END
		tr_end.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
		sm.add_transition(end_pair[0], end_pair[1], tr_end)

	anim_tree.tree_root = sm
	anim_tree.active = true
	playback = anim_tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
	if playback != null:
		playback.start(&"idle")


func reset_visual() -> void:
	_last_state = -1
	_reset_idle_quirk_timer()
	_pick_random_variant()
	if body_pivot != null:
		body_pivot.position = Vector3.ZERO
		body_pivot.rotation = Vector3.ZERO
	if playback != null:
		playback.start(&"idle")


func update_visual(delta: float, state: int, horizontal_speed: float) -> void:
	if anim_tree == null or playback == null:
		return

	# State enum values match ZombieAI.State:
	# 0=IDLE, 1=CHASE, 2=ATTACK_WINDUP, 3=ATTACK, 4=STAGGER, 5=DEAD
	if state == 5:
		if _last_state != 5:
			playback.travel(&"death")
			_last_state = 5
		return

	if state == 4:
		if _last_state != 4:
			playback.travel(&"hit_react")
			_last_state = 4
		return

	if state == 2 or state == 3:
		if _last_state != 2 and _last_state != 3:
			playback.travel(&"attack")
		_last_state = state
		return

	if horizontal_speed > 0.15:
		var walk_rate: float = maxf(horizontal_speed / STRIDE_METERS_PER_CYCLE, 0.25)
		anim_tree.set("parameters/walk/TimeScale/scale", walk_rate)
		if playback.get_current_node() != &"walk":
			playback.travel(&"walk")
	else:
		var cur_node: StringName = playback.get_current_node()
		if state == 0:
			# Random character idle business (belly pat / check nails), never during combat
			if cur_node != &"idle_quirk":
				_idle_quirk_timer -= delta
				if _idle_quirk_timer <= 0.0:
					_reset_idle_quirk_timer()
					playback.travel(&"idle_quirk")
				elif cur_node != &"idle":
					playback.travel(&"idle")
		elif cur_node != &"idle":
			playback.travel(&"idle")
	_last_state = state


func get_current_anim_state() -> StringName:
	if playback == null:
		return &""
	return playback.get_current_node()


func get_walk_time_scale() -> float:
	if anim_tree == null:
		return 1.0
	return float(anim_tree.get("parameters/walk/TimeScale/scale"))
