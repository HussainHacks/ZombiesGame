extends RefCounted
## Unit tests for HealthComponent, Hitbox headshot math, ammo/reload
## accounting, and Weapon fire-rate cadence.


func run_all() -> Dictionary:
	var results := {
		"passed": 0,
		"failed": 0,
		"failures": [] as Array[String],
	}

	_run_test("health_component_damage_and_death_once", _test_health_component_damage_and_death_once, results)
	_run_test("hitbox_headshot_multiplier_math", _test_hitbox_headshot_multiplier_math, results)
	_run_test("ammo_and_reload_accounting", _test_ammo_and_reload_accounting, results)
	_run_test("fire_rate_cadence", _test_fire_rate_cadence, results)

	return results


func _run_test(test_name: String, fn: Callable, results: Dictionary) -> void:
	var err: String = fn.call()
	if err.is_empty():
		results["passed"] += 1
		print("  [PASS] ", test_name)
	else:
		results["failed"] += 1
		var msg := "%s: %s" % [test_name, err]
		results["failures"].append(msg)
		print("  [FAIL] ", msg)


func _test_health_component_damage_and_death_once() -> String:
	var hc := HealthComponent.new()
	hc.max_health = 100.0
	hc.current_health = 100.0

	var death_count := [0]
	hc.died.connect(func(_src: Node) -> void: death_count[0] += 1)

	var applied_1: float = hc.take_damage(40.0)
	if not is_equal_approx(applied_1, 40.0) or not is_equal_approx(hc.current_health, 60.0):
		hc.free()
		return "Expected 40 applied and 60 remaining, got %s / %s" % [applied_1, hc.current_health]

	var applied_2: float = hc.take_damage(150.0)
	if not is_equal_approx(applied_2, 60.0) or not is_equal_approx(hc.current_health, 0.0) or not hc.is_dead:
		hc.free()
		return "Expected overkill clamped to 60, health=0, is_dead=true"

	var applied_after_death: float = hc.take_damage(25.0)
	if applied_after_death != 0.0 or death_count[0] != 1:
		hc.free()
		return "Expected 0 damage after death and died emitted once, got applied=%s deaths=%d" % [applied_after_death, death_count[0]]

	hc.free()
	return ""


func _test_hitbox_headshot_multiplier_math() -> String:
	var hc := HealthComponent.new()
	hc.max_health = 200.0
	hc.current_health = 200.0

	var body := Hitbox.new()
	body.part_type = Hitbox.BodyPart.BODY
	body.health_component = hc

	var head := Hitbox.new()
	head.part_type = Hitbox.BodyPart.HEAD
	head.health_component = hc

	var body_res: Dictionary = body.apply_hit(25.0, 2.2)
	var head_res: Dictionary = head.apply_hit(25.0, 2.2)

	body.free()
	head.free()

	if not is_equal_approx(body_res.get("applied", 0.0), 25.0) or body_res.get("is_headshot", true):
		hc.free()
		return "Body hitbox should apply 25.0 without headshot flag"
	if not is_equal_approx(head_res.get("applied", 0.0), 55.0) or not head_res.get("is_headshot", false):
		hc.free()
		return "Head hitbox should apply 55.0 with headshot flag"
	if not is_equal_approx(hc.current_health, 120.0):
		hc.free()
		return "Expected 120.0 health remaining, got %s" % hc.current_health

	hc.free()
	return ""


func _test_ammo_and_reload_accounting() -> String:
	# Full reload from plenty of reserve
	var full: Vector2i = Weapon.compute_reload_transfer(4, 12, 50)
	if full != Vector2i(12, 42):
		return "Expected (12, 42) on full reload, got %s" % full

	# Partial reserve reload
	var partial: Vector2i = Weapon.compute_reload_transfer(2, 12, 5)
	if partial != Vector2i(7, 0):
		return "Expected (7, 0) on partial reserve, got %s" % partial

	# Empty reserve never goes negative
	var empty_res: Vector2i = Weapon.compute_reload_transfer(0, 12, 0)
	if empty_res != Vector2i(0, 0):
		return "Expected (0, 0) on empty reserve, got %s" % empty_res

	return ""


func _test_fire_rate_cadence() -> String:
	var wd := WeaponData.new()
	wd.fire_mode = WeaponData.FireMode.AUTO
	wd.fire_rate = 10.0 # 0.1s interval
	wd.magazine_size = 10
	wd.reserve_ammo_max = 30

	var w := Weapon.new()
	w.setup(wd, 10, 30)

	var first_shot: bool = w.try_fire(null, null, [], null)
	var immediate_second: bool = w.try_fire(null, null, [], null)
	w.tick(0.05)
	var mid_cooldown: bool = w.try_fire(null, null, [], null)
	w.tick(0.06)
	var after_cooldown: bool = w.try_fire(null, null, [], null)

	w.free()

	if not first_shot:
		return "First shot should succeed"
	if immediate_second or mid_cooldown:
		return "Shots during fire_rate cooldown must be blocked"
	if not after_cooldown:
		return "Shot after cooldown elapsed should succeed"
	return ""
