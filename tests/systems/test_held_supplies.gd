extends SceneTree

## Real player hand sockets, physical pockets, input events and floor collisions.
## Checks finite drinks, separate opening/eating, blocked G drops and axe conversion.

var _failures: int = 0
var _player: Player
var _inventory: InventoryComponent
var _hub: PlayerHubComponent
var _held: HeldItemComponent
var _wood: WoodWorkComponent
var _camera: Camera3D
var _ledger: PickupLedger
var _floor: StaticBody3D


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_floor = _box(Vector3(20, 0.2, 20), Vector3(0, -0.1, 0))
	_ledger = PickupLedger.new()
	root.add_child(_ledger)
	_player = (load("res://scenes/actors/player/player.tscn") as PackedScene).instantiate() as Player
	root.add_child(_player)
	_player.set_physics_process(false)
	_player.position = Vector3.UP
	_inventory = _player.get_node(^"InventoryComponent") as InventoryComponent
	_hub = _player.get_node(^"PlayerHubComponent") as PlayerHubComponent
	_held = _player.get_node(^"HeldItemComponent") as HeldItemComponent
	_wood = _player.get_node(^"WoodWorkComponent") as WoodWorkComponent
	_camera = Camera3D.new()
	root.add_child(_camera)
	_camera.current = true
	await physics_frame
	await physics_frame
	await _test_draw_and_drink()
	await _test_tins()
	await _test_drops()
	await _test_chop_and_restore()
	print("test_held_supplies: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(0 if _failures == 0 else 1)


func _test_draw_and_drink() -> void:
	var knife_zone: int = _pocket(&"knife")
	_press(QuickAccessComponent.DIRECT_ACTIONS[knife_zone])
	_check(_held.get_item_id() == &"knife" and _held._prop.get_parent() == _player.animation_component.get_hand_socket(),
		"quick slot did not draw the knife into the real bone socket")
	var water_zone: int = _pocket(&"water_flask")
	_inventory.try_add(ItemCatalog.get_item(&"water_flask"))
	_press(QuickAccessComponent.DIRECT_ACTIONS[water_zone])
	_check(_held.get_item_id() == &"water_flask", "selecting water left the knife in the hand")
	_check(_held._prop.get_node(^"VolumeMark") is Label3D, "held flask has no physical volume mark")
	var eater: ConsumptionController = _player.consumption_controller
	eater.bio_monitor.current_hydration = 10.0
	for id: StringName in [&"water_flask_750", &"water_flask_500", &"water_flask_250", &"water_flask_empty"]:
		_press(&"fire")
		_check(_held.get_item_id() == id and _hub.get_quick_access_zones()[water_zone]["item_id"] == id,
			"drinking lost the held flask or its physical pocket")
		var ml: int = ItemCatalog.get_item(id).water_remaining_ml
		_check((_held._prop.get_node(^"VolumeMark") as Label3D).text.contains(str(ml)), "physical volume mark is stale")
		_check(_held._hint.text.contains(str(ml)), "persistent water status is stale")
		await _end_action()
	_check(is_equal_approx(eater.bio_monitor.current_hydration, 58.0), "four sips did not supply four finite doses")
	_press(&"fire")
	_check(is_equal_approx(eater.bio_monitor.current_hydration, 58.0), "empty held flask supplied infinite water")
	_check(_inventory.get_count(&"water_flask") == 1, "drinking the pocket flask spent the duplicate in the pack")
	_press(QuickAccessComponent.DIRECT_ACTIONS[knife_zone])
	_check(_held.get_item_id() == &"knife", "empty flask could not be stowed by changing slots")
	_press(&"open hub")
	if not _hub.is_open():
		_hub.open()
	_check(_hub.is_open() and not _held.is_holding(), "opening the Hub left an orphan held prop")
	_hub.close()
	await _end_action()


func _test_tins() -> void:
	var stew_zone: int = _pocket(&"tinned_stew")
	var pack_count: int = _inventory.get_count(&"tinned_stew")
	var quick: QuickAccessComponent = _player.get_node(^"QuickAccessComponent") as QuickAccessComponent
	quick.select(stew_zone)
	_press(&"quick_use")
	_check(_held.get_item_id() == &"tinned_stew" and _inventory.get_count(&"tinned_stew") == pack_count,
		"wheel click consumed stew invisibly instead of drawing it")
	_press(&"fire")
	_check(_held.get_item_id() == &"empty_tin" and _inventory.has_item(&"empty_tin"), "eating did not leave an owned empty tin in hand")
	_check(_inventory.get_count(&"tinned_stew") == pack_count and _hub.get_quick_access_zones()[stew_zone]["item_id"] == &"",
		"held stew consumed the pack duplicate instead of its own pocket")
	_held.put_away()
	await _end_action()
	var zone: int = _pocket(&"tinned_pineapple")
	_press(QuickAccessComponent.DIRECT_ACTIONS[zone])
	_player.consumption_controller.bio_monitor.current_calories = 1000.0
	var before: float = _player.consumption_controller.bio_monitor.current_calories
	_press(&"fire")
	_check(_held.get_item_id() == &"tinned_pineapple_open", "first Use did not open the pineapple tin")
	_check(is_equal_approx(_player.consumption_controller.bio_monitor.current_calories, before), "opening also ate the fruit")
	_check(_held._prop.get_child_count() == 6, "opened tin still looks sealed")
	await _end_action()
	_press(&"fire")
	_check(_held.get_item_id() == &"empty_tin" and is_equal_approx(_player.consumption_controller.bio_monitor.current_calories, before + 300.0),
		"second Use did not eat the opened pineapple")
	_check(_owns(&"knife"), "opening spent the reusable knife")
	_held.put_away()
	await _end_action()
	_inventory.try_add(ItemCatalog.get_item(&"tinned_pineapple"))
	var path: StringName = _hub.get_quick_access_zones()[zone]["path"]
	_check(_hub.move_to_zone(&"tinned_pineapple", path) == EquipmentComponent.Refusal.NONE, "could not pocket the refusal fixture")
	for pocket: Dictionary in _hub.get_quick_access_zones():
		if pocket["item_id"] == &"knife":
			_hub.move_to_pack(pocket["path"])
	while _inventory.has_item(&"knife"):
		_inventory.try_remove(&"knife")
	_press(QuickAccessComponent.DIRECT_ACTIONS[zone])
	_press(&"fire")
	_check(_held.get_item_id() == &"tinned_pineapple" and _hub.get_quick_access_zones()[zone]["item_id"] == &"tinned_pineapple",
		"missing knife consumed or opened the sealed tin")
	_hub.move_to_pack(path)
	await process_frame
	_check(not _held.is_holding() and _player.animation_component.get_held_prop() == null,
		"moving the held item removed storage but left a stale hand prop")


func _test_drops() -> void:
	_player.global_rotation = Vector3.ZERO
	for _i: int in range(3):
		_inventory.try_add(ItemCatalog.get_item(&"firewood"))
	var trigger := Area3D.new()
	var trigger_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(5, 5, 5)
	trigger_shape.shape = box
	trigger.add_child(trigger_shape)
	root.add_child(trigger)
	await physics_frame
	_check(bool(_wood.get_drop_placement().get("valid")), "service trigger prevented a clear floor drop")
	var wall: StaticBody3D = _box(Vector3(1, 2, 0.1), Vector3(0, 1, -0.7))
	await physics_frame
	await physics_frame
	_press(&"drop_carried")
	_check(_inventory.get_count(&"firewood") == 3 and _wood._drops.is_empty(), "G lost logs through a wall: count=%d drops=%d placement=%s yaw=%s" % [_inventory.get_count(&"firewood"), _wood._drops.size(), _wood.get_drop_placement(), _player.rotation])
	wall.queue_free()
	await physics_frame
	await physics_frame
	_floor.position.y = -4.0
	await physics_frame
	await physics_frame
	_check(not _wood.drop_carried() and _inventory.get_count(&"firewood") == 3, "drop over a deep void lost logs")
	_floor.position.y = -0.1
	await physics_frame
	await physics_frame
	_press(&"drop_carried")
	_check(_inventory.get_count(&"firewood") == 0 and _wood._drops.size() == 1, "G did not put the whole armful down")
	var logs: ItemPickup = _wood._drops.back()
	_check(logs.count == 3 and absf(logs.global_position.y - 0.015) < 0.01, "dropped logs float above the floor")
	trigger.queue_free()
	await _aim_and_f(logs)
	_check(_inventory.get_count(&"firewood") == 3 and logs.is_queued_for_deletion(), "F could not recover all dropped logs")
	_wood._process(0.0)
	_check(_wood._hint.text.begins_with("G"), "pickup left the old ground-placement message active")
	for _i: int in range(3):
		_inventory.try_remove(&"firewood")
	await _end_action()


func _test_chop_and_restore() -> void:
	_player.position = Vector3.UP
	_player.global_rotation = Vector3.ZERO
	for _i: int in range(3):
		_inventory.try_add(ItemCatalog.get_item(&"boards"))
	var obstacle: StaticBody3D = _box(Vector3(0.2, 0.4, 0.3), Vector3(0.8, 0.2, -1.35))
	await physics_frame
	await physics_frame
	_check(not _wood.drop_carried() and _inventory.get_count(&"boards") == 3, "drop ignored the wide board stack clearance")
	obstacle.queue_free()
	await physics_frame
	await physics_frame
	_press(&"drop_carried")
	var boards: ItemPickup = _wood._drops.back()
	_check(boards.item_id == &"boards" and not _wood.begin_chop(boards), "boards converted without a drawn axe")
	var zone: int = _pocket(&"axe")
	_press(QuickAccessComponent.DIRECT_ACTIONS[zone])
	_check(_held.get_item_id() == &"axe", "hatchet did not appear in the hand")
	await _aim_and_f(boards)
	_check(_wood.is_chopping(boards), "F on boards with the axe did not start chopping")
	_held.put_away()
	_wood._process(WoodWorkComponent.CHOP_SECONDS)
	_check(not boards.is_queued_for_deletion() and not _ledger.is_taken(boards.world_id), "interrupted chopping spent the boards")
	await _end_action()
	_press(QuickAccessComponent.DIRECT_ACTIONS[zone])
	await _aim_and_f(boards)
	_check(_wood.is_chopping(boards) and _held.get_item_id() == &"axe", "second F did not restart the chop: work=%s hand=%s" % [_wood._work_left, _held.get_item_id()])
	_wood._process(WoodWorkComponent.CHOP_SECONDS)
	_check(boards.is_queued_for_deletion() and _ledger.is_taken(boards.world_id), "finished chopping left reusable source boards")
	var logs: ItemPickup = _wood._drops.back()
	_check(logs.item_id == &"firewood" and logs.count == 3, "three boards did not yield exactly three logs: item=%s count=%d hand=%s drops=%d" % [logs.item_id, logs.count, _held.get_item_id(), _wood._drops.size()])
	var saved: Dictionary = JSON.parse_string(JSON.stringify(_wood.get_save_data()))
	var inventory_before_pickup: Dictionary = _inventory.get_save_data()
	_check(saved["piles"].size() == 1, "chopped boards remained in the loose-wood save")
	_held.put_away()
	await _end_action()
	await _aim_and_f(logs)
	_check(_inventory.get_count(&"firewood") == 3, "chopped firewood could not be picked up")
	var collected: Dictionary = _ledger.get_save_data()
	_wood.load_save_data(saved)
	_ledger.load_save_data(collected)
	await process_frame
	_check(_wood._drops.is_empty(), "collected loose logs duplicated on restore")
	_wood.load_save_data(saved)
	_inventory.load_save_data(inventory_before_pickup)
	_ledger.load_save_data({"taken": []})
	await process_frame
	_check(_wood._drops.size() == 1 and _wood._drops[0].count == 3, "older save lost its logs when the ledger restored last")
	_check(_inventory.get_count(&"firewood") == 0, "older-save restore duplicated the same wood in hands and on the floor")
	_wood.load_save_data(saved)
	_wood.load_save_data(saved)
	await process_frame
	_check(_wood._drops.size() == 1, "repeated restore duplicated a pile")


func _pocket(id: StringName) -> int:
	_held.put_away()
	_inventory.try_add(ItemCatalog.get_item(id))
	var zones: Array[Dictionary] = _hub.get_quick_access_zones()
	for i: int in range(mini(4, zones.size())):
		if zones[i]["item_id"] == &"" and _hub.move_to_zone(id, zones[i]["path"]) == EquipmentComponent.Refusal.NONE:
			return i
	_check(false, "no fitting direct-access pocket for %s" % id)
	return 0


func _owns(id: StringName) -> bool:
	if _inventory.has_item(id):
		return true
	for zone: Dictionary in _hub.get_quick_access_zones():
		if zone["item_id"] == id:
			return true
	return false


func _aim_and_f(target: ItemPickup) -> void:
	_player.global_position = target.global_position + Vector3(0, 1, 0.7)
	_camera.global_position = _player.global_position + Vector3.UP * 0.65
	_camera.look_at(target.global_position + Vector3.UP * 0.15)
	await physics_frame
	await physics_frame
	var interact: InteractComponent = _player.get_node(^"InteractComponent") as InteractComponent
	interact.detect_target()
	_check(interact.current_target == target, "camera did not focus the loose wood")
	_press(&"interact")


## Advance action clips only; the fixture keeps locomotion fixed around real physics bodies.
func _end_action() -> void:
	_player._hold_until_ms = 0
	_player.animation_component.animation_tree.set("parameters/actions/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
	_player.animation_component.animation_tree.advance(0.01)
	_player.animation_component.animation_tree.advance(5.0)
	await process_frame


func _box(size: Vector3, at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	root.add_child(body)
	body.position = at
	return body


func _press(action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	root.push_input(event)
	event = InputEventAction.new()
	event.action = action
	event.pressed = false
	root.push_input(event)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("held supplies: " + message)
