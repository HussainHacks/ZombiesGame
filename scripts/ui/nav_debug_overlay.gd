class_name NavDebugOverlay
extends CanvasLayer
## Toggleable (F4) navigation debug overlay showing navmesh debug rendering
## and each zombie's current AI state and path distance.

const DebugGateScript := preload("res://scripts/core/debug_gate.gd")

@onready var panel: PanelContainer = $PanelContainer
@onready var label: Label = $PanelContainer/MarginContainer/NavLabel

var debug_enabled: bool = false


func _ready() -> void:
	if panel:
		panel.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not DebugGateScript.is_debug_enabled():
		return
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_F4:
			set_debug_enabled(not debug_enabled)


func set_debug_enabled(enabled: bool) -> void:
	debug_enabled = enabled
	if panel:
		panel.visible = debug_enabled
	NavigationServer3D.set_debug_enabled(debug_enabled)
	for node: Node in get_tree().get_nodes_in_group("zombies"):
		if node is ZombieAI:
			var z := node as ZombieAI
			if z.nav_agent != null:
				z.nav_agent.debug_enabled = debug_enabled


func _process(_delta: float) -> void:
	if not debug_enabled or label == null:
		return

	var zombies: Array[Node] = get_tree().get_nodes_in_group("zombies")
	var lines: Array[String] = ["Nav Debug [F4] | Zombies: %d" % zombies.size()]
	for node: Node in zombies:
		if node is ZombieAI:
			var z := node as ZombieAI
			if z.nav_agent != null:
				z.nav_agent.debug_enabled = true
			var dist: float = z.nav_agent.distance_to_target() if z.nav_agent else 0.0
			lines.append("%s: %s (dist: %.1fm)" % [z.name, z.get_state_name(), dist])
	label.text = "\n".join(lines)
