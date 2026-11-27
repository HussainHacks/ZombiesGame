class_name PlayerHealth
extends Node
## Manages player health, delayed regeneration, hurt/death audio, and death state.

signal health_changed(current_health: float, max_health: float)
signal damage_taken(amount: float, attacker_world_pos: Vector3, has_attacker_pos: bool)
signal player_died

@export var health_component: HealthComponent
@export var player_stats: PlayerStats
@export var regen_delay: float = 4.0
@export var regen_rate: float = 15.0

var _time_since_damage: float = 0.0
var _hurt_player: AudioStreamPlayer
var _death_player: AudioStreamPlayer
var _hurt_stream: AudioStreamWAV
var _death_stream: AudioStreamWAV


func _ready() -> void:
	if health_component == null:
		health_component = get_parent().get_node_or_null("HealthComponent") as HealthComponent
	if player_stats == null:
		player_stats = get_parent().get_node_or_null("PlayerStats") as PlayerStats
	if player_stats != null:
		player_stats.stats_changed.connect(_on_stats_changed)
		_on_stats_changed()
	if health_component != null:
		health_component.died.connect(_on_died)

	_hurt_stream = PlayerAudio.create_hurt_sound()
	_death_stream = PlayerAudio.create_death_sound()

	_hurt_player = AudioStreamPlayer.new()
	_hurt_player.stream = _hurt_stream
	_hurt_player.bus = &"SFX"
	add_child(_hurt_player)

	_death_player = AudioStreamPlayer.new()
	_death_player.stream = _death_stream
	_death_player.bus = &"SFX"
	add_child(_death_player)


func _exit_tree() -> void:
	if _hurt_player:
		_hurt_player.stop()
		_hurt_player.stream = null
	if _death_player:
		_death_player.stop()
		_death_player.stream = null
	_hurt_stream = null
	_death_stream = null


func _process(delta: float) -> void:
	if health_component == null or health_component.is_dead:
		return
	if health_component.current_health >= health_component.max_health:
		return

	var delay_mult: float = player_stats.get_stat(&"regen_delay_multiplier") if player_stats != null else 1.0
	var rate_mult: float = player_stats.get_stat(&"regen_rate_multiplier") if player_stats != null else 1.0
	_time_since_damage += delta
	if _time_since_damage >= regen_delay * delay_mult:
		var heal_amount: float = minf(regen_rate * rate_mult * delta, health_component.max_health - health_component.current_health)
		if heal_amount > 0.0:
			health_component.current_health += heal_amount
			health_changed.emit(health_component.current_health, health_component.max_health)


func _on_stats_changed() -> void:
	if health_component == null or player_stats == null:
		return
	var new_max: float = player_stats.get_stat(&"max_health")
	if not is_equal_approx(health_component.max_health, new_max):
		health_component.max_health = new_max
		if health_component.current_health > new_max:
			health_component.current_health = new_max
		health_changed.emit(health_component.current_health, health_component.max_health)


func take_damage(amount: float, source: Node = null) -> float:
	if health_component == null or health_component.is_dead or amount <= 0.0:
		return 0.0

	var applied: float = health_component.take_damage(amount, false, source)
	if applied <= 0.0:
		return 0.0

	_time_since_damage = 0.0
	health_changed.emit(health_component.current_health, health_component.max_health)

	var has_pos: bool = source is Node3D
	var attacker_pos: Vector3 = (source as Node3D).global_position if has_pos else Vector3.ZERO
	damage_taken.emit(applied, attacker_pos, has_pos)

	if not health_component.is_dead and _hurt_player:
		_hurt_player.play()

	if is_inside_tree():
		var ge: Node = get_node_or_null("/root/GameEvents")
		if ge != null:
			ge.emit_signal("player_damaged", applied, health_component.current_health, health_component.max_health)
			if not health_component.is_dead and (health_component.current_health / maxf(health_component.max_health, 1.0)) < 0.35:
				ge.emit_signal("player_low_health", health_component.current_health, health_component.max_health)

	return applied


func _on_died(_source: Node) -> void:
	if _death_player:
		_death_player.play()
	var parent_player := get_parent() as PlayerController
	if parent_player != null:
		parent_player.set_dead(true)
	player_died.emit()
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null:
		gs.call("end_run")
	if is_inside_tree():
		var ge: Node = get_node_or_null("/root/GameEvents")
		if ge != null:
			ge.emit_signal("player_died")
