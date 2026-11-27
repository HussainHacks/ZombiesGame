class_name EconomyConfig
extends Resource
## Centralized prices and point reward configuration.

@export_group("Starting & Rewards")
@export var starting_points: int = 500
@export var points_per_hit: int = 10
@export var points_per_kill: int = 60
@export var points_headshot_bonus: int = 40

@export_group("Wall-Buys & Refills")
@export var rifle_wall_buy_cost: int = 1200
@export var rifle_ammo_cost: int = 600
@export var ammo_crate_cost: int = 450
@export var weapon_prices: Dictionary = {
	"Hammer-44": 800,
	"Breacher-12": 950,
	"Viper-9": 1000,
	"Strider-556": 1200,
	"Sweeper-12": 1500,
	"Longshot-308": 2000,
	"Bastion-762": 2500,
}
@export var weapon_ammo_prices: Dictionary = {
	"Street-9": 150,
	"Hammer-44": 400,
	"Breacher-12": 450,
	"Viper-9": 500,
	"Strider-556": 600,
	"Sweeper-12": 700,
	"Longshot-308": 850,
	"Bastion-762": 1000,
}


@export_group("Perks & Upgrades")
@export var perk_prices: Dictionary = {
	"iron_heart": 2500,
	"quick_hands": 3000,
	"street_runner": 2000,
	"heavy_caliber": 3500,
	"deadeye_tonic": 2250,
	"vital_surge": 1750,
}
@export var upgrade_base_cost: int = 5000
@export var upgrade_ammo_cost: int = 2500


func get_perk_price(perk: PerkData) -> int:
	if perk == null:
		return 0
	var key: String = String(perk.perk_id)
	if perk_prices.has(key):
		return int(perk_prices[key])
	return perk.cost


func get_weapon_price(wd: WeaponData) -> int:
	if wd == null:
		return 0
	if weapon_prices.has(wd.display_name):
		return int(weapon_prices[wd.display_name])
	return wd.cost


func get_ammo_price(wd: WeaponData, upgrade_tier: int = 0) -> int:
	if wd == null:
		return 0
	if upgrade_tier > 0:
		return upgrade_ammo_cost
	if weapon_ammo_prices.has(wd.display_name):
		return int(weapon_ammo_prices[wd.display_name])
	return wd.ammo_cost
