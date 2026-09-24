# =============================================================================
# inventory_component.gd — loose carry, gated by weight.
#
# Everything worn or pocketed belongs to EquipmentComponent. This is what is
# carried beyond that, and the only rule it enforces is the one that matters
# for this game: total weight. Kenny is dead weight for a whole act, and that
# has to cost something.
#
# Weight gates acceptance today; it does not yet slow movement. That is a
# deliberate order — a limit the player can feel before a penalty they cannot
# see the shape of.
#
# Ported from ADT.
# =============================================================================
class_name InventoryComponent
extends Node

## Emitted when an item lands, with the new total count of that item.
signal item_added(item: ItemResource, count_total: int)
## Emitted when an item leaves, with what remains.
signal item_removed(item: ItemResource, count_total: int)
## Emitted when an item was refused, with a reason the HUD can show.
signal add_rejected(item: ItemResource, reason: StringName)
## Emitted whenever the carried total changes.
signal weight_changed(total_kg: float, maximum_kg: float)

@export_group("Capacity")
## Kilograms Henry can carry beyond what he is wearing.
@export var max_carry_weight: float = 30.0
## Its carried non-garments (Kenny) count toward the same limit.
@export var equipment: EquipmentComponent

var _entries: Array[Dictionary] = []


## Adds one item, stacking where the item allows it. Returns false and emits
## add_rejected when the weight limit refuses it.
func try_add(item: ItemResource) -> bool:
	if item == null:
		return false
	if get_total_weight() + item.weight > max_carry_weight:
		add_rejected.emit(item, &"overweight")
		return false

	for entry: Dictionary in _entries:
		var stored: ItemResource = entry["item"]
		if stored.id == item.id and entry["count"] < item.max_stack:
			entry["count"] = int(entry["count"]) + 1
			item_added.emit(item, entry["count"])
			weight_changed.emit(get_total_weight(), max_carry_weight)
			return true

	_entries.append({"item": item, "count": 1})
	item_added.emit(item, 1)
	weight_changed.emit(get_total_weight(), max_carry_weight)
	return true


## Removes one of an item. Returns false when none is carried.
func try_remove(item_id: StringName) -> bool:
	for index: int in range(_entries.size()):
		var entry: Dictionary = _entries[index]
		var stored: ItemResource = entry["item"]
		if stored.id != item_id:
			continue
		entry["count"] = int(entry["count"]) - 1
		var remaining: int = entry["count"]
		if remaining <= 0:
			_entries.remove_at(index)
		item_removed.emit(stored, maxi(0, remaining))
		weight_changed.emit(get_total_weight(), max_carry_weight)
		return true
	return false


func get_count(item_id: StringName) -> int:
	for entry: Dictionary in _entries:
		var stored: ItemResource = entry["item"]
		if stored.id == item_id:
			return entry["count"]
	return 0


func has_item(item_id: StringName) -> bool:
	return get_count(item_id) > 0


func get_total_weight() -> float:
	var total: float = 0.0
	for entry: Dictionary in _entries:
		var stored: ItemResource = entry["item"]
		total += stored.weight * float(entry["count"])
	if equipment != null:
		total += equipment.get_carried_weight()
	return total


## The first inventory under a node, the player usually. Level objects and
## systems cannot be wired to the player in the editor, so they search.
static func find_in(node: Node) -> InventoryComponent:
	if node == null:
		return null
	var found := node as InventoryComponent
	if found != null:
		return found
	for child: Node in node.get_children():
		var nested: InventoryComponent = find_in(child)
		if nested != null:
			return nested
	return null


## How full the pack is, 0 empty to 1 at the carry limit. The one number the
## ice, fatigue and, later, movement read to make weight cost something.
func get_load_fraction() -> float:
	if max_carry_weight <= 0.0:
		return 0.0
	return clampf(get_total_weight() / max_carry_weight, 0.0, 1.0)


## Carried items as {id, count} pairs, for a HUD or a debug readout.
func get_entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Dictionary in _entries:
		var stored: ItemResource = entry["item"]
		out.append({"id": stored.id, "count": entry["count"]})
	return out


func get_save_key() -> StringName:
	return &"inventory"


func get_save_data() -> Dictionary:
	var stacks: Array = []
	for entry: Dictionary in _entries:
		var stored: ItemResource = entry["item"]
		stacks.append({"id": String(stored.id), "count": int(entry["count"])})
	return {"stacks": stacks}


## Re-resolves every id against the catalog rather than trusting the file, so
## an item deleted since the save is dropped instead of resurrected as null.
func load_save_data(data: Dictionary) -> void:
	_entries.clear()
	for stack: Variant in data.get("stacks", []):
		if typeof(stack) != TYPE_DICTIONARY:
			continue
		var item: ItemResource = ItemCatalog.get_item(StringName(stack.get("id", "")))
		if item == null:
			continue
		_entries.append({"item": item, "count": maxi(1, int(stack.get("count", 1)))})
	weight_changed.emit(get_total_weight(), max_carry_weight)
