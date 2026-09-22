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

	var sun := _scene_root.get_node_or_null("WorldEnvironmentSystem/Lighting/SunLight") as DirectionalLight3D
	if sun != null:
		sun.visible = false

	var world_env := _scene_root.get_node_or_null("WorldEnvironmentSystem/Environment/WorldEnvironment") as WorldEnvironment
	if world_env != null and world_env.environment != null:
		var env := world_env.environment.duplicate() as Environment
		env.fog_enabled = false
		env.volumetric_fog_enabled = false
		env.background_mode = 1
		env.background_color = Color(0.018, 0.021, 0.027, 1.0)
		env.background_energy_multiplier = 1.0
		world_env.environment = env

	_hide_canvas(_scene_root)

	var target := _scene_root.get_node("VisualFXShowcase") as Node3D
	_camera.look_at(target.global_position + Vector3(0.0, 1.4, -0.5), Vector3.UP)
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
