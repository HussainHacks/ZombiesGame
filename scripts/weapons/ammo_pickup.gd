class_name AmmoPickup
extends Purchasable
## Purchasable ammo crate refill in the arena.

@export var economy_config: EconomyConfig


func _ready() -> void:
	super._ready()
	add_to_group("ammo_pickup")
	item_name = "Ammo Refill"


func get_effective_cost(_player: Node) -> int:
	return economy_config.ammo_crate_cost if economy_config != null else cost


func _apply_purchase(player: Node) -> void:
	if player == null:
		return
	var wm: WeaponManager = player.get_node_or_null("WeaponManager") as WeaponManager
	if wm != null:
		wm.refill_all_reserve_ammo()
