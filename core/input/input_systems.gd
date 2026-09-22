# =============================================================================
# input_systems.gd — autoload.
#
# Single responsibility: turn Godot's Input into signals and query methods.
# NO game logic lives here. It does not decide what a press MEANS — that is
# the subscriber's job, based on whatever state the subscriber cares about.
# It emits unconditionally, always.
#
# Two rules taken from the ADT project, both learned the hard way there:
#
#   EDGES COME FROM EVENTS, LEVELS COME FROM POLLS.
#   A discrete press or release is matched on the InputEvent in
#   _unhandled_input(); held state and axes are polled in _physics_process().
#   Do NOT add Input.is_action_just_pressed() anywhere: polling an edge from
#   the physics frame drops presses as soon as the idle and physics rates
#   diverge. A query method that must stay a poll is answered from the edge
#   latch in this file, never from Input.
#
#   ONLY THIS FILE READS Input DIRECTLY.
#   A second reader means two places decide what is pressed, and they will
#   disagree on the frame it matters.
# =============================================================================
class_name InputSystemsService
extends Node

## --- Movement and locomotion ---
signal jump_pressed()
signal sprint_changed(active: bool)

## --- Interaction ---
signal interact_pressed()

## --- Sleep (hold S, confirm with interact) ---
## The relay reports WHEN and FOR HOW LONG; it never says "that was a hold".
## The threshold belongs to whoever acts on it.
signal sleep_hold_started()
signal sleep_hold_progress(duration: float)
signal sleep_hold_released(duration: float)
signal sleep_hours_step(delta: int)
signal sleep_cancel_pressed()

const ACTION_MOVE_FORWARD: StringName = &"move_forward"
const ACTION_MOVE_BACKWARD: StringName = &"move_backward"
const ACTION_MOVE_LEFT: StringName = &"move_left"
const ACTION_MOVE_RIGHT: StringName = &"move_right"
const ACTION_SPRINT: StringName = &"sprint"
const ACTION_JUMP: StringName = &"jump"
const ACTION_INTERACT: StringName = &"interact"
const ACTION_SLEEP: StringName = &"sleep"
const ACTION_SLEEP_CANCEL: StringName = &"sleep_cancel"
const ACTION_SLEEP_LESS: StringName = &"sleep_hours_less"
const ACTION_SLEEP_MORE: StringName = &"sleep_hours_more"

var _sleep_held_for: float = 0.0
var _is_sleep_held: bool = false
var _was_sprinting: bool = false


func _unhandled_input(event: InputEvent) -> void:
	if _pressed(event, ACTION_JUMP):
		jump_pressed.emit()
	if _pressed(event, ACTION_INTERACT):
		interact_pressed.emit()
	if _pressed(event, ACTION_SLEEP_CANCEL):
		sleep_cancel_pressed.emit()
	if _pressed(event, ACTION_SLEEP_LESS):
		sleep_hours_step.emit(-1)
	if _pressed(event, ACTION_SLEEP_MORE):
		sleep_hours_step.emit(1)
	if _pressed(event, ACTION_SLEEP):
		_is_sleep_held = true
		_sleep_held_for = 0.0
		sleep_hold_started.emit()
	elif _released(event, ACTION_SLEEP) and _is_sleep_held:
		_is_sleep_held = false
		sleep_hold_released.emit(_sleep_held_for)
		_sleep_held_for = 0.0


func _physics_process(delta: float) -> void:
	var sprinting: bool = is_sprinting()
	if sprinting != _was_sprinting:
		_was_sprinting = sprinting
		sprint_changed.emit(sprinting)
	if _is_sleep_held:
		_sleep_held_for += delta
		sleep_hold_progress.emit(_sleep_held_for)


## Movement intent as a 2D vector, x right and y forward.
func get_move_axis() -> Vector2:
	if not _has_move_actions():
		return Vector2.ZERO
	return Input.get_vector(
		ACTION_MOVE_LEFT, ACTION_MOVE_RIGHT, ACTION_MOVE_BACKWARD, ACTION_MOVE_FORWARD
	)


## True while any movement action is held. Used to tell a deliberate hold
## apart from a key that also means "walk".
func is_moving() -> bool:
	for action: StringName in [
		ACTION_MOVE_FORWARD, ACTION_MOVE_BACKWARD, ACTION_MOVE_LEFT,
		ACTION_MOVE_RIGHT, ACTION_JUMP,
	]:
		if InputMap.has_action(action) and Input.is_action_pressed(action):
			return true
	return false


func is_sprinting() -> bool:
	return InputMap.has_action(ACTION_SPRINT) and Input.is_action_pressed(ACTION_SPRINT)


## Seconds the sleep key has been held, answered from this file's own latch
## rather than from Input.
func get_sleep_hold_duration() -> float:
	return _sleep_held_for


func is_sleep_held() -> bool:
	return _is_sleep_held


## Drops the hold latch, for a consumer that has acted on it.
func clear_sleep_hold() -> void:
	_is_sleep_held = false
	_sleep_held_for = 0.0


func _pressed(event: InputEvent, action: StringName) -> bool:
	return InputMap.has_action(action) and event.is_action_pressed(action, false, true)


func _released(event: InputEvent, action: StringName) -> bool:
	return InputMap.has_action(action) and event.is_action_released(action, true)


func _has_move_actions() -> bool:
	for action: StringName in [
		ACTION_MOVE_LEFT, ACTION_MOVE_RIGHT, ACTION_MOVE_BACKWARD, ACTION_MOVE_FORWARD
	]:
		if not InputMap.has_action(action):
			return false
	return true
