extends RefCounted
## Unit tests for Phase 8: SaveManager (round-trip, missing, corrupt -> .corrupt,
## clamping, atomic write), SettingsManager.volume_to_db, and single-count run stats.

const SaveMgrScript := preload("res://scripts/core/save_manager.gd")
const SettingsMgrScript := preload("res://scripts/core/settings_manager.gd")


func run_all() -> Dictionary:
	var results := {
		"passed": 0,
		"failed": 0,
		"failures": [] as Array[String],
	}

	_run_test("save_manager_round_trip_and_atomic_write", _test_round_trip_and_atomic, results)
	_run_test("save_manager_missing_file_returns_defaults", _test_missing_file, results)
	_run_test("save_manager_corrupt_file_renamed_and_defaults_restored", _test_corrupt_file, results)
	_run_test("save_manager_clamps_out_of_range_values", _test_clamping, results)
	_run_test("volume_to_db_true_mute_at_zero", _test_volume_to_db, results)
	_run_test("stats_updated_once_per_run_end", _test_stats_once_per_run, results)
	_run_test("unknown_character_id_falls_back_to_default", _test_unknown_character_fallback, results)

	return results


func _run_test(test_name: String, fn: Callable, results: Dictionary) -> void:
	var err: String = fn.call()
	if err.is_empty():
		results["passed"] += 1
		print("  [PASS] ", test_name)
	else:
		results["failed"] += 1
		results["failures"].append("%s: %s" % [test_name, err])
		print("  [FAIL] ", test_name, ": ", err)


func _cleanup_test_files(base_path: String) -> void:
	for suffix: String in ["", ".tmp", ".corrupt"]:
		var abs_p: String = ProjectSettings.globalize_path(base_path + suffix)
		if FileAccess.file_exists(abs_p):
			DirAccess.remove_absolute(abs_p)


func _test_round_trip_and_atomic() -> String:
	var path := "res://.tmp_phase8_rt.json"
	_cleanup_test_files(path)

	var sm: Node = SaveMgrScript.new()
	sm.save_path = path
	sm.load_save()
	sm.get_settings()["fov"] = 96.0
	sm.set_selected_character_id("devon_carter")
	var tmp_exists_after: bool = FileAccess.file_exists(ProjectSettings.globalize_path(path + ".tmp"))

	var sm2: Node = SaveMgrScript.new()
	sm2.save_path = path
	sm2.load_save()
	var loaded_fov: float = float(sm2.get_settings()["fov"])
	var loaded_char: String = sm2.get_selected_character_id()

	sm.free()
	sm2.free()
	_cleanup_test_files(path)

	if tmp_exists_after:
		return "Atomic write left .tmp file behind"
	if not is_equal_approx(loaded_fov, 96.0) or loaded_char != "devon_carter":
		return "Round-trip mismatch (fov=%s, char=%s)" % [loaded_fov, loaded_char]
	return ""


func _test_missing_file() -> String:
	var path := "res://.tmp_phase8_missing.json"
	_cleanup_test_files(path)

	var sm: Node = SaveMgrScript.new()
	sm.save_path = path
	sm.load_save()
	var ver: int = int(sm.data.get("version", 0))
	var fov: float = float(sm.get_settings().get("fov", 0.0))
	sm.free()
	if ver != 1 or not is_equal_approx(fov, 80.0):
		return "Missing file did not load defaults"
	return ""


func _test_corrupt_file() -> String:
	var path := "res://.tmp_phase8_corrupt.json"
	_cleanup_test_files(path)

	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("{not valid json!!!")
	f.close()

	var sm: Node = SaveMgrScript.new()
	sm.save_path = path
	sm.load_save()
	var was_corrupt: bool = sm.last_load_was_corrupt
	var corrupt_exists: bool = FileAccess.file_exists(ProjectSettings.globalize_path(path + ".corrupt"))
	var fov: float = float(sm.get_settings()["fov"])
	sm.free()
	_cleanup_test_files(path)

	if not was_corrupt or not corrupt_exists or not is_equal_approx(fov, 80.0):
		return "Corrupt file handling failed (was_corrupt=%s, corrupt_exists=%s, fov=%s)" % [was_corrupt, corrupt_exists, fov]
	return ""


func _test_clamping() -> String:
	var path := "res://.tmp_phase8_clamp.json"
	_cleanup_test_files(path)

	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({
		"version": 1,
		"settings": {"fov": 250.0, "master_volume": -5.0, "mouse_sensitivity": 1.0},
		"progression": {"best_round": -3, "highest_score": -100, "total_kills": -7},
	}))
	f.close()

	var sm: Node = SaveMgrScript.new()
	sm.save_path = path
	sm.load_save()
	var s: Dictionary = sm.get_settings()
	var p: Dictionary = sm.get_progression()
	sm.free()
	_cleanup_test_files(path)

	if not is_equal_approx(float(s["fov"]), 110.0) or not is_equal_approx(float(s["master_volume"]), 0.0):
		return "Settings not clamped (fov=%s, vol=%s)" % [s["fov"], s["master_volume"]]
	if int(p["best_round"]) != 0 or int(p["highest_score"]) != 0 or int(p["total_kills"]) != 0:
		return "Progression negative values not clamped to 0"
	return ""


func _test_unknown_character_fallback() -> String:
	var path := "res://.tmp_phase11_unknown_char.json"
	_cleanup_test_files(path)

	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({
		"version": 1,
		"progression": {"selected_character_id": "devon_reid", "best_round": 3},
	}))
	f.close()

	var sm: Node = SaveMgrScript.new()
	sm.save_path = path
	sm.load_save()
	var p: Dictionary = sm.get_progression()
	sm.free()
	_cleanup_test_files(path)

	if str(p.get("selected_character_id", "")) != SaveMgrScript.DEFAULT_CHARACTER_ID:
		return "Expected fallback to %s, got %s" % [SaveMgrScript.DEFAULT_CHARACTER_ID, p.get("selected_character_id", "")]
	return ""


func _test_volume_to_db() -> String:
	var db_zero: float = SettingsMgrScript.volume_to_db(0.0)
	var db_one: float = SettingsMgrScript.volume_to_db(1.0)
	if not is_equal_approx(db_zero, -80.0) or not is_equal_approx(db_one, 0.0):
		return "Expected -80.0 at 0.0 and 0.0 at 1.0, got %s / %s" % [db_zero, db_one]
	return ""


func _test_stats_once_per_run() -> String:
	var path := "res://.tmp_phase8_once.json"
	_cleanup_test_files(path)

	var sm: Node = Engine.get_main_loop().root.get_node_or_null("SaveManager") if Engine.get_main_loop() else null
	var gs: Node = Engine.get_main_loop().root.get_node_or_null("GameState") if Engine.get_main_loop() else null
	if sm == null or gs == null:
		return "Autoloads SaveManager/GameState missing"

	var orig_path: String = sm.save_path
	sm.save_path = path
	sm.reset_save()

	gs.call("start_run")
	gs.set("round_reached", 5)
	gs.call("record_kill", true)
	gs.call("record_kill", false)
	gs.call("record_points_earned", 350)
	gs.call("end_run")
	gs.call("end_run")
	gs.call("abandon_run_to_menu")

	var prog: Dictionary = sm.call("get_progression")
	var best_r: int = int(prog["best_round"])
	var kills: int = int(prog["total_kills"])
	var score: int = int(prog["highest_score"])

	sm.save_path = orig_path
	sm.load_save()
	_cleanup_test_files(path)

	if best_r != 5 or kills != 2 or score != 350:
		return "Expected best_round=5, total_kills=2, highest_score=350 (no double-count), got %s/%s/%s" % [best_r, kills, score]
	return ""
