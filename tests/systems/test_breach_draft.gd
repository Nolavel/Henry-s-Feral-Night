extends SceneTree

## Breach drafts (#80 readability): snow blows in through an open breach that
## faces the wind, not through one on the lee side, and stops once it is boarded.
## Run: godot --headless --script tests/systems/test_breach_draft.gd

var _failures: int = 0
var _frame: int = 0
var _windward: ShelterBreach
var _lee: ShelterBreach


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		1:
			var weather := WeatherController.new()
			weather.profiles = WeatherController.load_profiles_from("res://resources/weather")
			root.add_child(weather)
			weather.set_weather(&"blizzard", true)
			BreachDraft.set_weather(weather)
			var wind: Vector3 = weather.get_wind_direction()
			_windward = _breach(-wind)   # faces where the wind comes from
			_lee = _breach(wind)
		2:
			var draft := _windward.get_node(^"Draft") as BreachDraft
			_check(draft.get_strength() > 0.3, "the windward hole shows no draft (%.2f)" % draft.get_strength())
			_check((_lee.get_node(^"Draft") as BreachDraft).get_strength() == 0.0, "the lee-side hole shows a draft")
			_windward.board_up()
			_check(draft.get_strength() == 0.0, "a boarded hole still shows a draft")
			print("test_breach_draft: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
			quit(1 if _failures > 0 else 0)
	return false


## A breach whose facing (-Z) points along `facing`.
func _breach(facing: Vector3) -> ShelterBreach:
	var breach := ShelterBreach.new()
	breach.severity = 0.6
	root.add_child(breach)
	var flat := Vector3(facing.x, 0.0, facing.z).normalized()
	breach.look_at(breach.global_position + flat, Vector3.UP)
	return breach


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)
