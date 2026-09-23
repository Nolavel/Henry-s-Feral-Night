extends SceneTree

const TEST_SCENE: String = "res://experimental/weather_snow/WindSnowTest.tscn"
const OUTPUT_DIR: String = "user://shots/wind_snow"
const SETTLE_FRAMES: int = 210
const TURN_FRAMES: int = 150
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
var _turn_capture_pending: bool = false


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
			if _turn_capture_pending:
				_capture_named("snowfall_same_phase_later")
				_turn_capture_pending = false
			else:
				var id: StringName = STATES[_state_index]
				_capture_state(id)
				if id == &"snowfall":
					# Keep the same WeatherProfile active and let its direction
					# wander/gust continue. This proves airborne flakes react live.
					_turn_capture_pending = true
					_settle = TURN_FRAMES
					return false
		return false

	_state_index += 1
	if _state_index >= STATES.size():
		quit(0)
		return true

	_scene_root.call("set_weather_profile", STATES[_state_index])
	_settle = SETTLE_FRAMES
	return false


func _capture_state(id: StringName) -> void:
	_capture_named("wind_snow_%s" % String(id))


func _capture_named(name: String) -> void:
	var image := root.get_texture().get_image()
	if image == null:
		push_error("Wind snow capture: viewport image is null.")
		quit(1)
		return
	var path := "%s/%s.png" % [OUTPUT_DIR, name]
	var absolute := ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var error := image.save_png(absolute)
	if error != OK:
		push_error("Wind snow capture: save_png failed: %s" % error)
		quit(1)
		return
	print("Wind snow capture saved: %s" % absolute)
