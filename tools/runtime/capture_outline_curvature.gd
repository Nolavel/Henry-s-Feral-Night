extends SceneTree

## Curvature validation for the production depth+normal CompositorEffect.
## Keeps Henry in frame and adds:
## - the real Flashlight.tscn prop (capture-only enlarged 2.5x for readability),
## - a cylinder and sphere as pure rounded-normal references.
## Nothing below is saved into TestScene.

const OUT_DIR := "res://docs/runtime_previews/outline_curvature"
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
		push_error("OutlineCurvatureCapture: failed to load main scene.")
		quit(2)
		return

	_scene = packed.instantiate() as Node3D
	root.add_child(_scene)
	root.size = VIEWPORT_SIZE
	await _wait_frames(30)

	_camera = _scene.get_node_or_null("PlayerCamera") as Camera3D
	_player = _scene.get_node_or_null("Player") as CharacterBody3D
	if _camera == null or _player == null:
		push_error("OutlineCurvatureCapture: camera/player missing.")
		quit(3)
		return

	if _camera.compositor == null or _camera.compositor.compositor_effects.is_empty():
		push_error("OutlineCurvatureCapture: compositor missing.")
		quit(4)
		return

	_prepare_scene()
	_add_curvature_references()
	_prepare_output_dir()

	await _wait_frames(14)
	await _capture()

	print("[HFN_OUTLINE_CURVATURE] complete")
	quit(0)


func _prepare_scene() -> void:
	_hide_canvas_items(_scene)

	_player.process_mode = Node.PROCESS_MODE_DISABLED
	_player.global_position = Vector3(-1.15, 1.0, -4.45)
	_player.rotation = Vector3(0.0, deg_to_rad(18.0), 0.0)
	_player.reset_physics_interpolation()

	_camera.set_process(false)
	_camera.set_physics_process(false)
	_camera.global_position = Vector3(5.1, 3.2, 0.75)
	_camera.fov = 52.0
	_camera.look_at(Vector3(0.0, 1.45, -5.0), Vector3.UP)
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

	# Capture-only neutral lighting. Materials stay unchanged.
	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.94, 0.88)
	key.light_energy = 1.20
	key.shadow_enabled = false
	key.rotation_degrees = Vector3(-38.0, -50.0, 0.0)
	_scene.add_child(key)

	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.70, 0.80, 1.0)
	fill.light_energy = 0.50
	fill.shadow_enabled = false
	fill.rotation_degrees = Vector3(-18.0, 130.0, 0.0)
	_scene.add_child(fill)


func _add_curvature_references() -> void:
	var reference_material := StandardMaterial3D.new()
	reference_material.albedo_color = Color(0.32, 0.36, 0.40, 1.0)
	reference_material.roughness = 0.72
	reference_material.metallic = 0.05

	var cylinder_mesh := CylinderMesh.new()
	cylinder_mesh.top_radius = 0.42
	cylinder_mesh.bottom_radius = 0.42
	cylinder_mesh.height = 1.35
	cylinder_mesh.radial_segments = 48
	cylinder_mesh.rings = 6
	cylinder_mesh.material = reference_material

	var cylinder := MeshInstance3D.new()
	cylinder.name = "CurvatureCylinder"
	cylinder.mesh = cylinder_mesh
	_scene.add_child(cylinder)
	cylinder.global_position = Vector3(0.65, 0.675, -5.1)

	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = 0.48
	sphere_mesh.height = 0.96
	sphere_mesh.radial_segments = 48
	sphere_mesh.rings = 24
	sphere_mesh.material = reference_material

	var sphere := MeshInstance3D.new()
	sphere.name = "CurvatureSphere"
	sphere.mesh = sphere_mesh
	_scene.add_child(sphere)
	sphere.global_position = Vector3(1.65, 1.0, -5.15)

	# Real project prop, enlarged only for this screenshot so its rounded body
	# spans enough pixels to judge normal-curvature response.
	var flashlight_scene := load("res://scenes/environment/props/Flashlight/Flashlight.tscn") as PackedScene
	if flashlight_scene != null:
		var flashlight := flashlight_scene.instantiate() as Node3D
		if flashlight != null:
			flashlight.name = "CurvatureFlashlight"
			flashlight.process_mode = Node.PROCESS_MODE_DISABLED
			_scene.add_child(flashlight)
			flashlight.global_position = Vector3(0.0, 1.55, -4.85)
			flashlight.rotation_degrees = Vector3(0.0, 0.0, 78.0)
			flashlight.scale = Vector3.ONE * 2.5


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
		push_error("OutlineCurvatureCapture: empty viewport image.")
		quit(5)
		return

	var path := ProjectSettings.globalize_path("%s/curvature_props.png" % OUT_DIR)
	var error := image.save_png(path)
	if error != OK:
		push_error("OutlineCurvatureCapture: save_png failed (%d)." % error)
		quit(6)
