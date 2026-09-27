class_name SnowScoopComponent
extends Node

## Item-Use bridge for the snow/water loop. Using an empty mug outdoors scoops
## snow into it; StoveWarmer owns the later mug_snow -> warm_water_mug step.

const THERMAL_SCRIPT: GDScript = preload("res://scripts/systems/survival/thermal_manager.gd")
const EMPTY_MUG: StringName = &"mug"
const FILLED_MUG: StringName = &"mug_snow"

@export var inventory: InventoryComponent

var _thermal: ThermalManager


func _ready() -> void:
	if inventory == null:
		inventory = InventoryComponent.find_in(get_parent())


func on_world_ready(context: WorldContext) -> void:
	_thermal = context.get_system(THERMAL_SCRIPT) as ThermalManager


func can_use(item_id: StringName) -> bool:
	return (
		item_id == EMPTY_MUG
		and inventory != null
		and inventory.has_item(EMPTY_MUG)
		and (_thermal == null or not _thermal.is_sheltered())
	)


func use(item_id: StringName) -> bool:
	if not can_use(item_id):
		return false
	var empty: ItemResource = ItemCatalog.get_item(EMPTY_MUG)
	var filled: ItemResource = ItemCatalog.get_item(FILLED_MUG)
	if empty == null or filled == null or not inventory.try_remove(EMPTY_MUG):
		return false
	if inventory.try_add(filled):
		return true
	## Preserve the container if the extra snow weight crosses the carry limit.
	inventory.try_add(empty)
	return false
