extends SceneTree

const TEST_SCENE: String = "res://experimental/weather_snow/WindSnowTest.tscn"
const OUTPUT_DIR: String = "user://shots/wind_snow"
const SETTLE_FRAMES: int = 90
const STATES: Array[StringName] = [
	&"calm",
	&"snowfall",
	&"windy",
	&"blizzard",
]

var _scene_root: Node
var _frame: int = 0
var _state_index: int = -1
var _settle: int = 0


func _initialize() -> void:
	root.size = Vector2i(960, 540)
	var packed := load(TEST_SCENE) as PackedScene
	if packed == null:
		push_error("Wind snow capture: test scene failed to load.")
		quit(1)
		return
	_scene_root = packed.instantiate()
	root.add_child(_scene_root)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 8:
		return false

	if _settle > 0:
		_settle -= 1
		if _settle == 0:
			_capture_state(STATES[_state_index])
		return false

	_state_index += 1
	if _state_index >= STATES.size():
		quit(0)
		return true

	_scene_root.call("set_weather_profile", STATES[_state_index])
	_settle = SETTLE_FRAMES
	return false


func _capture_state(id: StringName) -> void:
	var image := root.get_texture().get_image()
	if image == null:
		push_error("Wind snow capture: viewport image is null.")
		quit(1)
		return
	var path := "%s/wind_snow_%s.png" % [OUTPUT_DIR, String(id)]
	var absolute := ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var error := image.save_png(absolute)
	if error != OK:
		push_error("Wind snow capture: save_png failed: %s" % error)
		quit(1)
		return
	print("Wind snow capture saved: %s" % absolute)
