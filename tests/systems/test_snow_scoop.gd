extends SceneTree

## Empty mug -> mug of snow, without a second inventory.
## Run: godot --headless --script tests/systems/test_snow_scoop.gd

var _failures: int = 0
var _frame: int = 0


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame != 1:
		return false
	var body := CharacterBody3D.new()
	var inventory := InventoryComponent.new()
	body.add_child(inventory)
	var scoop := SnowScoopComponent.new()
	scoop.inventory = inventory
	body.add_child(scoop)
	root.add_child(body)

	inventory.try_add(load("res://data/items/mug.tres") as ItemResource)
	_check(scoop.can_use(&"mug"), "an empty mug cannot scoop snow outdoors")
	_check(scoop.use(&"mug"), "using the empty mug did not scoop snow")
	_check(not inventory.has_item(&"mug") and inventory.has_item(&"mug_snow"),
		"the empty mug was not replaced by a mug of snow")
	_check(not scoop.use(&"mug"), "snow was scooped without another empty mug")

	print("test_snow_scoop: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)
	return false


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)
