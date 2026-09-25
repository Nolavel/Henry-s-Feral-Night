extends SceneTree

## Focused regression for Henry's runtime AnimationTree.
## Run: godot --headless --script tests/systems/test_henry_animation.gd

const VISUAL: String = "res://scenes/actors/player/HenryUALVisual.tscn"
const BODY_SOURCE: String = """extends CharacterBody3D
var crouched: bool = false
func get_locomotion_speed_ratio() -> float:
	return 0.0
func get_crouch_speed_ratio() -> float:
	return 0.0
func is_crouching() -> bool:
	return crouched
func get_view_direction() -> Vector3:
	return Vector3.FORWARD
"""

var _failures: int = 0
var _frame: int = 0
var _sit_time: float = 0.0
var _body: CharacterBody3D
var _visual: HenryUALAnimation


func _process(delta: float) -> bool:
	_frame += 1
	match _frame:
		1:
			_build()
			_check_transition_modes()
			_visual.update_animation_state(true, false)
		2:
			_check(_visual._state_playback.get_current_node() == &"JumpStart", "jump did not enter JumpStart")
			_visual.update_animation_state(false, false)
		3:
			_check(_visual._state_playback.get_current_node() == &"JumpStart", "JumpStart was cut by the next frame")
			_visual.update_animation_state(false, true)
		4:
			_check(_visual._state_playback.get_current_node() == &"Land", "landing did not enter Land")
			_visual.update_animation_state(false, false)
		5:
			_check(_visual._state_playback.get_current_node() == &"Land", "Land was cut by the next grounded update")
			_check(_visual.play_action(&"interact"), "interact action clip did not resolve")
		6:
			_check(bool(_visual.animation_tree.get("parameters/actions/active")), "OneShot did not become active")
			_check(_visual.is_action_locking(), "a working action does not root Henry")
			_check_carry()
			_visual.set_sitting(true)
			_visual.update_animation_state(false, false)
		_:
			if _frame > 6:
				_update_sitting(delta)
	return false


## Frames run faster than real time headless, so the sit checks wait on elapsed time.
func _update_sitting(delta: float) -> void:
	_sit_time += delta
	_visual.update_animation_state(false, false)
	if _sit_time > 5.0 and _visual.is_sitting():
		_check(String(_visual._state_playback.get_current_node()).begins_with("Sit"),
			"sitting did not enter the sit states (%s)" % _visual._state_playback.get_current_node())
		_visual.set_sitting(false)
	elif _sit_time > 8.0:
		_check(_visual._state_playback.get_current_node() != &"SitLoop", "standing up stayed in the sit loop")
		_finish()


func _build() -> void:
	var script := GDScript.new()
	script.source_code = BODY_SOURCE
	_check(script.reload() == OK, "test body script did not compile")
	_body = CharacterBody3D.new()
	_body.set_script(script)
	_visual = (load(VISUAL) as PackedScene).instantiate() as HenryUALAnimation
	_body.add_child(_visual)
	root.add_child(_body)
	_check(_visual.animation_tree != null, "AnimationTree was not built")
	_check(_visual._state_playback != null, "state-machine playback was not exposed")


## Firewood in the arms: the UAL2 carry cycle resolves, the Carry state exists
## and the armful shows only while carried.
func _check_carry() -> void:
	_check(_visual._resolved_carry_walk == &"UAL2/Walk_Carry", "UAL2 Walk_Carry did not resolve")
	var tree := _visual.animation_tree.tree_root as AnimationNodeBlendTree
	var machine := tree.get_node(&"base") as AnimationNodeStateMachine
	_check(machine.has_node(&"Carry"), "Carry state is missing")
	_check(machine.has_node(&"SitLoop") and machine.has_node(&"SitEnter"), "Sitting states are missing")
	var prop := _visual.find_child("CarryFirewood", true, false) as Node3D
	_check(prop != null and not prop.visible, "the armful shows before anything is carried")
	_visual.set_carried_item(load("res://data/items/firewood.tres") as ItemResource)
	_check(prop != null and prop.visible and _visual.is_carrying(), "carried firewood is not in Henry's arms")
	_visual.set_carried_item(null)
	_check(prop != null and not prop.visible and not _visual.is_carrying(), "the armful stays after the carry ends")


func _check_transition_modes() -> void:
	if _visual.animation_tree == null:
		return
	var tree := _visual.animation_tree.tree_root as AnimationNodeBlendTree
	var state_machine := tree.get_node(&"base") as AnimationNodeStateMachine
	_check(state_machine != null, "base state machine is missing")
	if state_machine == null:
		return
	_check_at_end_transition(state_machine, &"JumpStart", &"AirLoop")
	_check_at_end_transition(state_machine, &"Land", &"Grounded")


func _check_at_end_transition(machine: AnimationNodeStateMachine, from: StringName, to: StringName) -> void:
	for index: int in range(machine.get_transition_count()):
		if machine.get_transition_from(index) != from or machine.get_transition_to(index) != to:
			continue
		var transition := machine.get_transition(index)
		_check(
			transition.advance_mode == AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO,
			"%s -> %s is not automatic" % [from, to]
		)
		_check(
			transition.switch_mode == AnimationNodeStateMachineTransition.SWITCH_MODE_AT_END,
			"%s -> %s does not wait for clip end" % [from, to]
		)
		return
	_check(false, "%s -> %s transition is missing" % [from, to])


func _finish() -> void:
	if _failures > 0:
		push_error("henry animation: %d check(s) failed" % _failures)
		quit(1)
		return
	print("henry animation: all checks passed")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("henry animation: %s" % message)
