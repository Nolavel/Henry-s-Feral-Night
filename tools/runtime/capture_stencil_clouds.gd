extends SceneTree

## Final stencil + parallax-cloud review frame.
## Uses the real TestScene, exact stencil exclusion on Henry, and the production
## overcast sky. Camera framing intentionally leaves a large sky region.

const OUT_DIR := "res://docs/runtime_previews/stencil_clouds"
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
		push_error("StencilCloudCapture: failed to load main scene.")
		quit(2)
		return

	_scene = packed.instantiate() as Node3D
	root.add_child(_scene)
	root.size = VIEWPORT_SIZE
	await _wait_frames(36)

	_camera = _scene.get_node_or_null("PlayerCamera") as Camera3D
	_player = _scene.get_node_or_null("Player") as CharacterBody3D
	if _camera == null or _player == null:
		push_error("StencilCloudCapture: camera/player missing.")
		quit(3)
		return

	if _camera.get_node_or_null("HandDrawnOutlineEffect") == null:
		push_error("StencilCloudCapture: stencil outline effect missing.")
		quit(4)
		return

	_prepare_scene()
	_prepare_output_dir()
	await _wait_frames(18)
	await _capture()

	print("[HFN_STENCIL_CLOUDS] complete")
	quit(0)


func _prepare_scene() -> void:
	_hide_canvas_items(_scene)

	_player.process_mode = Node.PROCESS_MODE_DISABLED
	_player.global_position = Vector3(-0.85, 1.0, -4.35)
	_player.rotation = Vector3(0.0, deg_to_rad(18.0), 0.0)
	_player.reset_physics_interpolation()

	_camera.set_process(false)
	_camera.set_physics_process(false)
	_camera.global_position = Vector3(5.6, 3.55, 1.95)
	_camera.fov = 60.0
	_camera.look_at(Vector3(-0.65, 2.75, -7.2), Vector3.UP)
	_camera.current = true

	var day_night := _scene.get_node_or_null("WorldEnvironmentSystem/DayNightManager")
	if day_night != null:
		day_night.set_process(false)
		day_night.set("total_game_time_hours", 14.25)
		if day_night.has_method("force_update_lighting"):
			day_night.call("force_update_lighting")

		var sky_material: ShaderMaterial = day_night.get("sky_material") as ShaderMaterial
		if sky_material != null:
			# Keep production values, but freeze wind for a deterministic review.
			sky_material.set_shader_parameter("wind_speed", Vector2.ZERO)

	# Capture-only fill: keeps Henry readable without changing his materials.
	var key := DirectionalLight3D.new()
	key.name = "CaptureKey"
	key.light_color = Color(1.0, 0.93, 0.86)
	key.light_energy = 1.18
	key.shadow_enabled = false
	key.rotation_degrees = Vector3(-35.0, -48.0, 0.0)
	_scene.add_child(key)

	var fill := DirectionalLight3D.new()
	fill.name = "CaptureFill"
	fill.light_color = Color(0.69, 0.78, 1.0)
	fill.light_energy = 0.44
	fill.shadow_enabled = false
	fill.rotation_degrees = Vector3(-18.0, 132.0, 0.0)
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
		push_error("StencilCloudCapture: empty viewport image.")
		quit(5)
		return

	var path := ProjectSettings.globalize_path("%s/stencil_parallax_clouds.png" % OUT_DIR)
	var error := image.save_png(path)
	if error != OK:
		push_error("StencilCloudCapture: save_png failed (%d)." % error)
		quit(6)
