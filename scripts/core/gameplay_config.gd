class_name GameplayConfig
extends Resource
## Gameplay-wide rules and mystery box configuration.

@export_group("Weapons")
@export var max_weapons: int = 3
@export var max_upgrade_tier: int = 1

@export_group("Perks")
@export var max_perks: int = 4

@export_group("Mystery Box")
@export var mystery_box_cost: int = 950
@export var box_spin_duration: float = 3.0
@export var box_offer_duration: float = 8.0
@export var box_cooldown_duration: float = 2.0
@export var box_min_uses_before_relocate: int = 3
@export var box_jam_chance: float = 0.25
@export var box_pity_max_uses: int = 6
@export var box_location_count: int = 3
