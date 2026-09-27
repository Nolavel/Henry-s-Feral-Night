class_name WeatherBeat
extends Node

## First Exit's authored weather turn (#78): calm on the way out, then once per
## run a storm when Henry is far from the start (or after a fallback time), never
## while he is already sheltered. Drives the one WeatherController; saved.

signal beat_started

const WEATHER_SCRIPT: GDScript = preload("res://scripts/systems/world/WeatherController.gd")
const THERMAL_SCRIPT: GDScript = preload("res://scripts/systems/survival/thermal_manager.gd")

@export_group("Before")
## Held from the start until the beat, so the way out reads softer.
@export var calm_profile_id: StringName = &"calm"
@export_group("Trigger")
## Flat metres from Henry's start that set the beat off.
@export var trigger_distance_m: float = 200.0
## Real seconds after which the beat starts anyway (no waiting it out at the door).
@export var fallback_seconds: float = 300.0
@export_group("Beat")
@export var beat_profile_id: StringName = &"blizzard"
## Real seconds the storm holds (the game clock runs fast; a return trip is minutes).
@export var beat_seconds: float = 180.0
## What follows the storm: never straight back to calm.
@export var after_profile_id: StringName = &"windy"

var weather: WeatherController
var thermal: ThermalManager
var player: Node3D
var _start: Vector3
var _elapsed: float = 0.0
var _fired: bool = false
var _beat_left: float = 0.0
var _armed: bool = false


var _search_left: float = 0.0


func _ready() -> void:
	add_to_group(&"saveable")
	var gusts := WindGusts.new()
	gusts.name = "WindGusts"
	add_child(gusts)
	beat_started.connect(gusts.burst)  # the turn itself reads as a burst of streaks


## Scenes not built by world.gd never call on_world_ready; the beat finds the
## one WeatherController (and thermal model) itself, once a second until found.
func _find_systems() -> void:
	for node: Node in get_tree().root.find_children("*", "", true, false):
		if weather == null and node is WeatherController and not (node as WeatherController).profiles.is_empty():
			weather = node  # an empty leftover controller in the environment scene is skipped
		elif thermal == null and node is ThermalManager:
			thermal = node
	if player == null:
		player = get_tree().get_first_node_in_group(&"player") as Node3D
	arm()


func on_world_ready(context: WorldContext) -> void:
	if weather == null or weather.profiles.is_empty():
		weather = context.get_system(WEATHER_SCRIPT) as WeatherController
	if thermal == null:
		thermal = context.get_system(THERMAL_SCRIPT) as ThermalManager
	if player == null:
		player = get_tree().get_first_node_in_group(&"player") as Node3D
	arm()


## Holds calm and notes where Henry starts. Public for tests.
func arm() -> void:
	if _armed or weather == null or player == null:
		return
	_armed = true
	_start = player.global_position
	if not _fired:
		weather.set_weather(calm_profile_id, true, 9999.0)


func has_fired() -> bool:
	return _fired


func _process(delta: float) -> void:
	if _beat_left > 0.0:
		_beat_left -= delta
		if _beat_left <= 0.0:
			weather.set_weather(after_profile_id)  # the scheduler takes over from here
		return
	if not _armed:
		_search_left -= delta
		if _search_left <= 0.0:
			_search_left = 1.0
			_find_systems()
		return
	if _fired:
		return
	_elapsed += delta
	var offset: Vector3 = player.global_position - _start
	offset.y = 0.0
	if offset.length() < trigger_distance_m and _elapsed < fallback_seconds:
		return
	if thermal != null and thermal.is_sheltered():
		return  # the beat is for the trip, not a punishment for being home
	fire()


func fire() -> void:
	if _fired or weather == null:
		return
	_fired = true
	_beat_left = beat_seconds
	weather.set_weather(beat_profile_id, false, 9999.0)
	beat_started.emit()


func is_storming() -> bool:
	return _beat_left > 0.0


func get_save_key() -> StringName:
	return &"weather_beat"


func get_save_data() -> Dictionary:
	return {"fired": _fired, "elapsed": _elapsed, "beat_left": _beat_left}


## A fired beat stays fired; the weather itself is restored by WeatherController.
func load_save_data(data: Dictionary) -> void:
	_fired = bool(data.get("fired", false))
	_elapsed = float(data.get("elapsed", 0.0))
	_beat_left = float(data.get("beat_left", 0.0))
