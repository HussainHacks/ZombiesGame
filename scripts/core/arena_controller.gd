class_name ArenaController
extends Node
## Coordinates the survival loop in an arena: connects RoundManager,
## PointsManager, PlayerController, GameState, and GameOverScreen.

@export var player_path: NodePath
@export var round_manager_path: NodePath
@export var points_manager_path: NodePath
@export var game_over_path: NodePath
@export var auto_start_run: bool = true

var _player: PlayerController
var _round_manager: RoundManager
var _points_manager: PointsManager
var _game_over: GameOverScreen
var _player_spawn_transform: Transform3D


func _ready() -> void:
	_player = get_node_or_null(player_path) as PlayerController
	_round_manager = get_node_or_null(round_manager_path) as RoundManager
	_points_manager = get_node_or_null(points_manager_path) as PointsManager
	_game_over = get_node_or_null(game_over_path) as GameOverScreen

	if _player != null:
		_player_spawn_transform = _player.global_transform

	if _round_manager != null and _points_manager != null:
		_round_manager.zombie_hit.connect(_on_zombie_hit)
		_round_manager.zombie_killed.connect(_on_zombie_killed)

	if _game_over != null:
		_game_over.restart_requested.connect(restart_run)

	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null:
		gs.connect("run_ended", _on_run_ended)

	if auto_start_run:
		call_deferred("start_run")


func start_run() -> void:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null:
		gs.call("start_run")
	if _points_manager != null:
		_points_manager.reset_balance()
	if _round_manager != null:
		_round_manager.start_new_run()


func restart_run() -> void:
	if _round_manager != null:
		_round_manager.stop_and_cleanup()
	for node: Node in get_tree().get_nodes_in_group("barricade"):
		if node is Barricade:
			(node as Barricade).reset_barricade()
	for node: Node in get_tree().get_nodes_in_group("door"):
		if node is Door:
			(node as Door).reset_door()
	var zm: ZoneManager = get_tree().get_first_node_in_group("zone_manager") as ZoneManager
	if zm != null:
		zm.reset_all_zones()
	var mbm: MysteryBoxManager = get_tree().get_first_node_in_group("mystery_box_manager") as MysteryBoxManager
	if mbm != null:
		mbm.reset_manager()
	for node: Node in get_tree().get_nodes_in_group("upgrade_station"):
		if node is UpgradeStation:
			(node as UpgradeStation).reset_station()
	if _player != null:
		_player.reset_for_new_run(_player_spawn_transform)
	start_run()


func _on_zombie_hit(zombie: ZombieAI, _is_headshot: bool, _source: Node) -> void:
	if _points_manager != null:
		_points_manager.reward_zombie_hit(zombie)


func _on_zombie_killed(zombie: ZombieAI, is_headshot: bool) -> void:
	if _points_manager != null:
		_points_manager.reward_zombie_kill(zombie, is_headshot)


func _on_run_ended(_stats: Dictionary) -> void:
	if _round_manager != null:
		_round_manager.stop_and_cleanup()
