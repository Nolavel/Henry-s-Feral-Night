extends SceneTree

## Headless-ish screenshot harness: boots a scene, waits, writes a PNG.
## Usage: godot --path . --script tools/ci/screenshot.gd -- <scene> <out.png> [frames]

const DEFAULT_FRAMES := 30

var _target_scene := ""
var _out_path := "user://shot.png"
var _frames := DEFAULT_FRAMES
var _elapsed := 0


func _initialize() -> void:
	_parse_arguments()
	if _target_scene.is_empty():
		push_error("screenshot.gd: no scene given")
		quit(1)
		return
	var packed := load(_target_scene) as PackedScene
	if packed == null:
		push_error("screenshot.gd: cannot load %s" % _target_scene)
		quit(1)
		return
	root.add_child(packed.instantiate())


func _process(_delta: float) -> bool:
	_elapsed += 1
	if _elapsed < _frames:
		return false
	_capture()
	return true


## Reads scene path, output path and frame count from the CLI tail.
func _parse_arguments() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_target_scene = args[0]
	if args.size() > 1:
		_out_path = args[1]
	if args.size() > 2:
		_frames = maxi(1, args[2].to_int())


## Grabs the root viewport and writes it as a PNG next to the given path.
func _capture() -> void:
	var image := root.get_texture().get_image()
	if image == null:
		push_error("screenshot.gd: viewport returned no image")
		quit(1)
		return
	var absolute := ProjectSettings.globalize_path(_out_path)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var error := image.save_png(absolute)
	if error != OK:
		push_error("screenshot.gd: save_png failed (%d)" % error)
		quit(1)
		return
	print("screenshot: %s (%dx%d)" % [absolute, image.get_width(), image.get_height()])
