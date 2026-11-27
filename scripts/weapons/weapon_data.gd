class_name WeaponData
extends Resource
## Resource-driven weapon definition for Hood Zombies.

enum Category {
	PISTOL,
	RIFLE,
	SHOTGUN,
	SMG,
	SNIPER,
	LMG,
	SPECIAL,
}

enum FireMode {
	SEMI,
	AUTO,
	PUMP,
}

enum Rarity {
	COMMON,
	UNCOMMON,
	RARE,
}

@export_group("Identity")
@export var display_name: String = "Unnamed Weapon"
@export var category: Category = Category.PISTOL
@export var fire_mode: FireMode = FireMode.SEMI
@export var rarity: Rarity = Rarity.COMMON
@export var box_weight: float = 1.0
@export var cost: int = 0
@export var ammo_cost: int = 250

@export_group("Damage & Ballistics")
@export var damage: float = 25.0
@export var headshot_multiplier: float = 2.0
@export var pellet_count: int = 1
@export var pierce_count: int = 0
@export var pierce_damage_falloff: float = 0.75
@export var fire_rate: float = 5.0
@export var pump_cycle_delay: float = 0.0
@export var range: float = 60.0

@export_group("Ammo & Reload")
@export var magazine_size: int = 12
@export var reserve_ammo_max: int = 60
@export var reload_time: float = 1.5

@export_group("Spread & Recoil")
@export var spread_hip: float = 1.5
@export var spread_aim: float = 0.3
@export var spread_per_shot: float = 0.6
@export var spread_max: float = 8.0
@export var spread_recovery_rate: float = 6.0
@export var recoil_pitch: float = 1.5
@export var recoil_yaw_range: float = 0.5

@export_group("Handling")
@export var move_speed_multiplier: float = 1.0
@export var aim_fov_multiplier: float = 0.85
@export var has_scope_overlay: bool = false

@export_group("Presentation")
@export var viewmodel_scene: PackedScene


func get_shot_interval() -> float:
	var base_interval: float = 1.0 / maxf(fire_rate, 0.01)
	if fire_mode == FireMode.PUMP:
		return maxf(base_interval, pump_cycle_delay)
	return base_interval


func calculate_damage(is_headshot: bool) -> float:
	return damage * (headshot_multiplier if is_headshot else 1.0)
