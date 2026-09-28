extends SceneTree

## Real generated shelter geometry must offer F under the camera centre, not through walls.
## Run: godot --headless --script tests/systems/test_shelter_focus.gd

const BLOCKOUT: String = "res://scenes/world/first_exit/first_exit_blockout.tscn"

var _failures: int = 0
var _scene: Node3D
var _player: CharacterBody3D
var _camera: Camera3D
var _interact: InteractComponent
var _inventory: InventoryComponent


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_scene = (load(BLOCKOUT) as PackedScene).instantiate() as Node3D
	root.add_child(_scene)
	_player = CharacterBody3D.new()
	_player.add_to_group(&"player")
	_inventory = InventoryComponent.new()
	_player.add_child(_inventory)
	_interact = InteractComponent.new()
	_player.add_child(_interact)
	root.add_child(_player)
	_camera = Camera3D.new()
	_camera.current = true
	root.add_child(_camera)
	await physics_frame
	await physics_frame
	var house: Node3D = _scene.get_node(^"ShelterHouse/House") as Node3D
	var feed: HeatSourceFeed = house.get_node(^"ShelterZone/Stove/Feed") as HeatSourceFeed
	var stove: Node3D = feed.get_parent() as Node3D
	_check((feed.get_node(^"CollisionShape3D") as CollisionShape3D).shape is BoxShape3D,
		"saved stove trigger reverted to the template sphere")
	await _aim(feed, stove.to_global(Vector3(1.0, 0.9, 0.0)), feed.focus_anchor.global_position)
	_check_target(feed, "stove body")
	var distractor := InteractiveArea.new()
	distractor.name = "OverlappingUnfocusedArea"
	distractor.position = _camera.global_position - _camera.global_basis.z * 0.3
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.15
	shape.shape = sphere
	distractor.add_child(shape)
	var off_axis := Marker3D.new()
	off_axis.position.x = 2.0
	distractor.add_child(off_axis)
	distractor.focus_anchor = off_axis
	root.add_child(distractor)
	await physics_frame
	await physics_frame
	_interact.detect_target()
	_check_target(feed, "overlapping unfocused area stole stove selection")
	var wall := StaticBody3D.new()
	var wall_shape := CollisionShape3D.new()
	var wall_box := BoxShape3D.new()
	wall_box.size = Vector3(1.5, 1.5, 0.08)
	wall_shape.shape = wall_box
	wall.add_child(wall_shape)
	root.add_child(wall)
	wall.global_position = _camera.global_position.lerp(feed.focus_anchor.global_position, 0.5)
	wall.look_at(feed.focus_anchor.global_position, Vector3.UP)
	await physics_frame
	await physics_frame
	_interact.detect_target()
	_check(_interact.current_target == null and not feed.shape_cast_detected, "F selected the stove through a wall")
	wall.queue_free()
	distractor.queue_free()
	await physics_frame
	await physics_frame
	_interact.detect_target()
	_check_target(feed, "stove did not recover after occluder removal")
	_inventory.try_add(ItemCatalog.get_item(&"firewood"))
	_inventory.try_add(ItemCatalog.get_item(&"lighter"))
	_interact.try_interact() # open
	_interact.try_interact() # stage one cold log
	_check(feed.is_acting(), "F did not start staged log loading")
	feed._process(HeatSourceFeed.ADD_SECONDS)
	_check(not feed.heat_source.is_burning() and feed.heat_source.get_remaining_hours() > 0.0,
		"staged cold log load did not complete")
	await physics_frame
	_interact.detect_target()
	_check_target(feed, "stove after staged log load")
	feed.first_strike_success_chance = 0.0
	feed.second_strike_success_chance = 0.0
	feed.guaranteed_success_strike = 3
	_interact.try_interact() # prepare lighter
	_check(feed.is_acting(), "F did not start lighting the real stove")
	_check(feed.attempt_lighter_strike(10.0) == HeatSourceFeed.StrikeResult.SPARK, "first LMB strike did not spark")
	_check(feed.attempt_lighter_strike(10.4) == HeatSourceFeed.StrikeResult.SPARK, "second LMB strike did not spark")
	_check(feed.attempt_lighter_strike(10.8) == HeatSourceFeed.StrikeResult.IGNITED, "third LMB strike did not ignite")
	_check(feed.heat_source.is_burning(), "stove did not ignite")
	var door: InteractiveArea = house.get_node(^"HouseDoor") as InteractiveArea
	await _aim(door, door.global_position + house.global_basis.z * 1.1, door.interactive_mesh.global_position)
	_check_target(door, "exterior door")
	var cabinet: InteractiveArea = house.get_node(^"ShelterZone/Cabinet/Open") as InteractiveArea
	var cab: Node3D = cabinet.get_parent() as Node3D
	await _aim(cabinet, cab.to_global(Vector3(0.0, 0.9, 1.2)), cabinet.focus_anchor.global_position)
	_check_target(cabinet, "cabinet door")
	var rest: InteractiveArea = house.get_node(^"ShelterZone/RestCrate/Rest") as InteractiveArea
	await _aim(rest, rest.global_position + house.global_basis.x * 0.8 + Vector3.UP * 0.9,
		rest.interactive_mesh.global_position)
	_check_target(rest, "rest crate")
	var sleep: InteractiveArea = house.get_node(^"ShelterZone/Mattress/Sleep") as InteractiveArea
	await _aim(sleep, sleep.global_position + house.global_basis.x * 0.7 + Vector3.UP * 0.9,
		sleep.focus_anchor.global_position)
	_check_target(sleep, "mattress")
	var pickup: ItemPickup = _scene.get_node(^"RoadFlareShelterTest") as ItemPickup
	await _aim(pickup, pickup.global_position + Vector3(0.0, 1.0, 0.5), pickup.interactive_mesh.global_position)
	_check_target(pickup, "test flare")
	_interact.try_interact()
	_check(_inventory.get_count(&"road_flare") == 1 and _interact.current_target == null,
		"successful pickup left an authoritative target")
	_check(not pickup.shape_cast_detected, "successful pickup left F active")
	_camera.look_at(_camera.global_position + Vector3.UP + Vector3.FORWARD)
	_interact.detect_target()
	_check(_interact.current_target == null, "looking away still offers F")
	print("test_shelter_focus: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(0 if _failures == 0 else 1)


func _aim(_target: InteractiveArea, from: Vector3, point: Vector3) -> void:
	_player.global_position = from
	_camera.global_position = from
	_camera.look_at(point, Vector3.UP)
	await physics_frame
	await physics_frame
	_interact.detect_target()


func _check_target(target: InteractiveArea, context: String) -> void:
	_check(_interact.current_target == target and target.shape_cast_detected,
		"%s: target is %s" % [context, _interact.current_target])


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("shelter focus: %s" % message)
