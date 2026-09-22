extends SceneTree

## A/B capture for the Forward+ hand-drawn Sobel prototype.
## Both images use the same scene instance, camera, player pose and daylight.
## Only HandDrawnOutlineEffect.visible changes between captures.

const OUT_DIR := "res://docs/runtime_previews/outline_ab"
const VIEWPORT_SIZE := Vector2i(1280, 720)

var _scene: Node3D
var _camera: Camera3D
var _player: CharacterBody3D
var _outline: MeshInstance3D


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var main_scene_path := String(ProjectSettings.get_setting("application/run/main_scene", ""))
	var packed := load(main_scene_path) as PackedScene
	if packed == null:
		push_error("OutlineAB: failed to load main scene: %s" % main_scene_path)
		quit(2)
		return

	_scene = packed.instantiate() as Node3D
	root.add_child(_scene)
	root.size = VIEWPORT_SIZE

	await _wait_frames(35)

	_camera = _scene.get_node_or_null("PlayerCamera") as Camera3D
	_player = _scene.get_node_or_null("Player") as CharacterBody3D
	_outline = _camera.get_node_or_null("HandDrawnOutlineEffect") as MeshInstance3D

	if _camera == null or _player == null or _outline == null:
		push_error("OutlineAB: camera/player/outline prototype missing.")
		quit(3)
		return

	_prepare_scene()
	_prepare_output_dir()
	await _wait_frames(8)

	_outline.visible = false
	await _capture("before.png")

	_outline.visible = true
	await _wait_frames(3)
	await _capture("after.png")

	var report := {
		"main_scene": main_scene_path,
		"viewport": [VIEWPORT_SIZE.x, VIEWPORT_SIZE.y],
		"camera_position": [
			_camera.global_position.x,
			_camera.global_position.y,
			_camera.global_position.z,
		],
		"player_position": [
			_player.global_position.x,
			_player.global_position.y,
			_player.global_position.z,
		],
		"outline_enabled_only_difference": true,
		"renderer": RenderingServer.get_video_adapter_name(),
	}
	var file := FileAccess.open("%s/report.json" % OUT_DIR, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))

	print("[HFN_OUTLINE_AB] complete")
	quit(0)


func _prepare_scene() -> void:
	var stats := _scene.get_node_or_null("StatsDisplay") as CanvasItem
	if stats != null:
		stats.visible = false

	var hud := _player.get_node_or_null("HUD") as CanvasItem
	if hud != null:
		hud.visible = false

	var in_game_ui := _player.get_node_or_null("InGameUI") as CanvasItem
	if in_game_ui != null:
		in_game_ui.visible = false

	# Freeze gameplay. The comparison should be pixel-identical except for
	# the outline material.
	_player.process_mode = Node.PROCESS_MODE_DISABLED
	_player.global_position = Vector3(-0.9, 1.0, -4.2)
	_player.rotation = Vector3(0.0, deg_to_rad(18.0), 0.0)
	_player.reset_physics_interpolation()

	_camera.set_process(false)
	_camera.set_physics_process(false)
	_camera.global_position = Vector3(7.6, 5.7, 2.6)
	_camera.fov = 63.0
	_camera.look_at(Vector3(-0.35, 1.85, -6.6), Vector3.UP)
	_camera.current = true

	# Use a readable daytime lighting state and freeze it, so the overcast
	# sky does not make both screenshots too dark.
	var day_night := _scene.get_node_or_null("WorldEnvironmentSystem/DayNightManager")
	if day_night != null:
		day_night.set_process(false)
		day_night.set("total_game_time_hours", 11.0)
		if day_night.has_method("force_update_lighting"):
			day_night.call("force_update_lighting")


func _prepare_output_dir() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))


func _wait_frames(count: int) -> void:
	for _i in range(count):
		await process_frame


func _capture(filename: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		push_error("OutlineAB: empty viewport image: %s" % filename)
		quit(4)
		return

	var path := ProjectSettings.globalize_path("%s/%s" % [OUT_DIR, filename])
	var error := image.save_png(path)
	if error != OK:
		push_error("OutlineAB: save_png failed: %s (%d)" % [filename, error])
		quit(5)
		return

	print("[HFN_OUTLINE_AB] saved %s" % filename)
