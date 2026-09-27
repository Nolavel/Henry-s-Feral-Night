class_name CarryComponent
extends Node

## Owns what Henry holds in both hands. The carry starts when the inventory
## gains an item flagged carried_in_hands and ends when the last one leaves it.

## Emitted whenever the carried item or its visible unit count changes.
signal carry_changed(item: ItemResource, count: int)

@export var inventory: InventoryComponent

var _carried: ItemResource = null
var _count: int = 0


func _ready() -> void:
	if inventory == null:
		inventory = InventoryComponent.find_in(get_parent())
	if inventory == null:
		return
	inventory.item_added.connect(func(_item: ItemResource, _total: int) -> void: _refresh())
	inventory.item_removed.connect(func(_item: ItemResource, _total: int) -> void: _refresh())
	_refresh()


func is_carrying() -> bool:
	return _carried != null and _count > 0


func get_carried_item() -> ItemResource:
	return _carried


func get_carried_count() -> int:
	return _count


func _refresh() -> void:
	var next: ItemResource = null
	var next_count: int = 0
	for entry: Dictionary in inventory.get_entries():
		var item: ItemResource = ItemCatalog.get_item(entry["id"])
		if item != null and item.carried_in_hands:
			next = item
			next_count = int(entry["count"])
			break
	if next == _carried and next_count == _count:
		return
	_carried = next
	_count = next_count
	carry_changed.emit(_carried, _count)
