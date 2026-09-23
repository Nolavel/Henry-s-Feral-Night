class_name HeatSourceFeed
extends InteractiveArea

## Lights and feeds one HeatSource. Firewood buys hours; a dead fire also
## needs tinder. Without this, a fire could only ever burn down.

## Emitted after fuel went in, carrying the hours the fire now has.
signal fuel_added(source: HeatSource, remaining_hours: float)
## Emitted when the player has nothing to feed it with, or it is already full.
signal feed_refused(reason: Refusal)

## Why a feed attempt was turned down.
enum Refusal { NONE, NO_SOURCE, ALREADY_FULL, NO_FUEL, NO_TINDER, NO_INVENTORY }

## Label shown over the fire, resolved through localisation.
const PROMPT_KEY: String = "FEED_PROMPT"

@export_group("Fire")
## The fire this prompt feeds. Defaults to a HeatSource sibling or parent.
@export var heat_source: HeatSource

@export_group("Cost")
## Item spent per feed. Empty means feeding costs nothing.
@export var fuel_item_id: StringName = &"firewood"
## Item spent only to light a dead fire. Empty means lighting is free.
@export var tinder_item_id: StringName = &"tinder"
## Units of fuel one item is worth, through HeatSource.hours_per_fuel_unit.
@export var units_per_item: float = 1.0

var _inventory: InventoryComponent


func _ready() -> void:
	## Found before super(), which sizes the highlight ring from a mesh.
	if heat_source == null:
		heat_source = _find_source()
	if interactive_mesh == null and heat_source != null:
		interactive_mesh = _first_mesh(heat_source)
	super()
	set_item_name(tr(PROMPT_KEY))
	set_description("")


## Only offers itself when feeding would actually do something.
func can_interact() -> bool:
	return super() and can_feed() == Refusal.NONE


## Whether the fire can be fed right now, without feeding it.
func can_feed() -> Refusal:
	if heat_source == null:
		return Refusal.NO_SOURCE
	if not heat_source.can_refuel():
		return Refusal.ALREADY_FULL
	var inventory: InventoryComponent = _get_inventory()
	if fuel_item_id != &"" or tinder_item_id != &"":
		if inventory == null:
			return Refusal.NO_INVENTORY
	if fuel_item_id != &"" and not inventory.has_item(fuel_item_id):
		return Refusal.NO_FUEL
	## Tinder is only owed when the fire is out and has to be started.
	if _needs_tinder() and not inventory.has_item(tinder_item_id):
		return Refusal.NO_TINDER
	return Refusal.NONE


## Spends the items, then feeds the fire. Nothing is spent on a refusal.
func feed() -> Refusal:
	var refusal: Refusal = can_feed()
	if refusal != Refusal.NONE:
		feed_refused.emit(refusal)
		return refusal

	var inventory: InventoryComponent = _get_inventory()
	var needed_tinder: bool = _needs_tinder()
	if needed_tinder and not inventory.try_remove(tinder_item_id):
		feed_refused.emit(Refusal.NO_TINDER)
		return Refusal.NO_TINDER
	if fuel_item_id != &"" and not inventory.try_remove(fuel_item_id):
		feed_refused.emit(Refusal.NO_FUEL)
		return Refusal.NO_FUEL

	heat_source.refuel(units_per_item)
	fuel_added.emit(heat_source, heat_source.get_remaining_hours())
	return Refusal.NONE


func _on_interaction_performed() -> void:
	feed()


## Names a refusal as a localisation key, never as a hardcoded sentence.
static func describe_refusal(refusal: Refusal) -> String:
	match refusal:
		Refusal.NO_SOURCE:
			return "FEED_REFUSED_NO_SOURCE"
		Refusal.ALREADY_FULL:
			return "FEED_REFUSED_ALREADY_FULL"
		Refusal.NO_FUEL:
			return "FEED_REFUSED_NO_FUEL"
		Refusal.NO_TINDER:
			return "FEED_REFUSED_NO_TINDER"
		Refusal.NO_INVENTORY:
			return "FEED_REFUSED_NO_INVENTORY"
		_:
			return ""


## A dead fire has to be started, which costs tinder on top of the wood.
func _needs_tinder() -> bool:
	return tinder_item_id != &"" and not heat_source.is_burning()


## The player's inventory, found once and cached. Level objects cannot be
## wired to the player in the editor, so the group is the handle.
func _get_inventory() -> InventoryComponent:
	if is_instance_valid(_inventory):
		return _inventory
	_inventory = InventoryComponent.find_in(get_tree().get_first_node_in_group("player"))
	return _inventory


## The stove's own body, for the highlight ring to sit under.
static func _first_mesh(node: Node) -> MeshInstance3D:
	for child: Node in node.get_children():
		var mesh := child as MeshInstance3D
		if mesh != null:
			return mesh
	return null


## A fire among the siblings, or the parent itself.
func _find_source() -> HeatSource:
	var parent_source := get_parent() as HeatSource
	if parent_source != null:
		return parent_source
	if get_parent() == null:
		return null
	for sibling: Node in get_parent().get_children():
		var candidate := sibling as HeatSource
		if candidate != null:
			return candidate
	return null
