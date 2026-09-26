extends SceneTree

## Stove-top warming (#42): a carried tin goes on the ring, warms only while the
## stove burns, becomes hot stew, and is eaten straight off the stove.
## Run: godot --headless --script tests/systems/test_stove_warmer.gd

var _failures: int = 0
var _frame: int = 0


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		var stove := HeatSource.new()
		stove.starts_burning = false
		root.add_child(stove)
		var warmer := StoveWarmer.new()
		stove.add_child(warmer)
		var body := CharacterBody3D.new()
		body.add_to_group(&"player")
		var inventory := InventoryComponent.new()
		body.add_child(inventory)
		var eater := ConsumptionController.new()
		eater.name = "ConsumptionController"
		eater.inventory = inventory
		eater.bio_monitor = BioMonitorManager.new()
		body.add_child(eater.bio_monitor)
		body.add_child(eater)
		root.add_child(body)
		inventory.try_add(load("res://data/items/tinned_stew.tres") as ItemResource)

		_check(not warmer.can_interact_with(body), "the ring offers warming on a cold stove")
		stove.ignite()
		_check(warmer.can_interact_with(body), "a burning stove does not offer to warm the carried tin")
		warmer.interact_with(body)
		_check(warmer.get_state() == StoveWarmer.State.WARMING, "F did not put the tin on the ring")
		_check(not inventory.has_item(&"tinned_stew"), "the tin on the ring is still in the pack")
		stove.extinguish()
		stove.advance_fuel(2.0)
		_check(warmer.get_state() == StoveWarmer.State.WARMING, "the tin warmed on a cold stove")
		stove.ignite()
		stove.advance_fuel(0.6)
		_check(warmer.get_state() == StoveWarmer.State.READY and warmer.get_item_id() == &"tinned_stew_hot",
			"the tin did not become hot stew after warming")
		warmer.interact_with(body)
		_check(warmer.get_state() == StoveWarmer.State.EMPTY, "eating did not clear the ring")
		_check(inventory.has_item(&"empty_tin"), "eating the hot stew left no empty tin")
		inventory.try_add(load("res://data/items/mug_snow.tres") as ItemResource)
		warmer.interact_with(body)
		_check(warmer.get_item_id() == &"mug_snow", "the mug of snow would not go on the ring")
		stove.advance_fuel(0.6)
		_check(warmer.get_state() == StoveWarmer.State.READY and warmer.get_item_id() == &"warm_water_mug",
			"the mug of snow did not become warm water")
		warmer.interact_with(body)
		_check(inventory.has_item(&"mug"), "drinking warm water did not return the empty mug")
		var saved: Dictionary = warmer.get_save_data()
		warmer.load_save_data({"state": 1, "item": "snow_handful", "progress": 0.1})
		_check(warmer.get_state() == StoveWarmer.State.WARMING and warmer.get_item_id() == &"snow_handful",
			"a saved warming ring did not restore")
		_check(int(saved["state"]) == 0, "an empty ring saved as busy")
		print("test_stove_warmer: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
		quit(1 if _failures > 0 else 0)
	return false


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)
