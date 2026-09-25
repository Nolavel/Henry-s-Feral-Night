class_name HeatSource
extends Node3D

## Point source of warmth: a fire, a barrel, a working heater. Sampled by
## distance rather than by Area3D, so falloff stays smooth and cheap.

## Emitted when the source ignites or dies, for VFX, audio and zone heating.
signal burning_changed(is_burning: bool)
## Emitted as fuel burns down, 1.0 full to 0.0 spent, for the HUD.
signal fuel_changed(fraction: float)
## Emitted for every stretch of game time the source burns through, for things
## warming on it; also for sources that never run out.
signal heat_elapsed(hours: float)

static var _registry: Array[HeatSource] = []

@export_group("Heat")
## Degrees added at the very centre of the source.
@export var peak_offset_c: float = 18.0
## Distance in metres at which the contribution reaches zero.
@export var radius_m: float = 6.0
## Shapes the falloff: 1.0 linear, 2.0 concentrated near the flame.
@export var falloff_exponent: float = 2.0

@export_group("Zone")
## Zone this source warms while it burns. Registering is automatic, so a fire
## going out stops heating the room without any scene wiring.
@export var heats_zone: ThermalZone

@export_group("Visual")
## Light shown while the source burns, so a lit stove reads at a glance.
@export var flame_light: Light3D

@export_group("Fuel")
## Starts lit when the scene loads.
@export var starts_burning: bool = true
## In-game hours the source burns on a full load of fuel; 0.0 means forever.
@export var burn_duration_h: float = 6.0
## Hours a single unit of fuel adds when the player feeds the fire.
@export var hours_per_fuel_unit: float = 2.0

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
	burning_changed.connect(_on_burning_changed)
	if flame_light != null:
		flame_light.visible = false
	if starts_burning:
		ignite()


func _exit_tree() -> void:
	_registry.erase(self)
	if _is_burning and heats_zone != null:
		heats_zone.remove_heat_source()


## Frees can bypass _exit_tree, so drop out of the registry here as well.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_registry.erase(self)


## Keeps the zone's heating count in step with this source's flame.
func _on_burning_changed(burning: bool) -> void:
	if flame_light != null:
		flame_light.visible = burning
	if heats_zone == null:
		return
	if burning:
		heats_zone.add_heat_source()
	else:
		heats_zone.remove_heat_source()


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


## Hours of fuel left; infinite sources report their nominal duration.
func get_remaining_hours() -> float:
	return _remaining_h


## Fuel left as 0.0 to 1.0, for a HUD gauge. Infinite sources report 1.0.
func get_fuel_fraction() -> float:
	if burn_duration_h <= 0.0:
		return 1.0
	return clampf(_remaining_h / burn_duration_h, 0.0, 1.0)


## Adds fuel, capped at the full load. Relights a fire that had gone out.
func refuel(units: float = 1.0) -> void:
	if burn_duration_h <= 0.0:
		return
	_remaining_h = minf(burn_duration_h, _remaining_h + units * hours_per_fuel_unit)
	fuel_changed.emit(get_fuel_fraction())
	if _remaining_h > 0.0 and not _is_burning:
		_is_burning = true
		burning_changed.emit(true)


## Whether another unit of fuel would do anything. A full fire refuses, so a
## caller does not burn an item for nothing.
func can_refuel() -> bool:
	if burn_duration_h <= 0.0:
		return false
	return _remaining_h < burn_duration_h


## Restores exact fuel state, for a save rather than for gameplay. Gameplay
## goes through refuel(), which is capped and relights.
func restore_fuel(hours: float, burning: bool) -> void:
	_remaining_h = clampf(hours, 0.0, maxf(burn_duration_h, hours))
	fuel_changed.emit(get_fuel_fraction())
	var should_burn: bool = burning and (_remaining_h > 0.0 or burn_duration_h <= 0.0)
	if should_burn == _is_burning:
		return
	_is_burning = should_burn
	burning_changed.emit(_is_burning)


## Lights the source and refills it to its full burn duration.
func ignite() -> void:
	_remaining_h = burn_duration_h
	fuel_changed.emit(get_fuel_fraction())
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
	if _is_burning and delta_hours > 0.0:
		heat_elapsed.emit(delta_hours)
	if not _is_burning or burn_duration_h <= 0.0:
		return
	_remaining_h = maxf(0.0, _remaining_h - delta_hours)
	fuel_changed.emit(get_fuel_fraction())
	if _remaining_h <= 0.0:
		extinguish()


## Advances every live source. Called once per tick by ThermalManager so fuel
## burns on the game clock rather than per frame.
static func advance_all_fuel(delta_hours: float) -> void:
	for source: HeatSource in get_all():
		source.advance_fuel(delta_hours)


## Degrees this source contributes at a world position, zero beyond its radius.
func get_offset_at(world_position: Vector3) -> float:
	if not _is_burning or radius_m <= 0.0 or not is_inside_tree():
		return 0.0
	var distance: float = global_position.distance_to(world_position)
	if distance >= radius_m:
		return 0.0
	var normalised: float = 1.0 - (distance / radius_m)
	return peak_offset_c * pow(normalised, falloff_exponent)
