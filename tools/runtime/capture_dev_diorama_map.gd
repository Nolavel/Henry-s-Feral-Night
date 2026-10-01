extends SceneTree

## Temporary lightweight evidence capture for the real StatsDisplay scene.

const STATS_SCENE: String = "res://tools/StatsDisplay/StatsDisplay.tscn"
const OUT_DIR: String = "res://docs/runtime_previews/dev_diorama_map"
const CAPTURE_FRAME: int = 24

var _frame: int = 0


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.16, 0.18, 0.21, 1.0)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(backdrop)

	var stats := (load(STATS_SCENE) as PackedScene).instantiate() as Control
	stats.update_interval = 0.1
	root.add_child(stats)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < CAPTURE_FRAME:
		return false
	var path := "%s/00_runtime_debug_panel.png" % OUT_DIR
	var error := root.get_texture().get_image().save_png(path)
	if error != OK:
		push_error("runtime debug panel capture: cannot save %s (%d)" % [path, error])
		quit(1)
		return true
	print("[runtime-debug-panel] ", path)
	quit()
	return true
