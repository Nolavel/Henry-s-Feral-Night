# =============================================================================
# item_resource.gd — one item, authored as a .tres in data/items/.
#
# Facet pattern: an optional sub-resource that is null means "not that kind of
# thing". `garment` null is an item you cannot wear; `consumable` null is one
# you cannot eat. A tin of food carries no empty garment fields.
#
# Ported from ADT, trimmed of what this game does not have: the ranged-weapon
# group, the held mesh and its fit, throwing, and the Readability axis.
# =============================================================================
class_name ItemResource
extends Resource

@export_group("Identity")
## Stable id, unique in the catalog. The file name matches it by convention.
@export var id: StringName = &""
## Player-facing name. A localisation key once items are named in game.
@export var display_name: String = "Item"

@export_group("Inventory")
## Kilograms. Gates what the inventory accepts; Kenny's weight is the point.
@export var weight: float = 1.0
## How many of these share one inventory entry. 1 means it never stacks.
@export var max_stack: int = 1

@export_group("Equipment")
## Which sockets will take it at all.
@export var size_class: ItemTraits.SizeClass = ItemTraits.SizeClass.POCKET
## Wearable facet. Null means this item cannot be worn.
@export var garment: GarmentData = null

@export_group("Visuals")
## Mesh on Henry shown while this non-garment rides in a body slot, e.g. Kenny.
@export var attached_mesh_node_name: StringName = &""

@export_group("Survival")
## Edible facet. Null means this item cannot be consumed.
@export var consumable: ConsumableData = null
