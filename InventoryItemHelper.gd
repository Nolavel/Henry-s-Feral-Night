# InventoryItemHelper.gd - простой скрипт для Node3D с метаданными
extends Node3D

func get_item_name() -> String:
	if has_meta("item_name"):
		return get_meta("item_name")
	return name.to_upper()

func get_item_category() -> String:
	if has_meta("item_category"):
		return get_meta("item_category")
	return "UNKNOWN"

func is_inventory_item() -> bool:
	return has_meta("is_inventory_item") and get_meta("is_inventory_item")
