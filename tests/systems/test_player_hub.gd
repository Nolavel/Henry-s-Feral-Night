extends SceneTree

## Player Hub (#68): the four-flap pack opens top-only or fully; the Hub opens,
## lists the real inventory and moves an item pack → pocket → pack without duplicating it.
## Run: godot --headless --script tests/systems/test_player_hub.gd

const LAYOUT: String = "res://data/equipment/player_layout.tres"

var _failures: int = 0
var _frame: int = 0


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		_test_pack_rig()
		_test_hub_flow()
		_finish()
	return false


func _test_pack_rig() -> void:
	var pack := PackRig.new()
	root.add_child(pack)
	_check(not pack.is_open(), "the pack starts open")
	pack.set_openness(PackRig.Openness.TOP_ONLY, true)
	_check(is_equal_approx(pack.get_flap_open(&"top"), 1.0), "top-only did not open the top flap")
	for side: StringName in [&"left", &"right", &"bottom"]:
		_check(is_zero_approx(pack.get_flap_open(side)), "top-only opened the %s flap" % side)
	pack.set_openness(PackRig.Openness.FULL, true)
	for flap: StringName in [&"top", &"left", &"right", &"bottom"]:
		_check(is_equal_approx(pack.get_flap_open(flap), 1.0), "full opening left the %s flap shut" % flap)
	pack.set_openness(PackRig.Openness.CLOSED, true)
	_check(is_zero_approx(pack.get_flap_open(&"left")), "closing left a flap open")
	pack.free()


func _test_hub_flow() -> void:
	var body := CharacterBody3D.new()
	var equipment := EquipmentComponent.new()
	equipment.name = "EquipmentComponent"
	equipment.layout = load(LAYOUT) as EquipmentLayout
	equipment.starter_garment_ids = [&"worn_coat", &"work_trousers", &"backpack"]
	body.add_child(equipment)
	var inventory := InventoryComponent.new()
	inventory.equipment = equipment
	body.add_child(inventory)
	var hub := PlayerHubComponent.new()
	body.add_child(hub)
	root.add_child(body)
	inventory.try_add(load("res://data/items/road_flare.tres") as ItemResource)
	inventory.try_add(load("res://data/items/bedroll.tres") as ItemResource)

	_check(hub.open(), "the Hub did not open")
	_check(hub.is_open(), "the Hub does not report open")
	var ids: Array = hub.get_pack_items().map(func(item: Dictionary) -> StringName: return item["id"])
	_check(ids.has(&"road_flare") and ids.has(&"bedroll"), "the Hub does not list the inventory: %s" % [ids])
	var zones: Array[Dictionary] = hub.get_quick_access_zones()
	var paths: Array = zones.map(func(zone: Dictionary) -> StringName: return zone["path"])
	_check(not paths.is_empty(), "no Quick Access zone is offered")
	_check(not paths.has(&"pack/pack_main"), "the main compartment is offered as Quick Access")
	var pocket: StringName = paths[0] if not paths.is_empty() else &""

	var weight: float = hub.get_weight()
	_check(hub.move_to_zone(&"bedroll", pocket) == EquipmentComponent.Refusal.TOO_LARGE,
		"a bulky bedroll went into a pocket")
	_check(inventory.has_item(&"bedroll"), "a refused bedroll left the pack")
	_check(hub.move_to_zone(&"road_flare", pocket) == EquipmentComponent.Refusal.NONE, "the flare did not go into a pocket")
	_check(not inventory.has_item(&"road_flare"), "the pocketed flare is still in the pack (duplicated)")
	_check(_zone_item(hub, pocket) == &"road_flare", "the pocket does not hold the flare")
	_check(is_equal_approx(hub.get_weight(), weight), "pocketing changed the carried weight")
	_check(hub.move_to_zone(&"road_flare", pocket) != EquipmentComponent.Refusal.NONE, "a flare no longer in the pack moved again")
	_check(hub.move_to_pack(pocket) == &"", "the flare did not return to the pack")
	_check(inventory.get_count(&"road_flare") == 1, "returning did not give back exactly one flare")
	_check(_zone_item(hub, pocket) == &"", "the pocket still holds the flare")

	_check(hub.close(), "the Hub did not close")
	_check(not hub.is_open(), "the Hub reports open after closing")
	body.free()


func _zone_item(hub: PlayerHubComponent, path: StringName) -> StringName:
	for zone: Dictionary in hub.get_quick_access_zones():
		if zone["path"] == path:
			return zone["item_id"]
	return &"?"


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)


func _finish() -> void:
	print("test_player_hub: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(1 if _failures > 0 else 0)
