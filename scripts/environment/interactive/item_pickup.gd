class_name ItemPickup
extends InteractiveArea

## An item lying in the world. F prefers an empty Quick Access pocket when the
## item fits; otherwise it goes into the pack and flies its mesh into the top
## flap. Too heavy to carry, and it stays where it is.

## Emitted after the item went into a pocket or the pack.
signal picked_up(item_id: StringName, count: int)
## Emitted when the pack refused it, carrying the item id.
signal pickup_refused(item_id: StringName)

## Stand-in shape and colour for items that have no mesh of their own yet.
const PLACEHOLDER_SIZE: Vector3 = Vector3(0.32, 0.16, 0.22)
const PLACEHOLDER_COLOR: Color = Color(0.42, 0.3, 0.2)
const ROAD_FLARE_ID: StringName = &"road_flare"
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
var _equipment: EquipmentComponent


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
## Prefer Quick Access (pockets via stow_anywhere) before the pack so small
## tools like the road flare land where the player can use them without Hub.
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

	var equipment: EquipmentComponent = _get_equipment()
	var went_to_pack: bool = false
	for i: int in range(count):
		var pocketed: bool = false
		if equipment != null and not item.carried_in_hands:
			var refusal: EquipmentComponent.Refusal = equipment.stow_anywhere(item_id)
			pocketed = refusal == EquipmentComponent.Refusal.NONE
		if not pocketed:
			if not inventory.try_add(item):
				## Should not happen after the weight gate, but stay safe.
				pickup_refused.emit(item_id)
				return false
			went_to_pack = true

	var ledger: PickupLedger = PickupLedger.find(get_tree()) if is_inside_tree() else null
	if ledger != null:
		ledger.record(world_id)
	picked_up.emit(item_id, count)
	if went_to_pack and not item.carried_in_hands:
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
	if item_id == ROAD_FLARE_ID:
		return _make_road_flare()
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


## The starting light must read as a flare, not as the generic brown loot box.
## It matches the unlit tube dimensions used by HeldFlare and lies in the snow.
func _make_road_flare() -> MeshInstance3D:
	var tube := MeshInstance3D.new()
	tube.name = "RoadFlareVisual"
	var tube_mesh := CylinderMesh.new()
	tube_mesh.top_radius = 0.014
	tube_mesh.bottom_radius = 0.016
	tube_mesh.height = 0.22
	tube_mesh.radial_segments = 12
	tube.mesh = tube_mesh
	var body_material := StandardMaterial3D.new()
	body_material.albedo_color = Color(0.19, 0.035, 0.026, 1.0)
	body_material.metallic = 0.18
	body_material.roughness = 0.58
	tube.material_override = body_material
	tube.rotation.z = PI * 0.5
	tube.position.y = -0.13
	add_child(tube)

	var cap := MeshInstance3D.new()
	cap.name = "StrikerCap"
	var cap_mesh := CylinderMesh.new()
	cap_mesh.top_radius = 0.018
	cap_mesh.bottom_radius = 0.018
	cap_mesh.height = 0.025
	cap_mesh.radial_segments = 12
	cap.mesh = cap_mesh
	var cap_material := StandardMaterial3D.new()
	cap_material.albedo_color = Color(0.055, 0.045, 0.04, 1.0)
	cap_material.roughness = 0.9
	cap.material_override = cap_material
	cap.position.y = 0.122
	tube.add_child(cap)
	return tube


func _get_inventory() -> InventoryComponent:
	if is_instance_valid(_inventory):
		return _inventory
	if not is_inside_tree():
		return null
	_inventory = InventoryComponent.find_in(get_tree().get_first_node_in_group("player"))
	return _inventory


func _get_equipment() -> EquipmentComponent:
	if is_instance_valid(_equipment):
		return _equipment
	if not is_inside_tree():
		return null
	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null:
		return null
	_equipment = player.get_node_or_null(^"EquipmentComponent") as EquipmentComponent
	return _equipment
