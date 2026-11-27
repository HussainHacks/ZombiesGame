extends SceneTree
## Verifies real user:// save write + reload + corrupt recovery across launches (Step 0.2).

func _initialize() -> void:
	_check()


func _check() -> void:
	await process_frame
	await process_frame
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var sm: Node = root.get_node_or_null("SaveManager")
	var setm: Node = root.get_node_or_null("SettingsManager")
	var abs_path: String = ProjectSettings.globalize_path("user://save_data.json")

	if args.has("--write"):
		if FileAccess.file_exists(abs_path):
			DirAccess.remove_absolute(abs_path)
		sm.call("load_save")
		setm.call("load_from_save")
		setm.call("set_master_volume", 0.42)
		setm.call("set_subtitles", false)
		sm.call("record_run_end", 7, 4200, 55)
		var prog: Dictionary = sm.call("get_progression")
		var sets: Dictionary = sm.call("get_settings")
		var ok: bool = FileAccess.file_exists("user://save_data.json")
		print("USER_SAVE_WRITE | ok=%s | best_round=%s | master_volume=%.2f | subtitles=%s | path=%s" % [
			ok, prog.get("best_round", -1), float(sets.get("master_volume", -1.0)), sets.get("subtitles", true), abs_path
		])
		quit(0 if ok else 1)
	elif args.has("--read"):
		var prog: Dictionary = sm.call("get_progression")
		var sets: Dictionary = sm.call("get_settings")
		var ok: bool = int(prog.get("best_round", 0)) == 7 and absf(float(sets.get("master_volume", 0.0)) - 0.42) < 0.01 and not bool(sets.get("subtitles", true))
		print("USER_SAVE_READ | ok=%s | best_round=%s | high_score=%s | total_kills=%s | master_volume=%.2f | subtitles=%s | path=%s" % [
			ok, prog.get("best_round", -1), prog.get("highest_score", -1), prog.get("total_kills", -1),
			float(sets.get("master_volume", -1.0)), sets.get("subtitles", true), abs_path
		])
		quit(0 if ok else 1)
	elif args.has("--corrupt"):
		var f := FileAccess.open("user://save_data.json", FileAccess.WRITE)
		f.store_string("corrupt{not_json")
		f.close()
		sm.call("load_save")
		setm.call("load_from_save")
		var prog: Dictionary = sm.call("get_progression")
		var sets: Dictionary = sm.call("get_settings")
		var has_corrupt: bool = FileAccess.file_exists("user://save_data.json.corrupt")
		var ok: bool = int(prog.get("best_round", -1)) == 0 and absf(float(sets.get("master_volume", 0.0)) - 1.0) < 0.01 and has_corrupt
		print("USER_SAVE_CORRUPT | ok=%s | best_round=%s | master_volume=%.2f | corrupt_backup=%s | path=%s" % [
			ok, prog.get("best_round", -1), float(sets.get("master_volume", -1.0)), has_corrupt, abs_path
		])
		if has_corrupt:
			DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save_data.json.corrupt"))
		if FileAccess.file_exists(abs_path):
			DirAccess.remove_absolute(abs_path)
		sm.call("load_save")
		quit(0 if ok else 1)
	else:
		print("Usage: -- --write | --read | --corrupt")
		quit(1)
