class_name ThermalManager
extends Node3D

## Simulates Henry's body temperature against the felt temperature of his
## surroundings. This is the survival pillar every other cold system feeds.

## Emitted whenever body temperature changes, for HUD and audio.
signal body_temperature_changed(celsius: float, normalised: float)
## Emitted when the felt temperature changes, for the thermometer readout.
signal felt_temperature_changed(celsius: float)
## Emitted when the player crosses into a new hypothermia stage.
signal stage_changed(stage: Stage)
## Emitted once when body temperature reaches the lethal floor.
signal freezing_death_reached
## Emitted when clothing wetness changes, 0.0 dry to 1.0 soaked.
signal wetness_changed(wetness: float)

## Hypothermia stages, ordered from safe to lethal.
enum Stage { NORMAL, CHILLED, COLD, HYPOTHERMIC, CRITICAL }

const HOURS_PER_DAY: float = 24.0

@export_group("Body")
## Core temperature the body holds when the environment is comfortable.
@export var normal_body_temp_c: float = 36.6
## Body temperature at or below which the player dies.
@export var lethal_body_temp_c: float = 28.0
## Felt temperature at which bare skin would neither gain nor lose heat.
@export var comfort_temp_c: float = 20.0
## Degrees of self-generated warmth from basal metabolism. Without this the
## body can never rewarm, because no reachable shelter beats bare-skin comfort.
@export var basal_heat_c: float = 12.0
## Degrees the body moves per in-game hour per degree of comfort deficit.
@export var cooling_coefficient: float = 0.075
## Degrees the body recovers per in-game hour when the surroundings are warm.
@export var rewarm_coefficient: float = 0.55

@export_group("Stage thresholds")
## Body temperature below which each stage begins, warmest first.
@export var chilled_below_c: float = 36.0
@export var cold_below_c: float = 35.0
@export var hypothermic_below_c: float = 33.0
@export var critical_below_c: float = 31.0

@export_group("Insulation")
## Degrees of protection from clothing; raised by better gear.
@export var clothing_insulation_c: float = 6.0
## Fraction of insulation lost when clothing is fully soaked.
@export_range(0.0, 1.0) var wetness_insulation_penalty: float = 0.8
## Wetness units lost per in-game hour while sheltered and warm.
@export var drying_rate_per_hour: float = 0.35

@export_group("Wind chill")
## Degrees lost per metre per second of wind at full exposure.
@export var wind_chill_per_mps: float = 0.55
## Wind speed beyond which extra wind stops mattering, in metres per second.
@export var wind_chill_cap_mps: float = 22.0

@export_group("Exertion")
## Degrees of self-generated warmth at full sprint.
@export var exertion_bonus_c: float = 3.5

@export_group("Wiring")
## Global weather state; without it the model runs on ambient alone.
@export var weather_controller: WeatherController
## Supplies the in-game clock that drives every hourly rate.
@export var day_night_manager: DayNightManager
## Probe area that reports which ThermalZones contain the player.
@export var zone_probe: Area3D
## Ambient air temperature by hour of day, sampled 0.0 to 1.0 across the curve.
@export var ambient_curve: Curve
## Coldest ambient air temperature, at the curve's minimum.
@export var ambient_min_c: float = -28.0
## Warmest ambient air temperature, at the curve's maximum.
@export var ambient_max_c: float = -8.0

var _body_temp_c: float = 36.6
var _felt_temp_c: float = 0.0
var _wetness: float = 0.0
var _stage: Stage = Stage.NORMAL
var _exertion: float = 0.0
var _is_dead: bool = false
var _hours: GameHourTracker = GameHourTracker.new()
var _zones: Array[ThermalZone] = []
var _initialized: bool = false


func _ready() -> void:
	initialize()


## Seeds body temperature and connects the clock and the zone probe.
## Public so headless tests can drive it without waiting for a frame.
func initialize() -> void:
	if _initialized:
		return
	_initialized = true
	_body_temp_c = normal_body_temp_c
	if day_night_manager != null:
		day_night_manager.time_update.connect(_on_time_update)
	else:
		push_warning("ThermalManager: no DayNightManager, body temperature will not tick")
	if zone_probe != null:
		zone_probe.area_entered.connect(_on_zone_entered)
		zone_probe.area_exited.connect(_on_zone_exited)


## Current core temperature in degrees Celsius.
func get_body_temperature_c() -> float:
	return _body_temp_c


## Core temperature as 0.0 at the lethal floor and 1.0 at normal.
func get_body_temperature_normalised() -> float:
	var span: float = maxf(0.001, normal_body_temp_c - lethal_body_temp_c)
	return clampf((_body_temp_c - lethal_body_temp_c) / span, 0.0, 1.0)


## Temperature the player feels right now, after wind, shelter and fires.
func get_felt_temperature_c() -> float:
	return _felt_temp_c


func get_stage() -> Stage:
	return _stage


func get_wetness() -> float:
	return _wetness


## True while the player is inside any zone flagged as an interior.
func is_sheltered() -> bool:
	for zone: ThermalZone in _zones:
		if zone.is_interior:
			return true
	return false


## Feeds movement effort in, 0.0 standing still to 1.0 sprinting.
func set_exertion(value: float) -> void:
	_exertion = clampf(value, 0.0, 1.0)


## Soaks clothing, for falling through ice or standing in heavy snowfall.
func add_wetness(amount: float) -> void:
	_set_wetness(_wetness + amount)


## Drops the clock baseline so the next tick does not bill skipped hours.
## Call this after any deliberate time skip, such as sleeping.
func reset_clock() -> void:
	_hours.reset()


## Applies a direct change to core temperature, for events the ambient model
## does not cover, such as falling into freezing water.
func apply_body_temperature_delta(degrees: float) -> void:
	if _is_dead:
		return
	_body_temp_c = clampf(_body_temp_c + degrees, lethal_body_temp_c, normal_body_temp_c)
	_emit_body_temperature()
	_update_stage()
	if _body_temp_c <= lethal_body_temp_c:
		_is_dead = true
		freezing_death_reached.emit()


## Instantly restores core temperature, for sleeping in a warm shelter.
func restore_body_temperature() -> void:
	_is_dead = false
	_body_temp_c = normal_body_temp_c
	_emit_body_temperature()
	_update_stage()


## Key this system owns in a save file, stated explicitly so renaming the
## script never orphans an existing save.
func get_save_key() -> StringName:
	return &"thermal"


## State the save system persists for this system.
func get_save_data() -> Dictionary:
	return {
		"body_temp_c": _body_temp_c,
		"wetness": _wetness,
		"is_dead": _is_dead,
	}


## Restores persisted state and re-derives everything downstream of it.
func load_save_data(data: Dictionary) -> void:
	_body_temp_c = clampf(
		float(data.get("body_temp_c", normal_body_temp_c)), lethal_body_temp_c, normal_body_temp_c
	)
	_is_dead = bool(data.get("is_dead", false))
	_set_wetness(float(data.get("wetness", 0.0)))
	_hours.reset()
	_emit_body_temperature()
	_update_stage()


## Advances every hourly rate. Driven by the day/night clock, not by frames.
func _on_time_update(current_hour: float) -> void:
	var hours: float = _hours.consume(current_hour)
	if hours <= 0.0 or _is_dead:
		return
	HeatSource.advance_all_fuel(hours)
	for zone: ThermalZone in _zones:
		zone.advance_heating(hours)
	_update_wetness(hours, current_hour)
	_felt_temp_c = _compute_felt_temperature(current_hour)
	felt_temperature_changed.emit(_felt_temp_c)
	_integrate_body_temperature(hours)


## Sums ambient air, weather, wind chill, zones and nearby fires.
func _compute_felt_temperature(current_hour: float) -> float:
	var felt: float = _sample_ambient_c(current_hour)
	var wind: float = 0.0
	if weather_controller != null:
		felt += weather_controller.get_ambient_offset_c()
		wind = weather_controller.get_wind_speed_mps()

	var zone_offset: float = 0.0
	var exposure: float = 1.0
	var best: ThermalZone = _get_dominant_zone()
	if best != null:
		zone_offset = best.get_total_offset_c()
		exposure = best.wind_exposure
	felt += zone_offset

	var capped_wind: float = minf(wind, wind_chill_cap_mps)
	felt -= capped_wind * wind_chill_per_mps * exposure

	for source: HeatSource in HeatSource.get_all():
		felt += source.get_offset_at(global_position)

	felt += exertion_bonus_c * _exertion
	return felt


## Moves body temperature toward the felt temperature through insulation.
func _integrate_body_temperature(hours: float) -> void:
	var insulation: float = clothing_insulation_c * (1.0 - _wetness * wetness_insulation_penalty)
	var effective: float = _felt_temp_c + insulation + basal_heat_c
	var deficit: float = comfort_temp_c - effective
	var previous: float = _body_temp_c

	if deficit > 0.0:
		_body_temp_c -= deficit * cooling_coefficient * hours
	else:
		var headroom: float = normal_body_temp_c - _body_temp_c
		_body_temp_c += minf(headroom, -deficit * rewarm_coefficient * hours)

	_body_temp_c = clampf(_body_temp_c, lethal_body_temp_c, normal_body_temp_c)
	if not is_equal_approx(previous, _body_temp_c):
		_emit_body_temperature()
	_update_stage()

	if _body_temp_c <= lethal_body_temp_c and not _is_dead:
		_is_dead = true
		freezing_death_reached.emit()


## Soaks clothing in exposed snowfall, dries it in warm shelter.
func _update_wetness(hours: float, _current_hour: float) -> void:
	var sheltered: bool = is_sheltered()
	if not sheltered and weather_controller != null:
		var rate: float = weather_controller.get_wetness_rate_per_hour()
		if rate > 0.0:
			_set_wetness(_wetness + rate * hours)
			return
	if sheltered and _felt_temp_c > comfort_temp_c * 0.5:
		_set_wetness(_wetness - drying_rate_per_hour * hours)


## Reads the ambient air temperature curve for the given hour of day.
func _sample_ambient_c(current_hour: float) -> float:
	var t: float = clampf(current_hour / HOURS_PER_DAY, 0.0, 1.0)
	var shaped: float = ambient_curve.sample(t) if ambient_curve != null else 0.5
	return lerpf(ambient_min_c, ambient_max_c, clampf(shaped, 0.0, 1.0))


## Highest-priority zone the player is standing in, or null when outdoors.
func _get_dominant_zone() -> ThermalZone:
	var best: ThermalZone = null
	for zone: ThermalZone in _zones:
		if best == null or zone.zone_priority > best.zone_priority:
			best = zone
	return best


func _set_wetness(value: float) -> void:
	var clamped: float = clampf(value, 0.0, 1.0)
	if is_equal_approx(clamped, _wetness):
		return
	_wetness = clamped
	wetness_changed.emit(_wetness)


func _emit_body_temperature() -> void:
	body_temperature_changed.emit(_body_temp_c, get_body_temperature_normalised())


## Recomputes the hypothermia stage and reports only real transitions.
func _update_stage() -> void:
	var next: Stage = Stage.NORMAL
	if _body_temp_c < critical_below_c:
		next = Stage.CRITICAL
	elif _body_temp_c < hypothermic_below_c:
		next = Stage.HYPOTHERMIC
	elif _body_temp_c < cold_below_c:
		next = Stage.COLD
	elif _body_temp_c < chilled_below_c:
		next = Stage.CHILLED
	if next == _stage:
		return
	_stage = next
	stage_changed.emit(_stage)


func _on_zone_entered(area: Area3D) -> void:
	var zone := area as ThermalZone
	if zone != null and not _zones.has(zone):
		_zones.append(zone)


func _on_zone_exited(area: Area3D) -> void:
	var zone := area as ThermalZone
	if zone != null:
		_zones.erase(zone)
