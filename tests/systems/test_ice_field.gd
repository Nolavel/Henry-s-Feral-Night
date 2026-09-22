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
	var mid: float = field.get_base_thickness(field.world_to_tile(_sea_point(50.0)))
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
	var here: Vector3 = _sea_point(60.0)
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
	## No crouch action exists in the project, so CROUCH must never be reported.
	_check(
		binder.classify(Vector3(1.0, 0.0, 0.0)) != IceField.Gait.CROUCH,
		"CROUCH was reported although no crouch action is bound"
	)
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
