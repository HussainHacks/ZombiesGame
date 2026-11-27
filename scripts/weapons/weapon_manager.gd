class_name WeaponManager
extends Node
## Manages up to 5 weapon slots, switching (1-5 and mouse wheel), per-weapon
## ammo persistence, viewmodel instantiation, recoil recovery, and placeholder audio.

const MAX_SLOTS := 5
const DEFAULT_GAMEPLAY_CONFIG := preload("res://resources/configuration/gameplay_config.tres")
const DEFAULT_UPGRADE_DATA := preload("res://resources/configuration/default_weapon_upgrade.tres")

signal weapon_switched(weapon_data: WeaponData)
signal ammo_changed(mag_ammo: int, reserve_ammo: int)
signal hit_confirmed(is_headshot: bool, is_kill: bool)
signal spread_changed(spread_degrees: float)

@export var starting_weapons: Array[WeaponData] = []
@export var gameplay_config: GameplayConfig
@export var switch_delay: float = 0.25
@export var ads_move_speed_multiplier: float = 0.72
@export var recoil_recovery_speed: float = 10.0

var slots: Array[Dictionary] = []
var active_slot: int = 0
var active_weapon: Weapon
var active_viewmodel: ViewmodelRig

var _switch_timer: float = 0.0
var _recoil_recover_pitch: float = 0.0
var _rt_trigger_held: bool = false
var _player: PlayerController
var _camera: Camera3D
var _viewmodel_anchor: Node3D
var _fire_player: AudioStreamPlayer
var _reload_player: AudioStreamPlayer
var _fire_sounds: Dictionary = {}
var _reload_sounds: Dictionary = {}


func _ready() -> void:
	active_weapon = Weapon.new()
	active_weapon.name = "ActiveWeapon"
	add_child(active_weapon)

	active_weapon.fired.connect(_on_weapon_fired)
	active_weapon.hit_landed.connect(_on_hit_landed)
	active_weapon.ammo_changed.connect(_on_ammo_changed)
	active_weapon.reload_started.connect(_on_reload_started)
	active_weapon.reload_finished.connect(_on_reload_finished)
	active_weapon.reload_cancelled.connect(_on_reload_cancelled)

	_fire_player = AudioStreamPlayer.new()
	_fire_player.name = "FireAudio"
	_fire_player.bus = &"SFX"
	add_child(_fire_player)

	_reload_player = AudioStreamPlayer.new()
	_reload_player.name = "ReloadAudio"
	_reload_player.bus = &"SFX"
	add_child(_reload_player)

	_init_slots()


func _exit_tree() -> void:
	if _fire_player:
		_fire_player.stop()
		_fire_player.stream = null
	if _reload_player:
		_reload_player.stop()
		_reload_player.stream = null
	_fire_sounds.clear()
	_reload_sounds.clear()


func setup_player(player: PlayerController, camera: Camera3D, viewmodel_anchor: Node3D) -> void:
	_player = player
	_camera = camera
	_viewmodel_anchor = viewmodel_anchor
	if active_weapon != null and player != null:
		active_weapon.player_stats = player.player_stats
	if not slots.is_empty():
		equip_slot(0, true)


func get_max_weapons() -> int:
	var cfg: GameplayConfig = gameplay_config if gameplay_config != null else DEFAULT_GAMEPLAY_CONFIG
	return clampi(cfg.max_weapons, 1, MAX_SLOTS) if cfg != null else 3


func get_max_upgrade_tier() -> int:
	var cfg: GameplayConfig = gameplay_config if gameplay_config != null else DEFAULT_GAMEPLAY_CONFIG
	return maxi(cfg.max_upgrade_tier, 1) if cfg != null else 1


func get_slot_tier(slot_index: int) -> int:
	if slot_index < 0 or slot_index >= slots.size():
		return 0
	return int(slots[slot_index].get("tier", 0))


func get_active_tier() -> int:
	return get_slot_tier(active_slot)


func get_weapon_tier(wd: WeaponData) -> int:
	if wd == null:
		return 0
	for entry: Dictionary in slots:
		if entry["data"] == wd:
			return int(entry.get("tier", 0))
	return 0


func get_active_display_name() -> String:
	if active_weapon == null or active_weapon.data == null:
		return ""
	var tier: int = get_active_tier()
	if tier > 0:
		return "%s%s" % [DEFAULT_UPGRADE_DATA.name_prefix, active_weapon.data.display_name]
	return active_weapon.data.display_name


func can_upgrade_active() -> bool:
	if active_weapon == null or active_weapon.data == null:
		return false
	return get_active_tier() < get_max_upgrade_tier()


func _init_slots() -> void:
	slots.clear()
	var cap: int = get_max_weapons()
	for i: int in range(mini(starting_weapons.size(), cap)):
		var wd: WeaponData = starting_weapons[i]
		if wd != null:
			slots.append({
				"data": wd,
				"mag": wd.magazine_size,
				"reserve": wd.reserve_ammo_max,
				"tier": 0,
			})
			if not _fire_sounds.has(wd.category):
				_fire_sounds[wd.category] = WeaponAudio.create_fire_sound(wd.category)
				_reload_sounds[wd.category] = WeaponAudio.create_reload_sound(wd.category)


func _unhandled_input(event: InputEvent) -> void:
	if _player == null or _player.is_paused:
		return

	for i: int in range(get_max_weapons()):
		if event.is_action_pressed("weapon_%d" % (i + 1)):
			equip_slot(i)
			return

	if event.is_action_pressed("weapon_next"):
		_cycle_slot(1)
		return
	if event.is_action_pressed("weapon_prev"):
		_cycle_slot(-1)
		return

	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cycle_slot(-1)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cycle_slot(1)


func _process(delta: float) -> void:
	if _player == null or _player.is_paused:
		return

	if _switch_timer > 0.0:
		_switch_timer = maxf(_switch_timer - delta, 0.0)

	_save_active_ammo()
	active_weapon.tick(delta)

	var idm: Node = get_node_or_null("/root/InputDeviceManager")
	var dev: int = int(idm.get("active_joypad_id")) if (idm != null and int(idm.get("active_joypad_id")) >= 0) else 0
	var lt_val: float = float(idm.call("get_axis_value", dev, JOY_AXIS_TRIGGER_LEFT)) if idm != null else Input.get_joy_axis(dev, JOY_AXIS_TRIGGER_LEFT)
	var rt_val: float = float(idm.call("get_axis_value", dev, JOY_AXIS_TRIGGER_RIGHT)) if idm != null else Input.get_joy_axis(dev, JOY_AXIS_TRIGGER_RIGHT)
	var rt_just_pressed: bool = false
	if not _rt_trigger_held and rt_val > 0.5:
		_rt_trigger_held = true
		rt_just_pressed = true
	elif _rt_trigger_held and rt_val < 0.35:
		_rt_trigger_held = false

	var wants_aim_raw: bool = Input.is_action_pressed("aim") or lt_val > 0.4
	if wants_aim_raw:
		_player.cancel_controller_sprint()
	var sprinting: bool = _player.is_sprinting_active()
	var wants_aim: bool = wants_aim_raw and not sprinting and not active_weapon.is_reloading and _switch_timer <= 0.0
	active_weapon.is_aiming = wants_aim

	if _switch_timer <= 0.0 and active_weapon.data != null:
		if Input.is_action_just_pressed("reload") and not sprinting:
			active_weapon.start_reload()

		var wants_fire: bool = false
		if active_weapon.data.fire_mode == WeaponData.FireMode.AUTO:
			wants_fire = Input.is_action_pressed("fire") or _rt_trigger_held
		else:
			wants_fire = Input.is_action_just_pressed("fire") or rt_just_pressed

		if wants_fire:
			_player.cancel_controller_sprint()
			if not _player.is_sprinting_active():
				var space_state: PhysicsDirectSpaceState3D = _player.get_world_3d().direct_space_state if _player.get_world_3d() else null
				var exclude: Array[RID] = [_player.get_rid()]
				var fx_parent: Node = _player.get_parent()
				var fired_ok: bool = active_weapon.try_fire(_camera, space_state, exclude, _player, fx_parent)
				if not fired_ok and active_weapon.mag_ammo == 0 and not active_weapon.is_reloading and active_viewmodel != null:
					active_viewmodel.trigger_empty_fire()

	if _recoil_recover_pitch > 0.0:
		var step: float = minf(_recoil_recover_pitch, recoil_recovery_speed * delta)
		_recoil_recover_pitch -= step
		_player.apply_recoil(-step, 0.0)

	if active_viewmodel != null:
		var horiz_speed: float = Vector2(_player.velocity.x, _player.velocity.z).length()
		active_viewmodel.update_pose(delta, _player.consume_look_delta(), horiz_speed, active_weapon.is_aiming, sprinting)

	spread_changed.emit(active_weapon.get_current_spread_degrees())


func equip_slot(slot_index: int, instant: bool = false) -> bool:
	if slot_index < 0 or slot_index >= slots.size():
		return false
	if slot_index == active_slot and active_weapon.data != null and not instant:
		return false

	if active_weapon.data != null:
		_save_active_ammo()
		active_weapon.cancel_reload()

	active_slot = slot_index
	var entry: Dictionary = slots[slot_index]
	var wd: WeaponData = entry["data"]
	var tier: int = int(entry.get("tier", 0))
	_apply_slot_modifiers(tier, entry.get("upgrade_data", DEFAULT_UPGRADE_DATA) as WeaponUpgradeData)
	active_weapon.setup(wd, entry["mag"], entry["reserve"])
	_switch_timer = 0.0 if instant else switch_delay

	_spawn_viewmodel(wd, tier, entry.get("upgrade_data", DEFAULT_UPGRADE_DATA) as WeaponUpgradeData)
	weapon_switched.emit(wd)
	return true


func _apply_slot_modifiers(tier: int, upg: WeaponUpgradeData) -> void:
	if active_weapon == null:
		return
	if tier > 0 and upg != null:
		active_weapon.damage_bonus_mult = pow(upg.damage_multiplier, tier)
		active_weapon.headshot_bonus_mult = pow(upg.headshot_multiplier_bonus, tier)
		active_weapon.mag_size_mult = pow(upg.mag_size_multiplier, tier)
		active_weapon.reserve_size_mult = pow(upg.reserve_ammo_multiplier, tier)
		active_weapon.fire_rate_mult = pow(upg.fire_rate_multiplier, tier)
	else:
		active_weapon.damage_bonus_mult = 1.0
		active_weapon.headshot_bonus_mult = 1.0
		active_weapon.mag_size_mult = 1.0
		active_weapon.reserve_size_mult = 1.0
		active_weapon.fire_rate_mult = 1.0


func _cycle_slot(direction: int) -> void:
	if slots.size() <= 1:
		return
	var next_idx: int = posmod(active_slot + direction, slots.size())
	equip_slot(next_idx)


func _save_active_ammo() -> void:
	if active_slot >= 0 and active_slot < slots.size() and active_weapon.data != null:
		slots[active_slot]["mag"] = active_weapon.mag_ammo
		slots[active_slot]["reserve"] = active_weapon.reserve_ammo


func refill_all_reserve_ammo() -> void:
	for i: int in range(slots.size()):
		var wd: WeaponData = slots[i]["data"]
		var tier: int = int(slots[i].get("tier", 0))
		var upg: WeaponUpgradeData = slots[i].get("upgrade_data", DEFAULT_UPGRADE_DATA) as WeaponUpgradeData
		var res_mult: float = pow(upg.reserve_ammo_multiplier, tier) if tier > 0 and upg != null else 1.0
		var max_res: int = maxi(roundi(float(wd.reserve_ammo_max) * res_mult), 0)
		slots[i]["reserve"] = max_res
		if i == active_slot and active_weapon.data != null:
			active_weapon.reserve_ammo = max_res
			ammo_changed.emit(active_weapon.mag_ammo, active_weapon.reserve_ammo)


func reset_to_starter_weapons() -> void:
	if active_weapon != null:
		active_weapon.cancel_reload()
	_init_slots()
	active_slot = 0
	if not slots.is_empty():
		equip_slot(0, true)
	set_process(true)
	set_process_unhandled_input(true)
	if active_viewmodel != null:
		active_viewmodel.visible = true


func has_weapon(wd: WeaponData) -> bool:
	if wd == null:
		return false
	for entry: Dictionary in slots:
		if entry["data"] == wd:
			return true
	return false


func give_or_refill_weapon(wd: WeaponData) -> bool:
	if wd == null:
		return false
	for i: int in range(slots.size()):
		if slots[i]["data"] == wd:
			var tier: int = int(slots[i].get("tier", 0))
			var upg: WeaponUpgradeData = slots[i].get("upgrade_data", DEFAULT_UPGRADE_DATA) as WeaponUpgradeData
			var mag_mult: float = pow(upg.mag_size_multiplier, tier) if tier > 0 and upg != null else 1.0
			var res_mult: float = pow(upg.reserve_ammo_multiplier, tier) if tier > 0 and upg != null else 1.0
			var max_mag: int = maxi(roundi(float(wd.magazine_size) * mag_mult), 1)
			var max_res: int = maxi(roundi(float(wd.reserve_ammo_max) * res_mult), 0)
			slots[i]["mag"] = max_mag
			slots[i]["reserve"] = max_res
			if i == active_slot and active_weapon != null:
				_apply_slot_modifiers(tier, upg)
				active_weapon.setup(wd, max_mag, max_res)
			else:
				equip_slot(i, false)
			return true

	if slots.size() < get_max_weapons():
		slots.append({
			"data": wd,
			"mag": wd.magazine_size,
			"reserve": wd.reserve_ammo_max,
			"tier": 0,
		})
		if not _fire_sounds.has(wd.category):
			_fire_sounds[wd.category] = WeaponAudio.create_fire_sound(wd.category)
			_reload_sounds[wd.category] = WeaponAudio.create_reload_sound(wd.category)
		equip_slot(slots.size() - 1, false)
		_emit_picked_up(wd)
		return true

	# Full inventory: replace the currently held weapon
	slots[active_slot] = {
		"data": wd,
		"mag": wd.magazine_size,
		"reserve": wd.reserve_ammo_max,
		"tier": 0,
	}
	if not _fire_sounds.has(wd.category):
		_fire_sounds[wd.category] = WeaponAudio.create_fire_sound(wd.category)
		_reload_sounds[wd.category] = WeaponAudio.create_reload_sound(wd.category)
	equip_slot(active_slot, true)
	_emit_picked_up(wd)
	return true


func take_active_for_upgrade() -> Dictionary:
	if slots.size() <= 1 or active_slot < 0 or active_slot >= slots.size():
		return {}
	if active_weapon != null:
		active_weapon.cancel_reload()
	var taken: Dictionary = slots[active_slot].duplicate()
	slots.remove_at(active_slot)
	var next_idx: int = clampi(active_slot, 0, slots.size() - 1)
	active_slot = -1
	equip_slot(next_idx, true)
	return taken


func receive_upgraded_weapon(wd: WeaponData, new_tier: int, upg: WeaponUpgradeData = null) -> bool:
	if wd == null:
		return false
	var eff_upg: WeaponUpgradeData = upg if upg != null else DEFAULT_UPGRADE_DATA
	var mag_mult: float = pow(eff_upg.mag_size_multiplier, new_tier) if new_tier > 0 and eff_upg != null else 1.0
	var res_mult: float = pow(eff_upg.reserve_ammo_multiplier, new_tier) if new_tier > 0 and eff_upg != null else 1.0
	var max_mag: int = maxi(roundi(float(wd.magazine_size) * mag_mult), 1)
	var max_res: int = maxi(roundi(float(wd.reserve_ammo_max) * res_mult), 0)
	var entry := {
		"data": wd,
		"mag": max_mag,
		"reserve": max_res,
		"tier": new_tier,
		"upgrade_data": eff_upg,
	}
	if slots.size() < get_max_weapons():
		slots.append(entry)
		equip_slot(slots.size() - 1, true)
	else:
		var target_idx: int = clampi(active_slot, 0, slots.size() - 1)
		slots[target_idx] = entry
		active_slot = -1
		equip_slot(target_idx, true)
	return true


func upgrade_slot(slot_index: int, upg: WeaponUpgradeData = null) -> bool:
	if slot_index < 0 or slot_index >= slots.size():
		return false
	var cur_tier: int = int(slots[slot_index].get("tier", 0))
	if cur_tier >= get_max_upgrade_tier():
		return false
	var eff_upg: WeaponUpgradeData = upg if upg != null else DEFAULT_UPGRADE_DATA
	var new_tier: int = cur_tier + 1
	var wd: WeaponData = slots[slot_index]["data"]
	var mag_mult: float = pow(eff_upg.mag_size_multiplier, new_tier)
	var res_mult: float = pow(eff_upg.reserve_ammo_multiplier, new_tier)
	slots[slot_index]["tier"] = new_tier
	slots[slot_index]["upgrade_data"] = eff_upg
	slots[slot_index]["mag"] = maxi(roundi(float(wd.magazine_size) * mag_mult), 1)
	slots[slot_index]["reserve"] = maxi(roundi(float(wd.reserve_ammo_max) * res_mult), 0)
	if slot_index == active_slot:
		active_slot = -1
		equip_slot(slot_index, true)
	return true


func _emit_picked_up(wd: WeaponData) -> void:
	if is_inside_tree():
		var ge: Node = get_node_or_null("/root/GameEvents")
		if ge != null:
			ge.emit_signal("weapon_picked_up", wd)


func get_move_speed_multiplier() -> float:
	if active_weapon.data == null:
		return 1.0
	var mult: float = active_weapon.data.move_speed_multiplier
	if active_weapon.is_aiming:
		if _player != null:
			var is_scoped: bool = active_weapon.data.aim_fov_multiplier < 0.7
			mult *= (_player.scoped_ads_speed_multiplier if is_scoped else _player.ads_speed_multiplier)
		else:
			mult *= ads_move_speed_multiplier
	return mult


func get_fov_multiplier() -> float:
	if active_weapon.data != null and active_weapon.is_aiming:
		return active_weapon.data.aim_fov_multiplier
	return 1.0


func _spawn_viewmodel(wd: WeaponData, tier: int = 0, upg: WeaponUpgradeData = null) -> void:
	if active_viewmodel != null:
		active_viewmodel.queue_free()
		active_viewmodel = null

	if _viewmodel_anchor == null or wd.viewmodel_scene == null:
		return

	var instance: Node = wd.viewmodel_scene.instantiate()
	if instance is ViewmodelRig:
		active_viewmodel = instance as ViewmodelRig
		_viewmodel_anchor.add_child(active_viewmodel)
		if tier > 0 and upg != null:
			_apply_viewmodel_upgrade_tint(active_viewmodel, upg.emissive_tint)
		var cat_name: String = str(WeaponData.Category.keys()[wd.category])
		_attach_character_sleeves(active_viewmodel, cat_name)
		active_viewmodel.trigger_equip(switch_delay)


func _attach_character_sleeves(rig: ViewmodelRig, weapon_cat: String = "rifle") -> void:
	var sleeve_col := Color(0.25, 0.28, 0.35, 1.0)
	var skin_col := Color(0.76, 0.57, 0.44, 1.0)
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null:
		var cid: String = str(gs.get("selected_character_id"))
		var char_path: String = "res://resources/characters/%s.tres" % cid
		if ResourceLoader.exists(char_path):
			var cd := load(char_path) as CharacterData
			if cd != null:
				sleeve_col = cd.sleeve_color
				skin_col = cd.skin_tone
	rig.configure_character_and_weapon(skin_col, sleeve_col, weapon_cat)


func _apply_viewmodel_upgrade_tint(root_node: Node, tint: Color) -> void:
	for child: Node in root_node.get_children():
		if child is MeshInstance3D:
			var mi := child as MeshInstance3D
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.28, 0.32, 0.38, 1.0).lerp(tint, 0.35)
			mat.emission_enabled = true
			mat.emission = tint
			mat.emission_energy_multiplier = 0.65
			mi.material_override = mat
		_apply_viewmodel_upgrade_tint(child, tint)


func _on_weapon_fired(recoil_pitch: float, recoil_yaw: float) -> void:
	if _player:
		_player.apply_recoil(recoil_pitch, recoil_yaw)
		_recoil_recover_pitch += recoil_pitch * 0.65
		var shake_amt: float = clampf(0.18 + (active_weapon.data.damage / 180.0 if active_weapon.data else 0.2), 0.15, 0.75)
		_player.add_camera_shake(shake_amt)

	if active_viewmodel:
		active_viewmodel.trigger_fire(0.055, recoil_pitch * 2.5)

	if active_weapon.data and _fire_sounds.has(active_weapon.data.category):
		_fire_player.stream = _fire_sounds[active_weapon.data.category]
		_fire_player.play()

	var idm: Node = get_node_or_null("/root/InputDeviceManager")
	if idm != null and active_weapon.data != null:
		var str_scale: float = 0.08 + clampf(active_weapon.data.damage / 150.0, 0.0, 0.25)
		idm.call("play_vibration", str_scale, str_scale * 0.6, 0.06, false)


func _on_hit_landed(is_headshot: bool, is_kill: bool) -> void:
	hit_confirmed.emit(is_headshot, is_kill)


func _on_ammo_changed(mag: int, reserve: int) -> void:
	_save_active_ammo()
	ammo_changed.emit(mag, reserve)


func _on_reload_started(duration: float) -> void:
	if active_viewmodel:
		active_viewmodel.trigger_reload(duration)
	if active_weapon.data and _reload_sounds.has(active_weapon.data.category):
		_reload_player.stream = _reload_sounds[active_weapon.data.category]
		_reload_player.play()
	if is_inside_tree() and active_weapon.data != null:
		var ge: Node = get_node_or_null("/root/GameEvents")
		if ge != null:
			ge.emit_signal("reloading_started", active_weapon.data)


func _on_reload_finished() -> void:
	if active_viewmodel:
		active_viewmodel.set_reloading(false)
	var idm: Node = get_node_or_null("/root/InputDeviceManager")
	if idm != null:
		idm.call("play_vibration", 0.20, 0.10, 0.08, false)


func _on_reload_cancelled() -> void:
	if active_viewmodel:
		active_viewmodel.set_reloading(false)
	if _reload_player.playing:
		_reload_player.stop()
