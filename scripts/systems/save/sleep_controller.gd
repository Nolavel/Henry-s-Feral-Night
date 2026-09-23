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

## Why a sleep attempt was turned down.
enum Refusal { NONE, NOT_SHELTERED, TOO_COLD, TOO_ALERT, ALREADY_SLEEPING }

const HOURS_PER_DAY: float = 24.0

## Scripts looked up through the world context, never by node path.
const THERMAL_SCRIPT: GDScript = preload("res://scripts/systems/survival/thermal_manager.gd")
const SAVE_SCRIPT: GDScript = preload("res://scripts/systems/save/save_manager.gd")
const DAY_NIGHT_SCRIPT: GDScript = preload("res://scripts/systems/world/DayNightManager.gd")
const BIO_MONITOR_SCRIPT: GDScript = preload("res://scripts/actors/player/henry/Managers/BioMonitorManager.gd")

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
	_advance_world(duration)
	var saved: bool = _autosave(duration)
	_is_sleeping = false
	sleep_completed.emit(duration, saved)
	return true


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


## Pushes the clock forward and lets each survival system settle to the new time.
func _advance_world(hours: float) -> void:
	if bio_monitor != null:
		bio_monitor.rest_sleep(hours)
	if day_night_manager != null:
		day_night_manager.total_game_time_hours += hours
	if thermal_manager == null:
		return
	## The body keeps simulating through the night rather than being handed a
	## free reset, so sleeping in a cooling shelter still costs something.
	var step: float = 0.25
	var elapsed: float = 0.0
	while elapsed < hours:
		elapsed += step
		var clock: float = fmod(_current_hour() + elapsed, HOURS_PER_DAY)
		thermal_manager._on_time_update(clock)
	thermal_manager.reset_clock()


func _current_hour() -> float:
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
	if day_night_manager != null:
		metadata["day"] = day_night_manager.get_current_day()
		metadata["hour"] = day_night_manager.get_current_hour_float()
	if thermal_manager != null:
		metadata["body_temp_c"] = thermal_manager.get_body_temperature_c()
	return metadata
