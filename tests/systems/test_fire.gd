extends SceneTree

## Covers the other half of preparing a shelter: a fire that has to be lit,
## fed, and that burns down to nothing if it is not.
## Run: godot --headless --script tests/systems/test_fire.gd

var _failures: int = 0


func _process(_delta: float) -> bool:
	_run()
	return true


func _run() -> void:
	_test_a_dead_fire_needs_tinder_and_wood()
	_test_a_burning_fire_needs_only_wood()
	_test_a_full_fire_refuses_without_spending_anything()
	_test_feeding_buys_the_night()
	_test_a_dead_fire_stops_warming_the_room()
	_test_the_sleep_prompt_warning_follows_the_fuel()
	_test_fuel_survives_a_save_round_trip()
	if _failures > 0:
		push_error("fire: %d check(s) failed" % _failures)
		quit(1)
		return
	print("fire: all checks passed")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("fire: %s" % message)


func _dispose(node: Node) -> void:
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	node.free()


func _make_fire(burning: bool = false) -> HeatSource:
	var fire := HeatSource.new()
	fire.name = "Stove"
	fire.starts_burning = burning
	fire.burn_duration_h = 6.0
	fire.hours_per_fuel_unit = 2.0
	root.add_child(fire)
	fire.initialize()
	if not burning:
		fire.restore_fuel(0.0, false)
	return fire


func _make_feeder(fire: HeatSource, inventory: InventoryComponent) -> HeatSourceFeed:
	var feeder := HeatSourceFeed.new()
	feeder.heat_source = fire
	feeder._inventory = inventory
	root.add_child(feeder)
	return feeder


func _make_inventory(items: Array[StringName]) -> InventoryComponent:
	var inventory := InventoryComponent.new()
	inventory.max_carry_weight = 60.0
	root.add_child(inventory)
	for id: StringName in items:
		inventory.try_add(ItemCatalog.get_item(id))
	return inventory


## Starting a fire costs more than keeping one alive.
func _test_a_dead_fire_needs_tinder_and_wood() -> void:
	var fire := _make_fire(false)
	var inventory := _make_inventory([&"firewood"])
	var feeder := _make_feeder(fire, inventory)

	_check(feeder.item_name == tr("LIGHT_PROMPT"), "a cold stove does not advertise the light action")
	_check(feeder.description == tr("LIGHT_REQUIREMENTS"), "the cold-stove prompt does not explain tinder + firewood")
	_check(
		feeder.feed() == HeatSourceFeed.Refusal.NO_TINDER,
		"a dead fire was lit with no tinder"
	)
	_check(
		inventory.has_item(&"firewood"),
		"the refused attempt burned the firewood anyway"
	)

	inventory.try_add(ItemCatalog.get_item(&"tinder"))
	_check(feeder.feed() == HeatSourceFeed.Refusal.NONE, "tinder and wood would not light the fire")
	_check(fire.is_burning(), "the fire did not light")
	_check(not inventory.has_item(&"tinder"), "lighting the fire did not spend the tinder")
	_check(not inventory.has_item(&"firewood"), "lighting the fire did not spend the wood")
	_dispose(feeder)
	_dispose(inventory)
	_dispose(fire)


func _test_a_burning_fire_needs_only_wood() -> void:
	var fire := _make_fire(true)
	fire.restore_fuel(1.0, true)
	var inventory := _make_inventory([&"firewood"])
	var feeder := _make_feeder(fire, inventory)

	_check(feeder.feed() == HeatSourceFeed.Refusal.NONE, "a burning fire refused wood")
	_check(
		fire.get_remaining_hours() > 1.0,
		"feeding a burning fire added nothing: %.2f hours" % fire.get_remaining_hours()
	)
	_dispose(feeder)
	_dispose(inventory)
	_dispose(fire)


## An item spent on a full fire is an item thrown away.
func _test_a_full_fire_refuses_without_spending_anything() -> void:
	var fire := _make_fire(true)
	var inventory := _make_inventory([&"firewood", &"tinder"])
	var feeder := _make_feeder(fire, inventory)

	_check(
		feeder.feed() == HeatSourceFeed.Refusal.ALREADY_FULL,
		"a full fire accepted more wood"
	)
	_check(inventory.has_item(&"firewood"), "a refused feed spent the wood")
	_check(inventory.has_item(&"tinder"), "a refused feed spent the tinder")
	_dispose(feeder)
	_dispose(inventory)
	_dispose(fire)


## burn_duration_h is deliberately shorter than a night, so the fire only
## outlasts eight hours if the player feeds it.
func _test_feeding_buys_the_night() -> void:
	var unfed := _make_fire(true)
	var fed := _make_fire(true)
	var inventory := _make_inventory([&"firewood", &"firewood"])
	var feeder := _make_feeder(fed, inventory)

	## Four hours in, both fires are down to two. Only one gets fed.
	for i: int in range(8):
		unfed.advance_fuel(0.5)
		fed.advance_fuel(0.5)
	_check(fed.is_burning() and unfed.is_burning(), "a fire died inside its own duration")
	feeder.feed()
	feeder.feed()

	## Four hours more takes the night past the unfed fire's six.
	for i: int in range(8):
		unfed.advance_fuel(0.5)
		fed.advance_fuel(0.5)

	_check(not unfed.is_burning(), "an unfed fire outlasted its burn duration")
	_check(
		fed.is_burning(),
		"the fed fire went out too, with %.2f hours left" % fed.get_remaining_hours()
	)
	_check(
		fed.get_remaining_hours() > unfed.get_remaining_hours(),
		"feeding bought nothing: fed %.2f h, unfed %.2f h"
		% [fed.get_remaining_hours(), unfed.get_remaining_hours()]
	)
	_dispose(feeder)
	_dispose(inventory)
	_dispose(fed)
	_dispose(unfed)


func _test_a_dead_fire_stops_warming_the_room() -> void:
	var zone := ThermalZone.new()
	zone.max_heated_offset_c = 18.0
	zone.heating_rate_c_per_hour = 9.0
	zone.cooling_rate_c_per_hour = 6.0
	root.add_child(zone)

	var fire := _make_fire(true)
	fire.heats_zone = zone
	fire._on_burning_changed(true)

	for i: int in range(8):
		zone.advance_heating(0.5)
	var warm: float = zone.get_total_offset_c()
	_check(warm > 0.0, "a burning fire never warmed the room")

	## Burn it out, then let the room cool.
	fire.advance_fuel(10.0)
	_check(not fire.is_burning(), "the fire did not burn out")
	for i: int in range(8):
		zone.advance_heating(0.5)
	_check(
		zone.get_total_offset_c() < warm,
		"the room stayed at %.2f after the fire died" % zone.get_total_offset_c()
	)
	_dispose(fire)
	_dispose(zone)


## The prompt already knew how to warn; this is the check that the warning
## means something now that the fire can be fed.
func _test_the_sleep_prompt_warning_follows_the_fuel() -> void:
	var fire := _make_fire(true)
	fire.restore_fuel(1.0, true)
	var inventory := _make_inventory([&"firewood", &"firewood"])
	var feeder := _make_feeder(fire, inventory)

	_check(fire.get_remaining_hours() < 8.0, "the fire started with a full night in it")
	feeder.feed()
	feeder.feed()
	_check(
		fire.get_remaining_hours() > 1.0,
		"two loads of wood left only %.2f hours" % fire.get_remaining_hours()
	)
	_dispose(feeder)
	_dispose(inventory)
	_dispose(fire)


## Sleeping beside a half-burnt fire must not refill it.
func _test_fuel_survives_a_save_round_trip() -> void:
	var zone := ThermalZone.new()
	zone.name = "Cabin"
	root.add_child(zone)
	var fire := _make_fire(true)
	root.remove_child(fire)
	zone.add_child(fire)
	fire.advance_fuel(3.5)
	var half: float = fire.get_remaining_hours()

	var state := ShelterState.new()
	root.add_child(state)
	var context := WorldContext.new()
	context.world = zone
	state.on_world_ready(context)

	var saved: Dictionary = state.get_save_data()
	_check(
		SaveManager.implements_save_contract(state),
		"ShelterState no longer implements the whole save contract"
	)

	fire.ignite()
	_check(fire.get_remaining_hours() > half, "relighting did not refill the fire")
	state.load_save_data(saved)
	_check(
		is_equal_approx(fire.get_remaining_hours(), half),
		"a loaded save left %.2f hours, expected %.2f" % [fire.get_remaining_hours(), half]
	)
	_check(fire.is_burning(), "a fire that was burning came back dead")
	_dispose(state)
	_dispose(zone)
