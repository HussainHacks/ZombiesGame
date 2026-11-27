class_name FlickerLight
extends OmniLight3D
## Subtle horror-style flickering light for interior fixtures.

@export var base_energy: float = 1.45
@export var flicker_amplitude: float = 0.45
@export var flicker_speed: float = 9.0

var _time: float = 0.0


func _process(delta: float) -> void:
	_time += delta * flicker_speed
	var wave: float = sin(_time * 1.7) * 0.5 + sin(_time * 4.3) * 0.35 + sin(_time * 11.1) * 0.15
	light_energy = maxf(base_energy + wave * flicker_amplitude, 0.25)
