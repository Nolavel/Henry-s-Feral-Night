class_name ShelterState
extends Node

## Remembers what the player did to a shelter: which breaches are boarded and
## how much fuel each fire has. Shelters live in streamed chunks, so this state
## cannot live in the zones.

## Emitted when a breach is boarded or torn open anywhere in the world.
signal shelter_changed(zone_path: String, sealed_fraction: float)

const SEPARATOR: String = "/"

var _world: Node
## Boarded state by "<zone path>/<breach name>", so a chunk that unloads and
## reloads gets its boards back.
var _boarded: Dictionary = {}
## Fuel state by "<zone name>/<fire name>", so a fire left burning is still
## burning down when its chunk comes back.
var _fires: Dictionary = {}


## The composition root's lifecycle hook. Adopts whatever is already in the
## scene; zones that stream in later adopt themselves through adopt_zone().
func on_world_ready(context: WorldContext) -> void:
	_world = context.world
	for zone: ThermalZone in find_zones():
		adopt_zone(zone)


## Every ThermalZone currently in the world.
func find_zones() -> Array[ThermalZone]:
	var zones: Array[ThermalZone] = []
	_collect(_world, zones)
	return zones


## Restores a zone's boards and starts listening to it. Safe to call again.
func adopt_zone(zone: ThermalZone) -> void:
	if zone == null:
		return
	for breach: ShelterBreach in zone.get_breaches():
		var key: String = _key(zone, breach)
		if _boarded.has(key):
			_apply(breach, bool(_boarded[key]))
		else:
			_boarded[key] = breach.is_boarded()
		if not breach.boarded_changed.is_connected(_on_breach_changed):
			breach.boarded_changed.connect(_on_breach_changed.bind(zone, breach))
	for fire: HeatSource in find_fires_in(zone):
		adopt_fire(zone, fire)


## Every HeatSource that belongs to a zone, by being under it in the scene.
static func find_fires_in(zone: ThermalZone) -> Array[HeatSource]:
	var fires: Array[HeatSource] = []
	_collect_fires(zone, fires)
	return fires


## Restores a fire's fuel and starts listening to it. Safe to call again.
func adopt_fire(zone: ThermalZone, fire: HeatSource) -> void:
	if fire == null:
		return
	var key: String = _fire_key(zone, fire)
	if _fires.has(key):
		var stored: Dictionary = _fires[key]
		fire.restore_fuel(float(stored.get("remaining_h", 0.0)), bool(stored.get("burning", false)))
	else:
		_remember_fire(key, fire)
	if not fire.fuel_changed.is_connected(_on_fuel_changed):
		fire.fuel_changed.connect(_on_fuel_changed.bind(key, fire))


## Key this system owns in a save file, stated explicitly so renaming the
## script never orphans an existing save.
func get_save_key() -> StringName:
	return &"shelter"


func get_save_data() -> Dictionary:
	return {"boarded": _boarded.duplicate(), "fires": _fires.duplicate(true)}


func load_save_data(data: Dictionary) -> void:
	_boarded = Dictionary(data.get("boarded", {})).duplicate()
	_fires = Dictionary(data.get("fires", {})).duplicate(true)
	for zone: ThermalZone in find_zones():
		for breach: ShelterBreach in zone.get_breaches():
			var key: String = _key(zone, breach)
			if _boarded.has(key):
				_apply(breach, bool(_boarded[key]))
		for fire: HeatSource in find_fires_in(zone):
			var fire_key: String = _fire_key(zone, fire)
			if not _fires.has(fire_key):
				continue
			var stored: Dictionary = _fires[fire_key]
			fire.restore_fuel(
				float(stored.get("remaining_h", 0.0)), bool(stored.get("burning", false))
			)


## Records the change and tells anyone listening the shelter got better.
func _on_breach_changed(_is_boarded: bool, zone: ThermalZone, breach: ShelterBreach) -> void:
	_boarded[_key(zone, breach)] = breach.is_boarded()
	shelter_changed.emit(String(zone.get_path()), zone.get_sealed_fraction())


## Fuel changes constantly as a fire burns, so this only records; it does not
## announce, or every tick would wake the HUD.
func _on_fuel_changed(_fraction: float, key: String, fire: HeatSource) -> void:
	_remember_fire(key, fire)


func _remember_fire(key: String, fire: HeatSource) -> void:
	_fires[key] = {"remaining_h": fire.get_remaining_hours(), "burning": fire.is_burning()}


func _fire_key(zone: ThermalZone, fire: HeatSource) -> String:
	return "%s%s%s" % [zone.name, SEPARATOR, fire.name]


## Fires under a zone, found the same way zones are found under the world.
static func _collect_fires(node: Node, out: Array[HeatSource]) -> void:
	if node == null:
		return
	var fire := node as HeatSource
	if fire != null:
		out.append(fire)
	for child: Node in node.get_children():
		_collect_fires(child, out)


## Sets a breach without bouncing the signal back as a fresh change.
func _apply(breach: ShelterBreach, boarded: bool) -> void:
	if boarded:
		breach.board_up()
	else:
		breach.tear_open()


func _key(zone: ThermalZone, breach: ShelterBreach) -> String:
	return "%s%s%s" % [zone.name, SEPARATOR, breach.name]


static func _collect(node: Node, out: Array[ThermalZone]) -> void:
	if node == null:
		return
	var zone := node as ThermalZone
	if zone != null:
		out.append(zone)
	for child: Node in node.get_children():
		_collect(child, out)
