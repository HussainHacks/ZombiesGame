class_name HealthComponent
extends Node
## Reusable health and damage component. Tracks current health, prevents
## damage after death, and emits damaged/died signals.

signal damaged(amount: float, is_headshot: bool, source: Node, remaining_health: float)
signal died(source: Node)
signal health_restored

@export var max_health: float = 100.0

var current_health: float = 100.0
var is_dead: bool = false


func _ready() -> void:
	current_health = max_health


func take_damage(amount: float, is_headshot: bool = false, source: Node = null) -> float:
	if is_dead or amount <= 0.0:
		return 0.0

	var applied_damage: float = minf(amount, current_health)
	current_health = maxf(current_health - amount, 0.0)
	damaged.emit(applied_damage, is_headshot, source, current_health)

	if current_health <= 0.0:
		is_dead = true
		died.emit(source)

	return applied_damage


func restore_full_health() -> void:
	current_health = max_health
	is_dead = false
	health_restored.emit()
