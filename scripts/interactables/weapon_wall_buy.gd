class_name WeaponWallBuy
extends Purchasable
## Wall-buy interactable: buys the weapon if unowned, or refills its ammo if owned.

@export var weapon_data: WeaponData
@export var economy_config: EconomyConfig


func _ready() -> void:
	super._ready()
	if weapon_data != null:
		item_name = weapon_data.display_name


func get_effective_cost(player: Node) -> int:
	if weapon_data != null:
		if _player_owns_weapon(player):
			var wm: WeaponManager = player.get_node_or_null("WeaponManager") as WeaponManager
			var tier: int = wm.get_weapon_tier(weapon_data) if wm != null else 0
			return economy_config.get_ammo_price(weapon_data, tier) if economy_config != null else (2500 if tier > 0 else weapon_data.ammo_cost)
		return economy_config.get_weapon_price(weapon_data) if economy_config != null else weapon_data.cost
	return cost


func get_prompt_text(player: Node) -> String:
	var label_name: String = weapon_data.display_name if weapon_data != null else item_name
	if _player_owns_weapon(player):
		return "Press E - %s Ammo [%d]" % [label_name, get_effective_cost(player)]
	return "Press E - %s [%d]" % [label_name, get_effective_cost(player)]


func _player_owns_weapon(player: Node) -> bool:
	if player == null or weapon_data == null:
		return false
	var wm: WeaponManager = player.get_node_or_null("WeaponManager") as WeaponManager
	return wm != null and wm.has_weapon(weapon_data)


func _apply_purchase(player: Node) -> void:
	if player == null or weapon_data == null:
		return
	var was_owned: bool = _player_owns_weapon(player)
	var price: int = get_effective_cost(player)
	var wm: WeaponManager = player.get_node_or_null("WeaponManager") as WeaponManager
	if wm != null:
		wm.give_or_refill_weapon(weapon_data)
	if is_inside_tree():
		var ge: Node = get_node_or_null("/root/GameEvents")
		if ge != null:
			ge.emit_signal("weapon_purchased", weapon_data, was_owned, price)
