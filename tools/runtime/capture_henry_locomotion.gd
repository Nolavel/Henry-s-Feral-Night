extends SceneTree

## Runtime locomotion capture.
## Loads the project's configured MAIN SCENE, drives the real input actions,
## and saves viewport PNGs plus the animation blend state observed in-game.

const OUT_DIR := "res://docs/runtime_previews/henry_locomotion"
const SETTLE_FRAMES := 20

var _scene: Node
var _player: CharacterBody3D
var _animation_component: Node
var _captures: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var main_scene_path: String = String(ProjectSettings.get_setting("application/run/main_scene", ""))
	if main_scene_path.is_empty():
		push_error("LocomotionCapture: application/run/main_scene is empty.")
		quit(2)
		return

	var packed := load(main_scene_path) as PackedScene
	if packed == null:
		push_error("LocomotionCapture: cannot load main scene %s" % main_scene_path)
		quit(3)
		return

	_scene = packed.instantiate()
	root.add_child(_scene)
	root.size = Vector2i(1280, 720)

	await _wait_process_frames(SETTLE_FRAMES)

	_player = _scene.get_node_or_null("Player") as CharacterBody3D
	if _player == null:
		push_error("LocomotionCapture: Player not found in main scene.")
		quit(4)
		return

	_animation_component = _player.get_node_or_null("HenryUALVisual")
	if _animation_component == null:
		push_error("LocomotionCapture: HenryUALVisual animation component not found.")
		quit(5)
		return

	_hide_capture_noise()
	_prepare_output_dir()

	_release_motion_input()
	await _wait_physics_seconds(0.65)
	await _capture("idle")

	Input.action_press("move_forward", 1.0)
	await _wait_physics_seconds(1.15)
	await _capture("walk")

	# Henry has no separate gameplay jog tier. During the authored 1-second
	# walk->sprint ramp, real speed passes through the Jog blend point.
	Input.action_press("sprint", 1.0)
	await _wait_physics_seconds(0.55)
	await _capture("jog_transition")

	await _wait_physics_seconds(0.75)
	await _capture("sprint")

	_release_motion_input()
	await _wait_physics_seconds(0.60)
	await _write_report(main_scene_path)

	print("[HFN_CAPTURE] complete: %s" % ProjectSettings.globalize_path(OUT_DIR))
	quit(0)


func _hide_capture_noise() -> void:
	var stats := _scene.get_node_or_null("StatsDisplay") as CanvasItem
	if stats != null:
		stats.visible = false

	var hud := _player.get_node_or_null("HUD") as CanvasItem
	if hud != null:
		hud.visible = false

	var in_game_ui := _player.get_node_or_null("InGameUI") as CanvasItem
	if in_game_ui != null:
		in_game_ui.visible = false


func _prepare_output_dir() -> void:
	var absolute_dir := ProjectSettings.globalize_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(absolute_dir)


func _release_motion_input() -> void:
	Input.action_release("move_forward")
	Input.action_release("move_backward")
	Input.action_release("move_left")
	Input.action_release("move_right")
	Input.action_release("sprint")


func _wait_process_frames(count: int) -> void:
	for _index in range(count):
		await process_frame


func _wait_physics_seconds(seconds: float) -> void:
	var end_msec: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end_msec:
		await physics_frame


func _capture(state_name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw

	var image: Image = root.get_texture().get_image()
	if image == null or image.is_empty():
		push_error("LocomotionCapture: viewport image is empty for %s" % state_name)
		return

	var relative_path := "%s/%s.png" % [OUT_DIR, state_name]
	var error := image.save_png(ProjectSettings.globalize_path(relative_path))
	if error != OK:
		push_error("LocomotionCapture: save_png failed for %s (%d)" % [state_name, error])

	var blend: float = 0.0
	var label: String = "UNKNOWN"
	if _animation_component.has_method("get_locomotion_blend_position"):
		blend = float(_animation_component.call("get_locomotion_blend_position"))
	if _animation_component.has_method("get_locomotion_label"):
		label = String(_animation_component.call("get_locomotion_label"))

	var horizontal_speed: float = Vector2(_player.velocity.x, _player.velocity.z).length()
	_captures.append({
		"state": state_name,
		"animation_label": label,
		"blend_position": blend,
		"horizontal_speed_mps": horizontal_speed,
		"player_position": [
			_player.global_position.x,
			_player.global_position.y,
			_player.global_position.z,
		],
		"player_velocity": [
			_player.velocity.x,
			_player.velocity.y,
			_player.velocity.z,
		],
	})

	print(
		"[HFN_CAPTURE] %s label=%s speed=%.3f blend=%.3f"
		% [state_name, label, horizontal_speed, blend]
	)


func _write_report(main_scene_path: String) -> void:
	var report := {
		"main_scene": main_scene_path,
		"viewport": [root.size.x, root.size.y],
		"captures": _captures,
	}

	var path := "%s/runtime_report.json" % OUT_DIR
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("LocomotionCapture: cannot write runtime report.")
		return
	file.store_string(JSON.stringify(report, "\t"))
