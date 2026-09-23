class_name SnowPresentationSystem
extends Node

## The one writer of the snow shader globals. Owns the settled snow and rime as
## world state, driven by the weather and the air but never mirroring them.

## Global names, declared in project.godot under [shader_globals].
const GLOBAL_SNOW_COVER: StringName = &"snow_cover"
const GLOBAL_FROST_AMOUNT: StringName = &"frost_amount"

## Looked up through the world context, never by node path.
const WEATHER_SCRIPT: GDScript = preload("res://scripts/systems/world/WeatherController.gd")
const THERMAL_SCRIPT: GDScript = preload("res://scripts/systems/survival/thermal_manager.gd")
const DAY_NIGHT_SCRIPT: GDScript = preload("res://scripts/systems/world/DayNightManager.gd")

## Changes smaller than this are not worth a render-thread write.
const EPSILON: float = 0.002

@export_group("Settled snow")
## How fast cover builds towards the weather's level in a full whiteout, per
## game hour. Scaled by snowfall density; nothing builds without snow falling.
@export var build_per_hour: float = 0.6
## How fast cover settles down towards a lighter weather's level, per game
## hour. Slow on purpose: a blizzard's snow does not vanish when it stops.
@export var settle_per_hour: float = 0.03
## Extra loss per game hour for each degree the outdoor air sits above zero.
@export var melt_per_hour_per_c: float = 0.02

@export_group("Frost")
## Outdoor air at which rime starts to form on vertical surfaces.
@export var frost_starts_c: float = -2.0
## Outdoor air at which rime is fully grown.
@export var frost_full_c: float = -25.0
## How fast rime grows or sheds, per game hour; it never snaps.
@export var frost_per_hour: float = 0.25

@export_group("Fallback")
## Cover used when no weather is running, so a bare scene still reads as winter.
@export_range(0.0, 1.0) var default_snow_cover: float = 0.5

var _weather: WeatherController
var _thermal: ThermalManager
var _clock: DayNightManager
var _hours: GameHourTracker = GameHourTracker.new()
var _settled: float = -1.0
var _frost: float = -1.0
var _written_cover: float = -1.0
var _written_frost: float = -1.0


func on_world_ready(context: WorldContext) -> void:
	_weather = context.get_system(WEATHER_SCRIPT) as WeatherController
	_thermal = context.get_system(THERMAL_SCRIPT) as ThermalManager
	_clock = context.find_in_scene(DAY_NIGHT_SCRIPT) as DayNightManager
	if _clock != null and not _clock.time_update.is_connected(_on_time_update):
		_clock.time_update.connect(_on_time_update)
	refresh()


## Writes the current state. The state itself only moves with game time.
func refresh() -> void:
	_seed_if_needed()
	_write(GLOBAL_SNOW_COVER, _settled, true)
	_write(GLOBAL_FROST_AMOUNT, _frost, false)


## Moves settled snow and rime on by a span of game time, then writes.
func advance_hours(hours: float) -> void:
	_seed_if_needed()
	if hours <= 0.0:
		return
	var target: float = weather_snow_cover()
	var density: float = _weather.get_snowfall_density() if _weather != null else 0.0
	if target > _settled:
		_settled = move_toward(_settled, target, build_per_hour * clampf(density, 0.0, 1.0) * hours)
	else:
		_settled = move_toward(_settled, target, settle_per_hour * hours)
	var air: float = _thermal.get_outdoor_air_c() if _thermal != null else -10.0
	if air > 0.0:
		_settled = maxf(0.0, _settled - melt_per_hour_per_c * air * hours)
	_frost = move_toward(_frost, target_frost(), frost_per_hour * hours)
	refresh()


## Cover the current weather would leave if it lasted forever.
func weather_snow_cover() -> float:
	if _weather == null:
		return default_snow_cover
	return clampf(_weather.get_snow_cover(), 0.0, 1.0)


## Rime the current air would grow if it lasted: frost_starts_c to frost_full_c.
func target_frost() -> float:
	if _thermal == null:
		return 0.0
	return clampf(inverse_lerp(frost_starts_c, frost_full_c, _thermal.get_outdoor_air_c()), 0.0, 1.0)


func get_settled_snow() -> float:
	return _settled


func get_frost() -> float:
	return _frost


## The last values written, for tests and debug overlays; never read back
## from RenderingServer, which would stall on the render thread.
func get_written_snow_cover() -> float:
	return _written_cover


func get_written_frost_amount() -> float:
	return _written_frost


## Key this system owns in a save file, stated explicitly so renaming the
## script never orphans an existing save.
func get_save_key() -> StringName:
	return &"snow"


func get_save_data() -> Dictionary:
	return {"settled": _settled, "frost": _frost}


func load_save_data(data: Dictionary) -> void:
	_settled = clampf(float(data.get("settled", weather_snow_cover())), 0.0, 1.0)
	_frost = clampf(float(data.get("frost", target_frost())), 0.0, 1.0)
	_hours.reset()
	refresh()


func _on_time_update(current_hour: float) -> void:
	advance_hours(_hours.consume(current_hour))


## A fresh world starts at whatever its weather and air imply, not bare.
func _seed_if_needed() -> void:
	if _settled < 0.0:
		_settled = weather_snow_cover()
	if _frost < 0.0:
		_frost = target_frost()


func _write(global_name: StringName, value: float, is_cover: bool) -> void:
	var last: float = _written_cover if is_cover else _written_frost
	if last >= 0.0 and absf(value - last) < EPSILON:
		return
	if is_cover:
		_written_cover = value
	else:
		_written_frost = value
	RenderingServer.global_shader_parameter_set(global_name, value)
