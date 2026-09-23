class_name ItemPickup
extends InteractiveArea

## An item lying in the world. Interacting puts it in the pack and removes it;
## too heavy to carry, and it stays where it is.

## Emitted after the item went into the pack.
signal picked_up(item_id: StringName, count: int)
## Emitted when the pack refused it, carrying the item id.
signal pickup_refused(item_id: StringName)

## Stand-in shape and colour for items that have no mesh of their own yet.
const PLACEHOLDER_SIZE: Vector3 = Vector3(0.32, 0.16, 0.22)
const PLACEHOLDER_COLOR: Color = Color(0.42, 0.3, 0.2)

@export_group("Item")
## Catalog id of what lies here.
@export var item_id: StringName = &""
## How many of it, picked up together.
@export_range(1, 99) var count: int = 1

var _inventory: InventoryComponent


func _ready() -> void:
	## The base class sizes its highlight ring from a mesh; without one a pickup
	## is invisible and unhighlighted, so a placeholder crate stands in.
	if interactive_mesh == null:
		interactive_mesh = _make_placeholder()
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


## A small crate until items have their own meshes.
func _make_placeholder() -> MeshInstance3D:
	var crate := MeshInstance3D.new()
	crate.name = "Placeholder"
	var box := BoxMesh.new()
	box.size = PLACEHOLDER_SIZE
	var material := StandardMaterial3D.new()
	material.albedo_color = PLACEHOLDER_COLOR
	box.material = material
	crate.mesh = box
	crate.position.y = PLACEHOLDER_SIZE.y * 0.5
	add_child(crate)
	return crate


func _get_inventory() -> InventoryComponent:
	if is_instance_valid(_inventory):
		return _inventory
	if not is_inside_tree():
		return null
	_inventory = InventoryComponent.find_in(get_tree().get_first_node_in_group("player"))
	return _inventory
