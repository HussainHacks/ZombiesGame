class_name AmbienceManager
extends Node
## Procedural night ambience (wind, crickets, occasional distant zombie moan)
## on the Ambience bus, plus optional dark drone on the Music bus.
## Pauses with GameState.PAUSED and stops on Return to Menu / GAME_OVER / exit.

const MIX_RATE: int = 22050

var _wind_player: AudioStreamPlayer
var _crickets_player: AudioStreamPlayer
var _moan_player: AudioStreamPlayer
var _drone_player: AudioStreamPlayer
var _moan_timer: float = 12.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_moan_timer = _rng.randf_range(10.0, 18.0)

	_wind_player = _make_player(&"Ambience", -10.0, _create_wind_loop())
	_crickets_player = _make_player(&"Ambience", -14.0, _create_crickets_loop())
	_moan_player = _make_player(&"Ambience", -11.0, _create_distant_moan())
	_drone_player = _make_player(&"Music", -18.0, _create_dark_drone())

	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null and gs.has_signal("state_changed"):
		gs.connect("state_changed", _on_game_state_changed)

	start_ambience()


func _exit_tree() -> void:
	stop_all()


func _make_player(bus_name: StringName, vol_db: float, stream: AudioStreamWAV) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus_name
	p.volume_db = vol_db
	p.stream = stream
	add_child(p)
	return p


func start_ambience() -> void:
	if _wind_player != null and not _wind_player.playing:
		_wind_player.stream_paused = false
		_wind_player.play()
	if _crickets_player != null and not _crickets_player.playing:
		_crickets_player.stream_paused = false
		_crickets_player.play()
	if _drone_player != null and not _drone_player.playing:
		_drone_player.stream_paused = false
		_drone_player.play()


func stop_all() -> void:
	for p: AudioStreamPlayer in [_wind_player, _crickets_player, _moan_player, _drone_player]:
		if p != null:
			p.stop()


func set_paused(paused: bool) -> void:
	for p: AudioStreamPlayer in [_wind_player, _crickets_player, _moan_player, _drone_player]:
		if p != null:
			p.stream_paused = paused


func is_any_playing() -> bool:
	for p: AudioStreamPlayer in [_wind_player, _crickets_player, _moan_player, _drone_player]:
		if p != null and p.playing and not p.stream_paused:
			return true
	return false


func _process(delta: float) -> void:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null and not bool(gs.call("is_playing")):
		return
	_moan_timer -= delta
	if _moan_timer <= 0.0:
		_moan_timer = _rng.randf_range(14.0, 26.0)
		if _moan_player != null and not _moan_player.playing:
			_moan_player.pitch_scale = _rng.randf_range(0.88, 1.12)
			_moan_player.play()


func _on_game_state_changed(new_state: int, _old_state: int) -> void:
	if new_state == 2: # PAUSED
		set_paused(true)
	elif new_state == 1: # PLAYING
		set_paused(false)
		start_ambience()
	else: # MENU or GAME_OVER
		stop_all()


func _create_wind_loop() -> AudioStreamWAV:
	var dur: float = 2.4
	var samples: int = int(dur * MIX_RATE)
	var data := PackedByteArray()
	data.resize(samples * 2)
	var lp: float = 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 201
	for i: int in range(samples):
		var t: float = float(i) / float(MIX_RATE)
		var gust: float = 0.55 + 0.45 * sin(TAU * t / dur)
		var white: float = rng.randf_range(-1.0, 1.0)
		lp = lp * 0.96 + white * 0.04
		var sample: int = clampi(int(lp * gust * 18000.0), -32767, 32767)
		data.encode_s16(i * 2, sample)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = samples
	wav.data = data
	return wav


func _create_crickets_loop() -> AudioStreamWAV:
	var dur: float = 2.0
	var samples: int = int(dur * MIX_RATE)
	var data := PackedByteArray()
	data.resize(samples * 2)
	for i: int in range(samples):
		var t: float = float(i) / float(MIX_RATE)
		var pulse: float = 1.0 if fmod(t, 0.5) < 0.14 and fmod(t, 0.035) < 0.018 else 0.0
		var sig: float = sin(TAU * 4250.0 * t) * 0.6 + sin(TAU * 4320.0 * t) * 0.4
		var sample: int = clampi(int(sig * pulse * 4200.0), -32767, 32767)
		data.encode_s16(i * 2, sample)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = samples
	wav.data = data
	return wav


func _create_distant_moan() -> AudioStreamWAV:
	var dur: float = 1.6
	var samples: int = int(dur * MIX_RATE)
	var data := PackedByteArray()
	data.resize(samples * 2)
	for i: int in range(samples):
		var u: float = float(i) / float(samples)
		var env: float = sin(PI * u)
		var freq: float = lerpf(118.0, 82.0, u)
		var t: float = float(i) / float(MIX_RATE)
		var sig: float = sin(TAU * freq * t) * 0.65 + sin(TAU * freq * 1.5 * t) * 0.35
		var sample: int = clampi(int(sig * env * 9000.0), -32767, 32767)
		data.encode_s16(i * 2, sample)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.loop_mode = AudioStreamWAV.LOOP_DISABLED
	wav.data = data
	return wav


func _create_dark_drone() -> AudioStreamWAV:
	var dur: float = 3.0
	var samples: int = int(dur * MIX_RATE)
	var data := PackedByteArray()
	data.resize(samples * 2)
	for i: int in range(samples):
		var t: float = float(i) / float(MIX_RATE)
		var lfo: float = 0.75 + 0.25 * sin(TAU * t / dur)
		var sig: float = sin(TAU * 55.0 * t) * 0.65 + sin(TAU * 82.5 * t) * 0.35
		var sample: int = clampi(int(sig * lfo * 7000.0), -32767, 32767)
		data.encode_s16(i * 2, sample)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = samples
	wav.data = data
	return wav
