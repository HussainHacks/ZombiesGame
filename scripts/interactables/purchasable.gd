class_name Purchasable
extends StaticBody3D
## Base class for world interactables that cost points (wall-buys, ammo crates).
## Includes per-frame and cooldown debouncing so one press = one purchase.

@export var item_name: String = "Item"
@export var cost: int = 500
@export var debounce_seconds: float = 0.25

var _last_purchase_usec: int = -1000000
var _last_purchase_frame: int = -1


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("purchasable")
	collision_layer = 17
	collision_mask = 0


func get_effective_cost(_player: Node) -> int:
	return cost


func get_prompt_text(player: Node) -> String:
	return "Press E - %s [%d]" % [item_name, get_effective_cost(player)]


func can_purchase(player: Node, points_manager: PointsManager) -> bool:
	if player == null or points_manager == null:
		return false
	if "is_dead" in player and player.get("is_dead"):
		return false
	if is_inside_tree():
		var gs: Node = get_node_or_null("/root/GameState")
		if gs != null and not gs.call("is_playing"):
			return false

	var now_frame: int = Engine.get_process_frames()
	if now_frame == _last_purchase_frame:
		return false
	var now_usec: int = Time.get_ticks_usec()
	if (now_usec - _last_purchase_usec) < int(debounce_seconds * 1000000.0):
		return false

	return points_manager.balance >= get_effective_cost(player)


func purchase(player: Node, points_manager: PointsManager) -> bool:
	if not can_purchase(player, points_manager):
		return false
	var price: int = get_effective_cost(player)
	if not points_manager.try_spend(price, item_name):
		return false

	_last_purchase_frame = Engine.get_process_frames()
	_last_purchase_usec = Time.get_ticks_usec()
	_apply_purchase(player)
	return true


func interact(player: Node) -> void:
	var pm: PointsManager = get_tree().get_first_node_in_group("points_manager") as PointsManager
	if pm != null:
		purchase(player, pm)


func _apply_purchase(_player: Node) -> void:
	pass
