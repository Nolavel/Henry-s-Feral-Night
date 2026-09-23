extends SceneTree

## Covers the seam between the weather and every snow shader: one writer, two
## globals, both following the weather and the air, neither reading back.
## Run: godot --headless --script tests/systems/test_snow_presentation.gd

var _failures: int = 0


func _process(_delta: float) -> bool:
	_run()
	return true


func _run() -> void:
	_test_every_profile_carries_a_sane_cover()
	_test_cover_follows_the_weather()
	_test_frost_follows_the_air()
	_test_the_globals_are_declared()
	_test_the_world_builds_it()
	if _failures > 0:
		push_error("snow: %d check(s) failed" % _failures)
		quit(1)
		return
	print("snow: all checks passed")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("snow: %s" % message)


func _dispose(node: Node) -> void:
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	node.free()


func _profiles() -> Array[WeatherProfile]:
	return WeatherController.load_profiles_from("res://resources/weather")


func _test_every_profile_carries_a_sane_cover() -> void:
	var by_id: Dictionary = {}
	for profile: WeatherProfile in _profiles():
		_check(
			profile.snow_cover > 0.0 and profile.snow_cover <= 1.0,
			"'%s' has snow_cover %.2f; the island is never bare" % [profile.id, profile.snow_cover]
		)
		by_id[profile.id] = profile.snow_cover
	_check(
		float(by_id.get(&"blizzard", 0.0)) > float(by_id.get(&"calm", 1.0)),
		"a blizzard does not leave more snow than a calm day"
	)


func _make_weather(profile_id: StringName) -> WeatherController:
	var weather := WeatherController.new()
	weather.profiles = _profiles()
	weather.starting_profile_id = profile_id
	weather.scheduler_enabled = false
	root.add_child(weather)
	weather.initialize()
	return weather


func _make_system(weather: WeatherController, thermal: ThermalManager) -> SnowPresentationSystem:
	var system := SnowPresentationSystem.new()
	root.add_child(system)
	system._weather = weather
	system._thermal = thermal
	system.refresh()
	return system


func _test_cover_follows_the_weather() -> void:
	var weather := _make_weather(&"calm")
	var system := _make_system(weather, null)
	var calm: float = system.get_written_snow_cover()
	_check(absf(calm - 0.35) < 0.01, "calm wrote %.2f, expected its profile's 0.35" % calm)

	weather.set_weather(&"blizzard", true)
	system.refresh()
	_check(
		system.get_written_snow_cover() > calm,
		"switching to a blizzard left the cover at %.2f" % system.get_written_snow_cover()
	)
	_dispose(system)
	_dispose(weather)


## Rime answers the air outside, not what Henry feels by the stove.
func _test_frost_follows_the_air() -> void:
	var thermal := ThermalManager.new()
	root.add_child(thermal)
	var system := _make_system(null, thermal)

	thermal._outdoor_air_c = 2.0
	system.refresh()
	_check(is_zero_approx(system.get_written_frost_amount()), "frost formed above freezing")

	thermal._outdoor_air_c = -14.0
	system.refresh()
	var mid: float = system.get_written_frost_amount()
	_check(mid > 0.2 and mid < 0.8, "at -14 C frost was %.2f, expected partway" % mid)

	thermal._outdoor_air_c = -30.0
	system.refresh()
	_check(is_equal_approx(system.get_written_frost_amount(), 1.0), "deep cold did not max the frost")
	_dispose(system)
	_dispose(thermal)


## A shader that declares `global uniform` will not compile if the name is
## missing from project settings, so the declaration is part of the contract.
func _test_the_globals_are_declared() -> void:
	for name: StringName in [SnowPresentationSystem.GLOBAL_SNOW_COVER, SnowPresentationSystem.GLOBAL_FROST_AMOUNT]:
		_check(
			ProjectSettings.has_setting("shader_globals/%s" % name),
			"shader global '%s' is not declared in project.godot" % name
		)


func _test_the_world_builds_it() -> void:
	_check(
		World.WORLD_SYSTEM_SCRIPTS.has(load("res://scripts/systems/world/snow/snow_presentation_system.gd")),
		"the composition root does not build the snow system"
	)
