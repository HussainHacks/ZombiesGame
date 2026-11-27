class_name ZombieVisual
extends Node3D
## Thin AnimationTree state-machine driver for the rigged zombie model.
## Maps ZombieAI.State and horizontal speed onto AnimationNodeStateMachine
## states (idle, walk, attack, hit_react, death) with speed-matched walk rate.

const STRIDE_METERS_PER_CYCLE: float = 1.75

@onready var body_pivot: Node3D = $ZombieRig
@onready var anim_player: AnimationPlayer = $ZombieRig/AnimationPlayer

var anim_tree: AnimationTree = null
var playback: AnimationNodeStateMachinePlayback = null
var _last_state: int = -1


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var s: float = rng.randf_range(0.95, 1.06)
	scale = Vector3(s, rng.randf_range(0.96, 1.05), s)
	_setup_animation_tree()


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

	# Walk uses a BlendTree with TimeScale so walk speed matches actual velocity
	var walk_bt := AnimationNodeBlendTree.new()
	var walk_anim := AnimationNodeAnimation.new()
	walk_anim.animation = &"walk"
	var walk_ts := AnimationNodeTimeScale.new()
	walk_bt.add_node(&"anim", walk_anim, Vector2(100, 100))
	walk_bt.add_node(&"TimeScale", walk_ts, Vector2(300, 100))
	walk_bt.connect_node(&"TimeScale", 0, &"anim")
	walk_bt.connect_node(&"output", 0, &"TimeScale")
	sm.add_node(&"walk", walk_bt, Vector2(320, 120))

	var n_attack := AnimationNodeAnimation.new()
	n_attack.animation = &"attack"
	sm.add_node(&"attack", n_attack, Vector2(520, 60))

	var n_hit := AnimationNodeAnimation.new()
	n_hit.animation = &"hit_react"
	sm.add_node(&"hit_react", n_hit, Vector2(520, 200))

	var n_death := AnimationNodeAnimation.new()
	n_death.animation = &"death"
	sm.add_node(&"death", n_death, Vector2(720, 120))

	# Start -> idle
	var t_start := AnimationNodeStateMachineTransition.new()
	t_start.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
	sm.add_transition(&"Start", &"idle", t_start)

	# Bidirectional transitions between locomotion and combat states
	for pair: Array in [
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

	var t_hit_end := AnimationNodeStateMachineTransition.new()
	t_hit_end.xfade_time = 0.12
	t_hit_end.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_AT_END
	t_hit_end.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
	sm.add_transition(&"hit_react", &"idle", t_hit_end)

	anim_tree.tree_root = sm
	anim_tree.active = true
	playback = anim_tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
	if playback != null:
		playback.start(&"idle")


func reset_visual() -> void:
	_last_state = -1
	if body_pivot != null:
		body_pivot.position = Vector3.ZERO
		body_pivot.rotation = Vector3.ZERO
	if playback != null:
		playback.start(&"idle")


func update_visual(_delta: float, state: int, horizontal_speed: float) -> void:
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
		if playback.get_current_node() != &"idle":
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
