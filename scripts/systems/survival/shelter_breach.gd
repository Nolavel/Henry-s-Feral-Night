@tool
class_name ShelterBreach
extends Node3D

## A hole in a shelter: a broken window, a missing door, a collapsed roof
## panel. Child of the ThermalZone it lets the weather into.

## Emitted when the breach is boarded up or torn open again.
signal boarded_changed(is_boarded: bool)

@export_group("Breach")
## How much of the shelter's protection this hole costs, 0 nothing to 1 all.
@export_range(0.0, 1.0) var severity: float = 0.35:
	set(value):
		severity = clampf(value, 0.0, 1.0)
		_announce()
## Starts boarded, for a shelter that is already prepared.
@export var starts_boarded: bool = false

@export_group("Repair")
## Item consumed to board this breach up. Empty means it costs nothing.
@export var repair_item_id: StringName = &"boards"
## Player-facing name key for the prompt, resolved through localisation.
@export var name_key: String = "BREACH_GENERIC"

@export_group("Visual")
## Shown while boarded: the planks across the gap.
@export var boarded_visual: Node3D

var _is_boarded: bool = false


func _ready() -> void:
	_is_boarded = starts_boarded
	_announce()
	if not Engine.is_editor_hint() and get_node_or_null(^"Draft") == null:
		var draft := BreachDraft.new()  # snow blowing in: which side the wind comes from
		draft.name = "Draft"
		draft.breach = self
		add_child(draft)


## Whether this hole is currently closed off.
func is_boarded() -> bool:
	return _is_boarded


## Which way the hole faces, in world space. The author turns the node; nobody
## fills in a vector by hand.
func get_facing() -> Vector3:
	var facing: Vector3 = -global_transform.basis.z
	facing.y = 0.0
	if facing.length_squared() < 0.0001:
		return Vector3.FORWARD
	return facing.normalized()


## What this breach costs against a given wind, 0.0 when it is boarded or the
## wind blows past it. A hole facing into the wind costs its full severity.
func get_exposure_against(wind_direction: Vector3) -> float:
	if _is_boarded:
		return 0.0
	if wind_direction.length_squared() < 0.0001:
		return severity
	return severity * maxf(0.0, get_facing().dot(-wind_direction.normalized()))


## Closes the hole. Returns false when it was already boarded, so a caller
## does not spend an item for nothing.
func board_up() -> bool:
	if _is_boarded:
		return false
	_is_boarded = true
	boarded_changed.emit(true)
	_announce()
	return true


## Opens it again, for a storm that rips the boards off or a debug key.
func tear_open() -> bool:
	if not _is_boarded:
		return false
	_is_boarded = false
	boarded_changed.emit(false)
	_announce()
	return true


## State the save system persists, through the owning zone.
func get_save_data() -> Dictionary:
	return {"boarded": _is_boarded}


func load_save_data(data: Dictionary) -> void:
	var boarded: bool = bool(data.get("boarded", starts_boarded))
	if boarded == _is_boarded:
		return
	_is_boarded = boarded
	boarded_changed.emit(_is_boarded)
	_announce()


## Tells the owning zone its protection changed, without the zone polling.
func _announce() -> void:
	if boarded_visual != null:
		boarded_visual.visible = _is_boarded
	if not is_inside_tree():
		return
	var zone := get_parent() as ThermalZone
	if zone != null:
		zone.refresh_breaches()
