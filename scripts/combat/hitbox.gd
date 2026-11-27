class_name Hitbox
extends Area3D
## Hitbox collider on the projectile_hitbox layer (layer 4 / bit 8).
## Routes incoming hits to a HealthComponent and applies headshot multipliers.

enum BodyPart {
	BODY,
	HEAD,
}

@export var part_type: BodyPart = BodyPart.BODY
@export var health_component: HealthComponent


func _ready() -> void:
	collision_layer = 8
	collision_mask = 0
	monitoring = false
	monitorable = true


func apply_hit(base_damage: float, headshot_multiplier: float, source: Node = null) -> Dictionary:
	var is_headshot: bool = part_type == BodyPart.HEAD
	if health_component == null or health_component.is_dead:
		return {
			"applied": 0.0,
			"is_headshot": is_headshot,
			"killed": false,
		}

	var raw_damage: float = base_damage * (headshot_multiplier if is_headshot else 1.0)
	var applied: float = health_component.take_damage(raw_damage, is_headshot, source)
	return {
		"applied": applied,
		"is_headshot": is_headshot,
		"killed": health_component.is_dead,
	}
