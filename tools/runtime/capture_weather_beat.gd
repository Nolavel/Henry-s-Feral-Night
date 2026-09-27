extends SceneTree

## Issue #78 frames on the First Exit route: the calm way out, then the authored
## storm after Henry walks 200 m from the start. Frames go to user://shots/weather/.
## Run: xvfb-run godot --path . --rendering-driver vulkan --script res://tools/runtime/capture_weather_beat.gd

const SCENE: String = "res://experimental_location/scenes/Graciosa_Island_Terrain.tscn"
const OUT_DIR: String = "user://shots/weather"
const WARMUP: float = 4.0

var _player: Player
var _beat: WeatherBeat
var _time: float = 0.0
var _step: int = 0


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var scene: Node = (load(SCENE) as PackedScene).instantiate()
	root.add_child(scene)
	_player = scene.find_child("Player", true, false) as Player
	_beat = scene.find_child("WeatherBeat", true, false) as WeatherBeat


func _process(delta: float) -> bool:
	_time += delta
	if _time < WARMUP:
		return false
	match _step:
		0:
			_shot("01_calm_way_out")
			var out: Vector3 = _player.global_position + Vector3(-160.0, 0.0, 140.0)
			_player.global_position = Vector3(out.x, _player.global_position.y + 30.0, out.z)
			_step = 1
		1:
			if _beat.has_fired() and _time > WARMUP + 20.0:
				_shot("02_storm_on_the_return")
				quit()
			elif _time > WARMUP + 60.0:
				print("[weather] beat never fired")
				quit(1)
	return false


func _shot(name: String) -> void:
	root.get_texture().get_image().save_png("%s/%s.png" % [OUT_DIR, name])
	var weather: WeatherController = _beat.weather
	print("[weather] %s profile=%s fired=%s" % [name, weather.get_current_profile().id if weather != null else "?", _beat.has_fired()])
