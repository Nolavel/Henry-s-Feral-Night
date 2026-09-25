extends SceneTree

## Issue #42 frames of the shelter stove: cold and empty, lit with a full load,
## and burnt down to one log. Frames go to user://shots/stove/.
## Run: xvfb-run godot --path . --rendering-driver vulkan --script res://tools/runtime/capture_stove.gd

const SCENE: String = "res://experimental_location/scenes/Graciosa_Island_Terrain.tscn"
const OUT_DIR: String = "user://shots/stove"
const WARMUP: float = 3.0

var _stove: HeatSource
var _visual: StoveVisual
var _time: float = 0.0
var _step: int = 0
var _wait: float = 0.0


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var scene: Node = (load(SCENE) as PackedScene).instantiate()
	root.add_child(scene)


func _process(delta: float) -> bool:
	_time += delta
	if _time < WARMUP or _time < _wait:
		return false
	match _step:
		0:
			for node: Node in root.find_children("*", "", true, false):
				if node is Label3D or (node is CanvasLayer):
					node.set(&"visible", false)
			_stove = root.find_child("ShelterZone", true, false).find_child("Stove", true, false) as HeatSource
			_visual = _stove.find_child("StoveVisual", true, false) as StoveVisual
			var camera := Camera3D.new()
			camera.fov = 50.0
			_stove.add_child(camera)
			camera.position = Vector3(1.5, 0.95, 0.55)
			camera.look_at(_stove.global_position + Vector3(0.0, 0.45, 0.0), Vector3.UP)
			camera.make_current()
			_stove.extinguish()
			_stove.restore_fuel(0.0, false)
			_next()
		1:
			_shot("01_cold_empty")
			_stove.ignite()
			_next()
		2:
			_shot("02_lit_full")
			_stove.restore_fuel(1.5, true)
			_next()
		3:
			_shot("03_burnt_down")
			quit()
	return false


func _next() -> void:
	_step += 1
	_wait = _time + 0.8


func _shot(name: String) -> void:
	root.get_texture().get_image().save_png("%s/%s.png" % [OUT_DIR, name])
	print("[stove] %s logs=%d glowing=%s" % [name, _visual.get_visible_log_count(), _visual.is_glowing()])
