extends SceneTree

## Real player components, shifted TPS projection and generated shelter collisions.
## Tests physical drop, floor pickups, staged boarding, cold loading and table eating.

var _failures: int = 0
var _scene: Node3D
var _house: Node3D
var _player: Player
var _camera: TpsCamera
var _interact: InteractComponent
var _inventory: InventoryComponent


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_scene = (load("res://scenes/world/first_exit/first_exit_blockout.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(_scene)
	_house = _scene.get_node(^"ShelterHouse/House") as Node3D
	_player = (load("res://scenes/actors/player/player.tscn") as PackedScene).instantiate() as Player
	root.add_child(_player)
	_player.set_physics_process(false)
	_interact = _player.get_node(^"InteractComponent") as InteractComponent
	_inventory = _player.get_node(^"InventoryComponent") as InventoryComponent
	_camera = (load("res://scenes/game/systems/camera/tps_camera.tscn") as PackedScene).instantiate() as TpsCamera
	_camera.player = _player
	root.add_child(_camera)
	_camera.set_process(false)
	_camera.set_physics_process(false)
	_camera.h_offset = 0.51
	_camera.current = true
	await physics_frame
	await physics_frame
	await _test_tools()
	await _test_boards()
	await _test_stove()
	await _test_table()
	await _test_drop()
	print("test_shelter_workflow: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(0 if _failures == 0 else 1)


func _test_tools() -> void:
	for node_name: String in ["HammerShelter", "NailsShelter", "LighterShelterTest"]:
		var pickup: ItemPickup = _scene.get_node(NodePath(node_name)) as ItemPickup
		_check(_house.to_local(pickup.global_position).y > 1.7, "%s is buried under the floor/bench" % node_name)
		var id: StringName = pickup.item_id
		var count: int = pickup.count
		await _aim(pickup, pickup.global_position + _house.global_basis.z * 0.8, _interact._focus_point(pickup))
		_check_target(pickup, node_name)
		_press(&"interact")
		_check(pickup.is_queued_for_deletion() and _inventory.get_count(id) == count, "%s did not pick up with real F" % node_name)
		await physics_frame
	await create_timer(0.5).timeout
	_check((_player.get_node(^"HammerComponent") as HammerComponent).can_use(&"hammer")
		or _has_pocket(&"hammer"), "picked-up hammer became inaccessible after stowing")
	var floor_item := ItemPickup.new()
	floor_item.item_id = &"lighter"
	floor_item.position = _house.to_global(Vector3(0, 0.915, 1.5))
	var col := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.3
	col.shape = sphere
	floor_item.add_child(col)
	root.add_child(floor_item)
	await _aim(floor_item, floor_item.global_position + _house.global_basis.z * 0.65 + Vector3.UP,
		_interact._focus_point(floor_item))
	_check_target(floor_item, "floor item with shifted TPS camera")
	var lighter_count: int = _inventory.get_count(&"lighter")
	_press(&"interact")
	_check(floor_item.is_queued_for_deletion() and _inventory.get_count(&"lighter") == lighter_count + 1,
		"F did not pick up a floor item through the real camera projection")


func _test_boards() -> void:
	var pickup: ItemPickup = _scene.get_node(^"BoardsShelterInside") as ItemPickup
	await _aim(pickup, pickup.global_position + _house.global_basis.z * 0.7 + Vector3.UP,
		_interact._focus_point(pickup))
	_press(&"interact")
	_check(_inventory.get_count(&"boards") == 3, "real board stack did not reach the hands")
	var breach: ShelterBreach = _house.get_node(^"ShelterZone/FrontWindow1") as ShelterBreach
	var area: BreachBoardUp = breach.get_node(^"BoardUp") as BreachBoardUp
	await _aim(area, breach.to_global(Vector3(0, -0.35, 1.45)), area.focus_anchor.global_position)
	_check_target(area, "window staging")
	_press(&"interact")
	_check(breach.get_staged_boards() == 3 and _inventory.get_count(&"boards") == 0, "F did not stage the armful")
	var stack: Node3D = breach.get_node(^"StagedBoards") as Node3D
	_check(absf(_house.to_local((stack.get_child(0) as Node3D).global_position).y - 0.94) < 0.01,
		"staged boards float above the floor")
	_press(&"interact")
	_check(area.is_placing_board(), "F did not take a board and equip the pocketed hammer")
	if not area.is_placing_board():
		return
	_check(String(area.get_interaction_prompt_data()["key"]) == "LMB", "placement still asks for F")
	var previous_nails: int = _inventory.get_count(&"nails")
	_point_camera(breach.to_global(Vector3(0, -0.43, 0)))
	area._update_preview()
	_check(area._preview_valid, "camera-centre ghost could not be placed at the real window")
	_point_camera(_camera.global_position + Vector3.UP * 4.0 + _house.global_basis.z)
	_press(&"fire")
	_check(breach.get_placed_board_positions().is_empty() and _inventory.get_count(&"nails") == previous_nails,
		"same-frame camera turn committed a stale board preview")
	_point_camera(breach.to_global(Vector3(0, -0.43, 0)))
	var wall := StaticBody3D.new()
	var wall_collision := CollisionShape3D.new()
	var wall_shape := BoxShape3D.new()
	wall_shape.size = Vector3(1.0, 1.8, 0.1)
	wall_collision.shape = wall_shape
	wall.add_child(wall_collision)
	root.add_child(wall)
	wall.global_position = _camera.project_ray_origin(root.get_visible_rect().size * 0.5).lerp(breach.global_position, 0.5)
	wall.global_basis = breach.global_basis
	await physics_frame
	area._update_preview()
	_press(&"fire")
	_check(breach.get_placed_board_positions().is_empty() and _inventory.get_count(&"nails") == previous_nails,
		"LMB placed/spent materials through an obstruction")
	wall.queue_free()
	await physics_frame
	await physics_frame
	area._update_preview()
	_press(&"fire")
	_check(breach.get_placed_board_positions().size() == 1 and breach.get_staged_boards() == 2,
		"LMB did not move one staged board onto the window")
	_check(_inventory.get_count(&"nails") == previous_nails - 2, "one placement did not consume exactly two nails")
	await physics_frame
	_interact.detect_target()
	_press(&"interact")
	_check(area.is_placing_board(), "second board could not be selected")
	_press(&"pause")
	_check(not area.is_placing_board() and breach.get_staged_boards() == 2, "cancel wasted a staged board")
	for y: float in [-0.215, 0.0]:
		await _place_board(area, y)
	(_player.get_node(^"HammerComponent") as HammerComponent).put_away()
	var next_stack: ItemPickup = _scene.get_node(^"BoardsShelterTest1") as ItemPickup
	await _aim(next_stack, next_stack.global_position + Vector3(0, 1, 0.7), _interact._focus_point(next_stack))
	_press(&"interact")
	_check(_inventory.get_count(&"boards") == 3, "next board armful could not be carried")
	await _aim(area, breach.to_global(Vector3(0, -0.35, 1.45)), area.focus_anchor.global_position)
	_press(&"interact")
	for y: float in [0.215, 0.43]:
		await _place_board(area, y)
	_check(breach.is_boarded() and breach.get_staged_boards() == 1, "five fitted boards did not seal the window and preserve the spare")
	_check(_inventory.get_count(&"nails") == previous_nails - 10, "sealing did not consume ten nails")
	(_player.get_node(^"HammerComponent") as HammerComponent).put_away()


func _place_board(area: BreachBoardUp, y: float) -> void:
	_interact.detect_target()
	_press(&"interact")
	_check(area.is_placing_board(), "next staged board did not enter the offhand")
	_point_camera(area.breach.to_global(Vector3(0, y, 0)))
	area._update_preview()
	_check(area._preview_valid, "ghost lost the visible aperture at y=%s" % y)
	_press(&"fire")
	await physics_frame
	await physics_frame


func _test_stove() -> void:
	var pickup: ItemPickup = _scene.get_node(^"FirewoodShelter") as ItemPickup
	await _aim(pickup, pickup.global_position + Vector3(0, 1, 0.7), _interact._focus_point(pickup))
	_press(&"interact")
	_check(_inventory.get_count(&"firewood") == 3, "three logs did not enter the hands")
	var feed: HeatSourceFeed = _house.get_node(^"ShelterZone/Stove/Feed") as HeatSourceFeed
	var source: HeatSource = feed.heat_source
	var stove_visual: StoveVisual = source.get_node(^"StoveVisual") as StoveVisual
	await _aim(feed, source.to_global(Vector3(1.2, 0.9, 0)), feed.focus_anchor.global_position)
	_check_target(feed, "stove with solid hull")
	_press(&"interact")
	_check(not source.is_burning() and _inventory.get_count(&"firewood") == 3, "opening consumed logs or ignited stove")
	_press(&"interact")
	_check(not source.is_burning() and is_equal_approx(source.get_remaining_hours(), 6), "cold load did not store three logs")
	_check(_inventory.get_count(&"firewood") == 0 and stove_visual.get_visible_log_count() == 3, "logs did not move from hands into firebox")
	while _inventory.has_item(&"lighter"):
		_inventory.try_remove(&"lighter")
	var before: float = source.get_remaining_hours()
	_press(&"interact")
	_check(not feed.is_acting() and is_equal_approx(source.get_remaining_hours(), before), "missing lighter spent loaded fuel")
	var feedback: String = String(feed.get_interaction_prompt_data()["detail"])
	_check(feedback == feed.tr("STOVE_NEED_LIGHTER"), "refusal did not reach the central prompt")
	_inventory.try_add(ItemCatalog.get_item(&"lighter"))
	_press(&"interact")
	_check(feed.is_acting() and not source.is_burning(), "ignition skipped the lighting act")
	feed._process(HeatSourceFeed.LIGHT_SECONDS)
	_check(source.is_burning() and stove_visual.is_glowing(), "lighting finished without flame and heat")
	var zone: ThermalZone = _house.get_node(^"ShelterZone") as ThermalZone
	var temp: float = zone.get_total_offset_c()
	zone.advance_heating(1.0 / 60.0)
	_check(zone.get_total_offset_c() > temp and zone.get_total_offset_c() < temp + 0.2,
		"room heat jumped instead of rising gradually")
	var thermal := ThermalManager.new()
	root.add_child(thermal)
	thermal._zones.append(zone)
	thermal._outdoor_air_c = -18.0
	var cluster: VitalCluster = _player.get_node(^"VitalHUD/VitalCluster") as VitalCluster
	cluster.thermal_manager = thermal
	cluster._process(0.1)
	_check(cluster._room_readout.visible and cluster._room_readout.text == cluster.tr("SHELTER_ROOM_TEMPERATURE") % thermal.get_room_temperature_c(),
		"room readout did not show the authoritative air temperature")
	thermal._zones.clear()
	cluster._process(0.1)
	_check(not cluster._room_readout.visible, "room readout remained outside the shelter")
	cluster.thermal_manager = null
	thermal.queue_free()
	var saved: float = source.get_remaining_hours()
	source.restore_fuel(saved, false)
	_check(not source.is_burning() and stove_visual.get_visible_log_count() == 3, "restored cold fuel vanished visually")
	source.restore_fuel(saved, true)


func _test_table() -> void:
	var rest: RestSpot = _house.get_node(^"ShelterZone/RestCrate/Sit") as RestSpot
	await _aim(rest, rest.focus_anchor.global_position + _house.global_basis.z * 0.75 + Vector3.UP * 0.5,
		rest.focus_anchor.global_position)
	_check_target(rest, "table ritual entry")
	_press(&"interact")
	var component: RestComponent = _player.get_node(^"RestComponent") as RestComponent
	_check(component.is_sitting(), "F on table did not sit Henry on the seat")
	var table: MealTable = _house.get_node(^"ShelterZone/RestCrate/MealTable") as MealTable
	_check(not table.get_targets().is_empty(), "sitting did not lay carried food on the cloth")
	if table.get_targets().is_empty():
		return
	var food: TableFood = table.get_targets()[0]
	_camera.global_position = _player.global_position + Vector3.UP * 0.3
	_point_camera(_interact._focus_point(food))
	await physics_frame
	_interact.detect_target()
	_check_target(food, "seated food with real projection")
	var id: StringName = food.item_id
	var previous: int = _inventory.get_count(id)
	_press(&"interact")
	_check(_inventory.get_count(id) == previous - 1, "seated F opened waiting instead of consuming food")
	_check(_interact.current_target == null, "consumed table prop left its obsolete F target active")
	_press(&"move_forward")
	_check(not component.is_sitting() and table.get_laid_ids().is_empty(), "standing left food/seat ritual active")


func _test_drop() -> void:
	_player.global_position = _house.to_global(Vector3(0, 1.95, 0))
	_inventory.try_add(ItemCatalog.get_item(&"road_flare"))
	var held: HeldLightComponent = _player.get_node(^"HeldLightComponent") as HeldLightComponent
	_check(held.light(), "drop fixture could not light flare")
	_player.animation_component.animation_tree.advance(0.3)
	var flare: HeldFlare = _player.animation_component.get_held_prop() as HeldFlare
	held.drop()
	var body: RigidBody3D = flare.get_parent() as RigidBody3D
	_check(body != null, "dropped flare has no gravity body")
	if body == null:
		return
	var initial: float = body.global_position.y
	for _i: int in range(120):
		await physics_frame
	_check(body.global_position.y < initial - 0.2, "flare stayed hanging at release height")
	var landed: float = _house.to_local(body.global_position).y
	_check(landed > 0.90 and landed < 1.05 and body.linear_velocity.length() < 0.2,
		"flare did not settle on the house floor: y=%.3f velocity=%s" % [landed, body.linear_velocity])
	_check(flare.is_burning(), "physical drop extinguished flare")


func _has_pocket(id: StringName) -> bool:
	for pocket: Dictionary in (_player.get_node(^"EquipmentComponent") as EquipmentComponent).get_available_pockets():
		if pocket["item_id"] == id:
			return true
	return false


func _aim(target: InteractiveArea, from: Vector3, point: Vector3) -> void:
	var local: Vector3 = _house.to_local(from)
	if absf(local.x) < 4.0 and absf(local.z) < 5.0:
		from.y = maxf(from.y, _house.to_global(Vector3(0, 1.91, 0)).y)
	_player.global_position = from
	_player.velocity = Vector3.ZERO
	_camera.global_position = from + Vector3.UP * 0.65
	_point_camera(point)
	await physics_frame
	await physics_frame
	_interact.detect_target()


## Lens shift translates the ray origin: looking the camera basis at a prop is insufficient.
func _point_camera(point: Vector3) -> void:
	_camera.look_at(point)
	var center: Vector2 = root.get_visible_rect().size * 0.5
	for _i: int in range(12):
		var from: Vector3 = _camera.project_ray_origin(center)
		var actual: Vector3 = _camera.project_ray_normal(center).normalized()
		var desired: Vector3 = (point - from).normalized()
		_camera.global_basis = Basis(Quaternion(actual, desired)) * _camera.global_basis


func _press(action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	root.push_input(event)
	event = InputEventAction.new()
	event.action = action
	event.pressed = false
	root.push_input(event)


func _check_target(target: InteractiveArea, context: String) -> void:
	_check(_interact.current_target == target and target.shape_cast_detected,
		"%s selected %s" % [context, _interact.current_target])


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("shelter workflow: " + message)
