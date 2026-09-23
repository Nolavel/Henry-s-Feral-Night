extends SceneTree

## Covers foot contact and the prints it leaves: one print per step, the right
## foot's print for the right foot, toe pointing where the foot points.
## Run: godot --headless --script tests/systems/test_footprints.gd

var _failures: int = 0


func _process(_delta: float) -> bool:
	_run()
	return true


func _run() -> void:
	_test_a_step_plants_once()
	_test_standing_still_leaves_nothing()
	_test_the_air_leaves_nothing()
	_test_the_rig_has_the_bones()
	_test_prints_point_heel_to_toe()
	_test_each_foot_leaves_its_own_print()
	_test_the_pool_reuses_the_oldest()
	_test_snowfall_buries_the_trail_faster()
	if _failures > 0:
		push_error("footprints: %d check(s) failed" % _failures)
		quit(1)
		return
	print("footprints: all checks passed")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("footprints: %s" % message)


func _dispose(node: Node) -> void:
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	node.free()


func _sensor() -> FootContactSensor:
	var sensor := FootContactSensor.new()
	root.add_child(sensor)
	return sensor


## Walks one foot through a stride: up, down, and held on the ground.
func _stride(sensor: FootContactSensor, side: int, on_floor: bool, speed: float) -> int:
	var planted: int = 0
	for height: float in [0.2, 0.12, 0.05, 0.02, 0.01, 0.01, 0.02]:
		if sensor.update_foot(side, height, Vector3.ZERO, Vector3.FORWARD, on_floor, speed):
			planted += 1
	return planted


func _test_a_step_plants_once() -> void:
	var sensor := _sensor()
	_check(_stride(sensor, FootContactSensor.Side.LEFT, true, 1.5) == 1, "one stride did not plant exactly once")
	_check(_stride(sensor, FootContactSensor.Side.LEFT, true, 1.5) == 1, "the second stride did not plant again")
	_dispose(sensor)


func _test_standing_still_leaves_nothing() -> void:
	var sensor := _sensor()
	_check(_stride(sensor, FootContactSensor.Side.RIGHT, true, 0.1) == 0, "shuffling on the spot left a print")
	_dispose(sensor)


func _test_the_air_leaves_nothing() -> void:
	var sensor := _sensor()
	_check(_stride(sensor, FootContactSensor.Side.RIGHT, false, 4.0) == 0, "a foot in the air left a print")
	_dispose(sensor)


## The rule is worthless if the real rig names its bones differently.
func _test_the_rig_has_the_bones() -> void:
	var model := (load("res://assets/models/characters/henry_ual/Henry_UAL_Rigged.glb") as PackedScene).instantiate()
	root.add_child(model)
	var skeleton: Skeleton3D = _find_skeleton(model)
	_check(skeleton != null, "Henry's rig has no skeleton")
	if skeleton != null:
		for side: int in FootContactSensor.BONES:
			for bone: StringName in FootContactSensor.BONES[side].values():
				_check(skeleton.find_bone(bone) >= 0, "Henry's rig has no bone '%s'" % bone)
	_dispose(model)


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child: Node in node.get_children():
		var found: Skeleton3D = _find_skeleton(child)
		if found != null:
			return found
	return null


func _prints() -> FootprintSystem:
	var system := FootprintSystem.new()
	root.add_child(system)
	return system


## A decal maps the top of its image to its -Z; the image has the toe at the top.
func _test_prints_point_heel_to_toe() -> void:
	var system := _prints()
	var toe := Vector3(1.0, 0.0, 0.0)
	var decal: Decal = system.stamp(FootContactSensor.Side.LEFT, Vector3(3.0, 0.0, 4.0), toe)
	var minus_z: Vector3 = -decal.global_transform.basis.z.normalized()
	_check(minus_z.dot(toe) > 0.99, "the print's toe points %s, the foot points %s" % [str(minus_z), str(toe)])
	_check(decal.global_transform.basis.y.normalized().dot(Vector3.UP) > 0.99, "the print does not project straight down")
	_check(decal.global_position.distance_to(Vector3(3.0, 0.05, 4.0)) < 0.01, "the print is not where the foot landed")
	_dispose(system)


func _test_each_foot_leaves_its_own_print() -> void:
	var system := _prints()
	var left: Decal = system.stamp(FootContactSensor.Side.LEFT, Vector3.ZERO, Vector3.FORWARD)
	var right: Decal = system.stamp(FootContactSensor.Side.RIGHT, Vector3.ZERO, Vector3.FORWARD)
	_check(left.texture_albedo == FootprintSystem.LEFT_PRINT, "the left foot left the wrong print")
	_check(right.texture_albedo == FootprintSystem.RIGHT_PRINT, "the right foot left the wrong print")
	_dispose(system)


func _test_the_pool_reuses_the_oldest() -> void:
	var system := _prints()
	system.pool_size = 8
	var first: Decal = system.stamp(FootContactSensor.Side.LEFT, Vector3.ZERO, Vector3.FORWARD)
	for i: int in range(7):
		system.stamp(FootContactSensor.Side.RIGHT, Vector3(float(i), 0.0, 0.0), Vector3.FORWARD)
	var ninth: Decal = system.stamp(FootContactSensor.Side.LEFT, Vector3(50.0, 0.0, 0.0), Vector3.FORWARD)
	_check(ninth == first, "a full pool did not reuse its oldest print")
	_check(system.get_child_count() == 8, "the pool grew past its size: %d" % system.get_child_count())
	_dispose(system)


func _test_snowfall_buries_the_trail_faster() -> void:
	var calm := _prints()
	var storm := _prints()
	var weather := WeatherController.new()
	weather.profiles = WeatherController.load_profiles_from("res://resources/weather")
	weather.starting_profile_id = &"blizzard"
	weather.scheduler_enabled = false
	root.add_child(weather)
	weather.initialize()
	storm._weather = weather

	calm.stamp(FootContactSensor.Side.LEFT, Vector3.ZERO, Vector3.FORWARD)
	storm.stamp(FootContactSensor.Side.LEFT, Vector3.ZERO, Vector3.FORWARD)
	for i: int in range(60):
		calm._process(1.0)
		storm._process(1.0)
	_check(calm.get_visible_count() == 1, "a calm minute already erased the print")
	_check(storm.get_visible_count() == 0, "a blizzard minute did not bury the print")
	_dispose(weather)
	_dispose(calm)
	_dispose(storm)
