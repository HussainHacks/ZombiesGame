class_name PointsManager
extends Node
## Manages player points balance, atomic spending, and zombie hit/kill rewards.

signal balance_changed(new_balance: int, delta: int, reason: String)

@export var config: EconomyConfig

var balance: int = 500


func _ready() -> void:
	reset_balance()


func reset_balance() -> void:
	balance = config.starting_points if config != null else 500
	balance_changed.emit(balance, 0, "run_start")


func add_points(amount: int, reason: String = "") -> bool:
	if amount <= 0:
		return false
	if not _can_transact():
		return false

	balance += amount
	if is_inside_tree():
		var gs: Node = get_node_or_null("/root/GameState")
		if gs != null:
			gs.call("record_points_earned", amount)
	balance_changed.emit(balance, amount, reason)
	return true


func refund_points(amount: int, reason: String = "refund") -> bool:
	if amount <= 0:
		return false
	balance += amount
	balance_changed.emit(balance, amount, reason)
	return true


func try_spend(cost: Variant, reason: String = "purchase") -> bool:
	if typeof(cost) == TYPE_FLOAT:
		var f: float = cost
		if is_nan(f) or is_inf(f):
			return false
	elif typeof(cost) != TYPE_INT:
		return false

	var amount: int = int(cost)
	if amount <= 0:
		return false
	if not _can_transact():
		return false
	if balance < amount:
		return false

	balance = maxi(balance - amount, 0)
	balance_changed.emit(balance, -amount, reason)
	return true


func reward_zombie_hit(zombie: ZombieAI) -> int:
	if zombie == null or not _can_transact():
		return 0
	var pts: int = zombie.data.points_hit if zombie.data != null else (config.points_per_hit if config != null else 10)
	if add_points(pts, "hit"):
		return pts
	return 0


func reward_zombie_kill(zombie: ZombieAI, is_headshot: bool) -> int:
	if zombie == null or zombie.kill_rewarded or not _can_transact():
		return 0
	zombie.kill_rewarded = true

	var base_kill: int = zombie.data.points_kill if zombie.data != null else (config.points_per_kill if config != null else 60)
	var bonus: int = (config.points_headshot_bonus if config != null else 40) if is_headshot else 0
	var total: int = base_kill + bonus
	var reason: String = "headshot_kill" if is_headshot else "kill"
	if add_points(total, reason):
		return total
	return 0


func _can_transact() -> bool:
	if not is_inside_tree():
		return true
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null and not gs.call("is_playing"):
		return false
	var player: Node = get_tree().get_first_node_in_group("player") if get_tree() else null
	if player != null and "is_dead" in player and player.get("is_dead"):
		return false
	return true
