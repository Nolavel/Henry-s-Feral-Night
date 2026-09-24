class_name CarryComponent
extends Node

## Owns what Henry holds in both hands. The carry starts when the inventory
## gains an item flagged carried_in_hands and ends when the last one leaves it.

## Emitted when the carried item changes; null means the hands are free.
signal carry_changed(item: ItemResource)

@export var inventory: InventoryComponent

var _carried: ItemResource = null


func _ready() -> void:
	if inventory == null:
		inventory = InventoryComponent.find_in(get_parent())
	if inventory == null:
		return
	inventory.item_added.connect(func(_item: ItemResource, _total: int) -> void: _refresh())
	inventory.item_removed.connect(func(_item: ItemResource, _total: int) -> void: _refresh())
	_refresh()


func is_carrying() -> bool:
	return _carried != null


func get_carried_item() -> ItemResource:
	return _carried


func _refresh() -> void:
	var next: ItemResource = null
	for entry: Dictionary in inventory.get_entries():
		var item: ItemResource = ItemCatalog.get_item(entry["id"])
		if item != null and item.carried_in_hands:
			next = item
			break
	if next == _carried:
		return
	_carried = next
	carry_changed.emit(_carried)
