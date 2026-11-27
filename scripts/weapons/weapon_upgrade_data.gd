class_name WeaponUpgradeData
extends Resource
## Configuration for the Forge Bench weapon upgrade station.

@export var upgrade_cost: int = 5000
@export var ammo_cost: int = 2500
@export var damage_multiplier: float = 2.0
@export var headshot_multiplier_bonus: float = 1.15
@export var mag_size_multiplier: float = 1.5
@export var reserve_ammo_multiplier: float = 1.5
@export var fire_rate_multiplier: float = 1.15
@export var name_prefix: String = "Forged "
@export var emissive_tint: Color = Color(0.25, 0.85, 1.0, 1.0)
@export var processing_duration: float = 3.0
@export var ready_timeout: float = 10.0
