extends CanvasLayer
## Simple toggleable (F3) debug overlay displaying FPS, player position,
## velocity, and grounded state.

@export var player_path: NodePath

@onready var panel: PanelContainer = $PanelContainer
@onready var label: Label = $PanelContainer/MarginContainer/DebugLabel

var _player: CharacterBody3D = null


func _ready() -> void:
	if player_path != NodePath():
		_player = get_node_or_null(player_path) as CharacterBody3D
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as CharacterBody3D
	panel.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_F3:
			panel.visible = not panel.visible


func _process(_delta: float) -> void:
	if not panel.visible:
		return

	var fps: int = Engine.get_frames_per_second()
	if _player == null:
		label.text = "FPS: %d\nPlayer: not found" % fps
		return

	var pos: Vector3 = _player.global_position
	var vel: Vector3 = _player.velocity
	var horiz_speed: float = Vector2(vel.x, vel.z).length()
	var grounded: bool = _player.is_on_floor()

	var stall_line: String = ""
	var rm: Node = get_tree().get_first_node_in_group("round_manager")
	if rm != null and "spawn_stall_seconds" in rm:
		var stall: float = rm.get("spawn_stall_seconds")
		if stall > 0.0:
			stall_line = "\nSpawn Stall: %.1fs" % stall

	label.text = (
		"FPS: %d\n" % fps
		+ "Pos: (%.2f, %.2f, %.2f)\n" % [pos.x, pos.y, pos.z]
		+ "Vel: (%.2f, %.2f, %.2f) [%.2f m/s]\n" % [vel.x, vel.y, vel.z, horiz_speed]
		+ "Grounded: %s" % str(grounded)
		+ stall_line
	)
