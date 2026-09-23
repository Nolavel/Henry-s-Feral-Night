class_name ItemPickup
extends InteractiveArea

## An item lying in the world. Interacting puts it in the pack and removes it;
## too heavy to carry, and it stays where it is.

## Emitted after the item went into the pack.
signal picked_up(item_id: StringName, count: int)
## Emitted when the pack refused it, carrying the item id.
signal pickup_refused(item_id: StringName)

@export_group("Item")
## Catalog id of what lies here.
@export var item_id: StringName = &""
## How many of it, picked up together.
@export_range(1, 99) var count: int = 1

var _inventory: InventoryComponent


func _ready() -> void:
	super()
	var item: ItemResource = ItemCatalog.get_item(item_id)
	if item != null:
		var label: String = item.display_name if count == 1 else "%s ×%d" % [item.display_name, count]
		set_item_name(label)
	set_description("")


func can_interact() -> bool:
	return super() and ItemCatalog.get_item(item_id) != null


## Adds every unit or none: a half-taken stack would leave the world lying.
func pick_up() -> bool:
	var item: ItemResource = ItemCatalog.get_item(item_id)
	var inventory: InventoryComponent = _get_inventory()
	if item == null or inventory == null:
		pickup_refused.emit(item_id)
		return false
	if inventory.get_total_weight() + item.weight * float(count) > inventory.max_carry_weight:
		pickup_refused.emit(item_id)
		return false
	for i: int in range(count):
		inventory.try_add(item)
	picked_up.emit(item_id, count)
	queue_free()
	return true


func _on_interaction_performed() -> void:
	pick_up()


func _get_inventory() -> InventoryComponent:
	if is_instance_valid(_inventory):
		return _inventory
	if not is_inside_tree():
		return null
	_inventory = BreachBoardUp._search_inventory(get_tree().get_first_node_in_group("player"))
	return _inventory
