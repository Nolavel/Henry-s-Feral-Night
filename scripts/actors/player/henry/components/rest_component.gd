class_name RestComponent
extends Node

## Henry sitting on a RestSpot. Sitting gives no bonus: the stove warms and dries.
## Seated, F waits (hours prompt); Esc or any move stands him up. Pack left, Kenny right.

signal sat_down(spot: Node3D)
signal stood_up

const HINT_KEY: String = "REST_SEATED_HINT"
const WAIT_ACTION: StringName = &"interact"
const STAND_ACTIONS: Array[StringName] = [&"pause", &"move_forward", &"move_backward",
	&"move_left", &"move_right", &"jump"]
## Where the pack and Kenny are set down, in the seat's space (-Z faces the stove).
const PACK_SPOT: Vector3 = Vector3(-0.62, 0.0, 0.05)
const KENNY_SPOT: Vector3 = Vector3(0.62, 0.0, 0.05)

var _spot: Node3D
var _hint: Label


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
		visual.set_pack_down(spot.global_transform * Transform3D(Basis(Vector3.UP, 0.4), PACK_SPOT),
			spot.global_transform * Transform3D(Basis(Vector3.UP, PI * 0.5), KENNY_SPOT))  # faces the pack
	_show_hint(true)
	sat_down.emit(spot)
	return true


func stand() -> bool:
	if not is_sitting():
		return false
	_spot = null
	var visual: HenryUALAnimation = _visual()
	if visual != null:
		visual.set_sitting(false)
		visual.pick_pack_up()
	_show_hint(false)
	stood_up.emit()
	return true


## Before InteractComponent hears F, so F waits instead of re-triggering the spot.
## While the hours prompt is open it owns the keys.
func _input(event: InputEvent) -> void:
	if not is_sitting() or event.is_echo() or _prompt_open():
		return
	if InputMap.has_action(WAIT_ACTION) and event.is_action_pressed(WAIT_ACTION):
		open_wait()
		get_viewport().set_input_as_handled()
		return
	for action: StringName in STAND_ACTIONS:
		if InputMap.has_action(action) and event.is_action_pressed(action):
			stand()
			if action == &"pause":
				get_viewport().set_input_as_handled()
			return


## Opens the hours prompt in wait mode; false when there is none (headless).
func open_wait() -> bool:
	var prompt := _prompt()
	return prompt != null and prompt.request_wait()


func _prompt() -> SleepPrompt:
	return get_tree().get_first_node_in_group(SleepPrompt.GROUP) as SleepPrompt if is_inside_tree() else null


func _prompt_open() -> bool:
	var prompt := _prompt()
	return prompt != null and prompt.is_open()


func _visual() -> HenryUALAnimation:
	var body: Node = get_parent()
	return body.get_node_or_null(^"HenryUALVisual") as HenryUALAnimation if body != null else null


## "F — wait · move — stand up" at the bottom of the screen while seated.
func _show_hint(show: bool) -> void:
	if not is_inside_tree():
		return
	if _hint == null:
		var layer := CanvasLayer.new()
		layer.layer = 15
		add_child(layer)
		_hint = Label.new()
		_hint.text = tr(HINT_KEY)
		_hint.anchor_left = 0.5
		_hint.anchor_right = 0.5
		_hint.anchor_top = 0.88
		_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		layer.add_child(_hint)
	_hint.visible = show
