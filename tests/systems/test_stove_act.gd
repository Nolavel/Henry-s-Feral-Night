extends SceneTree

## Door -> one-log staged load -> ignition -> one-log hot refuel.
## Fuel commits only after each action completes and one physical log is never
## spent unless there is room for its full fuel value.

class FireParticipant:
	extends Node

	func get_simulation_priority() -> int:
		return 300

	func advance_simulation(hours: float, _context: SimulationStepContext) -> void:
		HeatSource.advance_all_fuel(hours)


var _failures: int = 0


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var player_state: Node = root.get_node_or_null(^"PlayerState")
	if player_state != null:
		player_state.set_mode(player_state.Mode.ON_FOOT)

	var clock := SimulationClock.new()
	root.add_child(clock)
	clock.set_total_hours(12.0, &"test_seed")
	var fire_participant := FireParticipant.new()
	root.add_child(fire_participant)
	clock.register_participant(fire_participant)
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

	## Door opening is free and never spends fuel.
	_check(feed.begin_act() == HeatSourceFeed.Refusal.NONE, "door did not open")
	await create_timer(0.4).timeout
	_check(visual.is_door_open() and inventory.get_count(&"firewood") == 3, "opening spent logs")

	## One log is one cancellable WORKING action; cancellation spends nothing.
	var cancel_time: float = clock.get_total_hours()
	_check(feed.begin_act() == HeatSourceFeed.Refusal.NONE and feed.is_acting(), "first log action did not start")
	_check(actions.get_active_action_id().begins_with("feed_stove:"), "log loading bypassed TimeCostedActionSystem")
	if player_state != null:
		_check(player_state.mode == player_state.Mode.WORKING, "log loading did not enter WORKING")
	_check(actions.cancel(&"test_cancel"), "log loading refused cancellation")
	_check(inventory.get_count(&"firewood") == 3, "cancelled log action consumed fuel")
	_check(is_zero_approx(stove.get_remaining_hours()), "cancelled log action changed stove fuel")
	_check(is_equal_approx(clock.get_total_hours(), cancel_time), "cancelled log action billed time before progress")
	if player_state != null:
		_check(player_state.mode == player_state.Mode.ON_FOOT, "cancelled log action did not restore PlayerState")

	## Load exactly one cold log.
	var before_load: float = clock.get_total_hours()
	_check(feed.begin_act() == HeatSourceFeed.Refusal.NONE and feed.is_acting(), "cold one-log load refused")
	actions._process(HeatSourceFeed.ADD_SECONDS)
	_check(not feed.is_acting(), "cold log action did not finish")
	_check(not stove.is_burning() and is_equal_approx(stove.get_remaining_hours(), 2.0), "cold log silently ignited or added wrong fuel")
	_check(inventory.get_count(&"firewood") == 2, "cold load consumed more than one log")
	_check(is_equal_approx(clock.get_total_hours() - before_load, feed.add_time_cost_minutes / 60.0),
		"one-log load billed the wrong game time")
	_check(visual.get_visible_log_count() == 1, "one cold log is not visible")

	## Once cold fuel exists, ignition is the next step even if Henry still carries logs.
	_check(feed.begin_act() == HeatSourceFeed.Refusal.NO_LIGHTER, "cold loaded stove did not prioritise ignition")
	_check(inventory.get_count(&"firewood") == 2, "failed ignition consumed another log")

	inventory.try_add(ItemCatalog.get_item(&"lighter"))
	var before_light: float = clock.get_total_hours()
	_check(feed.begin_act() == HeatSourceFeed.Refusal.NONE and feed.is_acting(), "lighter did not start ignition")
	_check(actions.get_active_action_id().begins_with("light_stove:"), "stove ignition bypassed TimeCostedActionSystem")
	if player_state != null:
		_check(player_state.mode == player_state.Mode.WORKING, "stove ignition did not enter WORKING mode")
	actions._process(HeatSourceFeed.LIGHT_SECONDS)
	if player_state != null:
		_check(player_state.mode == player_state.Mode.ON_FOOT, "stove ignition did not restore PlayerState")
	_check(stove.is_burning() and visual.is_glowing(), "ignition did not create heat and light")
	_check(is_equal_approx(clock.get_total_hours() - before_light, feed.light_time_cost_minutes / 60.0),
		"stove ignition billed the wrong game time")
	_check(inventory.has_item(&"lighter"), "reusable lighter was consumed")
	await create_timer(0.4).timeout
	_check(not visual.is_door_open(), "door did not close after ignition")

	## Add the two remaining logs one at a time while the stove is burning.
	_check(feed.begin_act() == HeatSourceFeed.Refusal.NONE, "hot door did not open")
	var before_hot_one: float = clock.get_total_hours()
	_check(feed.begin_act() == HeatSourceFeed.Refusal.NONE and feed.is_acting(), "first hot log did not start")
	actions._process(HeatSourceFeed.ADD_SECONDS)
	_check(inventory.get_count(&"firewood") == 1, "first hot action consumed more than one log")
	_check(is_equal_approx(clock.get_total_hours() - before_hot_one, feed.add_time_cost_minutes / 60.0),
		"first hot log billed wrong time")
	await create_timer(0.4).timeout
	_check(visual.is_door_open(), "door closed before player could add a second log")

	_check(feed.begin_act() == HeatSourceFeed.Refusal.NONE and feed.is_acting(), "second hot log did not start")
	actions._process(HeatSourceFeed.ADD_SECONDS)
	_check(inventory.get_count(&"firewood") == 0, "second hot action did not consume exactly one log")
	_check(stove.get_remaining_hours() > 5.9 and stove.get_remaining_hours() <= 6.0,
		"two hot logs did not fill the stove to practical capacity")

	## With less than one full-log slot left, another physical log must not be wasted.
	inventory.try_add(ItemCatalog.get_item(&"firewood"))
	var near_full: float = stove.get_remaining_hours()
	_check(feed.begin_act() == HeatSourceFeed.Refusal.NONE, "full stove did not allow door close")
	_check(not feed.is_acting(), "full stove incorrectly started another feed action")
	_check(inventory.get_count(&"firewood") == 1, "full stove wasted a log")
	_check(is_equal_approx(stove.get_remaining_hours(), near_full), "closing full stove changed fuel")
	_check(not visual.is_door_open(), "full stove interaction did not close door")

	## After roughly one log burns, exactly one carried log can be added.
	clock.advance_hours(2.0, &"test_one_log_burn")
	var after_one_burn: float = stove.get_remaining_hours()
	_check(after_one_burn > 3.8 and after_one_burn < 4.1, "one-log burn did not free one fuel slot")
	_check(feed.begin_act() == HeatSourceFeed.Refusal.NONE, "door did not open after one log burned")
	_check(feed.begin_act() == HeatSourceFeed.Refusal.NONE and feed.is_acting(), "one-log top-up did not start")
	actions._process(HeatSourceFeed.ADD_SECONDS)
	_check(inventory.get_count(&"firewood") == 0, "one-log top-up consumed wrong inventory amount")
	_check(stove.get_remaining_hours() > 5.8, "one-log top-up did not restore near-full fuel")

	## After two logs burn, two logs can be deliberately added in two actions.
	_check(feed.begin_act() == HeatSourceFeed.Refusal.NONE, "near-full stove did not close after one-log top-up")
	clock.advance_hours(4.0, &"test_two_log_burn")
	_check(stove.get_remaining_hours() > 1.7 and stove.get_remaining_hours() < 2.1,
		"two-log burn did not free two fuel slots")
	inventory.try_add(ItemCatalog.get_item(&"firewood"))
	inventory.try_add(ItemCatalog.get_item(&"firewood"))
	_check(feed.begin_act() == HeatSourceFeed.Refusal.NONE, "door did not open after two logs burned")
	_check(feed.begin_act() == HeatSourceFeed.Refusal.NONE and feed.is_acting(), "first two-log top-up step refused")
	actions._process(HeatSourceFeed.ADD_SECONDS)
	_check(inventory.get_count(&"firewood") == 1, "first two-log top-up step consumed wrong amount")
	_check(feed.begin_act() == HeatSourceFeed.Refusal.NONE and feed.is_acting(), "second two-log top-up step refused")
	actions._process(HeatSourceFeed.ADD_SECONDS)
	_check(inventory.get_count(&"firewood") == 0, "second two-log top-up step consumed wrong amount")
	_check(stove.get_remaining_hours() > 5.7, "two-log top-up did not restore near-full fuel")

	## Fire persistence still follows ShelterState.
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
