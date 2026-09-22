class_name ColdWaterImmersion
extends Node

## Falling through the ice is a story beat, not a reload. The player is soaked,
## losing heat fast, and has to thrash, climb out and find a fire.

## Emitted when the player goes under.
signal immersion_started(world_position: Vector3)
## Emitted while submerged, with seconds elapsed and whether climbing is allowed.
signal immersion_tick(seconds: float, can_climb_out: bool)
## Emitted once the player is back on solid ground.
signal climbed_out(world_position: Vector3)

@export_group("Wiring")
@export var ice_field: IceField
@export var thermal_manager: ThermalManager
## Optional; the field stops loading tiles while the player is in the water.
@export var pause_ice_while_submerged: bool = true

@export_group("Tuning")
## Profile supplying the immersion rates; falls back to the field's profile.
@export var profile: IceProfile

var _is_submerged: bool = false
var _seconds: float = 0.0
var _entry_position: Vector3 = Vector3.ZERO


func _ready() -> void:
	if ice_field != null:
		ice_field.tile_broke.connect(_on_tile_broke)


func is_submerged() -> bool:
	return _is_submerged


## Seconds spent in the water so far.
func get_seconds_submerged() -> float:
	return _seconds


## True once the player has thrashed long enough to pull themselves out.
func can_climb_out() -> bool:
	return _is_submerged and _seconds >= _resolved_profile().climb_out_delay_s


## Puts the player in the water. Soaks clothing immediately.
func submerge(world_position: Vector3) -> void:
	if _is_submerged:
		return
	_is_submerged = true
	_seconds = 0.0
	_entry_position = world_position
	if thermal_manager != null:
		thermal_manager.add_wetness(1.0)
	if pause_ice_while_submerged and ice_field != null:
		ice_field.set_enabled(false)
	immersion_started.emit(world_position)


## Advances the immersion. Body heat is billed in game hours, like every other
## survival rate, so it stays consistent with the thermal model.
func step(delta_seconds: float, delta_hours: float) -> void:
	if not _is_submerged:
		return
	_seconds += delta_seconds
	if thermal_manager != null and delta_hours > 0.0:
		var loss: float = _resolved_profile().immersion_body_loss_per_hour * delta_hours
		thermal_manager.apply_body_temperature_delta(-loss)
	immersion_tick.emit(_seconds, can_climb_out())


## Pulls the player out. Refuses while they are still thrashing.
func climb_out(world_position: Vector3) -> bool:
	if not can_climb_out():
		return false
	_is_submerged = false
	_seconds = 0.0
	if pause_ice_while_submerged and ice_field != null:
		ice_field.set_enabled(true)
	climbed_out.emit(world_position)
	return true


## Where the player went in, for placing them back at the hole's edge.
func get_entry_position() -> Vector3:
	return _entry_position


func _on_tile_broke(_tile: Vector2i, world_position: Vector3) -> void:
	submerge(world_position)


func _resolved_profile() -> IceProfile:
	if profile != null:
		return profile
	if ice_field != null and ice_field.profile != null:
		return ice_field.profile
	return IceProfile.new()
