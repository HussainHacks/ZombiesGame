extends Node
## Global game state and run statistics autoload.
## Manages MENU / PLAYING / PAUSED / GAME_OVER transitions and run lifecycle.

enum State {
	MENU,
	PLAYING,
	PAUSED,
	GAME_OVER,
}

signal state_changed(new_state: State, old_state: State)
signal run_started
signal run_ended(stats: Dictionary)
signal stats_updated

var current_state: State = State.MENU
var selected_character_id: String = "marcus_vance"
var round_reached: int = 1
var kills: int = 0
var headshots: int = 0
var points_earned: int = 0
var time_survived: float = 0.0
var last_run_is_new_best: bool = false
var _run_stats_committed: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var sm: Node = get_node_or_null("/root/SaveManager")
	if sm != null:
		selected_character_id = str(sm.call("get_selected_character_id"))


func _process(delta: float) -> void:
	if current_state == State.PLAYING:
		time_survived += delta


func start_run() -> void:
	round_reached = 1
	kills = 0
	headshots = 0
	points_earned = 0
	time_survived = 0.0
	last_run_is_new_best = false
	_run_stats_committed = false
	if is_inside_tree() and get_tree() != null:
		get_tree().paused = false
	_set_state(State.PLAYING)
	stats_updated.emit()
	run_started.emit()


func end_run() -> void:
	if current_state == State.GAME_OVER:
		return
	if is_inside_tree() and get_tree() != null:
		get_tree().paused = false
	_commit_run_progression()
	_set_state(State.GAME_OVER)
	run_ended.emit(get_run_stats())


func abandon_run_to_menu() -> void:
	if is_inside_tree() and get_tree() != null:
		get_tree().paused = false
	if current_state == State.PLAYING or current_state == State.PAUSED:
		_commit_run_progression()
	_set_state(State.MENU)


func set_selected_character_id(char_id: String) -> void:
	if char_id.is_empty():
		return
	selected_character_id = char_id
	var sm: Node = get_node_or_null("/root/SaveManager")
	if sm != null:
		sm.call("set_selected_character_id", char_id)


func _get_save_manager() -> Node:
	if is_inside_tree() and get_tree() != null:
		return get_tree().root.get_node_or_null("SaveManager")
	var ml: MainLoop = Engine.get_main_loop()
	if ml is SceneTree:
		return (ml as SceneTree).root.get_node_or_null("SaveManager")
	return null


func _commit_run_progression() -> void:
	if _run_stats_committed:
		return
	_run_stats_committed = true
	var sm: Node = _get_save_manager()
	if sm != null:
		last_run_is_new_best = bool(sm.call("record_run_end", round_reached, points_earned, kills))


func set_paused(paused: bool) -> void:
	if current_state == State.GAME_OVER or current_state == State.MENU:
		return
	var target: State = State.PAUSED if paused else State.PLAYING
	if target == current_state:
		return
	if is_inside_tree() and get_tree() != null:
		get_tree().paused = paused
	_set_state(target)


func is_playing() -> bool:
	return current_state == State.PLAYING


func record_kill(is_headshot: bool) -> void:
	if current_state != State.PLAYING:
		return
	kills += 1
	if is_headshot:
		headshots += 1
	stats_updated.emit()


func record_points_earned(amount: int) -> void:
	if current_state != State.PLAYING or amount <= 0:
		return
	points_earned += amount
	stats_updated.emit()


func set_round_reached(round_num: int) -> void:
	round_reached = maxi(round_reached, round_num)
	stats_updated.emit()


func get_run_stats() -> Dictionary:
	return {
		"round_reached": round_reached,
		"kills": kills,
		"headshots": headshots,
		"points_earned": points_earned,
		"time_survived": time_survived,
	}


func _set_state(new_state: State) -> void:
	var old_state: State = current_state
	if old_state == new_state:
		return
	current_state = new_state
	state_changed.emit(new_state, old_state)
