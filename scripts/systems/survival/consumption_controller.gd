class_name ConsumptionController
extends Node

## Closes the eating half of the survival loop: an item with a consumable
## facet is spent and its calories, water and heat cost land on the body.

## Emitted after an item was consumed, so the HUD and audio can react.
signal consumed(item_id: StringName, item: ItemResource)
## Emitted when an attempt was turned down, carrying why.
signal consume_refused(item_id: StringName, reason: Refusal)

## Why a consume attempt was turned down.
enum Refusal { NONE, UNKNOWN_ITEM, NOT_CONSUMABLE, NOT_CARRIED, NO_BIO_MONITOR }

## Where the item is taken from, once found.
enum Source { NONE, INVENTORY, POCKET }

@export_group("Wiring")
@export var inventory: InventoryComponent
@export var equipment: EquipmentComponent
@export var bio_monitor: BioMonitorManager
@export var thermal_manager: ThermalManager


## Whether the item could be consumed right now, without consuming it.
func can_consume(item_id: StringName) -> Refusal:
	var item: ItemResource = ItemCatalog.get_item(item_id)
	if item == null:
		return Refusal.UNKNOWN_ITEM
	if item.consumable == null:
		return Refusal.NOT_CONSUMABLE
	if bio_monitor == null:
		return Refusal.NO_BIO_MONITOR
	if _locate(item_id)["source"] == Source.NONE:
		return Refusal.NOT_CARRIED
	return Refusal.NONE


## Item Use contract (PlayerHubComponent): Use on food or drink eats it.
func can_use(item_id: StringName) -> bool:
	return can_consume(item_id) == Refusal.NONE


## The Player plays the eating animation on `consumed`.
func use(item_id: StringName) -> bool:
	return consume(item_id) == Refusal.NONE


## Consumes one of the item, wherever it is carried. Returns the refusal,
## or NONE when it was eaten.
func consume(item_id: StringName) -> Refusal:
	var refusal: Refusal = can_consume(item_id)
	if refusal != Refusal.NONE:
		consume_refused.emit(item_id, refusal)
		return refusal

	var item: ItemResource = ItemCatalog.get_item(item_id)
	if not _take(item_id):
		consume_refused.emit(item_id, Refusal.NOT_CARRIED)
		return Refusal.NOT_CARRIED

	_apply(item.consumable)
	_leave_behind(item.consumable.leaves_behind_id)
	consumed.emit(item_id, item)
	return Refusal.NONE


## Eats something that is not carried, straight off a stove top. Same effects
## and leftover as consume(); the caller owns taking it away.
func consume_from_world(item_id: StringName) -> Refusal:
	var item: ItemResource = ItemCatalog.get_item(item_id)
	if item == null:
		return Refusal.UNKNOWN_ITEM
	if item.consumable == null:
		return Refusal.NOT_CONSUMABLE
	if bio_monitor == null:
		return Refusal.NO_BIO_MONITOR
	_apply(item.consumable)
	_leave_behind(item.consumable.leaves_behind_id)
	consumed.emit(item_id, item)
	return Refusal.NONE


## Names a refusal as a localisation key, never as a hardcoded sentence.
static func describe_refusal(refusal: Refusal) -> String:
	match refusal:
		Refusal.UNKNOWN_ITEM:
			return "CONSUME_REFUSED_UNKNOWN_ITEM"
		Refusal.NOT_CONSUMABLE:
			return "CONSUME_REFUSED_NOT_CONSUMABLE"
		Refusal.NOT_CARRIED:
			return "CONSUME_REFUSED_NOT_CARRIED"
		Refusal.NO_BIO_MONITOR:
			return "CONSUME_REFUSED_NO_BIO_MONITOR"
		_:
			return ""


## Pushes what the item restores onto the three tracks and the body's heat.
func _apply(consumable: ConsumableData) -> void:
	if consumable.calories != 0.0:
		bio_monitor.add_calories(consumable.calories)
	if consumable.hydration != 0.0:
		bio_monitor.add_hydration(consumable.hydration)
	if consumable.energy != 0.0:
		bio_monitor.add_energy(consumable.energy)
	if consumable.body_heat_cost_c != 0.0 and thermal_manager != null:
		thermal_manager.apply_body_temperature_delta(-consumable.body_heat_cost_c)


## Where one of the item is carried. The inventory is searched before pockets.
func _locate(item_id: StringName) -> Dictionary:
	if inventory != null and inventory.has_item(item_id):
		return {"source": Source.INVENTORY}
	if equipment != null:
		for pocket: Dictionary in equipment.get_available_pockets():
			if pocket["item_id"] == item_id:
				return {
					"source": Source.POCKET,
					"body_slot": pocket["body_slot"],
					"pocket": pocket["pocket"],
				}
	return {"source": Source.NONE}


## Removes one of the item from wherever it was found.
func _take(item_id: StringName) -> bool:
	var found: Dictionary = _locate(item_id)
	match found["source"]:
		Source.INVENTORY:
			return inventory.try_remove(item_id)
		Source.POCKET:
			return equipment.take_from_pocket(found["body_slot"], found["pocket"]) == item_id
		_:
			return false


## Puts the empty tin somewhere, preferring the inventory. A remainder that
## fits nowhere is dropped rather than duplicated.
func _leave_behind(leftover_id: StringName) -> void:
	if leftover_id == &"":
		return
	var leftover: ItemResource = ItemCatalog.get_item(leftover_id)
	if leftover == null:
		return
	if inventory != null and inventory.try_add(leftover):
		return
	if equipment != null:
		equipment.stow_anywhere(leftover_id)
