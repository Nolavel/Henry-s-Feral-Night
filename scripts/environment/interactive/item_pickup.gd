class_name ItemPickup
extends InteractiveArea

## An item lying in the world. F puts it in the pack and flies its mesh into the
## top flap; too heavy to carry, and it stays where it is.

## Emitted after the item went into the pack.
signal picked_up(item_id: StringName, count: int)
## Emitted when the pack refused it, carrying the item id.
signal pickup_refused(item_id: StringName)

## Stand-in shape and colour for items that have no mesh of their own yet.
const PLACEHOLDER_SIZE: Vector3 = Vector3(0.32, 0.16, 0.22)
const PLACEHOLDER_COLOR: Color = Color(0.42, 0.3, 0.2)
const TOO_HEAVY_KEY: String = "PICKUP_REFUSED_TOO_HEAVY"
const WORLD_GROUP: StringName = &"world_pickup"

@export_group("Item")
## Catalog id of what lies here.
@export var item_id: StringName = &""
## How many of it, picked up together.
@export_range(1, 99) var count: int = 1
## Stable id of an authored pickup (from the world layout); a taken one is saved
## in the PickupLedger and does not come back on reload. Empty for dropped items.
@export var world_id: StringName = &""

var _inventory: InventoryComponent


func _ready() -> void:
	## The base class sizes its highlight ring from a mesh; without one a pickup
	## is invisible and unhighlighted, so a placeholder crate stands in.
	if interactive_mesh == null:
		interactive_mesh = _make_placeholder()
	interaction_type = InteractionType.PICKUP
	if world_id != &"":
		add_to_group(WORLD_GROUP)
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
		show_message(tr(TOO_HEAVY_KEY))
		return false
	for i: int in range(count):
		inventory.try_add(item)
	var ledger: PickupLedger = PickupLedger.find(get_tree()) if is_inside_tree() else null
	if ledger != null:
		ledger.record(world_id)
	picked_up.emit(item_id, count)
	if not item.carried_in_hands:  # armfuls go to the hands, not the pack
		_hand_visual_to_pack()
	queue_free()
	return true


func _on_interaction_performed() -> void:
	pick_up()


## Passes the item's mesh to the player's Hub, which flies it into the pack.
func _hand_visual_to_pack() -> void:
	var visual := interactive_mesh as Node3D
	var player: Node = get_tree().get_first_node_in_group(&"player") if is_inside_tree() else null
	var hub: PlayerHubComponent = player.get_node_or_null(^"PlayerHubComponent") as PlayerHubComponent if player != null else null
	if hub == null or visual == null or not is_ancestor_of(visual):
		return
	visual.reparent(get_tree().current_scene if get_tree().current_scene != null else get_tree().root)
	hub.stow_visual(visual, item_id)


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
