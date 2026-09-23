class_name ShelterState
extends Node

## Remembers which breaches the player boarded up. Shelters live in streamed
## chunks, so their state is held here rather than in the zones themselves.

## Emitted when a breach is boarded or torn open anywhere in the world.
signal shelter_changed(zone_path: String, sealed_fraction: float)

const SEPARATOR: String = "/"

var _world: Node
## Boarded state by "<zone path>/<breach name>", so a chunk that unloads and
## reloads gets its boards back.
var _boarded: Dictionary = {}


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


## Key this system owns in a save file, stated explicitly so renaming the
## script never orphans an existing save.
func get_save_key() -> StringName:
	return &"shelter"


func get_save_data() -> Dictionary:
	return {"boarded": _boarded.duplicate()}


func load_save_data(data: Dictionary) -> void:
	var stored: Dictionary = data.get("boarded", {})
	_boarded = stored.duplicate()
	for zone: ThermalZone in find_zones():
		for breach: ShelterBreach in zone.get_breaches():
			var key: String = _key(zone, breach)
			if _boarded.has(key):
				_apply(breach, bool(_boarded[key]))


## Records the change and tells anyone listening the shelter got better.
func _on_breach_changed(_is_boarded: bool, zone: ThermalZone, breach: ShelterBreach) -> void:
	_boarded[_key(zone, breach)] = breach.is_boarded()
	shelter_changed.emit(String(zone.get_path()), zone.get_sealed_fraction())


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
