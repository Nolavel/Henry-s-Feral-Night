extends SceneTree

## Door -> cold logs -> lighter -> timed ignition -> hot refuel.
## Refusals preserve loaded fuel; saved state follows ignition.

var _failures: int = 0


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var state: Node = root.get_node_or_null(^"PlayerState")
	if state != null:
		state.set_mode(state.Mode.ON_FOOT)

	var clock := SimulationClock.new()
	root.add_child(clock)
	clock.set_total_hours(12.0, &"test_seed")
	var actions := TimeCostedActionSystem.new()
	actions.simulation_clock = clock
	root.add_child(actions)

	var player := CharacterBody3D.new()
	player.add_to_group(&"player")
	var inventory := InventoryComponent.new()
	player.add_child(inventory)
	root.add_child(player)
	var stove := HeatSource.new()
	stove.starts_burning = false
	var visual := StoveVisual.new()
	visual.name = "StoveVisual"
	stove.add_child(visual)
	var feed := HeatSourceFeed.new()
	feed.heat_source = stove
	stove.add_child(feed)
	root.add_child(stove)
	for _i: int in range(3):
		inventory.try_add(ItemCatalog.get_item(&"firewood"))
	_check(feed.begin_act() == HeatSourceFeed.Refusal.NONE, "door did not open")
	await create_timer(0.4).timeout
	_check(visual.is_door_open() and inventory.get_count(&"firewood") == 3, "opening spent logs")
	_check(feed.begin_act() == HeatSourceFeed.Refusal.NONE, "cold loading refused")
	_check(not stove.is_burning() and is_equal_approx(stove.get_remaining_hours(), 6), "loading ignited fuel")
	_check(visual.get_visible_log_count() == 3 and inventory.get_count(&"firewood") == 0, "cold load is not visible")
	_check(feed.begin_act() == HeatSourceFeed.Refusal.NO_LIGHTER, "cold stove did not require lighter")
	_check(is_equal_approx(stove.get_remaining_hours(), 6), "refusal spent fuel")
	inventory.try_add(ItemCatalog.get_item(&"lighter"))
	var before_light: float = clock.get_total_hours()
	_check(feed.begin_act() == HeatSourceFeed.Refusal.NONE and feed.is_acting(), "lighter did not start ignition")
	_check(actions.get_active_action_id().begins_with("light_stove:"), "stove bypassed TimeCostedActionSystem")
	if state != null:
		_check(state.mode == state.Mode.WORKING, "stove ignition did not enter WORKING mode")
	_check(not feed.can_interact() and not stove.is_burning(), "fire took before ignition finished")
	actions._process(HeatSourceFeed.LIGHT_SECONDS)
	if state != null:
		_check(state.mode == state.Mode.ON_FOOT, "stove ignition did not restore PlayerState")
	_check(stove.is_burning() and visual.is_glowing(), "ignition did not create heat and light")
	_check(is_equal_approx(clock.get_total_hours() - before_light, feed.light_time_cost_minutes / 60.0),
		"stove ignition billed the wrong game time")
	_check(inventory.has_item(&"lighter"), "reusable lighter was consumed")
	await create_timer(0.4).timeout
	_check(not visual.is_door_open(), "door did not close after ignition")
	stove.advance_fuel(2)
	inventory.try_add(ItemCatalog.get_item(&"firewood"))
	_check(feed.begin_act() == HeatSourceFeed.Refusal.NONE, "hot door did not open")
	_check(feed.begin_act() == HeatSourceFeed.Refusal.NONE, "hot refuel failed")
	_check(stove.is_burning() and is_equal_approx(stove.get_remaining_hours(), 6), "hot refuel failed")
	var state := ShelterState.new()
	root.add_child(state)
	var zone := ThermalZone.new()
	root.add_child(zone)
	state.adopt_fire(zone, stove)
	var key: String = "%s/%s" % [zone.name, stove.name]
	stove.restore_fuel(4, false)
	_check(not bool(state.get_save_data()["fires"][key]["burning"]), "cold state was not saved")
	stove.restore_fuel(4, true)
	_check(bool(state.get_save_data()["fires"][key]["burning"]), "ignited state was saved as cold")
	print("test_stove_act: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("stove act: " + message)
