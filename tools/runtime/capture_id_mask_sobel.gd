extends SceneTree

## Validates the exact Henry ID-mask render pass and the Canvas Sobel that uses it.
## Produces:
## - mask.png   : raw alpha silhouette from the Henry-only SubViewport
## - before.png : scene without Sobel
## - after.png  : scene with Sobel, excluding Henry by the ID mask

const OUT_DIR := "res://docs/runtime_previews/id_mask_sobel"
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
		push_error("IDMaskSobel: failed to load main scene.")
		quit(2)
		return

	_scene = packed.instantiate() as Node3D
	root.add_child(_scene)
	root.size = VIEWPORT_SIZE
	await _wait_frames(36)

	_camera = _scene.get_node_or_null("PlayerCamera") as Camera3D
	_player = _scene.get_node_or_null("Player") as CharacterBody3D
	_outline = _camera.get_node_or_null("HandDrawnOutlineEffect") as CanvasItem

	if _camera == null or _player == null or _outline == null:
		push_error("IDMaskSobel: required nodes missing.")
		quit(3)
		return

	_prepare_scene()
	_prepare_output_dir()
	await _wait_frames(16)

	var mask_texture: Texture2D = _outline.call("get_mask_texture") as Texture2D
	if mask_texture == null:
		push_error("IDMaskSobel: mask texture unavailable.")
		quit(4)
		return

	var mask_image := mask_texture.get_image()
	if mask_image == null or mask_image.is_empty():
		push_error("IDMaskSobel: empty mask image.")
		quit(5)
		return

	var coverage := _sample_mask_coverage(mask_image)
	print("[HFN_ID_MASK] coverage=%.6f" % coverage)
	if coverage < 0.001 or coverage > 0.18:
		push_error("IDMaskSobel: invalid mask coverage %.6f" % coverage)
		quit(6)
		return

	var mask_path := ProjectSettings.globalize_path("%s/mask.png" % OUT_DIR)
	if mask_image.save_png(mask_path) != OK:
		push_error("IDMaskSobel: failed to save mask.png")
		quit(7)
		return

	_outline.visible = false
	await _wait_frames(4)
	await _capture("before.png")

	_outline.visible = true
	await _wait_frames(6)
	await _capture("after.png")

	print("[HFN_ID_MASK] complete")
	quit(0)


func _prepare_scene() -> void:
	_hide_canvas_items(_scene)
	_outline.visible = true

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


func _sample_mask_coverage(image: Image) -> float:
	var width := image.get_width()
	var height := image.get_height()
	var step_x := maxi(width / 320, 1)
	var step_y := maxi(height / 180, 1)
	var covered := 0
	var total := 0

	for y in range(0, height, step_y):
		for x in range(0, width, step_x):
			if image.get_pixel(x, y).a > 0.10:
				covered += 1
			total += 1

	if total == 0:
		return 0.0
	return float(covered) / float(total)


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
		push_error("IDMaskSobel: empty frame.")
		quit(8)
		return

	var path := ProjectSettings.globalize_path("%s/%s" % [OUT_DIR, filename])
	if image.save_png(path) != OK:
		push_error("IDMaskSobel: failed to save %s" % filename)
		quit(9)
