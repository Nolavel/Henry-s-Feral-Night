extends SceneTree

## Full-size doors open and close on the same interaction used everywhere else,
## keep their physical leaf on the hinge, and lock when a shelter is boarded.
## Run: godot --headless --script tests/systems/test_hinged_door.gd

const INTERACTIVE_SCENE: String = "res://scenes/environment/interactive/InteractiveArea.tscn"
const DOOR_SCRIPT: String = "res://scripts/environment/interactive/hinged_door.gd"

var _failures: int = 0
var _elapsed: float = 0.0
var _step: int = 0
var _door: InteractiveArea
var _hinge: Node3D
var _breach: ShelterBreach


func _process(delta: float) -> bool:
	_elapsed += delta
	match _step:
		0:
			_build()
			_check(not bool(_door.call(&"is_open")), "door starts open")
			_check(_door.can_interact(), "closed door refuses F")
			_door.interact()
			_check(bool(_door.call(&"is_open")) and bool(_door.call(&"is_swinging")),
				"F did not start the opening swing")
			_check(not _door.can_interact(), "swinging door accepts another press")
			_elapsed = 0.0
			_step = 1
		1:
			if _elapsed > float(_door.get(&"hand_delay")) + float(_door.get(&"swing_time")) + 0.2:
				_check(is_equal_approx(_hinge.rotation.y, deg_to_rad(float(_door.get(&"open_angle_deg")))),
					"door did not reach its open angle")
				_door.interact()
				_elapsed = 0.0
				_step = 2
		2:
			if _elapsed > float(_door.get(&"hand_delay")) + float(_door.get(&"swing_time")) + 0.2:
				_check(not bool(_door.call(&"is_open")) and is_zero_approx(_hinge.rotation.y), "door did not close")
				_breach.board_up()
				_check(not _door.can_interact(), "boarded shelter door still accepts F")
				_finish()
	return false


func _build() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	_breach = ShelterBreach.new()
	holder.add_child(_breach)
	_hinge = Node3D.new()
	_hinge.name = "Hinge"
	holder.add_child(_hinge)
	var leaf := MeshInstance3D.new()
	leaf.mesh = BoxMesh.new()
	_hinge.add_child(leaf)
	var prompt: Node3D = (load(INTERACTIVE_SCENE) as PackedScene).instantiate()
	prompt.set_script(load(DOOR_SCRIPT))
	prompt.set(&"interactable_scene", null)
	prompt.set(&"door_hinge", _hinge)
	prompt.set(&"interactive_mesh", leaf)
	prompt.set(&"breach", _breach)
	holder.add_child(prompt)
	_door = prompt as InteractiveArea


func _finish() -> void:
	if _failures > 0:
		push_error("hinged door: %d check(s) failed" % _failures)
		quit(1)
		return
	print("hinged door: open, close and boarding lock passed")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("hinged door: %s" % message)
