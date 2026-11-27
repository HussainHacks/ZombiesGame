class_name CharacterData
extends Resource
## Playable character definition (Phase 8 data-only; dialogue hooks reserved for Phase 9).

@export var id: String = ""
@export var display_name: String = ""
@export var archetype: String = ""
@export_multiline var short_bio: String = ""
@export var ui_tint: Color = Color(0.3, 0.7, 0.95, 1.0)
@export var sleeve_color: Color = Color(0.2, 0.25, 0.35, 1.0)
@export var skin_tone: Color = Color(0.76, 0.57, 0.44, 1.0)
@export var dialogue_pool_id: String = ""
