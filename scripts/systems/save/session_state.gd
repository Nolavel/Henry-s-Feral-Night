class_name SessionState
extends Node

## Saves what belongs to no single system: where Henry lies down and what time
## it is. Without it Continue drops him at the spawn marker at dawn.

## Looked up through the world context, never by node path.
const DAY_NIGHT_SCRIPT: GDScript = preload("res://scripts/systems/world/DayNightManager.gd")
const SIMULATION_CLOCK_SCRIPT: GDScript = preload("res://scripts/systems/time/simulation_clock.gd")

var _player: Node3D
var _clock: SimulationClock
var _day_night: DayNightManager


func on_world_ready(context: WorldContext) -> void:
	_player = context.player
	_clock = context.get_system(SIMULATION_CLOCK_SCRIPT) as SimulationClock
	_day_night = context.find_in_scene(DAY_NIGHT_SCRIPT) as DayNightManager


## Key this system owns in a save file, stated explicitly so renaming the
## script never orphans an existing save.
func get_save_key() -> StringName:
	return &"session"


func get_save_data() -> Dictionary:
	var data: Dictionary = {}
	if _clock != null:
		data["game_hours"] = _clock.get_total_hours()
	elif _day_night != null:
		data["game_hours"] = _day_night.total_game_time_hours
	if _player != null and _player.is_inside_tree():
		var at: Vector3 = _player.global_position
		data["player_position"] = [at.x, at.y, at.z]
		data["player_yaw"] = _player.global_rotation.y
	return data


func load_save_data(data: Dictionary) -> void:
	if data.has("game_hours"):
		var hours: float = float(data["game_hours"])
		if _clock != null:
			_clock.set_total_hours(hours, &"load")
		elif _day_night != null:
			_day_night.total_game_time_hours = hours
	if _player != null and _player.is_inside_tree() and data.has("player_position"):
		var at: Array = data["player_position"]
		if at.size() == 3:
			_player.global_position = Vector3(float(at[0]), float(at[1]), float(at[2]))
		_player.global_rotation.y = float(data.get("player_yaw", _player.global_rotation.y))
		_player.reset_physics_interpolation()
		## A CharacterBody carries velocity; landing with the old one would slide.
		var body := _player as CharacterBody3D
		if body != null:
			body.velocity = Vector3.ZERO
