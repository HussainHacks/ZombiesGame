class_name EnemyData
extends Resource
## Resource-driven enemy stats and reward configuration.

@export_group("Identity")
@export var display_name: String = "Walker"

@export_group("Health & Locomotion")
@export var base_health: float = 100.0
@export var move_speed: float = 2.4
@export var run_speed: float = 4.2
@export var turn_speed: float = 8.0
@export var detection_range: float = 35.0

@export_group("Combat")
@export var attack_damage: float = 25.0
@export var attack_range: float = 1.85
@export var attack_windup: float = 0.4
@export var attack_cooldown: float = 1.1

@export_group("Rewards")
@export var points_hit: int = 10
@export var points_kill: int = 60
@export var points_headshot_kill: int = 100
@export var score_value: int = 100
