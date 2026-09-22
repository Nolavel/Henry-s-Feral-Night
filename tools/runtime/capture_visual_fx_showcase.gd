extends SceneTree

const TEST_SCENE := "res://tests/scenes/TestScene.tscn"
const SHADOW_OUTPUT := "res://artifacts/stylized_shadows_testscene.png"
const FADE_OUTPUT := "res://artifacts/fade_volume_testscene.png"
const SHADOW_CAPTURE_FRAME := 28
const FADE_CAPTURE_FRAME := 52

var _scene_root: Node
var _camera: Camera3D
var _sun: DirectionalLight3D
var _frame: int = 0
var _configured: bool = false
var _fade_view_set: bool = false


func _initialize() -> void:
	var packed := load(TEST_SCENE) as PackedScene
	if packed == null:
		push_error("VisualFX capture: TestScene failed to load.")
		quit(1)
		return

	_scene_root = packed.instantiate()
	root.add_child(_scene_root)


func _process(_delta: float) -> bool:
	_frame += 1

	if not _configured:
		_configure_test_scene()
		return false

	if _frame == SHADOW_CAPTURE_FRAME:
		_capture(SHADOW_OUTPUT)
		_set_fade_view()
		_fade_view_set = true
		return false

	if _fade_view_set and _frame >= FADE_CAPTURE_FRAME:
		_capture(FADE_OUTPUT)
		quit()
		return true

	return false


func _configure_test_scene() -> void:
	_camera = _scene_root.get_node_or_null("PlayerCamera") as Camera3D
	if _camera == null:
		push_error("VisualFX capture: PlayerCamera is missing from TestScene.")
		quit(1)
		return

	_camera.process_mode = Node.PROCESS_MODE_DISABLED
	_camera.current = true
	_camera.fov = 60.0

	var player := _scene_root.get_node_or_null("Player")
	if player != null:
		player.process_mode = Node.PROCESS_MODE_DISABLED

	var world_system := _scene_root.get_node_or_null("WorldEnvironmentSystem")
	if world_system != null:
		world_system.process_mode = Node.PROCESS_MODE_DISABLED

	_sun = _scene_root.get_node_or_null("WorldEnvironmentSystem/Lighting/SunLight") as DirectionalLight3D
	if _sun != null:
		_sun.visible = true
		_sun.rotation_degrees = Vector3(-23.0, -58.0, 0.0)
		_sun.light_energy = 2.6
		_sun.light_angular_distance = 1.2
		_sun.shadow_enabled = true
		_sun.shadow_bias = 0.085
		_sun.shadow_normal_bias = 1.25

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.045, 0.052, 0.065, 1.0)
	env.background_energy_multiplier = 1.0
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.28, 0.31, 0.37, 1.0)
	env.ambient_light_energy = 0.18
	_camera.environment = env

	_hide_canvas(_scene_root)

	_camera.global_position = Vector3(8.2, 7.6, 12.5)
	_camera.look_at(Vector3(8.1, 0.7, -2.0), Vector3.UP)
	_configured = true


func _set_fade_view() -> void:
	if _sun != null:
		_sun.light_energy = 0.16

	if _camera.environment != null:
		_camera.environment.ambient_light_energy = 0.42

	_camera.fov = 64.0
	_camera.global_position = Vector3(-8.5, 2.25, 1.8)
	_camera.look_at(Vector3(-8.5, 1.65, -13.2), Vector3.UP)


func _capture(path: String) -> void:
	var image := root.get_texture().get_image()
	if image == null:
		push_error("VisualFX capture: viewport image is null.")
		quit(1)
		return

	var absolute := ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var error := image.save_png(absolute)
	if error != OK:
		push_error("VisualFX capture: save_png failed: %s" % error)
		quit(1)
		return

	print("VisualFX capture saved: %s" % absolute)


func _hide_canvas(node: Node) -> void:
	if node is CanvasItem:
		(node as CanvasItem).visible = false
	if node is CanvasLayer:
		(node as CanvasLayer).visible = false
	for child in node.get_children():
		_hide_canvas(child)
