extends SceneTree
## Headless unit & integration test runner for Hood Zombies.
## Run with: godot --headless --script res://tools/run_tests.gd

const UNIT_SUITES := [
	"res://tests/unit/test_player_controller.gd",
	"res://tests/unit/test_input_map.gd",
	"res://tests/unit/test_weapon_data.gd",
	"res://tests/unit/test_combat_and_weapon_logic.gd",
	"res://tests/unit/test_zombie_logic.gd",
	"res://tests/unit/test_round_and_economy.gd",
	"res://tests/unit/test_barricades_doors_zones.gd",
	"res://tests/unit/test_weapons_and_box.gd",
	"res://tests/unit/test_perks_and_upgrades.gd",
	"res://tests/unit/test_save_and_settings.gd",
	"res://tests/unit/test_dialogue_system.gd",
	"res://tests/unit/test_controller_input.gd",
]

const INTEGRATION_SUITES := [
	"res://tests/integration/test_weapon_dummy_integration.gd",
	"res://tests/integration/test_zombie_arena_integration.gd",
	"res://tests/integration/test_round_loop_integration.gd",
	"res://tests/integration/test_compound_barricades_doors.gd",
	"res://tests/integration/test_mystery_box_and_weapons.gd",
	"res://tests/integration/test_perk_and_upgrade_integration.gd",
	"res://tests/integration/test_menus_and_persistence.gd",
	"res://tests/integration/test_dialogue_integration.gd",
	"res://tests/integration/test_phase10_visuals_and_perf.gd",
	"res://tests/integration/test_phase11_release.gd",
	"res://tests/integration/test_controller_integration.gd",
	"res://tests/integration/test_phase13_movement_anims_props.gd",
	"res://tests/integration/test_phase14_collision.gd",
	"res://tests/integration/test_phase15_stuck_zombies.gd",
]


func _initialize() -> void:
	_run_all_suites()


func _run_all_suites() -> void:
	var total_passed: int = 0
	var total_failed: int = 0

	print("=== Hood Zombies Test Runner ===")
	for suite_path: String in UNIT_SUITES:
		print("Running unit suite: ", suite_path)
		var script: GDScript = load(suite_path)
		if script == null or not script.can_instantiate():
			push_error("Failed to load test suite: " + suite_path)
			total_failed += 1
			continue

		var suite: Object = script.new()
		var res: Dictionary = suite.run_all()
		total_passed += res.get("passed", 0)
		total_failed += res.get("failed", 0)

	for suite_path: String in INTEGRATION_SUITES:
		print("Running integration suite: ", suite_path)
		var script: GDScript = load(suite_path)
		if script == null or not script.can_instantiate():
			push_error("Failed to load integration suite: " + suite_path)
			total_failed += 1
			continue

		var suite: Object = script.new()
		var res: Dictionary = await suite.run_all(self)
		total_passed += res.get("passed", 0)
		total_failed += res.get("failed", 0)

	print("=================================")
	print("Total Passed: %d | Total Failed: %d" % [total_passed, total_failed])

	quit(0 if total_failed == 0 else 1)
