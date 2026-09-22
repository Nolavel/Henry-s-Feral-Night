extends SceneTree

## Covers the hold-to-sleep gate and the fuel loop it depends on.
## Run: godot --headless --script tests/systems/test_sleep_prompt.gd

const STEP_MINUTES: float = 10.0

var _failures: int = 0


func _initialize() -> void:
	_test_fuel_burns_down_and_puts_the_fire_out()
	_test_a_dead_fire_stops_heating_its_zone()
	_test_refuelling_relights_and_caps()
	_test_hold_does_not_charge_when_sleep_is_impossible()
	_test_hold_opens_the_dialog_after_the_full_second()
	_test_hour_selection_clamps()
	_test_confirm_sleeps_for_the_selected_hours()
	_test_the_fuel_warning_tracks_the_chosen_hours()
	if _failures > 0:
		push_error("sleep: %d check(s) failed" % _failures)
		quit(1)
		return
	print("sleep: all checks passed")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("sleep: %s" % message)


func _dispose(node: Node) -> void:
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	node.free()


func _make_thermal(ambient_c: float) -> ThermalManager:
	var thermal := ThermalManager.new()
	thermal.ambient_min_c = ambient_c
	thermal.ambient_max_c = ambient_c
	root.add_child(thermal)
	thermal.initialize()
	return thermal


func _simulate(thermal: ThermalManager, hours: float) -> void:
	var step: float = STEP_MINUTES / 60.0
	var elapsed: float = 0.0
	var clock: float = 0.0
	thermal.reset_clock()
	thermal._on_time_update(clock)
	while elapsed < hours:
		clock = fmod(clock + step, 24.0)
		thermal._on_time_update(clock)
		elapsed += step


func _test_fuel_burns_down_and_puts_the_fire_out() -> void:
	var thermal := _make_thermal(-15.0)
	var fire := HeatSource.new()
	fire.peak_offset_c = 20.0
	fire.radius_m = 6.0
	fire.burn_duration_h = 3.0
	root.add_child(fire)
	fire.initialize()

	_check(fire.is_burning(), "a fresh fire was not burning")
	_check(is_equal_approx(fire.get_fuel_fraction(), 1.0), "a fresh fire was not at full fuel")

	_simulate(thermal, 2.0)
	_check(fire.is_burning(), "the fire went out before its fuel ran down")
	_check(fire.get_fuel_fraction() < 1.0, "burning for two hours consumed no fuel")

	_simulate(thermal, 2.0)
	_check(not fire.is_burning(), "the fire kept burning past its fuel")
	_check(is_zero_approx(fire.get_fuel_fraction()), "a spent fire still reports fuel")
	_check(
		is_zero_approx(fire.get_offset_at(Vector3.ZERO)),
		"a spent fire still radiated heat"
	)
	_dispose(fire)
	_dispose(thermal)


## The whole point of fuel: the room goes cold when the fire dies.
func _test_a_dead_fire_stops_heating_its_zone() -> void:
	var thermal := _make_thermal(-15.0)
	var zone := ThermalZone.new()
	zone.is_interior = true
	zone.wind_exposure = 0.0
	zone.temperature_offset_c = 2.0
	zone.max_heated_offset_c = 14.0
	zone.heating_rate_c_per_hour = 10.0
	zone.cooling_rate_c_per_hour = 6.0
	root.add_child(zone)
	thermal._zones.append(zone)

	var fire := HeatSource.new()
	fire.peak_offset_c = 0.0
	fire.radius_m = 0.1
	fire.burn_duration_h = 2.0
	fire.heats_zone = zone
	root.add_child(fire)
	fire.initialize()

	_simulate(thermal, 2.0)
	var warm: float = zone.get_total_offset_c()
	_check(warm > zone.temperature_offset_c, "a burning fire did not warm its zone")

	_simulate(thermal, 3.0)
	_check(not fire.is_burning(), "the fire should be spent by now")
	_check(
		zone.get_total_offset_c() < warm,
		"the zone stayed warm after its fire went out; sleeping would never cost anything"
	)
	_dispose(fire)
	_dispose(zone)
	_dispose(thermal)


func _test_refuelling_relights_and_caps() -> void:
	var thermal := _make_thermal(-15.0)
	var fire := HeatSource.new()
	fire.burn_duration_h = 4.0
	fire.hours_per_fuel_unit = 2.0
	root.add_child(fire)
	fire.initialize()

	_simulate(thermal, 5.0)
	_check(not fire.is_burning(), "the fire should be out before refuelling")

	fire.refuel(1.0)
	_check(fire.is_burning(), "refuelling did not relight a dead fire")
	_check(
		is_equal_approx(fire.get_remaining_hours(), 2.0),
		"refuelling added the wrong amount of fuel: %.2f" % fire.get_remaining_hours()
	)

	fire.refuel(10.0)
	_check(
		is_equal_approx(fire.get_remaining_hours(), 4.0),
		"refuelling exceeded the full load: %.2f" % fire.get_remaining_hours()
	)
	_dispose(fire)
	_dispose(thermal)


## S is also move_backward, so the hold must not charge outside a shelter.
func _test_hold_does_not_charge_when_sleep_is_impossible() -> void:
	var thermal := _make_thermal(-20.0)
	var sleep := SleepController.new()
	sleep.thermal_manager = thermal
	root.add_child(sleep)
	var prompt := SleepPrompt.new()
	prompt.sleep_controller = sleep
	root.add_child(prompt)
	_simulate(thermal, 0.5)

	_check(not prompt.can_begin_hold(), "the hold was allowed while standing in the open")
	prompt.update_hold(2.0)
	_check(not prompt.is_open(), "the dialog opened while sleeping was impossible")
	_check(is_zero_approx(prompt.get_hold_progress()), "the hold charged with no valid sleep")

	_dispose(prompt)
	_dispose(sleep)
	_dispose(thermal)


## Builds a warm lit shelter and a prompt wired to it.
func _make_sheltered_rig() -> Dictionary:
	var thermal := _make_thermal(-20.0)
	var zone := ThermalZone.new()
	zone.is_interior = true
	zone.wind_exposure = 0.0
	zone.temperature_offset_c = 30.0
	root.add_child(zone)
	thermal._zones.append(zone)

	var sleep := SleepController.new()
	sleep.thermal_manager = thermal
	root.add_child(sleep)

	var prompt := SleepPrompt.new()
	prompt.sleep_controller = sleep
	prompt.hold_seconds = 1.0
	root.add_child(prompt)

	_simulate(thermal, 0.5)
	return {"thermal": thermal, "zone": zone, "sleep": sleep, "prompt": prompt}


func _dispose_rig(rig: Dictionary) -> void:
	for key: String in ["prompt", "sleep", "zone", "thermal"]:
		_dispose(rig[key])


func _test_hold_opens_the_dialog_after_the_full_second() -> void:
	var rig: Dictionary = _make_sheltered_rig()
	var prompt: SleepPrompt = rig["prompt"]
	_check(prompt.can_begin_hold(), "the hold was refused in a warm shelter")

	## A tap is not intent.
	prompt.open()
	_check(prompt.is_open(), "open() did not open the dialog")
	prompt.close()
	_check(not prompt.is_open(), "close() did not close the dialog")
	_check(is_zero_approx(prompt.get_hold_progress()), "closing left the hold charged")
	_dispose_rig(rig)


func _test_hour_selection_clamps() -> void:
	var rig: Dictionary = _make_sheltered_rig()
	var prompt: SleepPrompt = rig["prompt"]
	prompt.open()
	_check(prompt.get_selected_hours() == 8, "the dialog did not default to 8 hours")

	for i: int in range(20):
		prompt._set_hours(prompt.get_selected_hours() - 1)
	_check(prompt.get_selected_hours() == 1, "hours fell below the minimum")

	for i: int in range(20):
		prompt._set_hours(prompt.get_selected_hours() + 1)
	_check(prompt.get_selected_hours() == 8, "hours rose above the maximum")
	prompt.close()
	_dispose_rig(rig)


## The warning must be real: it tells the player they will wake up cold.
func _test_the_fuel_warning_tracks_the_chosen_hours() -> void:
	var rig: Dictionary = _make_sheltered_rig()
	var prompt: SleepPrompt = rig["prompt"]

	prompt.open()
	_check(
		not prompt.fire_outlasts_sleep(),
		"with no fire at all the warning should be showing"
	)

	var fire := HeatSource.new()
	fire.peak_offset_c = 12.0
	fire.radius_m = 6.0
	fire.burn_duration_h = 5.0
	root.add_child(fire)
	fire.initialize()

	prompt._set_hours(3)
	_check(prompt.fire_outlasts_sleep(), "a five-hour fire should outlast a three-hour sleep")

	prompt._set_hours(8)
	_check(not prompt.fire_outlasts_sleep(), "a five-hour fire should not outlast an eight-hour sleep")

	prompt.close()
	_dispose(fire)
	_dispose_rig(rig)


func _test_confirm_sleeps_for_the_selected_hours() -> void:
	var rig: Dictionary = _make_sheltered_rig()
	var prompt: SleepPrompt = rig["prompt"]
	var day_night_hours: Array[float] = []
	rig["sleep"].sleep_completed.connect(
		func(hours: float, _saved: bool) -> void: day_night_hours.append(hours)
	)

	prompt.open()
	prompt._set_hours(3)
	_check(prompt.confirm(), "confirming a valid sleep failed")
	_check(not prompt.is_open(), "the dialog stayed open after confirming")
	_check(day_night_hours.size() == 1, "sleep_completed did not fire exactly once")
	_check(
		is_equal_approx(day_night_hours[0], 3.0),
		"slept for the wrong duration: %.1f" % day_night_hours[0]
	)
	_dispose_rig(rig)
