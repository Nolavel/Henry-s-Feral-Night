extends SceneTree

## Renders the sleep dialog and the hold indicator side by side, so the UI can
## be reviewed from CI without opening the editor.

const SCENE: String = "res://scenes/ui/hud/sleep_prompt.tscn"
const OUT_DIR: String = "user://shots"
const WARMUP_FRAMES: int = 3

var _frames: int = 0
var _shots: Array[String] = ["hold", "dialog"]
var _index: int = 0
var _prompt: SleepPrompt


func _initialize() -> void:
	var packed := load(SCENE) as PackedScene
	if packed == null:
		push_error("sleep prompt capture: cannot load %s" % SCENE)
		quit(1)
		return
	_prompt = packed.instantiate() as SleepPrompt
	root.add_child(_prompt)
	_prompt.resolve_nodes()
	_prompt.hold_indicator.value = 0.62


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < WARMUP_FRAMES:
		return false
	_capture(_shots[_index])
	_index += 1
	if _index >= _shots.size():
		return true
	_prompt.open()
	_frames = 0
	return false


func _capture(name: String) -> void:
	var image: Image = root.get_texture().get_image()
	if image == null:
		push_error("sleep prompt capture: no image")
		return
	var absolute: String = ProjectSettings.globalize_path("%s/sleep_%s.png" % [OUT_DIR, name])
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	image.save_png(absolute)
	print("sleep prompt capture: %s" % absolute)
