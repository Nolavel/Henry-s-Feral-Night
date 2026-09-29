extends SceneTree

var _failures: int = 0

func _initialize() -> void:
	var profile := load("res://data/world_profiles/key_west_test.tres") as WorldProfile
	_check(profile != null, "Key West profile failed to load")
	if profile != null:
		_check(profile.initial_weather_profile_id == &"blizzard", "Key West does not start in blizzard")
		_check(profile.prewarm_before_first_frame, "Key West weather can pop in after first frame")
		_check(is_equal_approx(profile.wind_direction_override_deg, 8.0), "coast-to-city wind bearing changed")
		_check(profile.world_data_path == "", "Key West must use runtime chunks")
		_check(profile.content_scene_path.ends_with("key_west_first_exit.tscn"), "Key West content scene is not selected")
	var content := KeyWestFirstExit.new()
	_check(content.get_route_distance_m() > 680.0 and content.get_route_distance_m() < 740.0, "Whitehead to Fort Street route is no longer about 700 m")
	_check(content.get_bunker_xz().distance_to(Vector2(-3452.88, 2273.84)) < 0.1, "Whitehead Spit anchor changed")
	_check(content.get_shelter_xz().distance_to(Vector2(-3551.61, 1567.72)) < 0.1, "Fort Street shelter anchor changed")
	var weather := WeatherController.new()
	weather.profiles = WeatherController.load_profiles_from("res://resources/weather")
	weather.apply_world_profile(profile)
	weather.initialize()
	_check(weather.get_current_profile() != null and weather.get_current_profile().id == &"blizzard", "WeatherController did not activate blizzard before runtime")
	var expected := Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(8.0))
	_check(weather.get_wind_direction().dot(expected) > 0.96, "initial wind is not sea to city")
	weather.free()
	content.free()
	if _failures == 0:
		print("key west first exit: all checks passed")
		quit()
	else:
		push_error("key west first exit: %d checks failed" % _failures)
		quit(1)

func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures += 1
		push_error(message)
