extends SceneTree

## The First Exit greybox carries the working TestScene loop: a shelter with a
## zone, breaches that board up, a stove that heats it, and scarce pickups.
## Run: godot --headless --script tests/systems/test_first_exit_route.gd

const BLOCKOUT: String = "res://scenes/world/first_exit/first_exit_blockout.tscn"

var _failures: int = 0
var _frame: int = 0
var _scene: Node


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		_scene = (load(BLOCKOUT) as PackedScene).instantiate()
		root.add_child(_scene)
	elif _frame == 3:
		_check_shelter()
		_check_building_access()
		_check_pickups()
		_finish()
	return false


func _check_shelter() -> void:
	var zone := _scene.find_child("ShelterZone", true, false) as ThermalZone
	_check(zone != null, "the shelter has no ThermalZone")
	if zone == null:
		return
	_check(zone.is_interior, "the shelter zone is not an interior")
	var breaches: Array[ShelterBreach] = zone.get_breaches()
	_check(breaches.size() == 5, "expected 5 openings, found %d" % breaches.size())
	for breach: ShelterBreach in breaches:
		_check(breach.boarded_visual != null, "%s has no boards visual" % breach.name)
		_check(breach.find_child("BoardUp", false, false) is BreachBoardUp, "%s has no board-up prompt" % breach.name)
	var before: float = zone.get_sealed_fraction()
	breaches[0].board_up()
	_check(zone.get_sealed_fraction() > before, "boarding a breach did not seal the shelter more")
	var stove := zone.find_child("Stove", false, false) as HeatSource
	_check(stove != null, "the shelter has no stove")
	if stove != null:
		_check(stove.heats_zone == zone, "the stove does not heat the shelter zone")
		_check(stove.find_child("Feed", false, false) is HeatSourceFeed, "the stove has no feed prompt")


## The route is not playable if its buildings only look enterable. Every
## veranda gets a smooth physical ramp under visible steps; every standing
## house gets a full-size F door and enough headroom for Henry's 2 m collider.
func _check_building_access() -> void:
	var houses: Array[Node] = _scene.find_children("House", "Node3D", true, false)
	_check(houses.size() == 11, "expected 11 suburb houses, found %d" % houses.size())
	for house_node: Node in houses:
		var house := house_node as Node3D
		var lot_name: String = house.get_parent().name
		var ramp := house.get_node_or_null(^"EntrySteps/EntryRamp") as MeshInstance3D
		_check(ramp != null, "%s has no walkable veranda ramp" % lot_name)
		if ramp != null:
			_check(not ramp.visible, "%s exposes the collision ramp instead of timber steps" % lot_name)
			_check(absf(rad_to_deg(ramp.rotation.x)) < 30.0, "%s entry ramp is too steep" % lot_name)
			_check(ramp.get_node_or_null(^"StaticBody3D/CollisionShape3D") != null,
				"%s entry ramp has no collision" % lot_name)
		_check(float(house.get_meta(&"entry_rise_m", 99.0)) <= 0.45,
			"%s veranda is too high above its approach" % lot_name)
		if lot_name == "LotN3":  # deliberately collapsed: no wall, no leaf
			continue
		var door := house.get_node_or_null(^"HouseDoor") as InteractiveArea
		_check(door != null and door.has_method(&"is_open"), "%s has no F-operated exterior door" % lot_name)
		_check(float(house.get_meta(&"door_width_m", 0.0)) >= 1.4,
			"%s doorway is narrower than Henry plus clearance" % lot_name)
		_check(float(house.get_meta(&"door_headroom_m", 0.0)) >= 2.2,
			"%s doorway has no standing headroom" % lot_name)
		if door != null:
			var leaf := door.get_node_or_null(^"Hinge/DoorLeaf") as MeshInstance3D
			_check(leaf != null and leaf.get_node_or_null(^"StaticBody3D/CollisionShape3D") != null,
				"%s door leaf has no matching physical collision" % lot_name)
			_check(door.get_node_or_null(^"Hinge/HandleOutside/Lever") is MeshInstance3D,
				"%s door has no visible exterior handle" % lot_name)
			_check(door.get_node_or_null(^"Hinge/HandleInside/Lever") is MeshInstance3D,
				"%s door has no visible interior handle" % lot_name)

	for shed_node: Node in _scene.find_children("Outbuilding", "Node3D", true, false):
		var shed_door := shed_node.get_node_or_null(^"HouseDoor") as InteractiveArea
		_check(shed_door != null and shed_door.has_method(&"is_open"),
			"%s outbuilding has an empty doorway" % shed_node.get_parent().name)


## Every pickup is a real item, and the route stays short of an easy answer.
func _check_pickups() -> void:
	var totals: Dictionary = {}
	for node: Node in _scene.find_children("*", "Area3D", true, false):
		var pickup := node as ItemPickup
		if pickup == null:
			continue
		_check(ItemCatalog.get_item(pickup.item_id) != null, "pickup %s holds unknown item %s" % [pickup.name, pickup.item_id])
		_check(pickup.get_signal_connection_list(&"body_entered").size() == 1,
			"pickup %s has %d body_entered connections, expected 1" % [pickup.name, pickup.get_signal_connection_list(&"body_entered").size()])
		totals[pickup.item_id] = int(totals.get(pickup.item_id, 0)) + pickup.count
	_check(int(totals.get(&"boards", 0)) < 5, "enough boards to seal every opening (%d)" % int(totals.get(&"boards", 0)))
	_check(int(totals.get(&"boards", 0)) >= 2, "too few boards to matter (%d)" % int(totals.get(&"boards", 0)))
	_check(int(totals.get(&"tinder", 0)) >= 1, "no tinder anywhere: the stove can never be lit")
	_check(int(totals.get(&"firewood", 0)) >= 2, "not enough firewood for a night")
	_check(int(totals.get(&"road_flare", 0)) == 1, "the bunker start needs exactly one road flare")
	var bedroll := _scene.get_node_or_null(^"BedrollBunker") as ItemPickup
	var flare := _scene.get_node_or_null(^"RoadFlareBunker") as ItemPickup
	_check(bedroll != null and flare != null, "bedroll or road flare is missing from the bunker start")
	if bedroll != null and flare != null:
		_check(bedroll.global_position.distance_to(flare.global_position) <= 1.0,
			"the road flare is not beside the bedroll")
		_check(flare.interactive_mesh != null and flare.interactive_mesh.name == &"RoadFlareVisual",
			"the road flare still looks like a generic loot box")


func _finish() -> void:
	if _failures > 0:
		push_error("first exit route: %d check(s) failed" % _failures)
		quit(1)
		return
	print("first exit route: all checks passed")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("first exit route: %s" % message)
