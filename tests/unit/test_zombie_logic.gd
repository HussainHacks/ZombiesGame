extends RefCounted
## Unit tests for EnemyData validity, ZombieAI state transitions,
## attack cooldown logic, and single died signal emission on lethal hits.

const STANDARD_ZOMBIE_PATH := "res://resources/enemies/standard_zombie.tres"
const ZombieScene := preload("res://scenes/enemies/zombie_standard.tscn")


func run_all() -> Dictionary:
	var results := {
		"passed": 0,
		"failed": 0,
		"failures": [] as Array[String],
	}

	_run_test("enemy_data_valid", _test_enemy_data_valid, results)
	_run_test("zombie_state_transitions", _test_zombie_state_transitions, results)
	_run_test("attack_cooldown_logic", _test_attack_cooldown_logic, results)
	_run_test("died_emits_once_on_repeated_lethal_hits", _test_died_emits_once, results)

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


func _test_enemy_data_valid() -> String:
	var res: Resource = load(STANDARD_ZOMBIE_PATH)
	if not (res is EnemyData):
		return "Failed to load EnemyData at %s" % STANDARD_ZOMBIE_PATH
	var ed := res as EnemyData
	if ed.display_name.is_empty():
		return "Empty display_name"
	if ed.base_health <= 0.0 or ed.move_speed <= 0.0 or ed.run_speed < ed.move_speed:
		return "Invalid health/speed bounds"
	if ed.attack_damage <= 0.0 or ed.attack_range <= 0.0 or ed.attack_windup <= 0.0 or ed.attack_cooldown <= 0.0:
		return "Invalid combat timing/damage bounds"
	if ed.detection_range <= ed.attack_range or ed.turn_speed <= 0.0:
		return "Invalid detection_range/turn_speed"
	if ed.points_hit < 0 or ed.points_kill < 0 or ed.points_headshot_kill < 0 or ed.score_value < 0:
		return "Reward values must be non-negative"
	return ""


func _test_zombie_state_transitions() -> String:
	var z := ZombieScene.instantiate() as ZombieAI
	z.transition_to(ZombieAI.State.CHASE)
	if z.current_state != ZombieAI.State.CHASE:
		z.free()
		return "Expected CHASE state"
	z.transition_to(ZombieAI.State.ATTACK_WINDUP)
	if z.current_state != ZombieAI.State.ATTACK_WINDUP:
		z.free()
		return "Expected ATTACK_WINDUP state"
	z.transition_to(ZombieAI.State.ATTACK)
	if z.current_state != ZombieAI.State.ATTACK:
		z.free()
		return "Expected ATTACK state"
	z.transition_to(ZombieAI.State.STAGGER)
	if z.current_state != ZombieAI.State.STAGGER:
		z.free()
		return "Expected STAGGER state"
	z.transition_to(ZombieAI.State.DEAD)
	if z.current_state != ZombieAI.State.DEAD:
		z.free()
		return "Expected DEAD state"
	z.transition_to(ZombieAI.State.CHASE)
	if z.current_state != ZombieAI.State.DEAD:
		z.free()
		return "DEAD state must not transition back to CHASE"
	z.free()
	return ""


func _test_attack_cooldown_logic() -> String:
	var z := ZombieScene.instantiate() as ZombieAI
	z.transition_to(ZombieAI.State.ATTACK)
	if z._attack_cooldown_timer <= 0.0:
		z.free()
		return "Attack swing should set _attack_cooldown_timer > 0"
	z.free()
	return ""


func _test_died_emits_once() -> String:
	var z := ZombieScene.instantiate() as ZombieAI
	var hc := z.get_node("HealthComponent") as HealthComponent
	hc.max_health = z.data.base_health
	hc.current_health = z.data.base_health
	hc.died.connect(z._on_died)

	var died_count := [0]
	z.died.connect(func(_zombie: ZombieAI) -> void: died_count[0] += 1)

	hc.take_damage(80.0)
	hc.take_damage(80.0)
	hc.take_damage(80.0)

	var count: int = died_count[0]
	var state: int = z.current_state
	z.free()

	if count != 1:
		return "Expected died signal once, got %d" % count
	if state != ZombieAI.State.DEAD:
		return "Expected zombie in DEAD state"
	return ""
