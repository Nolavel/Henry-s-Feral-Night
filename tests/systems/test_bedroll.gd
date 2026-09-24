extends SceneTree

## Bedroll: B spends it from the inventory into a laid roll with F — Sleep
## (a SleepSpot) and a pack prompt; packing returns it; a save restores it.
## Run: godot --headless --script tests/systems/test_bedroll.gd

var _failures: int = 0
var _frame: int = 0
var _body: CharacterBody3D
var _inventory: InventoryComponent
var _bedroll: BedrollComponent


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		1:
			_build()
			_check(not _bedroll.lay_down(), "a bedroll was laid with none in the inventory")
			_inventory.try_add(load("res://data/items/bedroll.tres") as ItemResource)
			_check(_bedroll.lay_down(), "the carried bedroll was not laid")
			_check(not _inventory.has_item(&"bedroll"), "laying did not take the bedroll out of the inventory")
			var roll: Node3D = _bedroll.get_laid_bedroll()
			_check(roll != null and roll.get_node_or_null(^"Sleep") is SleepSpot, "the laid roll offers no F — Sleep")
			_check(not _bedroll.lay_down(), "a second bedroll was laid on top of the first")
			var saved: Dictionary = _bedroll.get_save_data()
			_check(saved.has("x"), "a laid bedroll is not in the save")
			var pack := roll.get_node(^"Pack") as ItemPickup
			_check(pack != null and pack.pick_up(), "rolling it up failed")
		3:
			_check(not _bedroll.is_laid(), "the roll stayed after packing")
			_check(_inventory.has_item(&"bedroll"), "packing did not return the bedroll")
			_check(_bedroll.get_save_data().is_empty(), "a packed bedroll still saves as laid")
			_bedroll.load_save_data({"x": 1.0, "y": 0.0, "z": 2.0, "yaw": 0.5})
			_check(_bedroll.is_laid(), "loading a save did not restore the laid bedroll")
			_finish()
	return false


func _build() -> void:
	_body = CharacterBody3D.new()
	_inventory = InventoryComponent.new()
	_body.add_child(_inventory)
	_bedroll = BedrollComponent.new()
	_bedroll.inventory = _inventory
	_body.add_child(_bedroll)
	root.add_child(_body)
	## ItemPickup resolves the player's inventory through the player group.
	_body.add_to_group(&"player")


func _finish() -> void:
	if _failures > 0:
		push_error("bedroll: %d check(s) failed" % _failures)
		quit(1)
		return
	print("bedroll: all checks passed")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("bedroll: %s" % message)
