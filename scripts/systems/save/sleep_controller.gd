class_name SleepController
extends Node

## The only way the game saves: sleeping somewhere sheltered and warm enough.
## Refuses in the open or in the cold, and says exactly why.

## Emitted when sleep is refused, carrying the reason for the HUD.
signal sleep_refused(reason: Refusal)
## Emitted when sleep begins, so the screen can fade and audio can duck.
signal sleep_started(hours: float)
## Emitted after the world has been advanced and the autosave written.
signal sleep_completed(hours: float, saved: bool)
## Emitted after a seated wait, with the hours that actually passed.
signal wait_completed(hours: float, ended_early_key: String)

## Why a sleep attempt was turned down.
enum Refusal { NONE, NOT_SHELTERED, TOO_COLD, TOO_ALERT, ALREADY_SLEEPING }

const HOURS_PER_DAY: float = 24.0
## A seated wait ends early once Henry is this dry and this warm.
const WAIT_DRY_WETNESS: float = 0.02
const WAIT_WARM_BODY: float = 0.97
const WAIT_ENDED_RECOVERED_KEY: String = "WAIT_ENDED_RECOVERED"
const WAIT_ENDED_FIRE_OUT_KEY: String = "WAIT_ENDED_FIRE_OUT"

## Scripts looked up through the world context, never by node path.
const THERMAL_SCRIPT: GDScript = preload("res://scripts/systems/survival/thermal_manager.gd")
const SAVE_SCRIPT: GDScript = preload("res://scripts/systems/save/save_manager.gd")
const DAY_NIGHT_SCRIPT: GDScript = preload("res://scripts/systems/world/DayNightManager.gd")
const BIO_MONITOR_SCRIPT: GDScript = preload("res://scripts/actors/player/henry/Managers/BioMonitorManager.gd")
const SIMULATION_CLOCK_SCRIPT: GDScript = preload("res://scripts/systems/time/simulation_clock.gd")
const ACTION_SYSTEM_SCRIPT: GDScript = preload("res://scripts/systems/actions/time_costed_action_system.gd")

@export_group("Conditions")
## Minimum felt temperature, in Celsius, required to risk sleeping.
@export var minimum_felt_temp_c: float = 5.0
## Sleeping requires an enclosed ThermalZone, not merely a warm spot.
@export var require_shelter: bool = true
## Energy above this fraction means Henry is not tired enough to sleep.
@export_range(0.0, 1.0) var maximum_energy_to_sleep: float = 0.95

@export_group("Duration")
## Default hours slept when the player does not choose a duration.
@export var default_hours: float = 8.0
## Shortest and longest nap the player may choose.
@export var minimum_hours: float = 1.0
@export var maximum_hours: float = 12.0

@export_group("Wiring")
@export var thermal_manager: ThermalManager
@export var bio_monitor: BioMonitorManager
@export var day_night_manager: DayNightManager
@export var save_manager: SaveManager
var simulation_clock: SimulationClock
var action_system: TimeCostedActionSystem

var _is_sleeping: bool = false


## Lifecycle hook world.gd calls once every system exists. Sleeping needs four
## other systems, and none of them should have to be wired in a scene.
func on_world_ready(context: WorldContext) -> void:
	if thermal_manager == null:
		thermal_manager = context.get_system(THERMAL_SCRIPT) as ThermalManager
	if save_manager == null:
		save_manager = context.get_system(SAVE_SCRIPT) as SaveManager
	if day_night_manager == null:
		day_night_manager = context.find_in_scene(DAY_NIGHT_SCRIPT) as DayNightManager
	if bio_monitor == null:
		bio_monitor = context.find_in_scene(BIO_MONITOR_SCRIPT) as BioMonitorManager
	if simulation_clock == null:
		simulation_clock = context.get_system(SIMULATION_CLOCK_SCRIPT) as SimulationClock
	if action_system == null:
		action_system = context.get_system(ACTION_SYSTEM_SCRIPT) as TimeCostedActionSystem


## Whether sleeping is possible right now, without attempting it.
func can_sleep() -> Refusal:
	if _is_sleeping:
		return Refusal.ALREADY_SLEEPING
	if thermal_manager != null:
		if require_shelter and not thermal_manager.is_sheltered():
			return Refusal.NOT_SHELTERED
		if thermal_manager.get_felt_temperature_c() < minimum_felt_temp_c:
			return Refusal.TOO_COLD
	if bio_monitor != null and bio_monitor.calculate_energy_progress() > maximum_energy_to_sleep:
		return Refusal.TOO_ALERT
	return Refusal.NONE


## Attempts to sleep. Advances the world, restores Henry, then autosaves.
func try_sleep(hours: float = -1.0) -> bool:
	var refusal: Refusal = can_sleep()
	if refusal != Refusal.NONE:
		sleep_refused.emit(refusal)
		return false

	var duration: float = default_hours if hours < 0.0 else hours
	duration = clampf(duration, minimum_hours, maximum_hours)

	_is_sleeping = true
	sleep_started.emit(duration)
	var advanced: bool = _run_sleep_action(duration)
	var saved: bool = _autosave(duration) if advanced else false
	_is_sleeping = false
	sleep_completed.emit(duration, saved)
	return advanced


## Waits awake, seated by the stove: no rest, no save. Stops early once Henry is
## dry and warm, or when no fire warms him any more. Returns the hours waited.
func try_wait(hours: float) -> float:
	if _is_sleeping or hours <= 0.0:
		return 0.0
	if action_system != null:
		var request := TimeActionRequest.new()
		request.action_id = &"wait"
		request.duration_hours = hours
		request.reason = &"wait"
		request.simulation_step_hours = 0.25
		request.player_mode = _resolve_player_mode(&"WORKING")
		request.stop_check = _wait_stop_reason
		var result: Dictionary = action_system.run_to_completion(request)
		var elapsed: float = float(result.get("elapsed_hours", 0.0))
		var reason: String = String(result.get("reason", &""))
		wait_completed.emit(elapsed, reason if elapsed < hours else "")
		return elapsed

	var step: float = 0.25
	var elapsed: float = 0.0
	var reason: String = ""
	while elapsed < hours:
		var slice: float = minf(step, hours - elapsed)
		if simulation_clock != null:
			simulation_clock.advance_hours(slice, &"wait")
		else:
			_advance_wait_legacy(slice)
		elapsed += slice
		var stop_reason: StringName = _wait_stop_reason()
		if stop_reason != &"":
			reason = String(stop_reason)
			break
	wait_completed.emit(elapsed, reason if elapsed < hours else "")
	return elapsed


func _wait_stop_reason() -> StringName:
	if thermal_manager == null:
		return &""
	if _recovered():
		return StringName(WAIT_ENDED_RECOVERED_KEY)
	if not _fire_warms_henry():
		return StringName(WAIT_ENDED_FIRE_OUT_KEY)
	return &""


func _recovered() -> bool:
	return thermal_manager.get_wetness() <= WAIT_DRY_WETNESS \
		and thermal_manager.get_body_temperature_normalised() >= WAIT_WARM_BODY


func _fire_warms_henry() -> bool:
	for source: HeatSource in HeatSource.get_all():
		if source.is_burning() and source.get_offset_at(thermal_manager.global_position) > 0.0:
			return true
	return false


## Explains a refusal as a localisation key, never as a hardcoded sentence.
static func describe_refusal(refusal: Refusal) -> String:
	match refusal:
		Refusal.NOT_SHELTERED:
			return "SLEEP_REFUSED_NOT_SHELTERED"
		Refusal.TOO_COLD:
			return "SLEEP_REFUSED_TOO_COLD"
		Refusal.TOO_ALERT:
			return "SLEEP_REFUSED_TOO_ALERT"
		Refusal.ALREADY_SLEEPING:
			return "SLEEP_REFUSED_ALREADY_SLEEPING"
		_:
			return ""


func _run_sleep_action(hours: float) -> bool:
	if action_system != null:
		var request := TimeActionRequest.new()
		request.action_id = &"sleep"
		request.duration_hours = hours
		request.reason = &"sleep"
		request.interruptible = false
		request.simulation_step_hours = 0.25
		request.player_mode = _resolve_player_mode(&"SLEEPING")
		var result: Dictionary = action_system.run_to_completion(request)
		return bool(result.get("completed", false)) 			and is_equal_approx(float(result.get("elapsed_hours", 0.0)), hours)
	_advance_world(hours)
	return true


## Pushes time through the one world clock. Compatibility fallback exists only
## for isolated tests/scenes that do not build the composition root.
func _advance_world(hours: float) -> void:
	if simulation_clock != null:
		simulation_clock.advance_hours(hours, &"sleep")
		return
	if bio_monitor != null:
		bio_monitor.rest_sleep(hours)
	if day_night_manager != null:
		day_night_manager.total_game_time_hours += hours
	if thermal_manager == null:
		return
	var step: float = 0.25
	var elapsed: float = 0.0
	var start_hour: float = _current_hour()
	thermal_manager.reset_clock()
	thermal_manager._on_time_update(start_hour)
	while elapsed < hours:
		var slice: float = minf(step, hours - elapsed)
		elapsed += slice
		thermal_manager._on_time_update(fmod(start_hour + elapsed, HOURS_PER_DAY))
	thermal_manager.reset_clock()


func _advance_wait_legacy(hours: float) -> void:
	if hours <= 0.0:
		return
	if day_night_manager != null:
		day_night_manager.total_game_time_hours += hours
	if bio_monitor != null:
		bio_monitor.pass_awake_hours(hours)
	if thermal_manager != null:
		var start: float = fmod(_current_hour() - hours + HOURS_PER_DAY, HOURS_PER_DAY)
		thermal_manager.reset_clock()
		thermal_manager._on_time_update(start)
		thermal_manager._on_time_update(_current_hour())
		thermal_manager.reset_clock()


## Resolves the authoritative PlayerState enum without defining a parallel enum
## in the action/sleep systems.
func _resolve_player_mode(mode_name: StringName) -> int:
	var state: Node = get_node_or_null(^"/root/PlayerState")
	if state == null:
		return -1
	var script: Script = state.get_script() as Script
	if script == null:
		return -1
	var constants: Dictionary = script.get_script_constant_map()
	var modes: Dictionary = constants.get("Mode", {})
	return int(modes.get(String(mode_name), -1))


func _current_hour() -> float:
	if simulation_clock != null:
		return simulation_clock.get_hour_of_day()
	if day_night_manager != null:
		return day_night_manager.get_current_hour_float()
	return 0.0


## Writes the sleep autosave and reports whether it landed.
func _autosave(hours: float) -> bool:
	if save_manager == null:
		return false
	return save_manager.save_to_slot(SaveManager.SLEEP_SLOT, _build_metadata(hours))


## Summary a load menu can show without parsing the whole payload.
func _build_metadata(hours: float) -> Dictionary:
	var metadata: Dictionary = {"slept_hours": hours}
	if simulation_clock != null:
		metadata["day"] = simulation_clock.get_day_number()
		metadata["hour"] = simulation_clock.get_hour_of_day()
	elif day_night_manager != null:
		metadata["day"] = day_night_manager.get_current_day()
		metadata["hour"] = day_night_manager.get_current_hour_float()
	if thermal_manager != null:
		metadata["body_temp_c"] = thermal_manager.get_body_temperature_c()
	return metadata
