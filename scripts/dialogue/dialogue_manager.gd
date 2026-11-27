extends Node
## Event-driven dialogue coordinator (autoload: DialogueManager).
## Listens to GameEvents, enforces global & per-category cooldowns, trigger
## chances, priority interruption, and shuffle-bag anti-repeat.

signal line_started(speaker_name: String, speaker_tint: Color, text: String, duration: float, category: String)
signal line_cleared

const CATEGORIES := [
	"round_start",
	"round_end",
	"kill_streak",
	"took_damage",
	"low_health",
	"reloading",
	"out_of_ammo",
	"bought_weapon",
	"bought_perk",
	"door_opened",
	"box_good",
	"box_bad",
	"player_died",
	"high_round",
	"zombie_spotted",
]

const CATEGORY_COOLDOWNS := {
	"round_start": 16.0,
	"round_end": 28.0,
	"kill_streak": 30.0,
	"took_damage": 28.0,
	"low_health": 32.0,
	"reloading": 30.0,
	"out_of_ammo": 32.0,
	"bought_weapon": 20.0,
	"bought_perk": 24.0,
	"door_opened": 16.0,
	"box_good": 26.0,
	"box_bad": 26.0,
	"player_died": 0.0,
	"high_round": 30.0,
	"zombie_spotted": 30.0,
}

const CATEGORY_CHANCES := {
	"round_start": 0.65,
	"round_end": 0.55,
	"kill_streak": 0.70,
	"took_damage": 0.40,
	"low_health": 0.85,
	"reloading": 0.25,
	"out_of_ammo": 0.80,
	"bought_weapon": 0.55,
	"bought_perk": 0.75,
	"door_opened": 0.70,
	"box_good": 0.85,
	"box_bad": 0.85,
	"player_died": 1.0,
	"high_round": 1.0,
	"zombie_spotted": 0.35,
}

const PRIORITY_NORMAL: int = 1
const PRIORITY_LOW_HEALTH: int = 2
const PRIORITY_DEATH: int = 3
const MAX_SOAK_LPM: float = 6.0

@export var global_cooldown: float = 15.0
@export var kill_streak_window: float = 4.0
@export var kill_streak_threshold: int = 3

var _global_cd_timer: float = 0.0
var _category_cd_timers: Dictionary = {}
var _active_timer: float = 0.0
var _active_priority: int = 0
var _shuffle_bags: Dictionary = {}
var _last_drawn_line: Dictionary = {}
var _recent_kill_times: Array[float] = []
var _run_time: float = 0.0
var _lines_spoken_in_run: int = 0
var _rng := RandomNumberGenerator.new()
var _pools_cache: Dictionary = {}
var _chars_cache: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_connect_signals()


func _connect_signals() -> void:
	var ge: Node = get_node_or_null("/root/GameEvents")
	if ge != null:
		ge.connect("round_started", _on_round_started)
		ge.connect("round_ended", _on_round_ended)
		ge.connect("zombie_killed", _on_zombie_killed)
		ge.connect("player_damaged", _on_player_damaged)
		ge.connect("player_low_health", _on_player_low_health)
		ge.connect("player_died", _on_player_died)
		ge.connect("reloading_started", _on_reloading_started)
		ge.connect("out_of_ammo", _on_out_of_ammo)
		ge.connect("weapon_purchased", _on_weapon_purchased)
		ge.connect("perk_purchased", _on_perk_purchased)
		ge.connect("door_opened", _on_door_opened)
		ge.connect("box_result", _on_box_result)
		ge.connect("box_jammed", _on_box_jammed)
		ge.connect("zombie_spotted", _on_zombie_spotted)

	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null:
		gs.connect("run_started", reset_for_new_run)


func _process(delta: float) -> void:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null and int(gs.get("current_state")) == 2: # PAUSED
		return
	if gs != null and bool(gs.call("is_playing")):
		_run_time += delta
	tick_timers(delta)


func tick_timers(delta: float) -> void:
	if _global_cd_timer > 0.0:
		_global_cd_timer = maxf(_global_cd_timer - delta, 0.0)
	for cat: Variant in _category_cd_timers.keys():
		var t: float = float(_category_cd_timers[cat]) - delta
		if t <= 0.0:
			_category_cd_timers.erase(cat)
		else:
			_category_cd_timers[cat] = t
	if _active_timer > 0.0:
		_active_timer -= delta
		if _active_timer <= 0.0:
			_active_timer = 0.0
			_active_priority = 0
			line_cleared.emit()


func reset_for_new_run() -> void:
	_global_cd_timer = 0.0
	_category_cd_timers.clear()
	_active_timer = 0.0
	_active_priority = 0
	_shuffle_bags.clear()
	_last_drawn_line.clear()
	_recent_kill_times.clear()
	_run_time = 0.0
	_lines_spoken_in_run = 0
	line_cleared.emit()


func advance_game_time(delta: float) -> void:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null and int(gs.get("current_state")) == 2: # PAUSED
		return
	if gs != null and bool(gs.call("is_playing")):
		_run_time += delta
	tick_timers(delta)


func get_run_time_seconds() -> float:
	return _run_time


func get_lines_per_minute() -> float:
	if _run_time <= 0.1:
		return 0.0
	return float(_lines_spoken_in_run) / (_run_time / 60.0)


func get_lines_spoken_count() -> int:
	return _lines_spoken_in_run


static func get_category_priority(category: String) -> int:
	if category == "player_died":
		return PRIORITY_DEATH
	if category == "low_health":
		return PRIORITY_LOW_HEALTH
	return PRIORITY_NORMAL


static func compute_duration(text: String) -> float:
	return clampf(1.6 + float(text.length()) * 0.045, 2.0, 5.5)


func request_line(category: String, force_chance: bool = false) -> bool:
	var gs: Node = get_node_or_null("/root/GameState") if is_inside_tree() else null
	if gs != null:
		var state: int = int(gs.get("current_state"))
		if state == 2 or state == 0: # PAUSED or MENU
			return false
		if state == 3 and category != "player_died": # GAME_OVER
			return false

	var prio: int = get_category_priority(category)
	if _active_timer > 0.0 and prio <= _active_priority:
		return false

	if category != "player_died":
		if _global_cd_timer > 0.0:
			return false
		if float(_category_cd_timers.get(category, 0.0)) > 0.0:
			return false

	var chance: float = clampf(float(CATEGORY_CHANCES.get(category, 0.5)), 0.0, 1.0)
	if not force_chance and _rng.randf() > chance:
		return false

	var char_data: CharacterData = _get_active_character()
	var pool: DialoguePool = _get_pool_for_character(char_data)
	if pool == null:
		return false

	var line: String = draw_next_line(pool, category)
	if line.is_empty():
		return false

	var dur: float = compute_duration(line)
	_active_timer = dur
	_active_priority = prio
	_global_cd_timer = global_cooldown
	_category_cd_timers[category] = float(CATEGORY_COOLDOWNS.get(category, 10.0))
	_lines_spoken_in_run += 1

	var speaker_name: String = char_data.display_name if char_data != null else "Survivor"
	var speaker_tint: Color = char_data.ui_tint if char_data != null else Color.WHITE
	line_started.emit(speaker_name, speaker_tint, line, dur, category)
	return true


func draw_next_line(pool: DialoguePool, category: String) -> String:
	var lines: Array[String] = pool.get_lines(category)
	if lines.is_empty():
		return ""
	if lines.size() == 1:
		return lines[0]

	var bag_key: String = "%s::%s" % [pool.pool_id, category]
	var bag: Array = _shuffle_bags.get(bag_key, [])
	if bag.is_empty():
		bag = range(lines.size())
		_shuffle_array(bag)
		var last_line: String = str(_last_drawn_line.get(bag_key, ""))
		if not last_line.is_empty() and lines[int(bag[bag.size() - 1])] == last_line and bag.size() > 1:
			var tmp: int = int(bag[0])
			bag[0] = bag[bag.size() - 1]
			bag[bag.size() - 1] = tmp
	var idx: int = int(bag.pop_back())
	_shuffle_bags[bag_key] = bag
	var chosen: String = lines[idx]
	_last_drawn_line[bag_key] = chosen
	return chosen


func _shuffle_array(arr: Array) -> void:
	for i: int in range(arr.size() - 1, 0, -1):
		var j: int = _rng.randi_range(0, i)
		var tmp: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


func _get_active_character() -> CharacterData:
	var gs: Node = get_node_or_null("/root/GameState") if is_inside_tree() else null
	var cid: String = str(gs.get("selected_character_id")) if gs != null else "marcus_vance"
	if _chars_cache.has(cid):
		return _chars_cache[cid] as CharacterData
	var path: String = "res://resources/characters/%s.tres" % cid
	if not ResourceLoader.exists(path):
		cid = SaveManager.DEFAULT_CHARACTER_ID
		path = "res://resources/characters/%s.tres" % cid
	if ResourceLoader.exists(path):
		var cd := load(path) as CharacterData
		if cd != null:
			_chars_cache[cid] = cd
			return cd
	return null


func _get_pool_for_character(cd: CharacterData) -> DialoguePool:
	var pid: String = cd.dialogue_pool_id if cd != null and not cd.dialogue_pool_id.is_empty() else "pool_marcus"
	if _pools_cache.has(pid):
		return _pools_cache[pid] as DialoguePool
	var path: String = "res://resources/dialogue/%s.tres" % pid
	if ResourceLoader.exists(path):
		var p := load(path) as DialoguePool
		if p != null:
			_pools_cache[pid] = p
			return p
	return null


func _on_round_started(round_num: int, _total: int) -> void:
	if round_num == 5 or round_num == 10:
		request_line("high_round")
	else:
		request_line("round_start")


func _on_round_ended(_round_num: int) -> void:
	request_line("round_end")


func _on_zombie_killed(_zombie: Node, _is_headshot: bool) -> void:
	_recent_kill_times.append(_run_time)
	while not _recent_kill_times.is_empty() and (_run_time - _recent_kill_times[0]) > kill_streak_window:
		_recent_kill_times.remove_at(0)
	if _recent_kill_times.size() >= kill_streak_threshold:
		_recent_kill_times.clear()
		request_line("kill_streak")


func _on_player_damaged(_amount: float, _cur: float, _max: float) -> void:
	request_line("took_damage")


func _on_player_low_health(_cur: float, _max: float) -> void:
	request_line("low_health")


func _on_player_died() -> void:
	request_line("player_died", true)


func _on_reloading_started(_wd: WeaponData) -> void:
	request_line("reloading")


func _on_out_of_ammo(_wd: WeaponData) -> void:
	request_line("out_of_ammo")


func _on_weapon_purchased(_wd: WeaponData, _is_refill: bool, _cost: int) -> void:
	request_line("bought_weapon")


func _on_perk_purchased(_perk: PerkData) -> void:
	request_line("bought_perk")


func _on_door_opened(_door: Node) -> void:
	request_line("door_opened")


func _on_box_result(_wd: WeaponData, rarity: int) -> void:
	if rarity >= 1:
		request_line("box_good")
	else:
		request_line("box_bad")


func _on_box_jammed(_box: Node) -> void:
	request_line("box_bad")


func _on_zombie_spotted(_zombie: Node) -> void:
	request_line("zombie_spotted")
