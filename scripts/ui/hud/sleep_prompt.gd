class_name SleepPrompt
extends Control

## Hold-to-open sleep dialog. S is also move_backward, so the hold only charges
## while sleeping is actually possible and the player is not moving.

## Emitted while the hold charges, 0.0 to 1.0, for the ring or bar.
signal hold_progress_changed(progress: float)
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

const HOLD_ACTION: StringName = &"sleep"
const CONFIRM_ACTION: StringName = &"interact"
const CANCEL_ACTION: StringName = &"sleep_cancel"
const LESS_ACTION: StringName = &"sleep_hours_less"
const MORE_ACTION: StringName = &"sleep_hours_more"
const MOVE_ACTIONS: Array[StringName] = [
	&"move_forward", &"move_backward", &"move_left", &"move_right", &"jump", &"sprint"
]

@export_group("Hold")
## Seconds the player must hold before the dialog opens. A tap does nothing.
@export var hold_seconds: float = 1.0

@export_group("Duration")
@export var minimum_hours: int = 1
@export var maximum_hours: int = 8
@export var default_hours: int = 8

@export_group("Wiring")
@export var sleep_controller: SleepController
## Optional label showing the chosen duration; text is set by the owning scene.
@export var hours_label: Label
## Optional bar or ring filled by the hold, expects a 0..1 value range.
@export var hold_indicator: Range
## Optional panel shown while the dialog is open.
@export var dialog_panel: Control
## Optional hint shown only while the dialog is closed.
@export var hold_hint: Control
## Optional warning shown when the fire will not last the chosen duration.
@export var warning_label: Control

var _hold_time: float = 0.0
var _is_open: bool = false
var _hours: int = 8


## Lifecycle hook world.gd calls on every UI scene it builds. The prompt is
## useless without the controller, so it finds it rather than being wired.
func on_world_ready(context: WorldContext) -> void:
	if sleep_controller == null:
		sleep_controller = context.get_system(SLEEP_CONTROLLER_SCRIPT) as SleepController


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	resolve_nodes()
	_hours = clampi(default_hours, minimum_hours, maximum_hours)
	_set_dialog_visible(false)
	set_process(true)


## Fills in any widget the scene did not assign. A node-reference export on a
## scene root cannot resolve, because root properties are set before children
## exist, so the packed scene relies on these conventional names.
func resolve_nodes() -> void:
	if dialog_panel == null:
		dialog_panel = get_node_or_null("Dialog") as Control
	if hold_indicator == null:
		hold_indicator = get_node_or_null("HoldIndicator") as Range
	if hours_label == null:
		hours_label = get_node_or_null("Dialog/Rows/HoursRow/Hours") as Label
	if hold_hint == null:
		hold_hint = get_node_or_null("HoldHint") as Control
	if warning_label == null:
		warning_label = get_node_or_null("Dialog/Rows/Warning") as Control


func _process(delta: float) -> void:
	if _is_open:
		return
	_update_hold(delta)


func _input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event.is_action_pressed(CANCEL_ACTION):
		close()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(LESS_ACTION):
		_set_hours(_hours - 1)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(MORE_ACTION):
		_set_hours(_hours + 1)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(CONFIRM_ACTION):
		confirm()
		get_viewport().set_input_as_handled()


## Hours the player currently has selected.
func get_selected_hours() -> int:
	return _hours


func is_open() -> bool:
	return _is_open


## Progress of the current hold, 0.0 to 1.0.
func get_hold_progress() -> float:
	return clampf(_hold_time / maxf(0.01, hold_seconds), 0.0, 1.0)


## True when holding would charge right now: sleep is possible and Henry is
## standing still, so S is unambiguous rather than a walk-backwards input.
func can_begin_hold() -> bool:
	if sleep_controller == null:
		return false
	if sleep_controller.can_sleep() != SleepController.Refusal.NONE:
		return false
	return not _is_moving()


## Charges or decays the hold. Public so tests can drive it without a frame.
func update_hold(delta: float) -> void:
	_update_hold(delta)


## Opens the dialog and pauses the world behind it.
func open() -> void:
	if _is_open:
		return
	_is_open = true
	_hold_time = 0.0
	hold_progress_changed.emit(0.0)
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
	_hold_time = 0.0
	hold_progress_changed.emit(0.0)
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


func _update_hold(delta: float) -> void:
	if not Input.is_action_pressed(HOLD_ACTION) or not can_begin_hold():
		if _hold_time > 0.0:
			_hold_time = 0.0
			if hold_indicator != null:
				hold_indicator.value = 0.0
			hold_progress_changed.emit(0.0)
		return
	_hold_time += delta
	var progress: float = get_hold_progress()
	if hold_indicator != null:
		hold_indicator.value = progress
	hold_progress_changed.emit(progress)
	if _hold_time >= hold_seconds:
		open()


## Any movement intent cancels the hold, which is what keeps S usable for walking.
func _is_moving() -> bool:
	for action: StringName in MOVE_ACTIONS:
		if action == HOLD_ACTION:
			continue
		if InputMap.has_action(action) and Input.is_action_pressed(action):
			return true
	return false


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


func _set_dialog_visible(open_now: bool) -> void:
	if dialog_panel != null:
		dialog_panel.visible = open_now
	if hold_indicator != null:
		hold_indicator.visible = not open_now
	if hold_hint != null:
		hold_hint.visible = not open_now
	dialog_visibility_changed.emit(open_now)
