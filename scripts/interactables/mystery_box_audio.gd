class_name MysteryBoxAudio
extends RefCounted
## Placeholder synthesized AudioStreamWAV streams for the Mystery Box:
## spin tick, rarity result chime, and electrical short-circuit jam surge.

const SAMPLE_RATE := 22050


static func create_spin_tick() -> AudioStreamWAV:
	return _synth(0.05, 620.0, 880.0, 0.15, 0.45)


static func create_result_chime() -> AudioStreamWAV:
	return _synth(0.35, 520.0, 1040.0, 0.05, 0.65)


static func create_jam_surge() -> AudioStreamWAV:
	return _synth(0.45, 220.0, 65.0, 0.75, 0.8)


static func _synth(duration: float, f0: float, f1: float, noise_mix: float, gain: float) -> AudioStreamWAV:
	var count: int = int(duration * SAMPLE_RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(f0 * 17.0)
	var phase: float = 0.0
	for i: int in range(count):
		var t: float = float(i) / float(count)
		var env: float = pow(1.0 - t, 1.5)
		phase += TAU * lerpf(f0, f1, t) / float(SAMPLE_RATE)
		var sample: float = clampf((sin(phase) * (1.0 - noise_mix) + rng.randf_range(-1.0, 1.0) * noise_mix) * env * gain, -1.0, 1.0)
		var pcm: int = int(sample * 32767.0)
		data[i * 2] = pcm & 0xFF
		data[i * 2 + 1] = (pcm >> 8) & 0xFF
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.data = data
	return wav
