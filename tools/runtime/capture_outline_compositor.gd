extends SceneTree

## One-frame validation capture for the production CompositorEffect outline.
## The actual outline comes only from PlayerCamera's depth+normal compositor.

const OUT_DIR := "res://docs/runtime_previews/outline_compositor"
const VIEWPORT_SIZE := Vector2i(1280, 720)

var _scene: Node3D
var _camera: Camera3D
var _player: CharacterBody3D


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var main_scene_path := String(ProjectSettings.get_setting("application/run/main_scene", ""))
	var packed := load(main_scene_path) as PackedScene
	if packed == null:
		push_error("OutlineCompositorCapture: failed to load main scene.")
		quit(2)
		return

	_scene = packed.instantiate() as Node3D
	root.add_child(_scene)
	root.size = VIEWPORT_SIZE
	await _wait_frames(30)

	_camera = _scene.get_node_or_null("PlayerCamera") as Camera3D
	_player = _scene.get_node_or_null("Player") as CharacterBody3D
	if _camera == null or _player == null:
		push_error("OutlineCompositorCapture: camera/player missing.")
		quit(3)
		return

	if _camera.compositor == null or _camera.compositor.compositor_effects.is_empty():
		push_error("OutlineCompositorCapture: PlayerCamera compositor effect missing.")
		quit(4)
		return

	_prepare_scene()
	_prepare_output_dir()
	await _wait_frames(12)
	await _capture()

	print("[HFN_COMPOSITOR_OUTLINE] complete")
	quit(0)


func _prepare_scene() -> void:
	_hide_canvas_items(_scene)

	_player.process_mode = Node.PROCESS_MODE_DISABLED
	_player.global_position = Vector3(-0.75, 1.0, -4.15)
	_player.rotation = Vector3(0.0, deg_to_rad(22.0), 0.0)
	_player.reset_physics_interpolation()

	_camera.set_process(false)
	_camera.set_physics_process(false)
	_camera.global_position = Vector3(5.4, 3.8, 1.2)
	_camera.fov = 56.0
	_camera.look_at(Vector3(-0.55, 1.75, -5.15), Vector3.UP)
	_camera.current = true

	var day_night := _scene.get_node_or_null("WorldEnvironmentSystem/DayNightManager")
	if day_night != null:
		day_night.set_process(false)
		day_night.set("total_game_time_hours", 12.5)
		if day_night.has_method("force_update_lighting"):
			day_night.call("force_update_lighting")
		var sky_material: ShaderMaterial = day_night.get("sky_material") as ShaderMaterial
		if sky_material != null:
			sky_material.set_shader_parameter("wind_speed", Vector2.ZERO)

	# Capture-only neutral lighting so Henry's dark clothing remains readable.
	# This is not saved into TestScene and does not alter Henry materials.
	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.94, 0.88)
	key.light_energy = 1.15
	key.shadow_enabled = false
	key.rotation_degrees = Vector3(-38.0, -55.0, 0.0)
	_scene.add_child(key)

	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.72, 0.79, 0.95)
	fill.light_energy = 0.42
	fill.shadow_enabled = false
	fill.rotation_degrees = Vector3(-18.0, 125.0, 0.0)
	_scene.add_child(fill)


func _hide_canvas_items(node: Node) -> void:
	if node is CanvasItem:
		(node as CanvasItem).visible = false
	for child: Node in node.get_children():
		_hide_canvas_items(child)


func _prepare_output_dir() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))


func _wait_frames(count: int) -> void:
	for _i in range(count):
		await process_frame


func _capture() -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		push_error("OutlineCompositorCapture: empty viewport image.")
		quit(5)
		return

	var path := ProjectSettings.globalize_path("%s/compositor_depth_normal.png" % OUT_DIR)
	var error := image.save_png(path)
	if error != OK:
		push_error("OutlineCompositorCapture: save_png failed (%d)." % error)
		quit(6)
