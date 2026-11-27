extends Node
## JSON save & progression manager (autoload: SaveManager).
## Uses atomic temp-file writes, clamps out-of-range values, fills missing fields
## from defaults, and renames corrupt files to .corrupt without crashing.

const SAVE_VERSION: int = 1
const DEFAULT_SAVE_PATH: String = "user://save_data.json"
const DEFAULT_CHARACTER_ID: String = "marcus_vance"
const KNOWN_CHARACTER_IDS := ["marcus_vance", "simone_brooks", "devon_carter", "tasha_monroe"]

var save_path: String = DEFAULT_SAVE_PATH
var data: Dictionary = {}
var last_load_was_corrupt: bool = false


func _ready() -> void:
	load_save()


static func is_integrated_gpu() -> bool:
	if DisplayServer.get_name() != "headless":
		var adapter: String = RenderingServer.get_video_adapter_name().to_lower()
		return adapter.contains("intel") or adapter.contains("uhd") or adapter.contains("iris") or adapter.contains("integrated")
	return false


static func get_default_quality_preset() -> String:
	return "low" if is_integrated_gpu() else "high"


static func get_default_vsync() -> bool:
	return false if is_integrated_gpu() else true


static func create_default_data() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"settings": {
			"master_volume": 1.0,
			"music_volume": 0.8,
			"sfx_volume": 1.0,
			"ambience_volume": 0.8,
			"mouse_sensitivity": 0.0022,
			"fov": 80.0,
			"fullscreen": false,
			"vsync": get_default_vsync(),
			"fps_cap": 60,
			"subtitles": true,
			"quality_preset": get_default_quality_preset(),
			"controller_sensitivity": 160.0,
			"controller_deadzone": 0.20,
			"controller_invert_y": false,
			"vibration_enabled": true,
			"vibration_intensity": 1.0,
			"movement_profile": "riposte",
			"camera_bob_intensity": 1.0,
			"weapon_bob_intensity": 1.0,
			"camera_shake_intensity": 1.0,
			"landing_dip_intensity": 1.0,
		},
		"progression": {
			"selected_character_id": DEFAULT_CHARACTER_ID,
			"best_round": 0,
			"highest_score": 0,
			"total_kills": 0,
		},
	}


func load_save() -> void:
	last_load_was_corrupt = false
	data = create_default_data()
	if not FileAccess.file_exists(save_path):
		return

	var text: String = FileAccess.get_file_as_string(save_path)
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		_quarantine_corrupt_file()
		return

	var root_dict := parsed as Dictionary
	var defaults := create_default_data()
	data["version"] = SAVE_VERSION

	var raw_settings: Variant = root_dict.get("settings", {})
	var s_dict: Dictionary = raw_settings if raw_settings is Dictionary else {}
	var def_s: Dictionary = defaults["settings"]
	var raw_q: String = str(s_dict.get("quality_preset", def_s["quality_preset"])).to_lower()
	if raw_q != "low" and raw_q != "high":
		raw_q = str(def_s["quality_preset"])
	var raw_mp: String = str(s_dict.get("movement_profile", def_s["movement_profile"])).to_lower()
	if raw_mp != "classic" and raw_mp != "riposte":
		raw_mp = "riposte"
	data["settings"] = {
		"master_volume": clampf(float(s_dict.get("master_volume", def_s["master_volume"])), 0.0, 1.0),
		"music_volume": clampf(float(s_dict.get("music_volume", def_s["music_volume"])), 0.0, 1.0),
		"sfx_volume": clampf(float(s_dict.get("sfx_volume", def_s["sfx_volume"])), 0.0, 1.0),
		"ambience_volume": clampf(float(s_dict.get("ambience_volume", def_s["ambience_volume"])), 0.0, 1.0),
		"mouse_sensitivity": clampf(float(s_dict.get("mouse_sensitivity", def_s["mouse_sensitivity"])), 0.0005, 0.01),
		"fov": clampf(float(s_dict.get("fov", def_s["fov"])), 60.0, 110.0),
		"fullscreen": bool(s_dict.get("fullscreen", def_s["fullscreen"])),
		"vsync": bool(s_dict.get("vsync", def_s["vsync"])),
		"fps_cap": clampi(int(s_dict.get("fps_cap", def_s["fps_cap"])), 0, 240),
		"subtitles": bool(s_dict.get("subtitles", def_s["subtitles"])),
		"quality_preset": raw_q,
		"controller_sensitivity": clampf(float(s_dict.get("controller_sensitivity", def_s["controller_sensitivity"])), 40.0, 400.0),
		"controller_deadzone": clampf(float(s_dict.get("controller_deadzone", def_s["controller_deadzone"])), 0.05, 0.50),
		"controller_invert_y": bool(s_dict.get("controller_invert_y", def_s["controller_invert_y"])),
		"vibration_enabled": bool(s_dict.get("vibration_enabled", def_s["vibration_enabled"])),
		"vibration_intensity": clampf(float(s_dict.get("vibration_intensity", def_s["vibration_intensity"])), 0.0, 1.0),
		"movement_profile": raw_mp,
		"camera_bob_intensity": clampf(float(s_dict.get("camera_bob_intensity", def_s["camera_bob_intensity"])), 0.0, 1.0),
		"weapon_bob_intensity": clampf(float(s_dict.get("weapon_bob_intensity", def_s["weapon_bob_intensity"])), 0.0, 1.0),
		"camera_shake_intensity": clampf(float(s_dict.get("camera_shake_intensity", def_s["camera_shake_intensity"])), 0.0, 1.0),
		"landing_dip_intensity": clampf(float(s_dict.get("landing_dip_intensity", def_s["landing_dip_intensity"])), 0.0, 1.0),
	}

	var raw_prog: Variant = root_dict.get("progression", {})
	var p_dict: Dictionary = raw_prog if raw_prog is Dictionary else {}
	var def_p: Dictionary = defaults["progression"]
	var char_id: String = str(p_dict.get("selected_character_id", def_p["selected_character_id"]))
	if char_id.is_empty() or not KNOWN_CHARACTER_IDS.has(char_id):
		char_id = DEFAULT_CHARACTER_ID
	data["progression"] = {
		"selected_character_id": char_id,
		"best_round": maxi(int(p_dict.get("best_round", def_p["best_round"])), 0),
		"highest_score": maxi(int(p_dict.get("highest_score", def_p["highest_score"])), 0),
		"total_kills": maxi(int(p_dict.get("total_kills", def_p["total_kills"])), 0),
	}


func _quarantine_corrupt_file() -> void:
	last_load_was_corrupt = true
	var abs_src: String = ProjectSettings.globalize_path(save_path)
	var abs_dst: String = abs_src + ".corrupt"
	if FileAccess.file_exists(abs_dst):
		DirAccess.remove_absolute(abs_dst)
	if FileAccess.file_exists(abs_src):
		DirAccess.rename_absolute(abs_src, abs_dst)
	data = create_default_data()
	push_warning("[SaveManager] Corrupt save renamed to %s; defaults restored." % abs_dst)


func save_to_disk() -> bool:
	var tmp_path: String = save_path + ".tmp"
	var abs_tmp: String = ProjectSettings.globalize_path(tmp_path)
	var abs_dst: String = ProjectSettings.globalize_path(save_path)
	DirAccess.make_dir_recursive_absolute(abs_dst.get_base_dir())
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.flush()
	file.close()

	if FileAccess.file_exists(abs_dst):
		DirAccess.remove_absolute(abs_dst)
	var err: Error = DirAccess.rename_absolute(abs_tmp, abs_dst)
	return err == OK


func get_settings() -> Dictionary:
	if not data.has("settings"):
		data = create_default_data()
	return data["settings"]


func get_progression() -> Dictionary:
	if not data.has("progression"):
		data = create_default_data()
	return data["progression"]


func get_selected_character_id() -> String:
	return str(get_progression().get("selected_character_id", DEFAULT_CHARACTER_ID))


func set_selected_character_id(char_id: String) -> void:
	if char_id.is_empty():
		return
	get_progression()["selected_character_id"] = char_id
	save_to_disk()


func record_run_end(round_reached: int, score: int, kills: int) -> bool:
	var prog: Dictionary = get_progression()
	var prev_best_round: int = int(prog.get("best_round", 0))
	var safe_round: int = maxi(round_reached, 0)
	var safe_score: int = maxi(score, 0)
	var safe_kills: int = maxi(kills, 0)
	var is_new_best: bool = safe_round > prev_best_round
	if is_new_best:
		prog["best_round"] = safe_round
	if safe_score > int(prog.get("highest_score", 0)):
		prog["highest_score"] = safe_score
	prog["total_kills"] = int(prog.get("total_kills", 0)) + safe_kills
	save_to_disk()
	return is_new_best


func reset_save() -> void:
	data = create_default_data()
	save_to_disk()
