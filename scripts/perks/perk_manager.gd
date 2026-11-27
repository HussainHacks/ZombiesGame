class_name PerkManager
extends Node
## Tracks active player perks, enforces GameplayConfig.max_perks and no-duplicate
## rules, applies/removes source-keyed modifiers on PlayerStats, and resets on new run.

const DEFAULT_GAMEPLAY_CONFIG := preload("res://resources/configuration/gameplay_config.tres")

signal perk_added(perk: PerkData)
signal perks_changed(perks: Array[PerkData])

@export var gameplay_config: GameplayConfig
@export var player_stats: PlayerStats
@export var player_health: PlayerHealth

var active_perks: Array[PerkData] = []


func _ready() -> void:
	if player_stats == null and get_parent() != null:
		player_stats = get_parent().get_node_or_null("PlayerStats") as PlayerStats
	if player_health == null and get_parent() != null:
		player_health = get_parent().get_node_or_null("PlayerHealth") as PlayerHealth


func get_max_perks() -> int:
	var cfg: GameplayConfig = gameplay_config if gameplay_config != null else DEFAULT_GAMEPLAY_CONFIG
	return maxi(cfg.max_perks, 1) if cfg != null else 4


func has_perk(perk: PerkData) -> bool:
	if perk == null or perk.perk_id == &"":
		return false
	for p: PerkData in active_perks:
		if p.perk_id == perk.perk_id:
			return true
	return false


func has_perk_id(perk_id: StringName) -> bool:
	for p: PerkData in active_perks:
		if p.perk_id == perk_id:
			return true
	return false


func can_acquire_perk(perk: PerkData) -> bool:
	if perk == null or perk.perk_id == &"":
		return false
	if has_perk(perk):
		return false
	return active_perks.size() < get_max_perks()


func is_at_cap() -> bool:
	return active_perks.size() >= get_max_perks()


func acquire_perk(perk: PerkData) -> bool:
	if not can_acquire_perk(perk):
		return false

	active_perks.append(perk)
	var source_id: StringName = StringName("perk_%s" % perk.perk_id)
	if player_stats != null:
		player_stats.set_source_modifiers(source_id, perk.stat_modifiers)

	if perk.current_health_bonus > 0.0 and player_health != null and player_health.health_component != null:
		var hc: HealthComponent = player_health.health_component
		hc.current_health = minf(hc.current_health + perk.current_health_bonus, hc.max_health)
		player_health.health_changed.emit(hc.current_health, hc.max_health)

	perk_added.emit(perk)
	perks_changed.emit(active_perks)

	if is_inside_tree():
		var ge: Node = get_node_or_null("/root/GameEvents")
		if ge != null:
			ge.emit_signal("perk_purchased", perk)
	return true


func clear_perks() -> void:
	for p: PerkData in active_perks:
		if player_stats != null:
			player_stats.remove_source(StringName("perk_%s" % p.perk_id))
	active_perks.clear()
	perks_changed.emit(active_perks)
