extends SceneTree

## Physics-backed hinged door regression.
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

	_check(_door.door_hinge is RigidBody3D, "legacy hinge was not upgraded to RigidBody3D")
	_check(_door._joint is HingeJoint3D, "door has no HingeJoint3D")
	_check(_leaf.find_children("*", "StaticBody3D", true, false).is_empty(), "legacy StaticBody survived rigid upgrade")
	_check((_door.door_hinge as RigidBody3D).find_children("*", "CollisionShape3D", true, false).size() == 1, "rigid door lost its collision shape")
	_check(_door.is_latched(), "door did not start latched")
	_test_latched_collision_blocks_henry()

	## F from the +Z side must release and crack away from Henry.
	_body.global_position = Vector3(0.35, 1.0, 0.7)
	_door.player_reference = _body
	_door.interact()
	_check(not _door.is_latched(), "F did not release the latch")
	await _frames(24)
	var first_angle: float = _door.get_current_angle_deg()
	_check(absf(first_angle) > 1.0, "handle release produced no physical swing")

	## Reset free at zero. Push from +Z toward -Z: one sign.
	_door.load_door_save_data({"angle_deg": 0.0, "angular_velocity_deg": 0.0, "latched": false})
	_door.apply_body_contact(_body, Vector3(0.40, 1.0, 0.0), Vector3(0, 0, -2.0), Vector3(0, 0, 1.0))
	await _frames(18)
	var outside_angle: float = _door.get_current_angle_deg()
	_check(absf(outside_angle) > 1.0, "outside body push did not open rigid door")

	## Same leaf from -Z must rotate the other way, not clamp at 0.
	_door.load_door_save_data({"angle_deg": 0.0, "angular_velocity_deg": 0.0, "latched": false})
	_door.apply_body_contact(_body, Vector3(0.40, 1.0, 0.0), Vector3(0, 0, 2.0), Vector3(0, 0, -1.0))
	await _frames(18)
	var inside_angle: float = _door.get_current_angle_deg()
	_check(absf(inside_angle) > 1.0, "inside body push did not open rigid door")
	_check(signf(outside_angle) != signf(inside_angle), "both sides rotate the door in the same direction")

	_door.load_door_save_data({"angle_deg": -2.5, "angular_velocity_deg": 0.0, "latched": false})
	_door.interact()
	_check(_door.is_latched(), "near closed + F did not latch")
	_check(absf(_door.get_current_angle_deg()) < 0.1, "latch did not seat at zero")

	_door.load_door_save_data({"angle_deg": 1.0, "angular_velocity_deg": 0.0, "latched": false})
	_door.apply_external_torque(5.0)
	await _frames(20)
	_check(absf(_door.get_current_angle_deg()) > 1.0, "unlatched door ignored external/wind torque seam")

	_check(is_equal_approx(_breach.get_exposure_multiplier(), _breach.get_exposure_multiplier()), "breach exposure became invalid")
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
	_check(_body.global_position.z > 0.18, "Henry passed through the latched rigid door")
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

	var legacy_body := StaticBody3D.new()
	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.0, 2.0, 0.10)
	shape_node.shape = shape
	legacy_body.add_child(shape_node)
	_leaf.add_child(legacy_body)

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
	print("hinged door: rigid hinge, two-sided body push, latch and collision passed")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("hinged door: %s" % message)
