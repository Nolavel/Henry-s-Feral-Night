extends SceneTree

## Headless check of the thermal model: exposure kills, shelter and fire save.
## Run: godot --headless --script tests/systems/test_thermal_model.gd

const STEP_MINUTES: float = 10.0

var _failures: int = 0


func _initialize() -> void:
	_test_exposure_cools_the_body()
	_test_wind_chill_makes_it_worse()
	_test_fire_rewarms()
	_test_interior_blocks_wind()
	_test_wet_clothing_costs_insulation()
	_test_stage_ladder_is_ordered()
	_test_a_lit_shelter_rewarms_a_chilled_player()
	if _failures > 0:
		push_error("thermal: %d check(s) failed" % _failures)
		quit(1)
		return
	print("thermal: all checks passed")
	quit(0)


## Builds a manager with a fixed ambient and no weather, ready to simulate.
func _make_manager(ambient_c: float) -> ThermalManager:
	var manager := ThermalManager.new()
	manager.ambient_min_c = ambient_c
	manager.ambient_max_c = ambient_c
	manager.clothing_insulation_c = 6.0
	root.add_child(manager)
	manager.initialize()
	return manager


## Advances a manager by the given in-game hours in fixed steps.
func _simulate(manager: ThermalManager, hours: float) -> void:
	var step: float = STEP_MINUTES / 60.0
	var elapsed: float = 0.0
	var clock: float = 0.0
	manager.reset_clock()
	manager._on_time_update(clock)
	while elapsed < hours:
		clock = fmod(clock + step, 24.0)
		manager._on_time_update(clock)
		elapsed += step


## Removes a node from the tree and frees it immediately. queue_free() is
## deferred, which would leak heat sources into the next test.
func _dispose(node: Node) -> void:
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	node.free()


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("thermal: %s" % message)


func _test_exposure_cools_the_body() -> void:
	var manager := _make_manager(-25.0)
	_simulate(manager, 3.0)
	_check(
		manager.get_body_temperature_c() < manager.normal_body_temp_c,
		"three hours at -25C did not cool the body"
	)
	_check(
		manager.get_body_temperature_c() > manager.lethal_body_temp_c,
		"three hours at -25C already hit the lethal floor; the model is tuned too fast"
	)
	_check(manager.get_stage() != ThermalManager.Stage.NORMAL, "body cooled but stage stayed NORMAL")
	_dispose(manager)


func _test_wind_chill_makes_it_worse() -> void:
	var calm := _make_manager(-15.0)
	_simulate(calm, 2.0)
	var calm_temp: float = calm.get_body_temperature_c()
	_dispose(calm)

	var windy := _make_manager(-15.0)
	var weather := WeatherController.new()
	var profile := WeatherProfile.new()
	profile.id = &"blizzard"
	profile.wind_speed_mps = 18.0
	weather.profiles = [profile] as Array[WeatherProfile]
	weather.starting_profile_id = &"blizzard"
	weather.scheduler_enabled = false
	root.add_child(weather)
	weather.initialize()
	windy.weather_controller = weather
	_simulate(windy, 2.0)

	_check(
		windy.get_body_temperature_c() < calm_temp,
		"wind chill did not make the same ambient colder"
	)
	_dispose(windy)
	_dispose(weather)


func _test_fire_rewarms() -> void:
	var manager := _make_manager(-25.0)
	_simulate(manager, 2.0)
	var chilled: float = manager.get_body_temperature_c()

	var fire := HeatSource.new()
	fire.peak_offset_c = 45.0
	fire.radius_m = 6.0
	root.add_child(fire)
	fire.initialize()
	_simulate(manager, 2.0)

	_check(
		manager.get_body_temperature_c() > chilled,
		"standing in a fire did not rewarm the body"
	)
	_dispose(fire)
	_dispose(manager)


func _test_interior_blocks_wind() -> void:
	var manager := _make_manager(-20.0)
	var weather := WeatherController.new()
	var profile := WeatherProfile.new()
	profile.id = &"storm"
	profile.wind_speed_mps = 20.0
	weather.profiles = [profile] as Array[WeatherProfile]
	weather.starting_profile_id = &"storm"
	weather.scheduler_enabled = false
	root.add_child(weather)
	weather.initialize()
	manager.weather_controller = weather

	var zone := ThermalZone.new()
	zone.is_interior = true
	zone.wind_exposure = 0.0
	zone.temperature_offset_c = 8.0
	root.add_child(zone)
	manager._zones.append(zone)

	_simulate(manager, 1.0)
	var sheltered_felt: float = manager.get_felt_temperature_c()
	manager._zones.clear()
	_simulate(manager, 1.0)

	_check(
		sheltered_felt > manager.get_felt_temperature_c(),
		"interior zone did not beat standing outside in a storm"
	)
	_check(zone.is_interior, "interior flag lost")
	_dispose(zone)
	_dispose(weather)
	_dispose(manager)


func _test_wet_clothing_costs_insulation() -> void:
	var dry := _make_manager(-15.0)
	_simulate(dry, 2.0)
	var dry_temp: float = dry.get_body_temperature_c()
	_dispose(dry)

	var wet := _make_manager(-15.0)
	wet.add_wetness(1.0)
	_simulate(wet, 2.0)

	_check(
		wet.get_body_temperature_c() < dry_temp,
		"soaked clothing did not cool the body faster than dry clothing"
	)
	_check(is_equal_approx(wet.get_wetness(), 1.0), "wetness did not clamp to 1.0")
	_dispose(wet)


## The slice depends on this: reaching a warm shelter must reverse the cold,
## not merely slow it down. Without it there is no survival loop at all.
func _test_a_lit_shelter_rewarms_a_chilled_player() -> void:
	var manager := _make_manager(-18.0)
	_simulate(manager, 3.0)
	var chilled: float = manager.get_body_temperature_c()
	_check(
		chilled < manager.normal_body_temp_c and chilled > manager.lethal_body_temp_c,
		"rig failed: the player should be chilled but alive before sheltering"
	)

	var zone := ThermalZone.new()
	zone.is_interior = true
	zone.wind_exposure = 0.0
	zone.temperature_offset_c = 6.0
	zone.max_heated_offset_c = 16.0
	zone.heating_rate_c_per_hour = 9.0
	root.add_child(zone)
	zone.add_heat_source()
	manager._zones.append(zone)

	## The zone only models the room warming up; standing by the flames is the
	## HeatSource, and that is how a shelter is actually used.
	var fire := HeatSource.new()
	fire.peak_offset_c = 18.0
	fire.radius_m = 5.0
	root.add_child(fire)
	fire.initialize()

	_simulate(manager, 4.0)
	_check(
		manager.get_body_temperature_c() > chilled,
		"a lit shelter did not rewarm a chilled player; the survival loop cannot close"
	)
	_check(
		manager.get_stage() == ThermalManager.Stage.NORMAL,
		"a lit shelter did not bring the player back to a safe stage"
	)
	_dispose(fire)
	_dispose(zone)
	_dispose(manager)


func _test_stage_ladder_is_ordered() -> void:
	_check(
		ThermalManager.Stage.NORMAL < ThermalManager.Stage.CHILLED
		and ThermalManager.Stage.CHILLED < ThermalManager.Stage.COLD
		and ThermalManager.Stage.COLD < ThermalManager.Stage.HYPOTHERMIC
		and ThermalManager.Stage.HYPOTHERMIC < ThermalManager.Stage.CRITICAL,
		"hypothermia stages are not ordered warmest to coldest"
	)
