# =============================================================================
# equipment_component.gd — what Henry is wearing and what is in those pockets.
#
# Two levels, and the split is the whole point:
#   BODY SLOTS are fixed, described by an EquipmentLayout resource.
#   POCKETS are not. Each worn garment brings its own (GarmentData.pockets).
#   Take the coat off and its pockets — and their contents — go with it.
#
# Slots are addressed by a body slot id, or "<body_slot>/<pocket>".
#
# STORES ITEM IDS ONLY, never ItemResource references: the save contract
# carries dictionaries, arrays and primitives, and does not widen.
#
# Ported from ADT, minus draw/holster (no weapons here), plus the axis ADT
# does not have: get_total_insulation_c(), which feeds ThermalManager.
# =============================================================================
class_name EquipmentComponent
extends Node

## Emitted whenever a slot's contents change. An empty id means emptied.
signal slot_changed(slot_path: StringName, item_id: StringName)
## Emitted when total insulation changes, so the thermal model can resample.
signal insulation_changed(total_c: float)

## Why a placement was refused. Never a bare bool: the caller has to be able
## to say what went wrong.
enum Refusal {
	NONE,
	NO_SUCH_SLOT,
	UNKNOWN_ITEM,
	SLOT_OCCUPIED,
	TOO_LARGE,
	WRONG_BODY_SLOT,
	POCKETS_NOT_EMPTY,
}

const POCKET_SEPARATOR: String = "/"

@export_group("Data")
## The body slots this character has. Without it nothing can be equipped.
@export var layout: EquipmentLayout
## Worn from the start, by item id.
@export var starter_garment_ids: Array[StringName] = []
## Non-garments placed from the start, body slot id to item id: Kenny on his fixture.
@export var starter_slot_items: Dictionary[StringName, StringName] = {}

@export_group("Debug")
@export var debug_log: bool = false

var _body: Dictionary = {}
var _pockets: Dictionary = {}


func _ready() -> void:
	initialize()


## Wears the starter garments. Public and idempotent so headless tests can
## drive it without waiting for a frame.
func initialize() -> void:
	if not _body.is_empty():
		return
	for item_id: StringName in starter_garment_ids:
		var item: ItemResource = ItemCatalog.get_item(item_id)
		if item == null or item.garment == null:
			continue
		equip(item.garment.body_slot_id, item_id)
	for slot_id: StringName in starter_slot_items:
		equip(slot_id, starter_slot_items[slot_id])


## Kilograms of non-garments riding in body slots and pockets. Clothes are
## worn, not carried; Kenny and pocketed items count toward the load.
func get_carried_weight() -> float:
	var total: float = 0.0
	for slot_id: StringName in _body:
		var item: ItemResource = ItemCatalog.get_item(_body[slot_id])
		if item != null and item.garment == null:
			total += item.weight
	for path: StringName in _pockets:
		var pocketed: ItemResource = ItemCatalog.get_item(_pockets[path])
		if pocketed != null:
			total += pocketed.weight
	return total


## Item worn in a body slot, or empty.
func get_equipped(slot_id: StringName) -> StringName:
	return _body.get(slot_id, &"")


## Item in one pocket of one worn garment, or empty.
func get_pocket_item(body_slot_id: StringName, pocket_id: StringName) -> StringName:
	return _pockets.get(pocket_path(body_slot_id, pocket_id), &"")


## Every pocket currently available, which means every pocket brought by
## something currently worn. Entries: body_slot, pocket, definition, item_id.
func get_available_pockets() -> Array[Dictionary]:
	var available: Array[Dictionary] = []
	if layout == null:
		return available
	for body_slot: EquipmentSlotDefinition in layout.body_slots:
		if body_slot == null:
			continue
		var worn_id: StringName = get_equipped(body_slot.id)
		if worn_id == &"":
			continue
		var worn: ItemResource = ItemCatalog.get_item(worn_id)
		if worn == null or worn.garment == null:
			continue
		for pocket: EquipmentSlotDefinition in worn.garment.pockets:
			if pocket == null:
				continue
			available.append({
				"body_slot": body_slot.id,
				"pocket": pocket.id,
				"definition": pocket,
				"item_id": get_pocket_item(body_slot.id, pocket.id),
			})
	return available


## Degrees of insulation from everything worn on the body. What sits in a
## pocket does not keep anyone warm, so pockets are not counted.
func get_total_insulation_c() -> float:
	var total: float = 0.0
	for slot_id: StringName in _body:
		var item: ItemResource = ItemCatalog.get_item(_body[slot_id])
		if item != null and item.garment != null:
			total += item.garment.insulation_c
	return total


## Whether this item could go in this body slot right now.
func can_equip(slot_id: StringName, item_id: StringName) -> Refusal:
	var definition: EquipmentSlotDefinition = _find_body_slot(slot_id)
	if definition == null:
		return Refusal.NO_SUCH_SLOT
	if get_equipped(slot_id) != &"":
		return Refusal.SLOT_OCCUPIED
	var item: ItemResource = ItemCatalog.get_item(item_id)
	if item == null:
		return Refusal.UNKNOWN_ITEM
	if item.garment != null:
		if item.garment.body_slot_id != slot_id:
			return Refusal.WRONG_BODY_SLOT
	elif not definition.accepts_non_garment:
		return Refusal.WRONG_BODY_SLOT
	return _check_fit(definition, item)


## Whether this item could go in this pocket right now.
func can_stow(body_slot_id: StringName, pocket_id: StringName, item_id: StringName) -> Refusal:
	var definition: EquipmentSlotDefinition = _find_pocket(body_slot_id, pocket_id)
	if definition == null:
		return Refusal.NO_SUCH_SLOT
	if get_pocket_item(body_slot_id, pocket_id) != &"":
		return Refusal.SLOT_OCCUPIED
	var item: ItemResource = ItemCatalog.get_item(item_id)
	if item == null:
		return Refusal.UNKNOWN_ITEM
	return _check_fit(definition, item)


## Wears an item. REFUSES an occupied slot rather than swapping: a component
## that knows nothing about the inventory could only drop what it displaced.
func equip(slot_id: StringName, item_id: StringName) -> Refusal:
	var refusal: Refusal = can_equip(slot_id, item_id)
	if refusal != Refusal.NONE:
		_log("equip refused", slot_id, item_id, refusal)
		return refusal
	_body[slot_id] = item_id
	slot_changed.emit(slot_id, item_id)
	insulation_changed.emit(get_total_insulation_c())
	return Refusal.NONE


## Takes a garment off and returns it. Refuses while its own pockets hold
## anything — emptying someone's coat for them is not this component's call.
func unequip(slot_id: StringName) -> StringName:
	var item_id: StringName = get_equipped(slot_id)
	if item_id == &"":
		return &""
	if not _pockets_empty_for(slot_id):
		_log("unequip refused", slot_id, item_id, Refusal.POCKETS_NOT_EMPTY)
		return &""
	_body.erase(slot_id)
	slot_changed.emit(slot_id, &"")
	insulation_changed.emit(get_total_insulation_c())
	return item_id


## Puts an item into one pocket.
func stow(body_slot_id: StringName, pocket_id: StringName, item_id: StringName) -> Refusal:
	var refusal: Refusal = can_stow(body_slot_id, pocket_id, item_id)
	if refusal != Refusal.NONE:
		_log("stow refused", pocket_path(body_slot_id, pocket_id), item_id, refusal)
		return refusal
	var path: StringName = pocket_path(body_slot_id, pocket_id)
	_pockets[path] = item_id
	slot_changed.emit(path, item_id)
	return Refusal.NONE


## Takes whatever is in a pocket back out.
func take_from_pocket(body_slot_id: StringName, pocket_id: StringName) -> StringName:
	var path: StringName = pocket_path(body_slot_id, pocket_id)
	var item_id: StringName = _pockets.get(path, &"")
	if item_id == &"":
		return &""
	_pockets.erase(path)
	slot_changed.emit(path, &"")
	return item_id


## Finds somewhere for an item: worn if it is a garment, then any empty
## pocket, then any body slot that takes non-garments. Slots marked
## excluded_from_auto_stow are skipped — Kenny's fixture is not a spare shelf.
## Returns the most informative refusal when nothing takes it.
func stow_anywhere(item_id: StringName) -> Refusal:
	var item: ItemResource = ItemCatalog.get_item(item_id)
	if item == null:
		return Refusal.UNKNOWN_ITEM
	if item.garment != null and equip(item.garment.body_slot_id, item_id) == Refusal.NONE:
		return Refusal.NONE

	var reason: Refusal = Refusal.NO_SUCH_SLOT
	for pocket: Dictionary in get_available_pockets():
		if pocket["item_id"] != &"":
			continue
		var refusal: Refusal = can_stow(pocket["body_slot"], pocket["pocket"], item_id)
		if refusal == Refusal.NONE:
			return stow(pocket["body_slot"], pocket["pocket"], item_id)
		reason = refusal

	if layout != null:
		for body_slot: EquipmentSlotDefinition in layout.body_slots:
			if body_slot == null or not body_slot.accepts_non_garment:
				continue
			if body_slot.excluded_from_auto_stow or get_equipped(body_slot.id) != &"":
				continue
			var refusal: Refusal = can_equip(body_slot.id, item_id)
			if refusal == Refusal.NONE:
				return equip(body_slot.id, item_id)
			reason = refusal
	return reason


## Address of one pocket, as stored and as reported by slot_changed.
func pocket_path(body_slot_id: StringName, pocket_id: StringName) -> StringName:
	return StringName("%s%s%s" % [body_slot_id, POCKET_SEPARATOR, pocket_id])


func get_save_key() -> StringName:
	return &"equipment"


func get_save_data() -> Dictionary:
	return {"body": _to_string_keys(_body), "pockets": _to_string_keys(_pockets)}


## Restores body slots BEFORE pockets: a pocket only exists while the garment
## that brings it is worn. Every id is re-validated against the layout and the
## catalog rather than trusted, so a stale save drops entries instead of
## resurrecting items that no longer exist.
func load_save_data(data: Dictionary) -> void:
	_body.clear()
	_pockets.clear()

	var saved_body: Dictionary = data.get("body", {})
	for slot_key: Variant in saved_body:
		var slot_id := StringName(slot_key)
		var item_id := StringName(saved_body[slot_key])
		if _find_body_slot(slot_id) == null:
			push_warning("Equipment: save names body slot '%s', the layout does not" % slot_id)
			continue
		if ItemCatalog.get_item(item_id) == null:
			continue
		_body[slot_id] = item_id

	var saved_pockets: Dictionary = data.get("pockets", {})
	for path_key: Variant in saved_pockets:
		var parts: PackedStringArray = String(path_key).split(POCKET_SEPARATOR)
		if parts.size() != 2:
			push_warning("Equipment: malformed pocket path '%s' in save" % path_key)
			continue
		var item_id := StringName(saved_pockets[path_key])
		if _find_pocket(StringName(parts[0]), StringName(parts[1])) == null:
			push_warning("Equipment: nothing worn provides pocket '%s'" % path_key)
			continue
		if ItemCatalog.get_item(item_id) == null:
			continue
		_pockets[StringName(path_key)] = item_id

	insulation_changed.emit(get_total_insulation_c())


func _check_fit(definition: EquipmentSlotDefinition, item: ItemResource) -> Refusal:
	return Refusal.TOO_LARGE if item.size_class > definition.max_size else Refusal.NONE


func _find_body_slot(slot_id: StringName) -> EquipmentSlotDefinition:
	return layout.find_slot(slot_id) if layout != null else null


## A pocket exists only while the garment bringing it is worn in that slot.
func _find_pocket(body_slot_id: StringName, pocket_id: StringName) -> EquipmentSlotDefinition:
	var worn_id: StringName = get_equipped(body_slot_id)
	if worn_id == &"":
		return null
	var worn: ItemResource = ItemCatalog.get_item(worn_id)
	if worn == null or worn.garment == null:
		return null
	for pocket: EquipmentSlotDefinition in worn.garment.pockets:
		if pocket != null and pocket.id == pocket_id:
			return pocket
	return null


func _pockets_empty_for(body_slot_id: StringName) -> bool:
	var prefix: String = "%s%s" % [body_slot_id, POCKET_SEPARATOR]
	for path: StringName in _pockets:
		if String(path).begins_with(prefix) and _pockets[path] != &"":
			return false
	return true


## StringName keys do not survive JSON, so the save carries plain strings.
func _to_string_keys(source: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key: Variant in source:
		out[String(key)] = String(source[key])
	return out


func _log(action: String, slot: StringName, item_id: StringName, refusal: Refusal) -> void:
	if debug_log:
		print("[Equipment] %s: %s / %s (%s)" % [action, slot, item_id, Refusal.keys()[refusal]])
