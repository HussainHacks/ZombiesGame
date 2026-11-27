class_name PlayerStats
extends Node
## Source-keyed player stat modifier system.
## Stacking order: additive modifiers are summed onto the stat base first,
## then multiplicative modifiers are applied, and the result is clamped to
## per-stat hard caps: clamp((base + sum_add) * prod_mult, min_cap, max_cap).

signal stats_changed

enum ModifierOp {
	ADD,
	MULTIPLY,
}

const STAT_CONFIG := {
	&"max_health": {"base": 100.0, "min": 25.0, "max": 300.0},
	&"reload_speed": {"base": 1.0, "min": 0.4, "max": 2.5},
	&"move_speed": {"base": 1.0, "min": 0.5, "max": 1.6},
	&"damage_multiplier": {"base": 1.0, "min": 0.25, "max": 4.0},
	&"headshot_bonus": {"base": 1.0, "min": 0.5, "max": 2.5},
	&"weapon_handling": {"base": 1.0, "min": 0.5, "max": 2.5},
	&"regen_delay_multiplier": {"base": 1.0, "min": 0.25, "max": 2.0},
	&"regen_rate_multiplier": {"base": 1.0, "min": 0.5, "max": 4.0},
}

# { source_id: Array[{ "stat": StringName, "op": ModifierOp, "value": float }] }
var _sources: Dictionary = {}
var _cache: Dictionary = {}


func _ready() -> void:
	_recompute()


func add_modifier(source_id: StringName, stat: StringName, op: ModifierOp, value: float) -> void:
	if source_id == &"" or not STAT_CONFIG.has(stat):
		push_warning("[PlayerStats] Invalid modifier: source=%s stat=%s" % [source_id, stat])
		return
	if not _sources.has(source_id):
		_sources[source_id] = []
	var list: Array = _sources[source_id]
	list.append({
		"stat": stat,
		"op": op,
		"value": value,
	})
	_recompute()


func set_source_modifiers(source_id: StringName, modifiers: Array) -> void:
	if source_id == &"":
		return
	var valid: Array = []
	for entry: Variant in modifiers:
		if entry is Dictionary:
			var d := entry as Dictionary
			var stat: StringName = StringName(str(d.get("stat", "")))
			if STAT_CONFIG.has(stat):
				valid.append({
					"stat": stat,
					"op": int(d.get("op", ModifierOp.ADD)),
					"value": float(d.get("value", 0.0)),
				})
	if valid.is_empty():
		_sources.erase(source_id)
	else:
		_sources[source_id] = valid
	_recompute()


func remove_source(source_id: StringName) -> void:
	if not _sources.has(source_id):
		return
	_sources.erase(source_id)
	_recompute()


func clear_all() -> void:
	if _sources.is_empty():
		return
	_sources.clear()
	_recompute()


func has_source(source_id: StringName) -> bool:
	return _sources.has(source_id)


func get_stat(stat: StringName) -> float:
	if _cache.is_empty():
		_recompute_silent()
	if _cache.has(stat):
		return float(_cache[stat])
	if STAT_CONFIG.has(stat):
		return float(STAT_CONFIG[stat]["base"])
	return 1.0


func _recompute() -> void:
	_recompute_silent()
	stats_changed.emit()


func _recompute_silent() -> void:
	for stat_name: StringName in STAT_CONFIG.keys():
		var cfg: Dictionary = STAT_CONFIG[stat_name]
		var add_sum: float = 0.0
		var mult_prod: float = 1.0

		for source_id: Variant in _sources.keys():
			var list: Array = _sources[source_id]
			for mod: Dictionary in list:
				if mod["stat"] == stat_name:
					if mod["op"] == ModifierOp.ADD:
						add_sum += float(mod["value"])
					else:
						mult_prod *= float(mod["value"])

		var raw: float = (float(cfg["base"]) + add_sum) * mult_prod
		_cache[stat_name] = clampf(raw, float(cfg["min"]), float(cfg["max"]))
