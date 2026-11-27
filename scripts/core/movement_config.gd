class_name MovementConfig
extends Resource
## Tunable player movement profiles ("riposte" default and "classic").
## Values for "riposte" are derived from BenDBSS/Riposte-Frontline-Source.

@export_group("Riposte Profile")
@export var riposte_walk_speed: float = 4.75
@export var riposte_sprint_multiplier: float = 1.55
@export var riposte_crouch_multiplier: float = 0.60
@export var riposte_ads_speed_multiplier: float = 0.58
@export var riposte_scoped_ads_speed_multiplier: float = 0.40
@export var riposte_ground_accel: float = 16.5
@export var riposte_sprint_accel: float = 13.5
@export var riposte_ground_decel: float = 16.5
@export var riposte_air_accel: float = 2.2
@export var riposte_gravity: float = 19.0
@export var riposte_jump_velocity: float = 6.3
@export var riposte_standing_height: float = 1.75
@export var riposte_crouch_height: float = 1.2
@export var riposte_standing_eye_height: float = 1.62
@export var riposte_crouch_eye_height: float = 1.1
@export var riposte_slide_eye_height: float = 0.85

@export_group("Slide (Riposte Profile)")
@export var slide_duration: float = 0.75
@export var slide_cooldown: float = 0.26
@export var slide_wall_cooldown: float = 0.12
@export var slide_boost: float = 1.4
@export var slide_floor_speed: float = 6.8
@export var slide_max_speed: float = 10.3
@export var slide_min_speed: float = 3.0
@export var slide_end_speed: float = 3.1
@export var slide_turn_rate: float = 2.0
@export var slide_buffer_time: float = 0.3

@export_group("Classic Profile")
@export var classic_walk_speed: float = 5.0
@export var classic_sprint_multiplier: float = 1.60
@export var classic_crouch_multiplier: float = 0.56
@export var classic_ads_speed_multiplier: float = 0.72
@export var classic_scoped_ads_speed_multiplier: float = 0.72
@export var classic_ground_accel: float = 14.0
@export var classic_sprint_accel: float = 14.0
@export var classic_ground_decel: float = 16.0
@export var classic_air_accel: float = 4.0
@export var classic_gravity: float = 14.0
@export var classic_jump_velocity: float = 5.5
@export var classic_standing_height: float = 1.8
@export var classic_crouch_height: float = 1.0
@export var classic_standing_eye_height: float = 1.6
@export var classic_crouch_eye_height: float = 0.85


func get_profile(profile_name: String) -> Dictionary:
	if profile_name.to_lower() == "classic":
		return {
			"name": "classic",
			"walk_speed": classic_walk_speed,
			"sprint_multiplier": classic_sprint_multiplier,
			"crouch_multiplier": classic_crouch_multiplier,
			"ads_speed_multiplier": classic_ads_speed_multiplier,
			"scoped_ads_speed_multiplier": classic_scoped_ads_speed_multiplier,
			"ground_accel": classic_ground_accel,
			"sprint_accel": classic_sprint_accel,
			"ground_decel": classic_ground_decel,
			"air_accel": classic_air_accel,
			"gravity": classic_gravity,
			"jump_velocity": classic_jump_velocity,
			"standing_height": classic_standing_height,
			"crouch_height": classic_crouch_height,
			"standing_eye_height": classic_standing_eye_height,
			"crouch_eye_height": classic_crouch_eye_height,
			"slide_eye_height": classic_crouch_eye_height,
			"slide_enabled": false,
			"use_exp_damping": false,
		}
	return {
		"name": "riposte",
		"walk_speed": riposte_walk_speed,
		"sprint_multiplier": riposte_sprint_multiplier,
		"crouch_multiplier": riposte_crouch_multiplier,
		"ads_speed_multiplier": riposte_ads_speed_multiplier,
		"scoped_ads_speed_multiplier": riposte_scoped_ads_speed_multiplier,
		"ground_accel": riposte_ground_accel,
		"sprint_accel": riposte_sprint_accel,
		"ground_decel": riposte_ground_decel,
		"air_accel": riposte_air_accel,
		"gravity": riposte_gravity,
		"jump_velocity": riposte_jump_velocity,
		"standing_height": riposte_standing_height,
		"crouch_height": riposte_crouch_height,
		"standing_eye_height": riposte_standing_eye_height,
		"crouch_eye_height": riposte_crouch_eye_height,
		"slide_eye_height": riposte_slide_eye_height,
		"slide_enabled": true,
		"use_exp_damping": true,
	}
