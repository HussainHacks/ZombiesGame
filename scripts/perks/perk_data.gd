class_name PerkData
extends Resource
## Resource-driven perk definition. Modifiers are applied through PlayerStats
## using perk_id as the source key so perks never hardcode gameplay checks.

@export var perk_id: StringName = &""
@export var display_name: String = ""
@export var short_label: String = ""
@export var description: String = ""
@export var cost: int = 2000
@export var accent_color: Color = Color(0.25, 0.75, 0.95, 1.0)
@export var current_health_bonus: float = 0.0
@export var stat_modifiers: Array[Dictionary] = []
@export var icon_texture: Texture2D
