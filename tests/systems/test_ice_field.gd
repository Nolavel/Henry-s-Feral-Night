extends SceneTree

## Covers the frozen sea: thickness from shore, the load/recovery balance, the
## feedback ladder, the active window, and falling through into cold water.
## Run: godot --headless --script tests/systems/test_ice_field.gd

var _failures: int = 0


## A 100m square island centred on the origin.
func _island() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(-50.0, -50.0), Vector2(50.0, -50.0), Vector2(50.0, 50.0), Vector2(-50.0, 50.0)
	])


## Nodes added to root during _initialize() are not in the tree, so transforms
## and _ready() are both unavailable there. Running from the first frame puts
## the suite in the same conditions as the running game.
func _process(_delta: float) -> bool:
	_run()
	return true


func _run() -> void:
	_test_a_full_pack_loads_the_ice_harder()
	_test_a_loaded_walk_still_crosses_the_bay()
	_test_holes_survive_a_save_round_trip()
	_test_sprinting_the_bay_breaks_walking_it_does_not()
	_test_ice_thins_with_distance_from_shore()
	_test_land_is_not_ice()
	_test_standing_still_drains_slower_than_sprinting()
	_test_the_ladder_creaks_before_it_cracks()
	_test_a_tile_breaks_once_and_stays_broken()
	_test_leaving_a_tile_lets_it_recover()
	_test_the_active_window_is_bounded()
	_test_falling_through_soaks_and_chills()
	_test_climbing_out_requires_thrashing_first()
	_test_gait_follows_velocity()
	_test_gait_reaches_the_field()
	if _failures > 0:
		push_error("ice: %d check(s) failed" % _failures)
		quit(1)
		return
	print("ice: all checks passed")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("ice: %s" % message)


func _dispose(node: Node) -> void:
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	node.free()


func _make_field() -> IceField:
	var field := IceField.new()
	field.profile = load("res://resources/ice/bay_ice.tres") as IceProfile
	field.shore_polygon = _island()
	root.add_child(field)
	return field


## A point that many metres out to sea from the island edge.
func _sea_point(metres_out: float) -> Vector3:
	return Vector3(50.0 + metres_out, 0.0, 0.0)


func _test_ice_thins_with_distance_from_shore() -> void:
	var field := _make_field()
	var near: float = field.get_base_thickness(field.world_to_tile(_sea_point(4.0)))
	## Inside the gradient: past thinnest_from_m every tile sits on the floor.
	var mid: float = field.get_base_thickness(field.world_to_tile(_sea_point(16.0)))
	var far: float = field.get_base_thickness(field.world_to_tile(_sea_point(200.0)))

	_check(is_equal_approx(near, 1.0), "ice next to the shore was not solid: %.2f" % near)
	_check(mid < near, "ice did not thin with distance")
	_check(far < mid, "far ice was not thinner than mid ice")
	_check(
		far >= field.profile.minimum_thickness - 0.001,
		"far ice fell below the minimum thickness"
	)
	_dispose(field)


func _test_land_is_not_ice() -> void:
	var field := _make_field()
	_check(
		field.distance_to_shore(Vector2.ZERO) < 0.0,
		"a point in the middle of the island was not reported as land"
	)
	_check(
		field.distance_to_shore(Vector2(200.0, 0.0)) > 0.0,
		"a point far out to sea was reported as land"
	)
	_dispose(field)


func _test_standing_still_drains_slower_than_sprinting() -> void:
	var still := _make_field()
	var position: Vector3 = _sea_point(60.0)
	still.set_gait(IceField.Gait.STILL)
	still.step(position, 1.0)
	var still_value: float = still.get_integrity(still.world_to_tile(position))
	_dispose(still)

	var sprinting := _make_field()
	sprinting.set_gait(IceField.Gait.SPRINT)
	sprinting.step(position, 1.0)
	var sprint_value: float = sprinting.get_integrity(sprinting.world_to_tile(position))

	_check(sprint_value < still_value, "sprinting did not load the ice harder than standing")
	_dispose(sprinting)

	var crouching := _make_field()
	crouching.set_gait(IceField.Gait.CROUCH)
	crouching.step(position, 1.0)
	_check(
		crouching.get_integrity(crouching.world_to_tile(position)) > still_value,
		"crouching did not load the ice more gently than standing"
	)
	_dispose(crouching)


## Audio must land before visuals: the player always gets a warning they can act on.
func _test_the_ladder_creaks_before_it_cracks() -> void:
	var field := _make_field()
	var position: Vector3 = _sea_point(60.0)
	var tile: Vector2i = field.world_to_tile(position)
	var seen: Array[int] = []
	field.stage_changed.connect(
		func(changed: Vector2i, stage: IceField.Stage) -> void:
			if changed == tile:
				seen.append(int(stage))
	)

	field.set_gait(IceField.Gait.WALK)
	for i: int in range(400):
		field.step(position, 0.1)
		if field.is_broken(tile):
			break

	_check(seen.size() >= 3, "the ladder did not report every stage: %s" % str(seen))
	if seen.size() >= 3:
		_check(
			seen[0] == int(IceField.Stage.CREAKING),
			"the first warning was not a creak; audio must precede visuals"
		)
		_check(seen[1] == int(IceField.Stage.CRACKING), "cracking did not follow creaking")
		_check(
			seen[seen.size() - 1] == int(IceField.Stage.BROKEN),
			"the tile never reported breaking"
		)
	_dispose(field)


func _test_a_tile_breaks_once_and_stays_broken() -> void:
	var field := _make_field()
	var position: Vector3 = _sea_point(80.0)
	var tile: Vector2i = field.world_to_tile(position)
	## Lambdas capture local primitives by value, so the counter must be a
	## reference type or the increments never leave the closure.
	var breaks: Array[Vector2i] = []
	field.tile_broke.connect(
		func(broken: Vector2i, _where: Vector3) -> void:
			if broken == tile:
				breaks.append(broken)
	)

	field.set_gait(IceField.Gait.SPRINT)
	for i: int in range(600):
		field.step(position, 0.1)

	_check(breaks.size() == 1, "the tile broke %d times instead of once" % breaks.size())
	_check(field.is_broken(tile), "the tile did not stay broken")
	_check(is_zero_approx(field.get_integrity(tile)), "a broken tile still reports integrity")
	_dispose(field)


func _test_leaving_a_tile_lets_it_recover() -> void:
	var field := _make_field()
	## Thick enough that three seconds of walking loads it without breaking it.
	var here: Vector3 = _sea_point(16.0)
	var tile: Vector2i = field.world_to_tile(here)

	field.set_gait(IceField.Gait.WALK)
	for i: int in range(30):
		field.step(here, 0.1)
	var loaded: float = field.get_integrity(tile)
	_check(loaded < field.get_base_thickness(tile), "walking did not load the tile at all")

	## Step to a neighbour inside the same active window.
	var away: Vector3 = here + Vector3(field.profile.tile_size_m, 0.0, 0.0)
	field.set_gait(IceField.Gait.STILL)
	for i: int in range(200):
		field.step(away, 0.1)

	_check(
		field.get_integrity(tile) > loaded,
		"the abandoned tile did not recover any integrity"
	)
	_check(
		field.get_integrity(tile) <= field.get_base_thickness(tile) + 0.001,
		"the tile recovered past its natural thickness"
	)
	_dispose(field)


## The window must stay constant, or a large bay would cost more than a small one.
func _test_the_active_window_is_bounded() -> void:
	var field := _make_field()
	field.step(_sea_point(60.0), 0.1)
	var near_count: int = field.get_active_tiles().size()
	field.step(_sea_point(4000.0), 0.1)
	var far_count: int = field.get_active_tiles().size()

	var radius: int = field.profile.active_radius_tiles
	var expected: int = (radius * 2 + 1) * (radius * 2 + 1)
	_check(near_count == expected, "the active window was %d, expected %d" % [near_count, expected])
	_check(far_count == expected, "the active window grew with distance from shore")
	_dispose(field)


func _test_falling_through_soaks_and_chills() -> void:
	var field := _make_field()
	var thermal := ThermalManager.new()
	thermal.ambient_min_c = -18.0
	thermal.ambient_max_c = -18.0
	root.add_child(thermal)
	thermal.initialize()

	var water := ColdWaterImmersion.new()
	water.ice_field = field
	water.thermal_manager = thermal
	root.add_child(water)
	water._ready()

	var position: Vector3 = _sea_point(80.0)
	field.set_gait(IceField.Gait.SPRINT)
	for i: int in range(600):
		field.step(position, 0.1)
		if water.is_submerged():
			break

	_check(water.is_submerged(), "breaking through the ice did not put the player in the water")
	_check(is_equal_approx(thermal.get_wetness(), 1.0), "falling in did not soak the clothing")

	var before: float = thermal.get_body_temperature_c()
	water.step(1.0, 0.1)
	_check(
		thermal.get_body_temperature_c() < before,
		"time in freezing water cost no body heat"
	)
	_check(not field._enabled, "the ice kept simulating while the player was in the water")

	_dispose(water)
	_dispose(thermal)
	_dispose(field)


## Climbing out is deliberately not instant; the thrash is the story beat.
## The binder is what makes sprinting across the ice actually cost more.
func _test_gait_follows_velocity() -> void:
	var field := _make_field()
	var binder := IceGaitBinder.new()
	binder.ice_field = field
	root.add_child(binder)

	_check(
		binder.classify(Vector3.ZERO) == IceField.Gait.STILL,
		"a stationary body was not reported as still"
	)
	_check(
		binder.classify(Vector3(3.0, 0.0, 0.0)) == IceField.Gait.WALK,
		"walking speed was not reported as a walk"
	)
	_check(
		binder.classify(Vector3(7.5, 0.0, 0.0)) == IceField.Gait.SPRINT,
		"sprinting speed was not reported as a sprint"
	)
	_check(
		binder.classify(Vector3(0.0, -9.0, 0.0)) == IceField.Gait.STILL,
		"falling was mistaken for horizontal movement"
	)
	var movement := MovementController.new()
	root.add_child(movement)
	binder.movement_controller = movement
	movement.set_crouching(true)
	_check(
		binder.classify(Vector3(1.0, 0.0, 0.0)) == IceField.Gait.CROUCH,
		"the real crouch state did not reach IceField.Gait.CROUCH"
	)
	movement.set_crouching(false)
	_check(
		binder.classify(Vector3(1.0, 0.0, 0.0)) == IceField.Gait.WALK,
		"leaving crouch did not restore the walking gait"
	)
	_dispose(movement)
	_dispose(binder)
	_dispose(field)


func _test_gait_reaches_the_field() -> void:
	var walking := _make_field()
	var position: Vector3 = _sea_point(60.0)
	var walk_binder := IceGaitBinder.new()
	walk_binder.ice_field = walking
	root.add_child(walk_binder)
	walk_binder.apply(Vector3(3.0, 0.0, 0.0))
	walking.step(position, 1.0)
	var walked: float = walking.get_integrity(walking.world_to_tile(position))
	_dispose(walk_binder)
	_dispose(walking)

	var sprinting := _make_field()
	var sprint_binder := IceGaitBinder.new()
	sprint_binder.ice_field = sprinting
	root.add_child(sprint_binder)
	sprint_binder.apply(Vector3(7.5, 0.0, 0.0))
	sprinting.step(position, 1.0)

	_check(
		sprinting.get_integrity(sprinting.world_to_tile(position)) < walked,
		"sprinting through the binder did not load the ice harder than walking"
	)
	_dispose(sprint_binder)
	_dispose(sprinting)


func _test_climbing_out_requires_thrashing_first() -> void:
	var field := _make_field()
	var water := ColdWaterImmersion.new()
	water.ice_field = field
	root.add_child(water)
	water._ready()

	water.submerge(_sea_point(80.0))
	_check(not water.can_climb_out(), "the player could climb out instantly")
	_check(not water.climb_out(Vector3.ZERO), "climb_out succeeded before the delay")

	water.step(field.profile.climb_out_delay_s + 0.1, 0.0)
	_check(water.can_climb_out(), "the player could not climb out after thrashing")
	_check(water.climb_out(Vector3.ZERO), "climb_out failed after the delay")
	_check(not water.is_submerged(), "the player stayed submerged after climbing out")
	_check(field._enabled, "the ice did not resume simulating after climbing out")
	_dispose(water)
	_dispose(field)


## The author's call in issue #7: the bay is a real gamble at a sprint and a
## safe, slow crossing on foot. Same bay and route as capture_ice_map.gd.
func _test_sprinting_the_bay_breaks_walking_it_does_not() -> void:
	var walk: float = _cross_bay(IceField.Gait.WALK, 1.5)
	var sprint: float = _cross_bay(IceField.Gait.SPRINT, 4.5)
	_check(walk < 0.0, "walking the bay broke through at %.0f m" % walk)
	_check(sprint >= 0.0, "sprinting the bay survived, so the shortcut is free")
	## Mid-bay, not at the first step off the shore.
	_check(sprint > 20.0, "sprint broke only %.0f m in, at the shoreline" % sprint)


## Metres along the bay route where the ice gave way, or -1.0 if it held.
func _cross_bay(gait: IceField.Gait, speed_mps: float) -> float:
	var field := IceField.new()
	field.profile = load("res://resources/ice/bay_ice.tres") as IceProfile
	field.shore_polygon = PackedVector2Array([
		Vector2(-90.0, -80.0), Vector2(60.0, -95.0), Vector2(85.0, -30.0),
		Vector2(5.0, -12.0), Vector2(0.0, 30.0), Vector2(80.0, 42.0),
		Vector2(70.0, 95.0), Vector2(-85.0, 85.0),
	])
	root.add_child(field)
	var route := PackedVector2Array([Vector2(78.0, -34.0), Vector2(96.0, 6.0), Vector2(74.0, 46.0)])
	var broke: Array[bool] = []
	field.tile_broke.connect(func(_tile: Vector2i, _where: Vector3) -> void: broke.append(true))
	field.set_gait(gait)

	var total: float = route[0].distance_to(route[1]) + route[1].distance_to(route[2])
	var travelled: float = 0.0
	var result: float = -1.0
	while travelled < total:
		travelled += speed_mps * 0.1
		var remaining: float = travelled
		var point: Vector2 = route[route.size() - 1]
		for i: int in range(route.size() - 1):
			var length: float = route[i].distance_to(route[i + 1])
			if remaining <= length:
				point = route[i].lerp(route[i + 1], remaining / length)
				break
			remaining -= length
		field.step(Vector3(point.x, 0.0, point.y), 0.1)
		if not broke.is_empty():
			result = travelled
			break
	_dispose(field)
	return result


## Sleep is the only save, so a hole that heals on load would undo a fall. And
## loading must not re-announce the break, or Henry falls in again.
func _test_holes_survive_a_save_round_trip() -> void:
	var field := _make_field()
	_check(field.is_in_group(IceField.SAVEABLE_GROUP), "the ice field is not in the saveable group")
	_check(SaveManager.implements_save_contract(field), "the ice field does not implement the save contract")

	var hole: Vector3 = _sea_point(60.0)
	var hole_tile: Vector2i = field.world_to_tile(hole)
	field.set_gait(IceField.Gait.WALK)
	for i: int in range(400):
		field.step(hole, 0.1)
		if field.is_broken(hole_tile):
			break
	_check(field.is_broken(hole_tile), "the test could not break a tile")

	var worn: Vector3 = _sea_point(16.0)
	var worn_tile: Vector2i = field.world_to_tile(worn)
	for i: int in range(10):
		field.step(worn, 0.1)
	var worn_integrity: float = field.get_integrity(worn_tile)
	var saved: Dictionary = field.get_save_data()
	_dispose(field)

	var fresh := _make_field()
	var fell: Array[bool] = []
	fresh.tile_broke.connect(func(_t: Vector2i, _w: Vector3) -> void: fell.append(true))
	fresh.load_save_data(saved)
	_check(fresh.is_broken(hole_tile), "a loaded save healed the hole in the ice")
	_check(
		is_equal_approx(fresh.get_integrity(worn_tile), worn_integrity),
		"worn ice came back at %.3f, saved at %.3f" % [fresh.get_integrity(worn_tile), worn_integrity]
	)
	_check(fell.is_empty(), "loading the save announced a break, dropping Henry in again")
	_dispose(fresh)


func _loaded_binder(fraction: float) -> IceGaitBinder:
	var binder := IceGaitBinder.new()
	var inventory := InventoryComponent.new()
	inventory.max_carry_weight = 30.0
	root.add_child(inventory)
	var firewood: ItemResource = ItemCatalog.get_item(&"firewood")
	while inventory.get_total_weight() + firewood.weight <= 30.0 * fraction + 0.001:
		inventory.try_add(firewood)
	binder.inventory = inventory
	root.add_child(binder)
	return binder


## Weight is the price of carrying: the same step drains more from a full pack.
func _test_a_full_pack_loads_the_ice_harder() -> void:
	var drained: Array[float] = []
	for fraction: float in [0.0, 1.0]:
		var field := _make_field()
		var binder := _loaded_binder(fraction)
		binder.ice_field = field
		binder.apply(Vector3(4.0, 0.0, 0.0))
		var here: Vector3 = _sea_point(16.0)
		var tile: Vector2i = field.world_to_tile(here)
		var before: float = field.get_integrity(tile)
		field.step(here, 0.5)
		drained.append(before - field.get_integrity(tile))
		_dispose(binder.inventory)
		_dispose(binder)
		_dispose(field)
	_check(drained[1] > drained[0] * 1.3, "a full pack drained %.4f, an empty one %.4f" % [drained[1], drained[0]])


## The price must not make the bay impassable: a loaded walk cracks but holds.
func _test_a_loaded_walk_still_crosses_the_bay() -> void:
	var binder := _loaded_binder(1.0)
	var multiplier: float = binder.get_load_multiplier()
	_dispose(binder.inventory)
	_dispose(binder)
	var profile := load("res://resources/ice/bay_ice.tres") as IceProfile
	## One 4 m tile at 4 m/s is a second under load; it must not reach zero.
	var per_tile: float = profile.drain_per_second * profile.walk_multiplier * multiplier * 1.0
	_check(
		per_tile < profile.minimum_thickness,
		"a loaded walk drains %.3f per tile from %.3f ice: the bay is closed to anyone carrying"
		% [per_tile, profile.minimum_thickness]
	)
