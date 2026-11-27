extends RefCounted
## Integration test: spawns Player + TargetDummy in a live SceneTree, fires
## at body & head hitboxes, verifies damage/headshot/death, and verifies
## weapon switching preserves per-slot ammo.

const PlayerScene := preload("res://scenes/player/player.tscn")
const DummyScene := preload("res://scenes/enemies/target_dummy.tscn")


func run_all(tree: SceneTree) -> Dictionary:
	var results := {
		"passed": 0,
		"failed": 0,
		"failures": [] as Array[String],
	}

	var world := Node3D.new()
	world.name = "IntegrationTestWorld"
	tree.root.add_child(world)

	var player := PlayerScene.instantiate() as PlayerController
	var dummy := DummyScene.instantiate() as TargetDummy
	player.position = Vector3(0.0, 0.0, 4.0)
	dummy.position = Vector3(0.0, 0.0, 0.0)
	world.add_child(player)
	world.add_child(dummy)

	# Let physics space register Area3D hitboxes
	await tree.physics_frame
	await tree.physics_frame

	var err: String = await _run_combat_and_switch_checks(tree, player, dummy)
	if err.is_empty():
		results["passed"] += 1
		print("  [PASS] player_fires_at_dummy_and_switches_weapons")
	else:
		results["failed"] += 1
		results["failures"].append("player_fires_at_dummy_and_switches_weapons: " + err)
		print("  [FAIL] player_fires_at_dummy_and_switches_weapons: ", err)

	world.queue_free()
	await tree.process_frame
	await tree.process_frame
	return results


func _run_combat_and_switch_checks(tree: SceneTree, player: PlayerController, dummy: TargetDummy) -> String:
	var wm: WeaponManager = player.weapon_manager
	if wm == null or wm.active_weapon == null:
		return "Player missing WeaponManager/ActiveWeapon"

	var space_state: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	var exclude: Array[RID] = [player.get_rid()]

	# 1. Aim at BodyHitbox (y = 0.9) from camera (y = 1.6)
	player.camera.look_at(Vector3(0.0, 0.9, 0.0), Vector3.UP)
	var pistol_spread_backup: float = wm.active_weapon.data.spread_hip
	wm.active_weapon.data.spread_hip = 0.0

	var body_fired: bool = wm.active_weapon.try_fire(player.camera, space_state, exclude, player)
	if not body_fired:
		wm.active_weapon.data.spread_hip = pistol_spread_backup
		return "Failed to fire pistol at body"

	var body_damage: float = dummy.health_component.max_health - dummy.health_component.current_health
	if not is_equal_approx(body_damage, 28.0):
		wm.active_weapon.data.spread_hip = pistol_spread_backup
		return "Expected 28.0 body damage, got %s" % body_damage

	# Advance past pistol cooldown
	wm.active_weapon.tick(0.5)

	# 2. Aim at HeadHitbox (y = 1.65)
	player.camera.look_at(Vector3(0.0, 1.65, 0.0), Vector3.UP)
	var health_before_head: float = dummy.health_component.current_health
	var head_fired: bool = wm.active_weapon.try_fire(player.camera, space_state, exclude, player)
	if not head_fired:
		wm.active_weapon.data.spread_hip = pistol_spread_backup
		return "Failed to fire pistol at head"

	var head_damage: float = health_before_head - dummy.health_component.current_health
	if head_damage <= body_damage:
		wm.active_weapon.data.spread_hip = pistol_spread_backup
		return "Expected headshot damage (%s) > body damage (%s)" % [head_damage, body_damage]

	# 3. Second headshot should kill dummy (28 + 61.6 + 61.6 > 100)
	wm.active_weapon.tick(0.5)
	wm.active_weapon.try_fire(player.camera, space_state, exclude, player)
	wm.active_weapon.data.spread_hip = pistol_spread_backup

	if not dummy.health_component.is_dead:
		return "Dummy should be dead after 1 body + 2 headshots (remaining=%s)" % dummy.health_component.current_health

	# 4. Verify ammo preserved across weapon switches (3 pistol shots fired -> 9 left in mag)
	if wm.active_weapon.mag_ammo != 9:
		return "Expected 9 pistol mag ammo after 3 shots, got %d" % wm.active_weapon.mag_ammo

	var rifle_res := load("res://resources/weapons/assault_rifle.tres") as WeaponData
	wm.give_or_refill_weapon(rifle_res)
	wm.equip_slot(1, true)
	if wm.active_weapon.data.display_name != "Strider-556":
		return "Expected Strider-556 in slot 1"
	wm.active_weapon.try_fire(player.camera, space_state, exclude, player)
	var rifle_mag_after_one: int = wm.active_weapon.mag_ammo

	wm.equip_slot(0, true)
	if wm.active_weapon.mag_ammo != 9:
		return "Pistol mag ammo not preserved after switching back (got %d)" % wm.active_weapon.mag_ammo

	wm.equip_slot(1, true)
	if wm.active_weapon.mag_ammo != rifle_mag_after_one:
		return "Rifle mag ammo not preserved after switching back"

	await tree.process_frame
	return ""
