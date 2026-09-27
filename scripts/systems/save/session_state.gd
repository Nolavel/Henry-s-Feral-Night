class_name SessionState
extends Node

## Saves what belongs to no single system: where Henry lies down and what time
## it is. Without it Continue drops him at the spawn marker at dawn.

## Looked up through the world context, never by node path.
const DAY_NIGHT_SCRIPT: GDScript = preload("res://scripts/systems/world/DayNightManager.gd")
const THERMAL_SCRIPT: GDScript = preload("res://scripts/systems/survival/thermal_manager.gd")
const WEATHER_SCRIPT: GDScript = preload("res://scripts/systems/world/WeatherController.gd")

var _player: Node3D
var _clock: DayNightManager
var _thermal: ThermalManager
var _weather: WeatherController


func on_world_ready(context: WorldContext) -> void:
	_player = context.player
	_clock = context.find_in_scene(DAY_NIGHT_SCRIPT) as DayNightManager
	_thermal = context.get_system(THERMAL_SCRIPT) as ThermalManager
	_weather = context.get_system(WEATHER_SCRIPT) as WeatherController


## Key this system owns in a save file, stated explicitly so renaming the
## script never orphans an existing save.
func get_save_key() -> StringName:
	return &"session"


func get_save_data() -> Dictionary:
	var data: Dictionary = {}
	if _clock != null:
		data["game_hours"] = _clock.total_game_time_hours
	if _player != null and _player.is_inside_tree():
		var at: Vector3 = _player.global_position
		data["player_position"] = [at.x, at.y, at.z]
		data["player_yaw"] = _player.global_rotation.y
	return data


func load_save_data(data: Dictionary) -> void:
	if _clock != null and data.has("game_hours"):
		_clock.total_game_time_hours = float(data["game_hours"])
		## The clock jumped; the hour trackers must not bill the jump as elapsed.
		if _thermal != null:
			_thermal.reset_clock()
		if _weather != null:
			_weather.reset_clock()
	if _player != null and _player.is_inside_tree() and data.has("player_position"):
		var at: Array = data["player_position"]
		if at.size() == 3:
			_player.global_position = Vector3(float(at[0]), float(at[1]), float(at[2]))
		_player.global_rotation.y = float(data.get("player_yaw", _player.global_rotation.y))
		## A CharacterBody carries velocity; landing with the old one would slide.
		var body := _player as CharacterBody3D
		if body != null:
			body.velocity = Vector3.ZERO
