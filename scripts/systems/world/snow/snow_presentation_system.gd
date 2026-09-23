class_name SnowPresentationSystem
extends Node

## The one writer of the snow shader globals. Reads the weather and the air,
## never owns either, and knows nothing about what the ground is made of.

## Global names, declared in project.godot under [shader_globals].
const GLOBAL_SNOW_COVER: StringName = &"snow_cover"
const GLOBAL_FROST_AMOUNT: StringName = &"frost_amount"

## Looked up through the world context, never by node path.
const WEATHER_SCRIPT: GDScript = preload("res://scripts/systems/world/WeatherController.gd")
const THERMAL_SCRIPT: GDScript = preload("res://scripts/systems/survival/thermal_manager.gd")

## Changes smaller than this are not worth a render-thread write.
const EPSILON: float = 0.002

@export_group("Frost")
## Outdoor air at which rime starts to form on vertical surfaces.
@export var frost_starts_c: float = -2.0
## Outdoor air at which rime is fully grown.
@export var frost_full_c: float = -25.0

@export_group("Fallback")
## Cover used when no weather is running, so a bare scene still reads as winter.
@export_range(0.0, 1.0) var default_snow_cover: float = 0.5

var _weather: WeatherController
var _thermal: ThermalManager
var _written_cover: float = -1.0
var _written_frost: float = -1.0


func on_world_ready(context: WorldContext) -> void:
	_weather = context.get_system(WEATHER_SCRIPT) as WeatherController
	_thermal = context.get_system(THERMAL_SCRIPT) as ThermalManager
	refresh()


func _process(_delta: float) -> void:
	refresh()


## Recomputes both values and writes the ones that moved.
func refresh() -> void:
	_write(GLOBAL_SNOW_COVER, compute_snow_cover(), true)
	_write(GLOBAL_FROST_AMOUNT, compute_frost_amount(), false)


func compute_snow_cover() -> float:
	if _weather == null:
		return default_snow_cover
	return clampf(_weather.get_snow_cover(), 0.0, 1.0)


## Rime grows as outdoor air falls from frost_starts_c to frost_full_c.
func compute_frost_amount() -> float:
	if _thermal == null:
		return 0.0
	return clampf(inverse_lerp(frost_starts_c, frost_full_c, _thermal.get_outdoor_air_c()), 0.0, 1.0)


## The last values written, for tests and debug overlays; never read back
## from RenderingServer, which would stall on the render thread.
func get_written_snow_cover() -> float:
	return _written_cover


func get_written_frost_amount() -> float:
	return _written_frost


func _write(global_name: StringName, value: float, is_cover: bool) -> void:
	var last: float = _written_cover if is_cover else _written_frost
	if last >= 0.0 and absf(value - last) < EPSILON:
		return
	if is_cover:
		_written_cover = value
	else:
		_written_frost = value
	RenderingServer.global_shader_parameter_set(global_name, value)
