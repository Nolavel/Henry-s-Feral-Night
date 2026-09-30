extends SceneTree

## Continuous hinged-door regression.
## Run: godot --headless --script tests/systems/test_hinged_door.gd

const INTERACTIVE_SCENE: String = "res://scenes/environment/interactive/InteractiveArea.tscn"
const DOOR_SCRIPT: String = "res://scripts/environment/interactive/hinged_door.gd"
const DT: float = 1.0 / 60.0

var _failures: int = 0
var _door: HingedDoor
var _hinge: Node3D
var _leaf: MeshInstance3D
var _breach: ShelterBreach
var _body: CharacterBody3D


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_build()
	await physics_frame
	await physics_frame

	_check(_door.is_latched(), "door did not start latched")
	_check(not _door.is_open(), "door starts semantically open")
	_check(is_equal_approx(_breach.get_exposure_multiplier(), 0.05), "latched door does not reduce draft")
	_check(_leaf.find_child("*", true, false) != null, "door leaf lost its children")
	_check(_leaf.find_children("*", "StaticBody3D", true, false).size() == 1, "door leaf lost its physical StaticBody")
	_test_latched_collision_blocks_henry()

	_door.interact()
	_check(not _door.is_latched(), "F did not release the latch")
	for _i: int in range(36):
		_door._physics_process(DT)
	var cracked: float = absf(_door.get_current_angle_deg())
	_check(cracked >= 7.0 and cracked <= 16.0, "F did not physically crack the door 8-15 deg; got %.2f" % cracked)
	_check(_door.is_open(), "cracked door is not reported open")

	var before_push: float = absf(_door.get_current_angle_deg())
	_push_from_face(true, 36)
	var after_push: float = absf(_door.get_current_angle_deg())
	_check(after_push > before_push + 4.0, "real body-contact torque did not open the door farther")

	var before_close: float = absf(_door.get_current_angle_deg())
	_push_from_face(false, 54)
	var after_close: float = absf(_door.get_current_angle_deg())
	_check(after_close < before_close - 3.0, "opposite-side body contact did not close the door")

	_door.load_door_save_data({"angle_deg": 2.5, "angular_velocity_deg": 0.0, "latched": false})
	_check(not _door.is_latched() and absf(_door.get_current_angle_deg()) < _door.latch_angle_deg, "near-closed setup failed")
	_door.interact()
	_check(_door.is_latched(), "near closed + F did not latch")
	_check(is_zero_approx(_door.get_current_angle_deg()), "latch did not seat the leaf at zero")

	_door.load_door_save_data({"angle_deg": 1.0, "angular_velocity_deg": 0.0, "latched": false})
	var wind_before: float = absf(_door.get_current_angle_deg())
	for _i: int in range(90):
		_door.apply_external_torque(0.7 * signf(_door.open_angle_deg))
		_door._physics_process(DT)
	var wind_after: float = absf(_door.get_current_angle_deg())
	_check(wind_after > wind_before + 1.0, "unlatched near-closed door ignored simulated wind torque")

	var saved: Dictionary = _door.get_door_save_data()
	_door.load_door_save_data(saved)
	_check(bool(saved.get("latched", true)) == _door.is_latched(), "door save hook lost latch state")
	_check(absf(float(saved.get("angle_deg", 0.0)) - _door.get_current_angle_deg()) < 0.05, "door save hook lost partial angle")

	_breach.board_up()
	_check(not _breach.is_boarded(), "door still accepts boards")
	_breach.load_save_data({"forced": true, "boards": [0.0], "staged": 3})
	_check(not _breach.is_boarded(), "legacy save resurrected door boarding")

	_finish()


func _test_latched_collision_blocks_henry() -> void:
	_body.global_position = Vector3(0.30, 1.0, 0.48)
	_body.velocity = Vector3(0.0, 0.0, -2.0)
	var attempted: Vector3 = _body.velocity
	_body.move_and_slide()
	HingedDoor.apply_character_collisions(_body, attempted)
	_check(_body.global_position.z > 0.20, "Henry passed through the latched moving-door collider")
	_check(is_zero_approx(_door.get_current_angle_deg()), "body push bypassed the latch")


func _push_from_face(opening: bool, steps: int) -> void:
	for _i: int in range(steps):
		var axis_x: Vector3 = _hinge.global_basis.x.normalized()
		var face: Vector3 = _hinge.global_basis.z.normalized()
		var contact: Vector3 = _hinge.global_position + axis_x * 0.85
		var normal: Vector3 = face if opening else -face
		var attempted: Vector3 = -normal * 2.0
		_door.apply_body_contact(_body, contact, attempted, normal)
		_door._physics_process(DT)


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

	_hinge = Node3D.new()
	_hinge.name = "Hinge"
	_hinge.position = Vector3(-0.5, 1.0, 0.0)
	prompt.add_child(_hinge)

	_leaf = MeshInstance3D.new()
	_leaf.name = "DoorLeaf"
	_leaf.position = Vector3(0.5, 0.0, 0.0)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.0, 2.0, 0.10)
	_leaf.mesh = mesh
	_hinge.add_child(_leaf)

	var body := StaticBody3D.new()
	body.name = "DoorBody"
	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.0, 2.0, 0.10)
	shape_node.shape = shape
	body.add_child(shape_node)
	_leaf.add_child(body)

	prompt.set(&"door_hinge", _hinge)
	prompt.set(&"interactive_mesh", _leaf)
	holder.add_child(prompt)
	_door = prompt as HingedDoor
	_door.set_physics_process(false)

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
	print("hinged door: latch, continuous body torque, moving collision, wind and save hooks passed")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("hinged door: %s" % message)
