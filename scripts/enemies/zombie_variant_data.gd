class_name ZombieVariantData
extends Resource
## Data-driven visual variant definition for ZombieVisual.
## Allows random variant spawning from data without hard-coding per scene.

@export var variant_id: String = "male"
@export var weight: float = 1.0
@export var mesh: Mesh = null
@export var idle_quirk_anim: StringName = &"idle_male_pat"
@export var attack_anim: StringName = &"attack_male_shove"
@export var death_anim: StringName = &"death_male_collapse"
