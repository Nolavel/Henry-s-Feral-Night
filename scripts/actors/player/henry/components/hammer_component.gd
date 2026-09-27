class_name HammerComponent
extends Node

## One-hand hammer used by breach boarding. Quick Access draws it from a
## physical pocket; changing selection or opening the Hub can put it away.

signal hammer_drawn
signal hammer_stowed

@export var inventory: InventoryComponent
@export var hammer_item_id: StringName = &"hammer"

var _hammer: Node3D
var _source_zone: StringName = &""


func _ready() -> void:
	if inventory == null:
		inventory = InventoryComponent.find_in(get_parent())


func can_use(item_id: StringName) -> bool:
	return (
		item_id == hammer_item_id
		and not is_holding()
		and inventory != null
		and inventory.has_item(item_id)
		and _other_hands_clear()
	)


func use(item_id: StringName) -> bool:
	if not can_use(item_id) or not inventory.try_remove(item_id):
		return false
	_source_zone = &""
	if _draw():
		return true
	inventory.try_add(ItemCatalog.get_item(hammer_item_id))
	return false


func equip_from_zone(item_id: StringName, zone_path: StringName) -> bool:
	if item_id != hammer_item_id or is_holding() or not _other_hands_clear():
		return false
	var equipment: EquipmentComponent = _equipment()
	var parts: PackedStringArray = String(zone_path).split(EquipmentComponent.POCKET_SEPARATOR)
	if equipment == null or parts.size() != 2:
		return false
	var body_slot := StringName(parts[0])
	var pocket := StringName(parts[1])
	if equipment.get_pocket_item(body_slot, pocket) != item_id:
		return false
	if equipment.take_from_pocket(body_slot, pocket) != item_id:
		return false
	_source_zone = zone_path
	if _draw():
		return true
	_restore_item()
	return false


func is_holding() -> bool:
	return is_instance_valid(_hammer)


## QuickAccess already calls this name when selection changes.
func put_away_unlit() -> bool:
	return put_away()


func put_away() -> bool:
	if not is_holding():
		return false
	var animation: HenryUALAnimation = _animation()
	var prop: Node3D = _hammer
	_hammer = null
	if animation != null:
		animation.release_hand()
	if is_instance_valid(prop):
		prop.queue_free()
	_restore_item()
	hammer_stowed.emit()
	return true


func release_held() -> bool:
	return put_away()


## Small visible hit. Board placement owns the actual resource transaction.
func swing() -> void:
	if not is_holding():
		return
	var start: Vector3 = _hammer.rotation
	var hit: Vector3 = start + Vector3(-0.65, 0.0, 0.0)
	var tween := _hammer.create_tween().set_trans(Tween.TRANS_SINE)
	tween.tween_property(_hammer, ^"rotation", hit, 0.10).set_ease(Tween.EASE_IN)
	tween.tween_property(_hammer, ^"rotation", start, 0.16).set_ease(Tween.EASE_OUT)


func _draw() -> bool:
	var animation: HenryUALAnimation = _animation()
	if animation == null or animation.get_hand_socket() == null:
		return false
	_hammer = _make_prop()
	animation.hold_in_hand(_hammer)
	hammer_drawn.emit()
	return true


func _make_prop() -> Node3D:
	var root := Node3D.new()
	root.name = "HeldHammer"
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.26, 0.16, 0.08)
	wood.roughness = 0.9
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.22, 0.24, 0.25)
	metal.metallic = 0.75
	metal.roughness = 0.38
	var handle := MeshInstance3D.new()
	var handle_mesh := BoxMesh.new()
	handle_mesh.size = Vector3(0.035, 0.30, 0.035)
	handle_mesh.material = wood
	handle.mesh = handle_mesh
	handle.position.y = 0.12
	root.add_child(handle)
	var head := MeshInstance3D.new()
	var head_mesh := BoxMesh.new()
	head_mesh.size = Vector3(0.18, 0.065, 0.065)
	head_mesh.material = metal
	head.mesh = head_mesh
	head.position = Vector3(0.0, 0.29, 0.0)
	root.add_child(head)
	return root


func _other_hands_clear() -> bool:
	var player: Node = get_parent()
	if player == null:
		return false
	var carry := player.get_node_or_null(^"CarryComponent") as CarryComponent
	if carry != null and carry.is_carrying():
		return false
	var light := player.get_node_or_null(^"HeldLightComponent") as HeldLightComponent
	var held := player.get_node_or_null(^"HeldItemComponent") as HeldItemComponent
	return (light == null or not light.is_holding()) and (held == null or not held.is_holding())


func _restore_item() -> void:
	var source: StringName = _source_zone
	_source_zone = &""
	var equipment: EquipmentComponent = _equipment()
	if source != &"" and equipment != null:
		var parts: PackedStringArray = String(source).split(EquipmentComponent.POCKET_SEPARATOR)
		if parts.size() == 2:
			var result := equipment.stow(StringName(parts[0]), StringName(parts[1]), hammer_item_id)
			if result == EquipmentComponent.Refusal.NONE:
				return
	if inventory != null:
		inventory.try_add(ItemCatalog.get_item(hammer_item_id))


func _equipment() -> EquipmentComponent:
	var player: Node = get_parent()
	return player.get_node_or_null(^"EquipmentComponent") as EquipmentComponent if player != null else null


func _animation() -> HenryUALAnimation:
	var player: Node = get_parent()
	return player.get(&"animation_component") as HenryUALAnimation if player != null else null
