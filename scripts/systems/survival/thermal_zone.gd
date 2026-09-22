@tool
class_name ThermalZone
extends Area3D

## Static volume that modifies the felt temperature inside it: shelter interiors,
## wind shadows, caves. Placed in the level, never moved with the player.

## Emitted when the zone's own warmth changes, so interiors can be heated.
signal warmth_changed(current_offset_c: float)

@export_group("Thermal")
## Degrees added to the felt temperature while inside. Interiors are positive.
@export var temperature_offset_c: float = 0.0
## How much of the outside wind still reaches the player: 0 sealed, 1 exposed.
@export_range(0.0, 1.0) var wind_exposure: float = 1.0
## Marks a fully enclosed space; blocks snowfall wetness and muffles wind audio.
@export var is_interior: bool = false

@export_group("Heating")
## Extra degrees this zone can gain from heat sources burning inside it.
@export var max_heated_offset_c: float = 0.0
## Degrees per in-game hour the zone gains while a heat source burns inside.
@export var heating_rate_c_per_hour: float = 6.0
## Degrees per in-game hour the zone loses once nothing is burning.
@export var cooling_rate_c_per_hour: float = 3.0

@export_group("Priority")
## Higher value wins when zones overlap. Named to avoid Area3D.priority.
@export var zone_priority: int = 0

var _heated_offset_c: float = 0.0
var _active_heat_sources: int = 0


## Total offset this zone contributes right now, base plus accumulated heating.
func get_total_offset_c() -> float:
	return temperature_offset_c + _heated_offset_c


## Registers a burning heat source so the zone starts accumulating warmth.
func add_heat_source() -> void:
	_active_heat_sources += 1


## Unregisters a heat source; the zone cools once the count reaches zero.
func remove_heat_source() -> void:
	_active_heat_sources = maxi(0, _active_heat_sources - 1)


## Advances the zone's stored warmth. Called by ThermalManager with game hours.
func advance_heating(delta_hours: float) -> void:
	if max_heated_offset_c <= 0.0:
		return
	var previous: float = _heated_offset_c
	if _active_heat_sources > 0:
		_heated_offset_c = minf(
			max_heated_offset_c, _heated_offset_c + heating_rate_c_per_hour * delta_hours
		)
	else:
		_heated_offset_c = maxf(0.0, _heated_offset_c - cooling_rate_c_per_hour * delta_hours)
	if not is_equal_approx(previous, _heated_offset_c):
		warmth_changed.emit(get_total_offset_c())
