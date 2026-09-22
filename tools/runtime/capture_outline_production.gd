extends SceneTree

## One-frame production-preview capture for the hand-drawn outline.
## Lighting added here is capture-only; Henry materials and the game scene stay untouched.

const OUT_DIR := "res://docs/runtime_previews/outline_production"
const VIEWPORT_SIZE := Vector2i(1280, 720)

var _scene: Node3D
var _camera: Camera3D
var _player: CharacterBody3D
var _outline: CanvasItem


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var main_scene_path := String(ProjectSettings.get_setting("application/run/main_scene", ""))
	var packed := load(main_scene_path) as PackedScene
	if packed == null:
		push_error("OutlineProduction: failed to load main scene.")
		quit(2)
		return

	_scene = packed.instantiate() as Node3D
	root.add_child(_scene)
	root.size = VIEWPORT_SIZE
	await _wait_frames(28)

	_camera = _scene.get_node_or_null("PlayerCamera") as Camera3D
	_player = _scene.get_node_or_null("Player") as CharacterBody3D
	_outline = _camera.get_node_or_null("HandDrawnOutlineEffect") as CanvasItem
	if _camera == null or _player == null or _outline == null:
		push_error("OutlineProduction: required nodes missing.")
		quit(3)
		return

	_prepare_scene()
	_prepare_output_dir()
	await _wait_frames(10)
	await _capture()
	print("[HFN_OUTLINE_PRODUCTION] complete")
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

	# Capture-only portrait lighting. It is intentionally not written into
	# TestScene or Player: it only prevents the dark outfit from collapsing
	# into a black silhouette in this review frame.
	var key := DirectionalLight3D.new()
	key.name = "CaptureKey"
	key.light_color = Color(1.0, 0.92, 0.84)
	key.light_energy = 1.35
	key.shadow_enabled = false
	key.rotation_degrees = Vector3(-38.0, -55.0, 0.0)
	_scene.add_child(key)

	var fill := DirectionalLight3D.new()
	fill.name = "CaptureFill"
	fill.light_color = Color(0.66, 0.76, 1.0)
	fill.light_energy = 0.62
	fill.shadow_enabled = false
	fill.rotation_degrees = Vector3(-22.0, 125.0, 0.0)
	_scene.add_child(fill)

	var rim := OmniLight3D.new()
	rim.name = "CaptureRim"
	rim.light_color = Color(0.72, 0.82, 1.0)
	rim.light_energy = 2.2
	rim.omni_range = 7.0
	rim.shadow_enabled = false
	rim.global_position = _player.global_position + Vector3(-2.0, 2.8, -2.8)
	_scene.add_child(rim)

	_outline.visible = true


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
		push_error("OutlineProduction: empty viewport image.")
		quit(4)
		return

	var path := ProjectSettings.globalize_path("%s/production_preview.png" % OUT_DIR)
	var error := image.save_png(path)
	if error != OK:
		push_error("OutlineProduction: save_png failed (%d)." % error)
		quit(5)
