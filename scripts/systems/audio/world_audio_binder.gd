class_name WorldAudioBinder
extends Node

## Feeds the world into SoundSystem parameters: wind speed from the weather,
## "interior" from shelter, and Henry's planted feet into the footstep event.

const WEATHER_SCRIPT: GDScript = preload("res://scripts/systems/world/WeatherController.gd")
const THERMAL_SCRIPT: GDScript = preload("res://scripts/systems/survival/thermal_manager.gd")
const PARAM_WIND: StringName = &"wind_speed"
const PARAM_INTERIOR: StringName = &"interior"
const PARAM_FOOT_SPEED: StringName = &"foot_speed"

## Played on every planted foot; empty until footstep recordings exist.
@export var footstep_event: SoundEvent
## Beds started with the world, e.g. the wind layer.
@export var ambience_layers: Array[SoundLayer] = []

var _sound: Node
var _thermal: ThermalManager
var _layer_handles: Array[int] = []


func on_world_ready(context: WorldContext) -> void:
	_sound = get_node_or_null(^"/root/SoundSystem")
	if _sound == null:
		push_warning("WorldAudioBinder: SoundSystem autoload missing, world stays silent.")
		return
	var weather: WeatherController = context.get_system(WEATHER_SCRIPT) as WeatherController
	if weather != null:
		weather.conditions_updated.connect(_on_conditions_updated)
		_sound.call(&"set_parameter", PARAM_WIND, weather.get_wind_speed_mps())
	_thermal = context.get_system(THERMAL_SCRIPT) as ThermalManager
	if _thermal != null:
		_thermal.sheltered_changed.connect(_on_sheltered_changed)
		_on_sheltered_changed(_thermal.is_sheltered())
	_bind_feet(context.player)
	for layer: SoundLayer in ambience_layers:
		_layer_handles.append(int(_sound.call(&"start_layer", layer)))


func _exit_tree() -> void:
	if _sound == null:
		return
	for handle: int in _layer_handles:
		_sound.call(&"stop", handle)


func _bind_feet(player: Node3D) -> void:
	if player == null:
		return
	var sensor: FootContactSensor = player.get_node_or_null(^"FootContactSensor") as FootContactSensor
	if sensor != null:
		sensor.foot_planted.connect(_on_foot_planted)


func _on_conditions_updated(_offset_c: float, wind_speed_mps: float, _snowfall: float) -> void:
	_sound.call(&"set_parameter", PARAM_WIND, wind_speed_mps)


func _on_sheltered_changed(is_sheltered: bool) -> void:
	_sound.call(&"set_parameter", PARAM_INTERIOR, 1.0 if is_sheltered else 0.0)


func _on_foot_planted(
	_side: int, position: Vector3, _normal: Vector3, _forward: Vector3, speed_mps: float
) -> void:
	_sound.call(&"set_parameter", PARAM_FOOT_SPEED, speed_mps)
	if footstep_event != null:
		_sound.call(&"play", footstep_event, position)
