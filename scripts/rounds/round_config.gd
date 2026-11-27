class_name RoundConfig
extends Resource
## Resource-driven round difficulty curves for Hood Zombies.
## All curves are monotonic and bounded so late rounds remain beatable.

@export_group("Round Counts")
@export var start_round: int = 1
@export var base_zombie_count: int = 6
@export var count_growth_per_round: float = 3.5
@export var max_zombies_per_round: int = 100
@export var max_concurrent_zombies: int = 24

@export_group("Health Scaling")
@export var base_health_multiplier: float = 1.0
@export var early_health_growth_per_round: float = 0.25
@export var late_health_growth_per_round: float = 0.08
@export var health_taper_round: int = 10
@export var max_health_multiplier: float = 8.0

@export_group("Speed Scaling")
@export var base_speed_multiplier: float = 1.0
@export var speed_growth_per_round: float = 0.04
@export var max_speed_multiplier: float = 1.65

@export_group("Timing")
@export var base_spawn_interval: float = 1.8
@export var spawn_interval_decay_per_round: float = 0.08
@export var min_spawn_interval: float = 0.45
@export var intermission_duration: float = 5.0
@export var initial_countdown: float = 1.5


func get_zombie_count(round_num: int) -> int:
	var r: int = maxi(round_num, 1)
	var raw: int = int(round(float(base_zombie_count) + float(r - 1) * count_growth_per_round))
	return clampi(raw, base_zombie_count, max_zombies_per_round)


func get_health_multiplier(round_num: int) -> float:
	var r: int = maxi(round_num, 1)
	var early_steps: int = mini(r - 1, maxi(health_taper_round - 1, 0))
	var late_steps: int = maxi((r - 1) - early_steps, 0)
	var mult: float = (
		base_health_multiplier
		+ float(early_steps) * early_health_growth_per_round
		+ float(late_steps) * late_health_growth_per_round
	)
	return clampf(mult, base_health_multiplier, max_health_multiplier)


func get_speed_multiplier(round_num: int) -> float:
	var r: int = maxi(round_num, 1)
	var mult: float = base_speed_multiplier + float(r - 1) * speed_growth_per_round
	return clampf(mult, base_speed_multiplier, max_speed_multiplier)


func get_spawn_interval(round_num: int) -> float:
	var r: int = maxi(round_num, 1)
	var interval: float = base_spawn_interval - float(r - 1) * spawn_interval_decay_per_round
	return clampf(interval, min_spawn_interval, base_spawn_interval)
