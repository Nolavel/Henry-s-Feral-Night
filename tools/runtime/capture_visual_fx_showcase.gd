extends SceneTree

const TEST_SCENE := "res://tests/scenes/TestScene.tscn"
const OUTPUT_PATH := "res://artifacts/visual_fx_showcase.png"
const WARMUP_FRAMES := 24

var _scene_root: Node
var _camera: Camera3D
var _frame: int = 0


func _initialize() -> void:
	var packed := load(TEST_SCENE) as PackedScene
	if packed == null:
		push_error("VisualFX capture: TestScene failed to load.")
		quit(1)
		return

	_scene_root = packed.instantiate()
	root.add_child(_scene_root)

	_camera = _scene_root.get_node_or_null("VisualFXShowcase/ShowcaseCamera") as Camera3D
	if _camera == null:
		push_error("VisualFX capture: ShowcaseCamera is missing from TestScene.")
		quit(1)
		return

	var player_camera := _scene_root.get_node_or_null("PlayerCamera") as Camera3D
	if player_camera != null:
		player_camera.current = false

	var world_system := _scene_root.get_node_or_null("WorldEnvironmentSystem")
	if world_system != null:
		world_system.process_mode = Node.PROCESS_MODE_DISABLED

	var sun := _scene_root.get_node_or_null("WorldEnvironmentSystem/Lighting/SunLight") as DirectionalLight3D
	if sun != null:
		sun.visible = false

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.055, 0.065, 0.08, 1.0)
	env.background_energy_multiplier = 1.0
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.34, 0.38, 0.45, 1.0)
	env.ambient_light_energy = 0.62
	_camera.environment = env

	_hide_canvas(_scene_root)

	var target := _scene_root.get_node("VisualFXShowcase") as Node3D
	_camera.look_at(target.global_position + Vector3(0.0, 2.5, 0.0), Vector3.UP)
	_camera.current = true


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < WARMUP_FRAMES:
		return false

	var image := root.get_texture().get_image()
	if image == null:
		push_error("VisualFX capture: viewport image is null.")
		quit(1)
		return true

	var absolute := ProjectSettings.globalize_path(OUTPUT_PATH)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var error := image.save_png(absolute)
	if error != OK:
		push_error("VisualFX capture: save_png failed: %s" % error)
		quit(1)
		return true

	print("VisualFX capture saved: %s" % absolute)
	quit()
	return true


func _hide_canvas(node: Node) -> void:
	if node is CanvasItem:
		(node as CanvasItem).visible = false
	if node is CanvasLayer:
		(node as CanvasLayer).visible = false
	for child in node.get_children():
		_hide_canvas(child)
