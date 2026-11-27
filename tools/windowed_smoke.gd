extends SceneTree
## Quick windowed smoke check: boots MainMenu, transitions to greybox_compound,
## runs 90 frames, and reports GPU adapter + FPS.

const MainMenuScene := preload("res://scenes/ui/main_menu.tscn")
const CompoundScene := preload("res://scenes/environment/greybox_compound.tscn")


func _initialize() -> void:
	_run_smoke()


func _run_smoke() -> void:
	var menu := MainMenuScene.instantiate() as Control
	root.add_child(menu)
	for _i: int in range(15):
		await process_frame
	menu.queue_free()
	await process_frame

	var compound := CompoundScene.instantiate() as Node3D
	root.add_child(compound)
	for _i: int in range(30):
		await process_frame

	var dm: Node = root.get_node_or_null("DialogueManager")
	if dm != null:
		dm.call("request_line", "round_start", true)
	for _i: int in range(60):
		await process_frame

	var hud := compound.get_node_or_null("HUD")
	var sub_panel := hud.get_node_or_null("SubtitlePanel") as PanelContainer if hud != null else null
	var sub_lbl := hud.get_node_or_null("SubtitlePanel/SubtitleLabel") as RichTextLabel if hud != null else null
	var sub_ok: bool = sub_panel != null and sub_panel.visible and sub_lbl != null and not sub_lbl.text.is_empty()

	var adapter: String = RenderingServer.get_video_adapter_name()
	var fps: float = Engine.get_frames_per_second()
	var rm := compound.get_node_or_null("RoundManager") as RoundManager
	if rm != null:
		rm.stop_and_cleanup()
	compound.queue_free()
	await process_frame
	print("WINDOWED_SMOKE_OK | GPU: %s | FPS: %.1f | SubtitleVisible: %s" % [adapter, fps, sub_ok])
	quit(0 if sub_ok else 1)
