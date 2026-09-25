extends SceneTree

## Authored weather turn (#78): calm is held on the way out; walking 200 m out
## (or waiting out the fallback) starts one storm, never while sheltered, then
## windy follows, not calm. It fires once and a save keeps it fired.
## Run: godot --headless --script tests/systems/test_weather_beat.gd

var _failures: int = 0
var _frame: int = 0
var _time: float = 0.0
var _weather: WeatherController
var _beat: WeatherBeat
var _player: Node3D


func _process(delta: float) -> bool:
	_frame += 1
	_time += delta
	match _frame:
		1:
			_weather = WeatherController.new()
			_weather.profiles = WeatherController.load_profiles_from("res://resources/weather")
			root.add_child(_weather)
			_player = Node3D.new()
			root.add_child(_player)
			_beat = WeatherBeat.new()
			_beat.weather = _weather
			_beat.player = _player
			_beat.beat_seconds = 0.3
			root.add_child(_beat)
			_beat.arm()
			_check(_weather.get_current_profile().id == &"calm", "the way out is not held calm")
		3:
			_check(not _beat.has_fired(), "the beat fired at the door")
			_player.position = Vector3(150.0, 0.0, 150.0)  # 212 m flat
		5:
			_check(_beat.has_fired() and _weather.get_current_profile().id == &"blizzard",
				"walking 200 m out did not start the storm")
			_player.position = Vector3.ZERO
		6, 7, 8:
			pass
		_:
			if _time > 1.0 and _frame < 200:
				_check(_weather.get_current_profile().id == &"windy", "the storm was not followed by windy")
				_check(not _beat.is_storming(), "the storm did not end")
				_beat.fire()
				_check(_weather.get_current_profile().id == &"windy", "the beat fired twice")
				var fresh := WeatherBeat.new()
				fresh.load_save_data(_beat.get_save_data())
				_check(fresh.has_fired(), "a saved fired beat would fire again after load")
				fresh.free()
				_test_fallback()
				print("test_weather_beat: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
				quit(1 if _failures > 0 else 0)
				_frame = 1000
	return false


## Standing at the door still gets the storm after the fallback time.
func _test_fallback() -> void:
	var weather := WeatherController.new()
	weather.profiles = WeatherController.load_profiles_from("res://resources/weather")
	root.add_child(weather)
	var beat := WeatherBeat.new()
	beat.weather = weather
	beat.player = Node3D.new()
	root.add_child(beat.player)
	beat.fallback_seconds = 0.0
	root.add_child(beat)
	beat.arm()
	beat._process(0.1)
	_check(beat.has_fired(), "the fallback did not start the storm at the door")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)
