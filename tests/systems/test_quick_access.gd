extends SceneTree

## Quick access (#68): the wheel cycles pockets, a click uses the selected pocket's
## item through the Use contract, and a failed use puts it back in the pocket.
## Run: godot --headless --script tests/systems/test_quick_access.gd

const LAYOUT: String = "res://data/equipment/player_layout.tres"
## A stand-in item user: accepts road flares, spends one per use.
const FAKE_USER: String = """extends Node
var inventory: InventoryComponent
var uses: int = 0
var accept: bool = true
func can_use(item_id: StringName) -> bool:
	return accept and item_id == &"road_flare" and inventory.has_item(item_id)
func use(item_id: StringName) -> bool:
	uses += 1
	return inventory.try_remove(item_id)
"""

var _failures: int = 0
var _frame: int = 0


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		_run()
	return false


func _run() -> void:
	var body := CharacterBody3D.new()
	var equipment := EquipmentComponent.new()
	equipment.name = "EquipmentComponent"
	equipment.layout = load(LAYOUT) as EquipmentLayout
	equipment.starter_garment_ids = [&"worn_coat", &"work_trousers"]
	body.add_child(equipment)
	var inventory := InventoryComponent.new()
	inventory.equipment = equipment
	body.add_child(inventory)
	var hub := PlayerHubComponent.new()
	hub.name = "PlayerHubComponent"
	body.add_child(hub)
	var script := GDScript.new()
	script.source_code = FAKE_USER
	script.reload()
	var user: Node = Node.new()
	user.set_script(script)
	user.set(&"inventory", inventory)
	body.add_child(user)
	var quick := QuickAccessComponent.new()
	body.add_child(quick)
	root.add_child(body)

	var zones: Array[Dictionary] = hub.get_quick_access_zones()
	_check(zones.size() >= 2, "fewer than two pockets to cycle")
	quick.select(zones.size())
	_check(quick.get_selected_index() == 0, "selection did not wrap past the last pocket")
	quick.select(-1)
	_check(quick.get_selected_index() == zones.size() - 1, "selection did not wrap below the first pocket")

	inventory.try_add(load("res://data/items/road_flare.tres") as ItemResource)
	inventory.try_add(load("res://data/items/road_flare.tres") as ItemResource)
	var path: StringName = zones[1]["path"]
	hub.move_to_zone(&"road_flare", path)
	quick.select(0)
	_check(not quick.use_selected(), "an empty pocket used something")
	quick.select(1)
	_check(quick.use_selected(), "the pocketed flare was not used")
	_check(int(user.get(&"uses")) == 1, "the item user was not called once")
	_check(_zone_item(hub, path) == &"", "the used flare is still in its pocket")
	_check(inventory.get_count(&"road_flare") == 1, "using the pocketed flare touched the pack's flare")

	hub.move_to_zone(&"road_flare", path)
	user.set(&"accept", false)
	_check(not quick.use_selected(), "a use nobody accepts reported success")
	_check(_zone_item(hub, path) == &"road_flare", "a failed use did not put the flare back in its pocket")
	_test_eating(body, inventory, hub)
	var key := InputEventAction.new()
	key.action = &"select item slot 2"
	key.pressed = true
	var uses_before: int = int(user.get(&"uses"))
	if _zone_item(hub, path) == &"":
		hub.move_to_zone(&"road_flare", path)
	user.set(&"accept", true)
	quick._unhandled_input(key)
	_check(int(user.get(&"uses")) == uses_before, "a number key used the pocket instead of only selecting it")
	_check(quick.get_selected_index() == 1, "a number key did not select its pocket")
	for dead: StringName in [&"open inventory", &"open map", &"open health_panel", &"open craft_panel",
			&"select item slot 5", &"reload", &"secondary action", &"drop item", &"toggle camera view",
			&"use_ability_gizmo_2", &"orbit_left", &"orbit_right", &"DEBUG"]:
		_check(not InputMap.has_action(dead), "the dead input action %s is back (#76)" % dead)
	_check(not InputMap.has_action(&"toggle_flashlight"), "the temporary L action is still mapped")
	print("test_quick_access: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)


## The missing link: nothing called ConsumptionController, so Henry could not eat.
func _test_eating(body: Node, inventory: InventoryComponent, hub: PlayerHubComponent) -> void:
	var eater := ConsumptionController.new()
	eater.inventory = inventory
	eater.bio_monitor = BioMonitorManager.new()
	body.add_child(eater.bio_monitor)
	body.add_child(eater)
	inventory.try_add(load("res://data/items/tinned_stew.tres") as ItemResource)
	_check(hub.can_use(&"tinned_stew"), "carried food offers no Use")
	_check(hub.use_item(&"tinned_stew"), "Use did not eat the stew")
	_check(not inventory.has_item(&"tinned_stew"), "the eaten stew is still carried")


func _zone_item(hub: PlayerHubComponent, path: StringName) -> StringName:
	for zone: Dictionary in hub.get_quick_access_zones():
		if zone["path"] == path:
			return zone["item_id"]
	return &"?"


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)
