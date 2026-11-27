class_name WeaponAudio
extends RefCounted
## Generates short placeholder synthesized AudioStreamWAV streams for weapon
## fire and reload sounds so each weapon category sounds distinct.

const SAMPLE_RATE := 22050


static func create_fire_sound(category: WeaponData.Category) -> AudioStreamWAV:
	match category:
		WeaponData.Category.PISTOL:
			return _synth_shot(0.11, 420.0, 120.0, 0.55)
		WeaponData.Category.RIFLE:
			return _synth_shot(0.13, 300.0, 90.0, 0.70)
		WeaponData.Category.SHOTGUN:
			return _synth_shot(0.24, 150.0, 45.0, 0.90)
		WeaponData.Category.SMG:
			return _synth_shot(0.08, 520.0, 180.0, 0.50)
		WeaponData.Category.SNIPER:
			return _synth_shot(0.32, 240.0, 40.0, 0.80)
		WeaponData.Category.LMG:
			return _synth_shot(0.16, 210.0, 65.0, 0.78)
		_:
			return _synth_shot(0.12, 340.0, 100.0, 0.60)


static func create_reload_sound(category: WeaponData.Category) -> AudioStreamWAV:
	match category:
		WeaponData.Category.PISTOL:
			return _synth_reload(0.22, 680.0, 920.0)
		WeaponData.Category.RIFLE:
			return _synth_reload(0.28, 480.0, 740.0)
		WeaponData.Category.SHOTGUN:
			return _synth_reload(0.32, 320.0, 520.0)
		WeaponData.Category.SMG:
			return _synth_reload(0.20, 760.0, 980.0)
		WeaponData.Category.SNIPER:
			return _synth_reload(0.38, 380.0, 620.0)
		WeaponData.Category.LMG:
			return _synth_reload(0.45, 260.0, 440.0)
		_:
			return _synth_reload(0.25, 550.0, 800.0)


static func _synth_shot(duration: float, start_freq: float, end_freq: float, noise_mix: float) -> AudioStreamWAV:
	var sample_count: int = int(duration * SAMPLE_RATE)
	var data := PackedByteArray()
	data.resize(sample_count * 2)

	var rng := RandomNumberGenerator.new()
	rng.seed = int(start_freq * 100.0)
	var phase: float = 0.0

	for i: int in range(sample_count):
		var t: float = float(i) / float(sample_count)
		var env: float = pow(1.0 - t, 2.2)
		var freq: float = lerpf(start_freq, end_freq, t)
		phase += TAU * freq / float(SAMPLE_RATE)
		var tone: float = sin(phase)
		var noise: float = rng.randf_range(-1.0, 1.0)
		var sample: float = clampf((tone * (1.0 - noise_mix) + noise * noise_mix) * env * 0.85, -1.0, 1.0)
		var pcm: int = int(sample * 32767.0)
		data[i * 2] = pcm & 0xFF
		data[i * 2 + 1] = (pcm >> 8) & 0xFF

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.data = data
	return wav


static func _synth_reload(duration: float, freq_a: float, freq_b: float) -> AudioStreamWAV:
	var sample_count: int = int(duration * SAMPLE_RATE)
	var data := PackedByteArray()
	data.resize(sample_count * 2)

	var phase: float = 0.0
	for i: int in range(sample_count):
		var t: float = float(i) / float(sample_count)
		var click_a: float = exp(-pow((t - 0.15) * 18.0, 2.0))
		var click_b: float = exp(-pow((t - 0.72) * 18.0, 2.0))
		var freq: float = freq_a if t < 0.5 else freq_b
		phase += TAU * freq / float(SAMPLE_RATE)
		var sample: float = clampf(sin(phase) * (click_a + click_b) * 0.55, -1.0, 1.0)
		var pcm: int = int(sample * 32767.0)
		data[i * 2] = pcm & 0xFF
		data[i * 2 + 1] = (pcm >> 8) & 0xFF

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.data = data
	return wav
