class_name TpsShoulderState
extends RefCounted

## Which shoulder the camera sits over, with a smoothstep swap between them.
## Ported from ADT's TpsShoulderCameraState.

enum Side { LEFT, RIGHT, TRANSITION }

var right_offset: float = 0.85
var left_offset: float = -0.85
var transition_duration: float = 0.18
var state: int = Side.RIGHT

var _pending: int = Side.RIGHT
var _from: int = Side.RIGHT
var _time: float = 0.0


func toggle() -> void:
	if state == Side.TRANSITION:
		return
	_start(Side.LEFT if state == Side.RIGHT else Side.RIGHT)


func is_right() -> bool:
	return state == Side.RIGHT


## Advances any swap in progress and returns the current offset in metres.
func update(delta: float) -> float:
	if state != Side.TRANSITION:
		return _offset_for(state)
	_time += delta
	var t: float = clampf(_time / transition_duration, 0.0, 1.0)
	var eased: float = t * t * (3.0 - 2.0 * t)
	var result: float = lerpf(_offset_for(_from), _offset_for(_pending), eased)
	if _time >= transition_duration:
		state = _pending
	return result


func _start(to: int) -> void:
	_from = state
	_pending = to
	_time = 0.0
	state = Side.TRANSITION


func _offset_for(side: int) -> float:
	return left_offset if side == Side.LEFT else right_offset
