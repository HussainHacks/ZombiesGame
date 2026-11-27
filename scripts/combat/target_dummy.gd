class_name TargetDummy
extends Node3D
## Greybox shooting-range target dummy with body/head hitboxes and auto-respawn.

@export var respawn_delay: float = 3.0

@onready var health_component: HealthComponent = $HealthComponent
@onready var body_hitbox: Hitbox = $BodyHitbox
@onready var head_hitbox: Hitbox = $HeadHitbox
@onready var visuals: Node3D = $Visuals
@onready var respawn_timer: Timer = $RespawnTimer


func _ready() -> void:
	health_component.died.connect(_on_died)
	health_component.health_restored.connect(_on_health_restored)
	respawn_timer.wait_time = respawn_delay
	respawn_timer.one_shot = true
	respawn_timer.timeout.connect(_on_respawn_timeout)


func _on_died(_source: Node) -> void:
	_set_active(false)
	respawn_timer.start(respawn_delay)


func _on_respawn_timeout() -> void:
	health_component.restore_full_health()


func _on_health_restored() -> void:
	_set_active(true)


func _set_active(active: bool) -> void:
	if visuals:
		visuals.visible = active
	if body_hitbox:
		body_hitbox.monitorable = active
	if head_hitbox:
		head_hitbox.monitorable = active
