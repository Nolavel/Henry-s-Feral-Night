class_name SleepPrompt
extends Control

## Sleep dialog, opened by a SleepSpot through the normal interact path. Hours
## step with the mouse wheel or left/right; F or Enter sleeps, Esc cancels.

## Emitted when the dialog opens or closes.
signal dialog_visibility_changed(open: bool)
## Emitted when the chosen duration changes, so the label can follow.
signal hours_changed(hours: int)
## Emitted when sleep was refused, carrying a localisation key.
signal refused(reason_key: String)
## Emitted when the fire's ability to outlast the chosen duration changes.
signal fuel_warning_changed(fire_outlasts_sleep: bool)

## Looked up through the world context, never by node path.
const SLEEP_CONTROLLER_SCRIPT: GDScript = preload("res://scripts/systems/save/sleep_controller.gd")

## Autoload that owns the interact key; looked up rather than preloaded so a
## headless suite without autoloads still runs this scene.
const INPUT_SYSTEMS_PATH: NodePath = ^"/root/InputSystems"

## Group SleepSpots use to find the dialog; there is one per world.
const GROUP: StringName = &"sleep_prompt"
const CONFIRM_ACTIONS: Array[StringName] = [&"interact", &"ui_accept"]
const CANCEL_ACTIONS: Array[StringName] = [&"sleep_cancel", &"ui_cancel"]

@export_group("Duration")
@export var minimum_hours: int = 1
@export var maximum_hours: int = 8
@export var default_hours: int = 8

@export_group("Wiring")
@export var sleep_controller: SleepController
## Optional label showing the chosen duration; text is set by the owning scene.
@export var hours_label: Label
## Optional panel shown while the dialog is open.
@export var dialog_panel: Control
## Optional warning shown when the fire will not last the chosen duration.
@export var warning_label: Control

var _is_open: bool = false
var _hours: int = 8


## Lifecycle hook world.gd calls on every UI scene it builds. The prompt is
## useless without the controller, so it finds it rather than being wired.
func on_world_ready(context: WorldContext) -> void:
	if sleep_controller == null:
		sleep_controller = context.get_system(SLEEP_CONTROLLER_SCRIPT) as SleepController


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group(GROUP)
	resolve_nodes()
	_hours = clampi(default_hours, minimum_hours, maximum_hours)
	_set_dialog_visible(false)


## Fills in any widget the scene did not assign. A node-reference export on a
## scene root cannot resolve, because root properties are set before children
## exist, so the packed scene relies on these conventional names.
func resolve_nodes() -> void:
	if dialog_panel == null:
		dialog_panel = get_node_or_null("Dialog") as Control
	if hours_label == null:
		hours_label = get_node_or_null("Dialog/Rows/HoursRow/Hours") as Label
	if warning_label == null:
		warning_label = get_node_or_null("Dialog/Rows/Warning") as Control


func _input(event: InputEvent) -> void:
	if not _is_open:
		return
	var step: int = _hour_step(event)
	if step != 0:
		_set_hours(_hours + step)
	elif _pressed_any(event, CANCEL_ACTIONS):
		close()
	elif _pressed_any(event, CONFIRM_ACTIONS):
		confirm()
	else:
		return
	get_viewport().set_input_as_handled()


## +1 or -1 for wheel up/down and right/left, 0 for anything else.
func _hour_step(event: InputEvent) -> int:
	var wheel := event as InputEventMouseButton
	if wheel != null and wheel.pressed:
		if wheel.button_index == MOUSE_BUTTON_WHEEL_UP:
			return 1
		if wheel.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			return -1
	if event.is_action_pressed(&"ui_right"):
		return 1
	if event.is_action_pressed(&"ui_left"):
		return -1
	return 0


func _pressed_any(event: InputEvent, actions: Array[StringName]) -> bool:
	for action: StringName in actions:
		if InputMap.has_action(action) and event.is_action_pressed(action):
			return true
	return false


## Hours the player currently has selected.
func get_selected_hours() -> int:
	return _hours


func is_open() -> bool:
	return _is_open


## Opens the dialog when sleeping is possible here; otherwise emits refused
## with the reason and stays closed. SleepSpot calls this on F.
func request_open() -> bool:
	if sleep_controller == null:
		return false
	var refusal: SleepController.Refusal = sleep_controller.can_sleep()
	if refusal != SleepController.Refusal.NONE:
		refused.emit(SleepController.describe_refusal(refusal))
		return false
	open()
	return true


## Opens the dialog and pauses the world behind it.
func open() -> void:
	if _is_open:
		return
	_is_open = true
	_set_hours(_hours)
	_set_dialog_visible(true)
	## Pause belongs to PlayerState, which owns the coupling between it and
	## mode. Setting get_tree().paused here would be a second owner.
	_player_state_call(&"open_menu")


## Closes the dialog without sleeping and unpauses the world.
func close() -> void:
	if not _is_open:
		return
	_is_open = false
	_set_dialog_visible(false)
	_player_state_call(&"close_menu")


## Attempts the sleep with the selected duration, then closes.
func confirm() -> bool:
	if sleep_controller == null:
		return false
	var refusal: SleepController.Refusal = sleep_controller.can_sleep()
	if refusal != SleepController.Refusal.NONE:
		refused.emit(SleepController.describe_refusal(refusal))
		close()
		return false
	var slept: bool = sleep_controller.try_sleep(float(_hours))
	close()
	return slept


## PlayerState is an autoload, but this scene is also driven directly by tests
## where it may not exist, so the call is guarded rather than assumed.
func _player_state_call(method: StringName) -> void:
	if not is_inside_tree():
		return
	var state: Node = get_node_or_null(^"/root/PlayerState")
	if state != null:
		state.call(method)


func _set_hours(value: int) -> void:
	_hours = clampi(value, minimum_hours, maximum_hours)
	if hours_label != null:
		hours_label.text = str(_hours)
	hours_changed.emit(_hours)
	_update_fuel_warning()


## True when every fire warming this spot outlasts the chosen duration.
func fire_outlasts_sleep() -> bool:
	var relevant: Array[HeatSource] = _get_relevant_sources()
	if relevant.is_empty():
		return false
	for source: HeatSource in relevant:
		if source.burn_duration_h <= 0.0:
			return true
		if source.get_remaining_hours() >= float(_hours):
			return true
	return false


## Fires that are actually keeping this spot warm right now.
func _get_relevant_sources() -> Array[HeatSource]:
	var relevant: Array[HeatSource] = []
	if sleep_controller == null or sleep_controller.thermal_manager == null:
		return relevant
	var origin: Vector3 = sleep_controller.thermal_manager.global_position
	for source: HeatSource in HeatSource.get_all():
		if source.is_burning() and source.get_offset_at(origin) > 0.0:
			relevant.append(source)
	return relevant


## Shows the warning only when the player would wake up in a cold shelter.
func _update_fuel_warning() -> void:
	var outlasts: bool = fire_outlasts_sleep()
	if warning_label != null:
		warning_label.visible = not outlasts
	fuel_warning_changed.emit(outlasts)


## Takes the interact key while the dialog is up, so confirming sleep does not
## also trigger whatever the player happens to be standing next to.
func _set_dialog_visible(open_now: bool) -> void:
	_claim_interact(open_now)
	if dialog_panel != null:
		dialog_panel.visible = open_now
	dialog_visibility_changed.emit(open_now)


## Claims or releases the interact key through InputSystems, when it exists.
## Absent in a bare headless suite, so its absence is not an error.
func _claim_interact(claim: bool) -> void:
	var input_systems: Node = get_node_or_null(INPUT_SYSTEMS_PATH)
	if input_systems == null:
		return
	if claim:
		input_systems.claim_interact(self)
	else:
		input_systems.release_interact(self)


## Called by InputSystems while this prompt owns the interact key.
func on_interact_claimed() -> void:
	if _is_open:
		confirm()


func on_interact_held(_duration: float) -> void:
	pass


func on_interact_released(_duration: float) -> void:
	pass
