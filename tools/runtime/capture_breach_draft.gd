extends SceneTree

## #80 readability frame: inside the First Exit shelter in a blizzard, looking at
## the breach most exposed to the wind, snow blowing in. Frames go to user://shots/draft/.
## Run: xvfb-run godot --path . --rendering-driver vulkan --script res://tools/runtime/capture_breach_draft.gd

const SCENE: String = "res://experimental_location/scenes/Graciosa_Island_Terrain.tscn"
const OUT_DIR: String = "user://shots/draft"

var _time: float = 0.0
var _step: int = 0
var _view: SubViewport
var _camera: Camera3D


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	root.add_child((load(SCENE) as PackedScene).instantiate())


func _process(delta: float) -> bool:
	_time += delta
	if _time < 4.0:
		return false
	match _step:
		0:
			for node: Node in root.find_children("*", "", true, false):
				if node is WeatherController and not (node as WeatherController).profiles.is_empty():
					(node as WeatherController).set_weather(&"blizzard", true)
				elif node is Label3D:
					(node as Label3D).visible = false
			_step = 1
		1:
			if _time < 7.0:
				return false
			var zone: Node = root.find_child("ShelterZone", true, false)
			var best: BreachDraft = null
			for node: Node in zone.find_children("*", "", true, false):
				var draft := node as BreachDraft
				if draft != null and (best == null or draft.get_strength() > best.get_strength()):
					best = draft
			var breach: ShelterBreach = best.breach
			_view = SubViewport.new()
			_view.size = Vector2i(1280, 720)
			_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			root.add_child(_view)
			_camera = Camera3D.new()
			_camera.fov = 60.0
			_view.add_child(_camera)
			var inward: Vector3 = -breach.get_facing()
			_camera.global_position = breach.global_position + inward * 2.4 + Vector3(0.6, 0.2, 0.0)
			_camera.look_at(breach.global_position, Vector3.UP)
			print("[draft] breach=%s strength=%.2f blowing=%s" % [breach.name, best.get_strength(), best.is_blowing()])
			_step = 2
		2:
			if _time > 9.5:
				_view.get_texture().get_image().save_png("%s/01_snow_through_windward_breach.png" % OUT_DIR)
				quit()
	return false
