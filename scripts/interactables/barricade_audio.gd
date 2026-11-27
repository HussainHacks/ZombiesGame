class_name BarricadeAudio
extends RefCounted
## Generates placeholder synthesized AudioStreamWAV streams for barricade
## board hit/break/repair and door purchase/open SFX.

const SAMPLE_RATE := 22050


static func create_board_hit_sound() -> AudioStreamWAV:
	return _synth_thud(0.10, 190.0, 95.0, 0.45, 0.7)


static func create_board_break_sound() -> AudioStreamWAV:
	return _synth_thud(0.22, 260.0, 70.0, 0.80, 0.85)


static func create_repair_sound() -> AudioStreamWAV:
	return _synth_thud(0.14, 340.0, 520.0, 0.25, 0.65)


static func create_door_open_sound() -> AudioStreamWAV:
	return _synth_thud(0.32, 160.0, 420.0, 0.30, 0.75)


static func _synth_thud(duration: float, f0: float, f1: float, noise_mix: float, gain: float) -> AudioStreamWAV:
	var count: int = int(duration * SAMPLE_RATE)
	var data := PackedByteArray()
	data.resize(count * 2)

	var rng := RandomNumberGenerator.new()
	rng.seed = int(f0 * 31.0)
	var phase: float = 0.0

	for i: int in range(count):
		var t: float = float(i) / float(count)
		var env: float = pow(1.0 - t, 1.8)
		var freq: float = lerpf(f0, f1, t)
		phase += TAU * freq / float(SAMPLE_RATE)
		var tone: float = sin(phase)
		var noise: float = rng.randf_range(-1.0, 1.0)
		var sample: float = clampf((tone * (1.0 - noise_mix) + noise * noise_mix) * env * gain, -1.0, 1.0)
		var pcm: int = int(sample * 32767.0)
		data[i * 2] = pcm & 0xFF
		data[i * 2 + 1] = (pcm >> 8) & 0xFF

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.data = data
	return wav
