extends SceneTree

## Covers the save contract end to end: round-trip, slot metadata, corrupt
## files, atomic writes, and the sleep gate that is the only way to save.
## Run: godot --headless --script tests/systems/test_save_system.gd

const STEP_MINUTES: float = 10.0

var _failures: int = 0


func _initialize() -> void:
	_clear_slots()
	_test_round_trip_restores_state()
	_test_empty_and_corrupt_slots_are_survivable()
	_test_slot_listing_reports_metadata()
	_test_out_of_range_slots_are_refused()
	_test_sleep_is_refused_without_shelter()
	_test_sleep_is_refused_when_too_cold()
	_test_sleep_saves_and_advances_the_world()
	_test_a_failed_save_leaves_the_previous_one_intact()
	_test_an_empty_save_is_refused()
	_test_sleeping_still_costs_body_heat()
	_clear_slots()
	if _failures > 0:
		push_error("save: %d check(s) failed" % _failures)
		quit(1)
		return
	print("save: all checks passed")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("save: %s" % message)


func _dispose(node: Node) -> void:
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	node.free()


func _clear_slots() -> void:
	var manager := SaveManager.new()
	root.add_child(manager)
	for slot: int in range(0, manager.max_slot + 1):
		manager.delete_slot(slot)
	_dispose(manager)


func _make_save_manager() -> SaveManager:
	var manager := SaveManager.new()
	root.add_child(manager)
	return manager


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


## Makes a sheltered, lit, warm spot so sleeping is allowed.
func _make_shelter(thermal: ThermalManager) -> Array[Node]:
	var zone := ThermalZone.new()
	zone.is_interior = true
	zone.wind_exposure = 0.0
	zone.temperature_offset_c = 8.0
	root.add_child(zone)
	thermal._zones.append(zone)

	var fire := HeatSource.new()
	fire.peak_offset_c = 30.0
	fire.radius_m = 6.0
	root.add_child(fire)
	fire.initialize()
	return [zone, fire]


func _test_round_trip_restores_state() -> void:
	var manager := _make_save_manager()
	var thermal := _make_thermal(-25.0)
	manager.register(thermal)
	_simulate(thermal, 3.0)
	thermal.add_wetness(0.5)
	var expected_temp: float = thermal.get_body_temperature_c()
	var expected_wetness: float = thermal.get_wetness()

	_check(manager.save_to_slot(1), "saving a populated slot failed: %s" % manager.get_last_error())

	thermal.restore_body_temperature()
	thermal.add_wetness(-1.0)
	_check(
		not is_equal_approx(thermal.get_body_temperature_c(), expected_temp),
		"rig failed: state was not disturbed before loading"
	)

	_check(manager.load_from_slot(1), "loading slot 1 failed: %s" % manager.get_last_error())
	_check(
		is_equal_approx(thermal.get_body_temperature_c(), expected_temp),
		"body temperature did not survive the round trip"
	)
	_check(
		is_equal_approx(thermal.get_wetness(), expected_wetness),
		"wetness did not survive the round trip"
	)
	_dispose(thermal)
	_dispose(manager)


func _test_empty_and_corrupt_slots_are_survivable() -> void:
	var manager := _make_save_manager()
	_check(not manager.has_slot(3), "slot 3 should be empty at this point")
	_check(manager.read_slot(3).is_empty(), "reading an empty slot returned a document")
	_check(not manager.load_from_slot(3), "loading an empty slot reported success")

	var path: String = "user://saves/slot_3.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://saves"))
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("{ this is not json")
	file.close()

	_check(manager.has_slot(3), "a corrupt file should still count as an occupied slot")
	_check(manager.read_slot(3).is_empty(), "a corrupt slot parsed as a valid document")
	_check(not manager.load_from_slot(3), "loading a corrupt slot reported success")
	manager.delete_slot(3)
	_dispose(manager)


func _test_slot_listing_reports_metadata() -> void:
	var manager := _make_save_manager()
	var thermal := _make_thermal(-10.0)
	manager.register(thermal)
	_check(
		manager.save_to_slot(2, {"day": 4, "hour": 21.5}),
		"saving with metadata failed: %s" % manager.get_last_error()
	)

	var slots: Array[Dictionary] = manager.list_slots()
	var found: Dictionary = {}
	for entry: Dictionary in slots:
		if entry["slot"] == 2:
			found = entry
	_check(not found.is_empty(), "slot 2 missing from the listing")
	_check(not found.get("corrupt", true), "slot 2 was reported corrupt")
	_check(int(found["metadata"].get("day", 0)) == 4, "slot metadata lost the day")
	_check(int(found.get("saved_at_unix", 0)) > 0, "slot listing has no timestamp")

	manager.delete_slot(2)
	_check(not manager.has_slot(2), "deleting slot 2 left it in place")
	_dispose(thermal)
	_dispose(manager)


func _test_out_of_range_slots_are_refused() -> void:
	var manager := _make_save_manager()
	_check(not manager.save_to_slot(-1), "a negative slot was accepted")
	_check(not manager.save_to_slot(manager.max_slot + 1), "an oversized slot was accepted")
	_dispose(manager)


func _test_sleep_is_refused_without_shelter() -> void:
	var thermal := _make_thermal(-20.0)
	var sleep := SleepController.new()
	sleep.thermal_manager = thermal
	root.add_child(sleep)
	_simulate(thermal, 0.5)

	_check(
		sleep.can_sleep() == SleepController.Refusal.NOT_SHELTERED,
		"sleeping in the open was not refused as unsheltered"
	)
	_check(not sleep.try_sleep(), "try_sleep succeeded in the open")
	_dispose(sleep)
	_dispose(thermal)


func _test_sleep_is_refused_when_too_cold() -> void:
	var thermal := _make_thermal(-30.0)
	var zone := ThermalZone.new()
	zone.is_interior = true
	zone.wind_exposure = 0.0
	zone.temperature_offset_c = 2.0
	root.add_child(zone)
	thermal._zones.append(zone)

	var sleep := SleepController.new()
	sleep.thermal_manager = thermal
	root.add_child(sleep)
	_simulate(thermal, 0.5)

	_check(
		sleep.can_sleep() == SleepController.Refusal.TOO_COLD,
		"sleeping in a freezing shelter was not refused as too cold"
	)
	_dispose(sleep)
	_dispose(zone)
	_dispose(thermal)


func _test_sleep_saves_and_advances_the_world() -> void:
	var manager := _make_save_manager()
	var thermal := _make_thermal(-20.0)
	manager.register(thermal)
	var props: Array[Node] = _make_shelter(thermal)
	_simulate(thermal, 1.0)

	var sleep := SleepController.new()
	sleep.thermal_manager = thermal
	sleep.save_manager = manager
	root.add_child(sleep)

	_check(
		sleep.can_sleep() == SleepController.Refusal.NONE,
		"sleeping in a warm lit shelter was refused"
	)
	_check(sleep.try_sleep(8.0), "try_sleep failed in a valid shelter")
	_check(
		manager.has_slot(SaveManager.SLEEP_SLOT),
		"sleeping did not write the autosave slot"
	)

	var document: Dictionary = manager.read_slot(SaveManager.SLEEP_SLOT)
	_check(not document.is_empty(), "the sleep autosave is unreadable")
	_check(
		is_equal_approx(float(document["metadata"].get("slept_hours", 0.0)), 8.0),
		"the autosave did not record how long Henry slept"
	)
	_check(
		document["payload"].has("thermal"),
		"the autosave payload is missing the thermal system"
	)

	manager.delete_slot(SaveManager.SLEEP_SLOT)
	_dispose(sleep)
	for node: Node in props:
		_dispose(node)
	_dispose(thermal)
	_dispose(manager)


## Writing a save with nothing in it is the worst failure a save system can
## have: the player believes they saved. It must fail loudly instead.
func _test_an_empty_save_is_refused() -> void:
	var manager := _make_save_manager()
	_check(not manager.save_to_slot(5), "a save with no participants reported success")
	_check(not manager.has_slot(5), "a save with no participants still wrote a file")
	_check(
		manager.get_last_error().contains("no save participants"),
		"the empty-save refusal did not explain itself: '%s'" % manager.get_last_error()
	)
	_dispose(manager)


## Sleeping must not be a free reset: a cooling shelter still costs heat.
func _test_sleeping_still_costs_body_heat() -> void:
	var manager := _make_save_manager()
	var thermal := _make_thermal(-22.0)
	manager.register(thermal)

	var zone := ThermalZone.new()
	zone.is_interior = true
	zone.wind_exposure = 0.0
	zone.temperature_offset_c = 32.0
	root.add_child(zone)
	thermal._zones.append(zone)
	_simulate(thermal, 0.5)

	var sleep := SleepController.new()
	sleep.thermal_manager = thermal
	sleep.save_manager = manager
	root.add_child(sleep)
	_check(sleep.can_sleep() == SleepController.Refusal.NONE, "the rig shelter was refused")

	thermal.restore_body_temperature()
	var before: float = thermal.get_body_temperature_c()
	zone.temperature_offset_c = 4.0
	_check(sleep.try_sleep(8.0), "sleeping in the rig shelter failed")

	_check(
		thermal.get_body_temperature_c() < before,
		"sleeping in a shelter that went cold did not cost any body heat"
	)

	manager.delete_slot(SaveManager.SLEEP_SLOT)
	_dispose(sleep)
	_dispose(zone)
	_dispose(thermal)
	_dispose(manager)


## A save that cannot gather valid state must not destroy the previous save.
func _test_a_failed_save_leaves_the_previous_one_intact() -> void:
	var manager := _make_save_manager()
	var thermal := _make_thermal(-12.0)
	manager.register(thermal)
	_simulate(thermal, 1.0)
	_check(manager.save_to_slot(4), "the first save failed: %s" % manager.get_last_error())
	var before: Dictionary = manager.read_slot(4)
	_check(not before.is_empty(), "the first save is unreadable")

	## A second participant claiming the same id makes the save unresolvable.
	var clash := ThermalManager.new()
	root.add_child(clash)
	clash.initialize()
	manager.register(clash)

	_check(not manager.save_to_slot(4), "a save with duplicate ids reported success")
	var after: Dictionary = manager.read_slot(4)
	_check(not after.is_empty(), "the failed save destroyed the previous one")
	_check(
		int(after.get("saved_at_unix", -1)) == int(before.get("saved_at_unix", -2)),
		"the failed save overwrote the previous one"
	)

	manager.delete_slot(4)
	_dispose(clash)
	_dispose(thermal)
	_dispose(manager)
