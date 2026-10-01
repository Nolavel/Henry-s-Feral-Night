extends SceneTree

## Temporary lightweight evidence capture for the runtime debug panel.

const MAIN_SCENE: String = "res://scenes/world/key_west/key_west.tscn"
const OUT_DIR: String = "res://docs/runtime_previews/dev_diorama_map"
const CAPTURE_FRAME: int = 90

var _scene: Node3D
var _frame: int = 0


func _initialize() -> void:
	OS.set_environment("HFN_WORLD", "key_west_test")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_scene = (load(MAIN_SCENE) as PackedScene).instantiate() as Node3D
	if _scene is World:
		(_scene as World).enable_runtime_dev_map = false
		(_scene as World).enable_runtime_debug_panel = true
		(_scene as World).print_runtime_debug_stats = false
	root.add_child(_scene)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < CAPTURE_FRAME:
		return false
	var splash := _scene.get_node_or_null(^"StartupTitleCard")
	if splash != null:
		splash.visible = false
	var path := "%s/00_runtime_debug_panel.png" % OUT_DIR
	var error := root.get_texture().get_image().save_png(path)
	if error != OK:
		push_error("runtime debug panel capture: cannot save %s (%d)" % [path, error])
		quit(1)
		return true
	print("[runtime-debug-panel] ", path)
	quit()
	return true
