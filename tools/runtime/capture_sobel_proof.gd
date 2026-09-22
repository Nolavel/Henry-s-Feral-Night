extends SceneTree

## Visual proof of the readable screen-space Sobel.
## This intentionally does NOT exclude Henry. The goal is to prove the Sobel
## itself clearly before combining it with player exclusion again.

const OUT_DIR := "res://docs/runtime_previews/sobel_proof"
const VIEWPORT_SIZE := Vector2i(1280, 720)

var _scene: Node3D
var _camera: Camera3D
var _player: CharacterBody3D
var _sobel_layer: CanvasLayer
var _sobel_rect: ColorRect


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var main_scene_path := String(ProjectSettings.get_setting("application/run/main_scene", ""))
	var packed := load(main_scene_path) as PackedScene
	if packed == null:
		push_error("SobelProof: failed to load main scene.")
		quit(2)
		return

	_scene = packed.instantiate() as Node3D
	root.add_child(_scene)
	root.size = VIEWPORT_SIZE
	await _wait_frames(30)

	_camera = _scene.get_node_or_null("PlayerCamera") as Camera3D
	_player = _scene.get_node_or_null("Player") as CharacterBody3D
	if _camera == null or _player == null:
		push_error("SobelProof: camera/player missing.")
		quit(3)
		return

	_prepare_scene()
	_create_sobel_overlay()
	_prepare_output_dir()

	_sobel_rect.visible = false
	await _wait_frames(6)
	await _capture("before.png")

	_sobel_rect.visible = true
	await _wait_frames(6)
	await _capture("after.png")

	print("[HFN_SOBEL_PROOF] complete")
	quit(0)


func _prepare_scene() -> void:
	_hide_canvas_items(_scene)

	var existing_outline := _camera.get_node_or_null("HandDrawnOutlineEffect")
	if existing_outline != null:
		existing_outline.visible = false

	_player.process_mode = Node.PROCESS_MODE_DISABLED
	_player.global_position = Vector3(-0.75, 1.0, -4.15)
	_player.rotation = Vector3(0.0, deg_to_rad(22.0), 0.0)
	_player.reset_physics_interpolation()

	_camera.set_process(false)
	_camera.set_physics_process(false)
	_camera.global_position = Vector3(5.2, 3.65, 1.25)
	_camera.fov = 56.0
	_camera.look_at(Vector3(-0.55, 2.15, -5.4), Vector3.UP)
	_camera.current = true

	var day_night := _scene.get_node_or_null("WorldEnvironmentSystem/DayNightManager")
	if day_night != null:
		day_night.set_process(false)
		day_night.set("total_game_time_hours", 13.75)
		if day_night.has_method("force_update_lighting"):
			day_night.call("force_update_lighting")
		var sky_material: ShaderMaterial = day_night.get("sky_material") as ShaderMaterial
		if sky_material != null:
			sky_material.set_shader_parameter("wind_speed", Vector2.ZERO)
			sky_material.set_shader_parameter("parallax_strength", 0.34)
			sky_material.set_shader_parameter("parallax_layer_separation", 0.48)
			sky_material.set_shader_parameter("parallax_detail_weight", 0.58)

	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.93, 0.86)
	key.light_energy = 1.28
	key.shadow_enabled = false
	key.rotation_degrees = Vector3(-38.0, -52.0, 0.0)
	_scene.add_child(key)

	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.68, 0.78, 1.0)
	fill.light_energy = 0.54
	fill.shadow_enabled = false
	fill.rotation_degrees = Vector3(-20.0, 128.0, 0.0)
	_scene.add_child(fill)


func _create_sobel_overlay() -> void:
	var shader := load("res://shaders/postprocess/hand_drawn_outline_screen_sobel.gdshader") as Shader
	if shader == null:
		push_error("SobelProof: screen Sobel shader missing.")
		quit(4)
		return

	var material := ShaderMaterial.new()
	material.shader = shader

	# Disable the experimental player exclusion in this proof.
	material.set_shader_parameter("player_mask_enabled", 0.0)

	# Deliberately readable, close to the successful production-preview family.
	material.set_shader_parameter("edge_color", Color(0.006, 0.008, 0.012, 1.0))
	material.set_shader_parameter("edge_opacity", 0.76)
	material.set_shader_parameter("edge_width_px", 1.35)
	material.set_shader_parameter("edge_threshold", 0.018)
	material.set_shader_parameter("jitter_amount_px", 0.30)

	_sobel_layer = CanvasLayer.new()
	_sobel_layer.layer = 100
	root.add_child(_sobel_layer)

	_sobel_rect = ColorRect.new()
	_sobel_rect.name = "SobelProofOverlay"
	_sobel_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sobel_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sobel_rect.material = material
	_sobel_layer.add_child(_sobel_rect)


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


func _capture(filename: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw

	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		push_error("SobelProof: empty viewport image.")
		quit(5)
		return

	var path := ProjectSettings.globalize_path("%s/%s" % [OUT_DIR, filename])
	var error := image.save_png(path)
	if error != OK:
		push_error("SobelProof: save_png failed (%d)." % error)
		quit(6)
