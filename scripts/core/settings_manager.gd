extends Node
## Live settings manager (autoload: SettingsManager).
## Reads/writes settings via SaveManager, applies audio buses, sensitivity, FOV,
## fullscreen, VSync, and subtitles live.

signal settings_changed

var master_volume: float = 1.0
var music_volume: float = 0.8
var sfx_volume: float = 1.0
var ambience_volume: float = 0.8
var mouse_sensitivity: float = 0.0022
var fov: float = 80.0
var fullscreen: bool = false
var vsync: bool = false
var fps_cap: int = 60
var subtitles: bool = true
var quality_preset: String = "high"
var controller_sensitivity: float = 160.0
var controller_deadzone: float = 0.20
var controller_invert_y: bool = false
var vibration_enabled: bool = true
var vibration_intensity: float = 1.0


func _ready() -> void:
	load_from_save()
	apply_all()


func load_from_save() -> void:
	var sm: Node = get_node_or_null("/root/SaveManager")
	if sm == null:
		return
	var s: Dictionary = sm.call("get_settings")
	master_volume = clampf(float(s.get("master_volume", 1.0)), 0.0, 1.0)
	music_volume = clampf(float(s.get("music_volume", 0.8)), 0.0, 1.0)
	sfx_volume = clampf(float(s.get("sfx_volume", 1.0)), 0.0, 1.0)
	ambience_volume = clampf(float(s.get("ambience_volume", 0.8)), 0.0, 1.0)
	mouse_sensitivity = clampf(float(s.get("mouse_sensitivity", 0.0022)), 0.0005, 0.01)
	fov = clampf(float(s.get("fov", 80.0)), 60.0, 110.0)
	fullscreen = bool(s.get("fullscreen", false))
	vsync = bool(s.get("vsync", SaveManager.get_default_vsync()))
	fps_cap = clampi(int(s.get("fps_cap", 60)), 0, 240)
	subtitles = bool(s.get("subtitles", true))
	var q: String = str(s.get("quality_preset", "high")).to_lower()
	quality_preset = q if (q == "low" or q == "high") else "high"
	controller_sensitivity = clampf(float(s.get("controller_sensitivity", 160.0)), 40.0, 400.0)
	controller_deadzone = clampf(float(s.get("controller_deadzone", 0.20)), 0.05, 0.50)
	controller_invert_y = bool(s.get("controller_invert_y", false))
	vibration_enabled = bool(s.get("vibration_enabled", true))
	vibration_intensity = clampf(float(s.get("vibration_intensity", 1.0)), 0.0, 1.0)


func _save_to_disk() -> void:
	var sm: Node = get_node_or_null("/root/SaveManager")
	if sm == null:
		return
	var s: Dictionary = sm.call("get_settings")
	s["master_volume"] = master_volume
	s["music_volume"] = music_volume
	s["sfx_volume"] = sfx_volume
	s["ambience_volume"] = ambience_volume
	s["mouse_sensitivity"] = mouse_sensitivity
	s["fov"] = fov
	s["fullscreen"] = fullscreen
	s["vsync"] = vsync
	s["fps_cap"] = fps_cap
	s["subtitles"] = subtitles
	s["quality_preset"] = quality_preset
	s["controller_sensitivity"] = controller_sensitivity
	s["controller_deadzone"] = controller_deadzone
	s["controller_invert_y"] = controller_invert_y
	s["vibration_enabled"] = vibration_enabled
	s["vibration_intensity"] = vibration_intensity
	sm.call("save_to_disk")


func apply_all() -> void:
	_apply_audio_bus(&"Master", master_volume)
	_apply_audio_bus(&"Music", music_volume)
	_apply_audio_bus(&"SFX", sfx_volume)
	_apply_audio_bus(&"Ambience", ambience_volume)
	var is_low: bool = (quality_preset == "low")
	ImpactEffect.set_low_quality(is_low)
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(
			DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		)
		DisplayServer.window_set_vsync_mode(
			DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED
		)
	Engine.max_fps = 0 if vsync else fps_cap
	var idm: Node = get_node_or_null("/root/InputDeviceManager")
	if idm != null:
		idm.set("controller_deadzone", controller_deadzone)
		idm.set("vibration_enabled", vibration_enabled)
		idm.set("vibration_intensity", vibration_intensity)
	var tree: SceneTree = get_tree()
	if tree != null:
		for lnode: Node in tree.get_nodes_in_group("quality_shadow_light"):
			if lnode is Light3D:
				(lnode as Light3D).shadow_enabled = not is_low
		var envs: Array[Node] = tree.root.find_children("*", "WorldEnvironment", true, false)
		for enode: Node in envs:
			var we := enode as WorldEnvironment
			if we != null and we.environment != null:
				we.environment.glow_enabled = not is_low
				we.environment.ssao_enabled = false
				we.environment.fog_density = 0.015 if is_low else 0.022
				we.environment.fog_sky_affect = 0.35 if is_low else 0.75
		for node: Node in tree.get_nodes_in_group("player"):
			if node.has_method("apply_settings"):
				node.call("apply_settings", mouse_sensitivity, fov)
	settings_changed.emit()


func _apply_audio_bus(bus_name: StringName, linear: float) -> void:
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	var muted: bool = linear <= 0.0001
	AudioServer.set_bus_mute(idx, muted)
	AudioServer.set_bus_volume_db(idx, volume_to_db(linear))


static func volume_to_db(linear: float) -> float:
	if linear <= 0.0001:
		return -80.0
	return linear_to_db(clampf(linear, 0.0, 1.0))


func set_master_volume(val: float) -> void:
	master_volume = clampf(val, 0.0, 1.0)
	_save_to_disk()
	apply_all()


func set_music_volume(val: float) -> void:
	music_volume = clampf(val, 0.0, 1.0)
	_save_to_disk()
	apply_all()


func set_sfx_volume(val: float) -> void:
	sfx_volume = clampf(val, 0.0, 1.0)
	_save_to_disk()
	apply_all()


func set_mouse_sensitivity(val: float) -> void:
	mouse_sensitivity = clampf(val, 0.0005, 0.01)
	_save_to_disk()
	apply_all()


func set_fov(val: float) -> void:
	fov = clampf(val, 60.0, 110.0)
	_save_to_disk()
	apply_all()


func set_fullscreen(val: bool) -> void:
	fullscreen = val
	_save_to_disk()
	apply_all()


func set_vsync(val: bool) -> void:
	vsync = val
	_save_to_disk()
	apply_all()


func set_subtitles(val: bool) -> void:
	subtitles = val
	_save_to_disk()
	apply_all()


func set_ambience_volume(val: float) -> void:
	ambience_volume = clampf(val, 0.0, 1.0)
	_save_to_disk()
	apply_all()


func set_quality_preset(val: String) -> void:
	var q: String = val.to_lower()
	quality_preset = q if (q == "low" or q == "high") else "high"
	_save_to_disk()
	apply_all()


func set_fps_cap(val: int) -> void:
	fps_cap = clampi(val, 0, 240)
	_save_to_disk()
	apply_all()


func set_controller_sensitivity(val: float) -> void:
	controller_sensitivity = clampf(val, 40.0, 400.0)
	_save_to_disk()
	apply_all()


func set_controller_deadzone(val: float) -> void:
	controller_deadzone = clampf(val, 0.05, 0.50)
	_save_to_disk()
	apply_all()


func set_controller_invert_y(val: bool) -> void:
	controller_invert_y = val
	_save_to_disk()
	apply_all()


func set_vibration_enabled(val: bool) -> void:
	vibration_enabled = val
	_save_to_disk()
	apply_all()


func set_vibration_intensity(val: float) -> void:
	vibration_intensity = clampf(val, 0.0, 1.0)
	_save_to_disk()
	apply_all()


func reset_to_defaults() -> void:
	var def_s: Dictionary = SaveManager.create_default_data()["settings"]
	master_volume = float(def_s["master_volume"])
	music_volume = float(def_s["music_volume"])
	sfx_volume = float(def_s["sfx_volume"])
	ambience_volume = float(def_s["ambience_volume"])
	mouse_sensitivity = float(def_s["mouse_sensitivity"])
	fov = float(def_s["fov"])
	fullscreen = bool(def_s["fullscreen"])
	vsync = bool(def_s["vsync"])
	fps_cap = int(def_s["fps_cap"])
	subtitles = bool(def_s["subtitles"])
	quality_preset = str(def_s["quality_preset"])
	controller_sensitivity = float(def_s["controller_sensitivity"])
	controller_deadzone = float(def_s["controller_deadzone"])
	controller_invert_y = bool(def_s["controller_invert_y"])
	vibration_enabled = bool(def_s["vibration_enabled"])
	vibration_intensity = float(def_s["vibration_intensity"])
	_save_to_disk()
	apply_all()
