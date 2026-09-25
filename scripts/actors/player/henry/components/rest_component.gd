class_name RestComponent
extends Node

## Henry sitting on a RestSpot. Sitting gives no bonus: the stove does the warming
## and drying; this only holds him still. F, Esc or any move input stands him up.

signal sat_down(spot: Node3D)
signal stood_up

const STAND_ACTIONS: Array[StringName] = [&"interact", &"pause", &"move_forward", &"move_backward",
	&"move_left", &"move_right", &"jump"]

var _spot: Node3D


func is_sitting() -> bool:
	return is_instance_valid(_spot)


## Sits on a spot: Henry moves onto its seat and faces its forward (-Z).
func sit(spot: Node3D) -> bool:
	var body := get_parent() as CharacterBody3D
	var visual: HenryUALAnimation = _visual()
	if is_sitting() or body == null or spot == null or body.velocity.y < -0.5:
		return false
	if visual != null and visual.is_carrying():
		return false
	_spot = spot
	body.velocity = Vector3.ZERO
	var facing: Vector3 = -spot.global_transform.basis.z
	facing.y = 0.0
	body.global_position = Vector3(spot.global_position.x, body.global_position.y, spot.global_position.z)
	if facing.length() > 0.01:
		body.rotation.y = atan2(-facing.x, -facing.z)
	if visual != null:
		visual.set_sitting(true)
	sat_down.emit(spot)
	return true


func stand() -> bool:
	if not is_sitting():
		return false
	_spot = null
	var visual: HenryUALAnimation = _visual()
	if visual != null:
		visual.set_sitting(false)
	stood_up.emit()
	return true


## Before InteractComponent hears F, so standing up does not re-trigger the spot.
func _input(event: InputEvent) -> void:
	if not is_sitting() or event.is_echo():
		return
	for action: StringName in STAND_ACTIONS:
		if InputMap.has_action(action) and event.is_action_pressed(action):
			stand()
			if action == &"interact" or action == &"pause":
				get_viewport().set_input_as_handled()
			return


func _visual() -> HenryUALAnimation:
	var body: Node = get_parent()
	return body.get_node_or_null(^"HenryUALVisual") as HenryUALAnimation if body != null else null
