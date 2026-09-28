extends SceneTree

## Production colour-grade review capture.
## Uses the real Graciosa main scene and the authored First Exit shelter.
## Day / Dusk / Night share one fixed exterior camera; Shelter uses one fixed
## interior camera facing the stove. UI/debug/interaction markers are hidden.

const MAIN_SCENE: String = "res://experimental_location/scenes/Graciosa_Island_Terrain.tscn"
const OUTPUT_DIR: String = "res://docs/runtime_previews/color_grading"
const PREPARE_AFTER_FRAMES: int = 12
const INITIAL_SETTLE_FRAMES: int = 150
const PROFILE_SETTLE_FRAMES: int = 36

const STAGES: Array[Dictionary] = [
	{"hour": 12.0, "shelter": false, "file": "HFN_ColdAsh_Day.png"},
	{"hour": 18.5, "shelter": false, "file": "HFN_ColdAsh_Dusk.png"},
	{"hour": 22.5, "shelter": false, "file": "HFN_ColdAsh_Night.png"},
	{"hour": 12.0, "shelter": true, "file": "HFN_ColdAsh_Shelter.png"},
]

var _scene_root: World
var _controller: ColorGradeController
var _manager: DayNightManager
var _camera: Camera3D
var _player: Node3D
var _house: Node3D
var _weather: WeatherController

var _frame: int = 0
var _stage: int = 0
var _prepared: bool = false


func _initialize() -> void:
	var packed := load(MAIN_SCENE) as PackedScene
	if packed == null:
		push_error("Color grade capture: main Graciosa scene failed to load.")
		quit(1)
		return

	_scene_root = packed.instantiate() as World
	if _scene_root == null:
		push_error("Color grade capture: main scene root is not World.")
		quit(1)
		return

	# The shelter and island terrain are already authored in this scene. The
	# preview does not need streamed content, so avoid unrelated async work.
	_scene_root.streaming_enabled = false
	root.add_child(_scene_root)


func _process(_delta: float) -> bool:
	_frame += 1

	if not _prepared:
		if _frame < PREPARE_AFTER_FRAMES:
			return false
		if not _prepare_production_scene():
			return true
		_prepared = true
		_frame = 0
		_configure_stage(0)
		return false

	var required: int = INITIAL_SETTLE_FRAMES if _stage == 0 else PROFILE_SETTLE_FRAMES
	if _frame < required:
		return false

	if not _capture(String(STAGES[_stage]["file"])):
		return true

	_stage += 1
	if _stage >= STAGES.size():
		print("Color grade capture: production Day / Dusk / Night / Shelter PNGs saved.")
		quit(0)
		return true

	_configure_stage(_stage)
	return false


func _prepare_production_scene() -> bool:
	_controller = _scene_root.get_node_or_null(
		"WorldEnvironmentSystem/ColorGradeController"
	) as ColorGradeController
	_manager = _scene_root.get_node_or_null(
		"WorldEnvironmentSystem/DayNightManager"
	) as DayNightManager
	_camera = _scene_root.get_node_or_null("PlayerCamera") as Camera3D
	_player = _scene_root.get_node_or_null("Player") as Node3D
	_house = _scene_root.get_node_or_null(
		"FirstExitBlockout/ShelterHouse/House"
	) as Node3D

	for child: Node in _scene_root.get_children():
		if child is WeatherController:
			_weather = child as WeatherController
			break

	if (
		_controller == null
		or _manager == null
		or _camera == null
		or _player == null
		or _house == null
	):
		push_error("Color grade capture: production shelter/camera/environment wiring is incomplete.")
		quit(1)
		return false

	_manager.set_process(false)
	_camera.set_process(false)
	_camera.set_physics_process(false)
	_camera.set_process_input(false)
	_camera.set_process_unhandled_input(false)
	_camera.current = true

	# Keep the runtime terrain focused around the real shelter while the review
	# camera is positioned independently.
	_player.global_position = _house.to_global(Vector3(0.0, 1.1, 8.0))
	_player.set_process(false)
	_player.set_physics_process(false)

	_hide_review_noise(_scene_root)

	# One stable weather state makes the three exterior captures directly
	# comparable. Cloud motion remains wired through the real weather system.
	if _weather != null:
		_weather.scheduler_enabled = false
		_weather.set_weather(&"calm", true, 24.0)
	else:
		push_warning("Color grade capture: WeatherController not found; using current sky state.")

	return true


func _configure_stage(index: int) -> void:
	var stage: Dictionary = STAGES[index]
	_frame = 0

	if bool(stage["shelter"]):
		_set_shelter_camera()
	else:
		_set_outdoor_camera()
		_controller.initialize_for_interior(false)

	_manager.total_game_time_hours = float(stage["hour"])
	_manager._force_update_visuals()

	if bool(stage["shelter"]):
		_controller.initialize_for_interior(true)


func _set_outdoor_camera() -> void:
	# Real player-height review angle: snow foreground, shelter facade/roof and
	# enough sky to judge cloud colour/exposure. Identical for Day/Dusk/Night.
	_camera.fov = 62.0
	_camera.global_position = _house.to_global(Vector3(10.5, 3.6, 16.0))
	var target := _house.to_global(Vector3(0.0, 2.7, 1.0))
	_camera.look_at(target, Vector3.UP)


func _set_shelter_camera() -> void:
	# Interior review angle from just inside the entry, looking across the room
	# toward the stove wall so the Shelter grade is judged on actual materials.
	_camera.fov = 68.0
	_camera.global_position = _house.to_global(Vector3(2.4, 2.25, 3.3))
	var target := _house.to_global(Vector3(-3.0, 1.55, -1.8))
	_camera.look_at(target, Vector3.UP)


func _hide_review_noise(node: Node) -> void:
	if node is CanvasLayer:
		(node as CanvasLayer).visible = false
	elif node is Control:
		(node as Control).visible = false
	elif node is Label3D:
		(node as Label3D).visible = false
	elif node is Sprite3D:
		# Interactive action icons are Sprite3D in the First Exit blockout.
		(node as Sprite3D).visible = false

	for child: Node in node.get_children():
		_hide_review_noise(child)


func _capture(file_name: String) -> bool:
	var image := root.get_texture().get_image()
	if image == null:
		push_error("Color grade capture: viewport returned no image.")
		quit(1)
		return false

	var output := "%s/%s" % [OUTPUT_DIR, file_name]
	var absolute := ProjectSettings.globalize_path(output)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var error := image.save_png(absolute)
	if error != OK:
		push_error("Color grade capture: save_png failed for %s (%d)." % [output, error])
		quit(1)
		return false

	print("Color grade capture saved from production scene: %s" % absolute)
	return true
