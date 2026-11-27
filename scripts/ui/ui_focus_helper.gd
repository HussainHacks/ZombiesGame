extends RefCounted
## Shared UI focus styling and neighbor-wiring helpers for full controller
## menu navigation without keyboard or mouse.


static func apply_focus_theme(root_ctrl: Control) -> void:
	if root_ctrl == null:
		return
	var focus_sb := StyleBoxFlat.new()
	focus_sb.bg_color = Color(0.24, 0.28, 0.38, 0.95)
	focus_sb.border_color = Color(1.0, 0.82, 0.25, 1.0)
	focus_sb.set_border_width_all(3)
	focus_sb.set_corner_radius_all(4)
	focus_sb.set_content_margin_all(6)

	var theme := Theme.new()
	theme.set_stylebox("focus", "Button", focus_sb)
	theme.set_stylebox("focus", "CheckButton", focus_sb)
	theme.set_stylebox("grabber_area_highlight", "HSlider", focus_sb)
	root_ctrl.theme = theme


static func wire_vertical(controls: Array[Control], wrap: bool = true) -> void:
	var valid: Array[Control] = []
	for c: Control in controls:
		if c != null and c.visible:
			c.focus_mode = Control.FOCUS_ALL
			valid.append(c)
	if valid.is_empty():
		return
	for i: int in range(valid.size()):
		var cur: Control = valid[i]
		var prev_idx: int = (i - 1 + valid.size()) % valid.size() if wrap else maxi(i - 1, 0)
		var next_idx: int = (i + 1) % valid.size() if wrap else mini(i + 1, valid.size() - 1)
		cur.focus_neighbor_top = cur.get_path_to(valid[prev_idx])
		cur.focus_neighbor_bottom = cur.get_path_to(valid[next_idx])


static func wire_horizontal(controls: Array[Control], wrap: bool = true) -> void:
	var valid: Array[Control] = []
	for c: Control in controls:
		if c != null and c.visible:
			c.focus_mode = Control.FOCUS_ALL
			valid.append(c)
	if valid.is_empty():
		return
	for i: int in range(valid.size()):
		var cur: Control = valid[i]
		var prev_idx: int = (i - 1 + valid.size()) % valid.size() if wrap else maxi(i - 1, 0)
		var next_idx: int = (i + 1) % valid.size() if wrap else mini(i + 1, valid.size() - 1)
		cur.focus_neighbor_left = cur.get_path_to(valid[prev_idx])
		cur.focus_neighbor_right = cur.get_path_to(valid[next_idx])


static func grab_safe(ctrl: Control) -> void:
	if ctrl != null and ctrl.is_inside_tree() and ctrl.is_visible_in_tree():
		ctrl.focus_mode = Control.FOCUS_ALL
		ctrl.grab_focus()
