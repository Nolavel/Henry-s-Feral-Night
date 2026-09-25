extends SceneTree

## Consumed world pickups (#79): pick up boards/tinder/firewood/food → save →
## rebuild the world → load: the items stay in the inventory, the authored
## pickups are gone and cannot be taken again; unrelated pickups stay.
## Run: godot --headless --script tests/systems/test_pickup_ledger.gd

const AREA_SCENE: String = "res://scenes/environment/interactive/InteractiveArea.tscn"
const TAKEN: Array[String] = ["boards_fort_1", "tinder_hut", "firewood_road", "stew_shore"]
const ITEMS: Array[String] = ["boards", "tinder", "firewood", "tinned_stew"]

var _failures: int = 0
var _frame: int = 0
var _world: Node
var _inventory: InventoryComponent
var _saved_ledger: Dictionary
var _saved_inventory: Dictionary


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		1:
			var body := CharacterBody3D.new()
			body.add_to_group(&"player")
			_inventory = InventoryComponent.new()
			_inventory.max_carry_weight = 60.0
			body.add_child(_inventory)
			root.add_child(body)
			_world = _build_world()
		3:
			for id: String in TAKEN:
				var pickup := _world.get_node(NodePath(id)) as ItemPickup
				_check(pickup.pick_up(), "%s was not picked up" % id)
			_saved_ledger = (_world.get_node(^"PickupLedger") as PickupLedger).get_save_data()
			_saved_inventory = _inventory.get_save_data()
			_check(_saved_ledger["taken"].size() == TAKEN.size(), "the ledger did not record every taken pickup")
			_world.free()
			_world = _build_world()  # a fresh load rebuilds the authored world
		5:
			_inventory.load_save_data(_saved_inventory)
			(_world.get_node(^"PickupLedger") as PickupLedger).load_save_data(_saved_ledger)
		6:
			for i: int in range(TAKEN.size()):
				_check(_world.get_node_or_null(NodePath(TAKEN[i])) == null, "%s came back after reload" % TAKEN[i])
				_check(_inventory.has_item(StringName(ITEMS[i])), "%s left the inventory on reload" % ITEMS[i])
			_check(_world.get_node_or_null(^"boards_fort_2") != null, "an untaken pickup vanished on reload")
			_check(_world.get_node_or_null(^"dropped") != null, "a pickup without a world id was removed")
			print("test_pickup_ledger: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
			quit(1 if _failures > 0 else 0)
	return false


func _build_world() -> Node:
	var world := Node3D.new()
	root.add_child(world)
	var ledger := PickupLedger.new()
	ledger.name = "PickupLedger"
	world.add_child(ledger)
	for i: int in range(TAKEN.size()):
		world.add_child(_pickup(TAKEN[i], ITEMS[i], TAKEN[i]))
	world.add_child(_pickup("boards_fort_2", "boards", "boards_fort_2"))
	world.add_child(_pickup("dropped", "boards", ""))
	return world


func _pickup(node_name: String, item_id: String, world_id: String) -> ItemPickup:
	var area: Node = (load(AREA_SCENE) as PackedScene).instantiate()
	area.set_script(load("res://scripts/environment/interactive/item_pickup.gd"))
	area.set(&"interactable_scene", null)
	area.name = node_name
	area.set(&"item_id", StringName(item_id))
	area.set(&"world_id", StringName(world_id))
	return area as ItemPickup


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)
