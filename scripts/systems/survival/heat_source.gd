class_name HeatSource
extends Node3D

## Point source of warmth: a fire, a barrel, a working heater. Sampled by
## distance rather than by Area3D, so falloff stays smooth and cheap.

## Emitted when the source ignites or dies, for VFX, audio and zone heating.
signal burning_changed(is_burning: bool)

static var _registry: Array[HeatSource] = []

@export_group("Heat")
## Degrees added at the very centre of the source.
@export var peak_offset_c: float = 18.0
## Distance in metres at which the contribution reaches zero.
@export var radius_m: float = 6.0
## Shapes the falloff: 1.0 linear, 2.0 concentrated near the flame.
@export var falloff_exponent: float = 2.0

@export_group("Fuel")
## Starts lit when the scene loads.
@export var starts_burning: bool = true
## In-game hours the source burns on a full load of fuel; 0.0 means forever.
@export var burn_duration_h: float = 0.0

var _is_burning: bool = false
var _remaining_h: float = 0.0


func _ready() -> void:
	initialize()


## Registers the source and lights it if configured to start burning.
## Public so headless tests can drive it without waiting for a frame.
func initialize() -> void:
	if _registry.has(self):
		return
	_registry.append(self)
	if starts_burning:
		ignite()


func _exit_tree() -> void:
	_registry.erase(self)


## Frees can bypass _exit_tree, so drop out of the registry here as well.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_registry.erase(self)


## All live heat sources. Freed entries are dropped rather than returned,
## so one stale source cannot break every temperature calculation.
static func get_all() -> Array[HeatSource]:
	var live: Array[HeatSource] = []
	var stale: bool = false
	for source: HeatSource in _registry:
		if is_instance_valid(source):
			live.append(source)
		else:
			stale = true
	if stale:
		_registry = live
	return live


func is_burning() -> bool:
	return _is_burning


## Lights the source and refills it to its full burn duration.
func ignite() -> void:
	_remaining_h = burn_duration_h
	if _is_burning:
		return
	_is_burning = true
	burning_changed.emit(true)


## Puts the source out immediately.
func extinguish() -> void:
	if not _is_burning:
		return
	_is_burning = false
	burning_changed.emit(false)


## Burns fuel for the given number of in-game hours.
func advance_fuel(delta_hours: float) -> void:
	if not _is_burning or burn_duration_h <= 0.0:
		return
	_remaining_h -= delta_hours
	if _remaining_h <= 0.0:
		extinguish()


## Degrees this source contributes at a world position, zero beyond its radius.
func get_offset_at(world_position: Vector3) -> float:
	if not _is_burning or radius_m <= 0.0:
		return 0.0
	var distance: float = global_position.distance_to(world_position)
	if distance >= radius_m:
		return 0.0
	var normalised: float = 1.0 - (distance / radius_m)
	return peak_offset_c * pow(normalised, falloff_exponent)
