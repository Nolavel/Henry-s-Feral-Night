extends SceneTree

## Captures both profiles from the same TestScene camera and fixed night hour.
## Run: godot --path . --script tools/runtime/capture_color_grading.gd

const TEST_SCENE: String = "res://tests/scenes/TestScene.tscn"
const OUTPUT_DIR: String = "res://docs/runtime_previews/color_grading"
const SETTLE_FRAMES: int = 90
const PROFILE_SETTLE_FRAMES: int = 24

var _scene_root: Node
var _controller: ColorGradeController
var _frame: int = 0
var _stage: int = 0


func _initialize() -> void:
	var packed := load(TEST_SCENE) as PackedScene
	if packed == null:
		push_error("Color grade capture: TestScene failed to load.")
		quit(1)
		return
	_scene_root = packed.instantiate()
	root.add_child(_scene_root)
	_controller = _scene_root.get_node_or_null(
		"WorldEnvironmentSystem/ColorGradeController"
	) as ColorGradeController
	if _controller == null:
		push_error("Color grade capture: ColorGradeController is missing.")
		quit(1)
		return
	_freeze_night()
	_hide_capture_only_debug()
	_controller.use_outdoor_profile()


func _process(_delta: float) -> bool:
	_frame += 1
	if _stage == 0 and _frame >= SETTLE_FRAMES:
		if not _capture("HFN_ColdAsh_Night.png"):
			return true
		_controller.use_shelter_profile()
		_stage = 1
		_frame = 0
	elif _stage == 1 and _frame >= PROFILE_SETTLE_FRAMES:
		if not _capture("HFN_ColdAsh_Shelter.png"):
			return true
		print("Color grade capture: both TestScene PNGs saved.")
		quit(0)
		return true
	return false


func _freeze_night() -> void:
	var manager := _scene_root.get_node_or_null(
		"WorldEnvironmentSystem/DayNightManager"
	) as DayNightManager
	if manager == null:
		return
	manager.set_process(false)
	manager.total_game_time_hours = 21.0
	manager._force_update_visuals()


func _hide_capture_only_debug() -> void:
	var accelerator := _scene_root.get_node_or_null(
		"WorldEnvironmentSystem/TimeAccelerator/DebugAccelerator"
	) as Control
	if accelerator != null:
		accelerator.visible = false


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
	print("Color grade capture saved: %s" % absolute)
	return true
