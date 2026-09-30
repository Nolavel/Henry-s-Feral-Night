extends SceneTree

## Kinematic hinged door regression: latch, crack, two-sided push, hand push,
## F-close into the latch, and a leaf stopping against Henry.
## Run: godot --headless --script tests/systems/test_hinged_door.gd

const INTERACTIVE_SCENE: String = "res://scenes/environment/interactive/InteractiveArea.tscn"
const DOOR_SCRIPT: String = "res://scripts/environment/interactive/hinged_door.gd"

var _failures: int = 0
var _door: HingedDoor
var _leaf: MeshInstance3D
var _breach: ShelterBreach
var _body: CharacterBody3D


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_build()
	await physics_frame
	await physics_frame

	_check(not (_door.door_hinge is RigidBody3D), "door hinge must stay kinematic")
	_check(_leaf.find_children("*", "StaticBody3D", true, false).size() == 1, "leaf lost its collision body")
	_check(_door.is_latched(), "door did not start latched")
	_test_latched_collision_blocks_henry()

	## F from the +Z side releases and cracks away from Henry, towards -Z.
	_body.global_position = Vector3(0.35, 1.0, 0.7)
	_door.player_reference = _body
	_door.interact()
	_check(not _door.is_latched(), "F did not release the latch")
	_check(not _door.get_hand_hold().is_empty(), "F did not put Henry's hand on the handle")
	await _frames(40)
	var crack: float = _door.get_current_angle_deg()
	_check(crack > 3.0 and crack < 25.0, "F crack settled at %.1f deg, not a small gap away from Henry" % crack)

	## The door opens inward only (towards -Z here): an outside push opens it, an
	## inside push on a shut leaf is stopped by the frame, and on an open leaf closes it.
	_body.global_position = Vector3(3.0, 1.0, 3.0)
	_door.load_door_save_data({"angle_deg": 0.0, "angular_velocity_deg": 0.0, "latched": false})
	_door.apply_body_contact(_body, Vector3(0.40, 1.0, 0.0), Vector3(0, 0, -2.0), Vector3(0, 0, 1.0))
	await _frames(18)
	_check(_door.get_current_angle_deg() > 1.0, "an outside body push did not open the door inward")
	_door.load_door_save_data({"angle_deg": 0.0, "angular_velocity_deg": 0.0, "latched": false})
	_door.apply_body_contact(_body, Vector3(0.40, 1.0, 0.0), Vector3(0, 0, 2.0), Vector3(0, 0, -1.0))
	await _frames(18)
	_check(absf(_door.get_current_angle_deg()) < 0.1, "an inside push swung the leaf out through its frame")
	_door.load_door_save_data({"angle_deg": 40.0, "angular_velocity_deg": 0.0, "latched": false})
	var leaf_point: Vector3 = _door.door_hinge.global_transform * Vector3(0.9, 0.0, 0.0)
	_door.apply_body_contact(_body, leaf_point, Vector3(0, 0, 2.0), _door.door_hinge.global_basis.z * -1.0)
	await _frames(18)
	_check(_door.get_current_angle_deg() < 38.0, "an inside push did not swing an open leaf shut")

	## A palm from the +Z side past the leaf plane drives it ahead of the hand.
	_door.load_door_save_data({"angle_deg": 0.0, "angular_velocity_deg": 0.0, "latched": false})
	var side: float = _door.side_of(Vector3(0.3, 1.0, 0.6))
	_check(side < 0.0, "a point at +Z should face the -1 side")
	for i: int in range(12):
		_door.push_with_hand(Vector3(0.3, 1.0, 0.1 - 0.02 * float(i)), side, 1.0 / 60.0)
		await physics_frame
	var pushed: float = _door.get_current_angle_deg()
	_check(pushed > 5.0, "hand push left the leaf at %.1f deg" % pushed)
	var ray: Dictionary = _door.leaf_ray(Vector3(0.3, 1.0, 0.8), Vector3(0, 0, -1), side)
	_check(not ray.is_empty(), "a ray at the pushed leaf missed it")

	## F on an open door swings it shut and latches it.
	_body.global_position = Vector3(0.3, 1.0, 1.4)
	_door.load_door_save_data({"angle_deg": 60.0, "angular_velocity_deg": 0.0, "latched": false})
	_door.interact()
	await _frames(120)
	_check(_door.is_latched(), "F on an open door did not close and latch it (%.1f deg)" % _door.get_current_angle_deg())

	## F from inside on a latched door pulls it wide open towards Henry.
	_body.global_position = Vector3(1.4, 1.0, -0.8)
	_door.interact()
	_check(not _door.is_latched(), "F from inside did not release the latch")
	await _frames(90)
	_check(_door.get_current_angle_deg() > 40.0, "F from inside pulled the door only to %.1f deg" % _door.get_current_angle_deg())

	## F from inside on an open door, standing behind the leaf, pushes it shut.
	_body.global_position = Vector3(-0.2, 1.0, -0.9)
	_door.load_door_save_data({"angle_deg": 50.0, "angular_velocity_deg": 0.0, "latched": false})
	_door.interact()
	await _frames(120)
	_check(_door.is_latched(), "F from inside did not close the open door")

	## A swinging leaf stops against Henry instead of passing through him.
	HingedDoor.blocker = _body
	_body.global_position = Vector3(0.1, 1.0, -0.45)
	_door.load_door_save_data({"angle_deg": 0.0, "angular_velocity_deg": 0.0, "latched": false})
	_door.apply_external_torque(300.0)
	await _frames(60)
	_check(_door.get_current_angle_deg() < 55.0, "leaf swung through Henry to %.1f deg" % _door.get_current_angle_deg())
	HingedDoor.blocker = null

	_door.load_door_save_data({"angle_deg": -2.5, "angular_velocity_deg": 0.0, "latched": false})
	_door.interact()
	_check(_door.is_latched(), "near closed + F did not latch")
	_check(absf(_door.get_current_angle_deg()) < 0.1, "latch did not seat at zero")

	_breach.board_up()
	_check(not _breach.is_boarded(), "door still accepts boards")
	_finish()


func _frames(count: int) -> void:
	for _i: int in range(count):
		await physics_frame


func _test_latched_collision_blocks_henry() -> void:
	_body.global_position = Vector3(0.30, 1.0, 0.55)
	_body.velocity = Vector3(0.0, 0.0, -2.0)
	var attempted: Vector3 = _body.velocity
	_body.move_and_slide()
	HingedDoor.apply_character_collisions(_body, attempted)
	_check(_body.global_position.z > 0.18, "Henry passed through the latched door")
	_check(_door.is_latched(), "body collision bypassed latch")


func _build() -> void:
	var holder := Node3D.new()
	root.add_child(holder)

	_breach = ShelterBreach.new()
	holder.add_child(_breach)

	var prompt := (load(INTERACTIVE_SCENE) as PackedScene).instantiate() as InteractiveArea
	prompt.set_script(load(DOOR_SCRIPT))
	prompt.set(&"interactable_scene", null)
	prompt.set(&"breach", _breach)
	prompt.set(&"opening_size", Vector2(1.0, 2.0))

	var hinge := Node3D.new()
	hinge.name = "Hinge"
	hinge.position = Vector3(-0.5, 1.0, 0.0)
	prompt.add_child(hinge)

	_leaf = MeshInstance3D.new()
	_leaf.name = "DoorLeaf"
	_leaf.position = Vector3(0.5, 0.0, 0.0)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.0, 2.0, 0.10)
	_leaf.mesh = mesh
	hinge.add_child(_leaf)

	var leaf_body := StaticBody3D.new()
	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.0, 2.0, 0.10)
	shape_node.shape = shape
	leaf_body.add_child(shape_node)
	_leaf.add_child(leaf_body)

	prompt.set(&"door_hinge", hinge)
	prompt.set(&"interactive_mesh", _leaf)
	holder.add_child(prompt)
	_door = prompt as HingedDoor

	_body = CharacterBody3D.new()
	_body.name = "HenryDoorProbe"
	var body_shape_node := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.25
	capsule.height = 1.8
	body_shape_node.shape = capsule
	_body.add_child(body_shape_node)
	root.add_child(_body)


func _finish() -> void:
	if _failures > 0:
		push_error("hinged door: %d check(s) failed" % _failures)
		quit(1)
		return
	print("hinged door: latch, crack, two-sided push, hand push, close and blocking passed")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("hinged door: %s" % message)
