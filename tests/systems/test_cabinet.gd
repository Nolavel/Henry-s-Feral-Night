extends SceneTree

## Cabinet: the door swings on its hinge after Henry's hand delay, requests
## chest_open, refuses while swinging, and closes on the next use.
## Run: godot --headless --script tests/systems/test_cabinet.gd

const INTERACTIVE_SCENE: String = "res://scenes/environment/interactive/InteractiveArea.tscn"
const CABINET_SCRIPT: String = "res://scripts/environment/interactive/cabinet.gd"

var _failures: int = 0
var _elapsed: float = 0.0
var _step: int = 0
var _cabinet: Cabinet
var _hinge: Node3D


func _process(delta: float) -> bool:
	_elapsed += delta
	match _step:
		0:
			_build()
			_check(_cabinet.player_animation_action == &"chest_open", "cabinet does not request chest_open")
			_check(not _cabinet.is_open(), "cabinet starts open")
			_cabinet.interact()
			_check(_cabinet.is_open() and _cabinet.is_swinging(), "interacting did not start opening the door")
			_check(not _cabinet.can_interact(), "a swinging door accepts another press")
			_check(is_zero_approx(_hinge.rotation.y), "the door moved before Henry's hand reached it")
			_elapsed = 0.0
			_step = 1
		1:
			if _elapsed > _cabinet.hand_delay + _cabinet.swing_time + 0.2:
				_check(is_equal_approx(_hinge.rotation.y, deg_to_rad(_cabinet.open_angle_deg)), "door did not reach open")
				_check(_cabinet.can_interact(), "an open cabinet cannot be closed")
				_cabinet.interact()
				_elapsed = 0.0
				_step = 2
		2:
			if _elapsed > _cabinet.hand_delay + _cabinet.swing_time + 0.2:
				_check(not _cabinet.is_open() and is_zero_approx(_hinge.rotation.y), "door did not close again")
				_finish()
	return false


func _build() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	_hinge = Node3D.new()
	_hinge.name = "DoorHinge"
	holder.add_child(_hinge)
	var panel := MeshInstance3D.new()
	panel.mesh = BoxMesh.new()
	_hinge.add_child(panel)
	var prompt: Node3D = (load(INTERACTIVE_SCENE) as PackedScene).instantiate()
	prompt.set_script(load(CABINET_SCRIPT))
	prompt.set(&"interactable_scene", null)
	prompt.set(&"door_hinge", _hinge)
	prompt.set(&"interactive_mesh", panel)
	holder.add_child(prompt)
	_cabinet = prompt as Cabinet


func _finish() -> void:
	if _failures > 0:
		push_error("cabinet: %d check(s) failed" % _failures)
		quit(1)
		return
	print("cabinet: all checks passed")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("cabinet: %s" % message)
