class_name PlayerAudio
extends RefCounted
## Generates placeholder synthesized AudioStreamWAV streams for player hurt and death SFX.

const SAMPLE_RATE := 22050


static func create_hurt_sound() -> AudioStreamWAV:
	return _synth_tone(0.18, 220.0, 110.0, 0.35, 0.7)


static func create_death_sound() -> AudioStreamWAV:
	return _synth_tone(0.55, 180.0, 55.0, 0.25, 0.85)


static func _synth_tone(duration: float, start_freq: float, end_freq: float, noise_mix: float, gain: float) -> AudioStreamWAV:
	var sample_count: int = int(duration * SAMPLE_RATE)
	var data := PackedByteArray()
	data.resize(sample_count * 2)

	var rng := RandomNumberGenerator.new()
	rng.seed = int(start_freq * 50.0)
	var phase: float = 0.0

	for i: int in range(sample_count):
		var t: float = float(i) / float(sample_count)
		var env: float = pow(1.0 - t, 1.6)
		var freq: float = lerpf(start_freq, end_freq, t)
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
