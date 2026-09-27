class_name HeldItemComponent
extends Node

## Presents an owned pack/pocket item in the hand; storage remains its save authority.
@export var inventory: InventoryComponent
@export var equipment: EquipmentComponent
@export var consumption: ConsumptionController

var _prop: Node3D
var _item_id: StringName = &""
var _source_zone: StringName = &""
var _using: bool = false
var _hint: Label
var _message_left: float = 0.0


func _ready() -> void:
	if inventory == null:
		inventory = InventoryComponent.find_in(get_parent())
	if equipment == null:
		equipment = get_parent().get_node_or_null(^"EquipmentComponent") as EquipmentComponent
	if consumption == null:
		consumption = get_parent().get_node_or_null(^"ConsumptionController") as ConsumptionController
	if inventory != null:
		inventory.weight_changed.connect(func(_a: float, _b: float) -> void: _queue_sync())
	if equipment != null:
		equipment.slot_changed.connect(func(_a: StringName, _b: StringName) -> void: _queue_sync())


func supports_item(item_id: StringName) -> bool:
	var item: ItemResource = ItemCatalog.get_item(item_id)
	return item != null and item.garment == null and not item.carried_in_hands \
		and item.size_class == ItemTraits.SizeClass.POCKET and item_id not in [&"hammer", &"road_flare"]


func equip_from_zone(item_id: StringName, zone_path: StringName) -> bool:
	if not supports_item(item_id) or equipment == null:
		return false
	var parts: PackedStringArray = String(zone_path).split(EquipmentComponent.POCKET_SEPARATOR)
	if parts.size() != 2 or equipment.get_pocket_item(StringName(parts[0]), StringName(parts[1])) != item_id:
		return false
	if is_holding():
		return _item_id == item_id and _source_zone == zone_path
	var visual: HenryUALAnimation = _animation()
	var carry := get_parent().get_node_or_null(^"CarryComponent") as CarryComponent
	if visual == null or visual.get_hand_socket() == null or visual.get_held_prop() != null \
		or (carry != null and carry.is_carrying()) or visual.is_action_locking():
		return false
	_item_id = item_id
	_source_zone = zone_path
	_draw()
	return is_holding()


func is_holding() -> bool:
	return is_instance_valid(_prop)


func get_item_id() -> StringName:
	return _item_id if is_holding() else &""


func use_held() -> bool:
	if not is_holding():
		return false
	var item: ItemResource = ItemCatalog.get_item(_item_id)
	if item == null:
		put_away()
		return true
	if item.consumable == null or consumption == null:
		_show_hint()
		return true
	_using = true
	var refusal: ConsumptionController.Refusal = consumption.consume_from_zone(_source_zone) \
		if _source_zone != &"" else consumption.consume(_item_id)
	if refusal == ConsumptionController.Refusal.NONE:
		var next: StringName = item.opens_into if item.opens_into != &"" else item.consumable.leaves_behind_id
		if item.opens_into != &"":
			get_parent().call(&"play_action_animation", &"fix")
		if next != &"":
			_item_id = next
			if _zone_item() != next:
				_source_zone = &""
			_draw()
		else:
			put_away()
	else:
		_show_hint(tr(ConsumptionController.describe_refusal(refusal)))
	_using = false
	return true


func put_away_unlit() -> bool:
	return put_away()


func put_away() -> bool:
	if not is_holding():
		return false
	_clear_prop()
	_item_id = &""
	_source_zone = &""
	if is_instance_valid(_hint):
		_hint.visible = false
	return true


func _draw() -> void:
	_clear_prop()
	_prop = SurvivalItemVisual.make(_item_id)
	_prop.name = "Held_%s" % _item_id
	_animation().hold_in_hand(_prop)
	## The shared socket was fitted to legacy tools; upright containers need a reversed local Y.
	_prop.rotate_object_local(Vector3.BACK, PI)
	_prop.rotate_object_local(Vector3.RIGHT, deg_to_rad(33.0))
	if _item_id == &"knife":
		_prop.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	else:
		var grip_height: float = 0.08 if String(_item_id).begins_with("water_flask") or _item_id == &"axe" else 0.04
		_prop.position -= _prop.basis.y * grip_height
	_show_hint()


func _clear_prop() -> void:
	if not is_instance_valid(_prop):
		return
	var visual: HenryUALAnimation = _animation()
	if visual != null and visual.get_held_prop() == _prop:
		visual.release_hand()
	_prop.queue_free()
	_prop = null


func _queue_sync() -> void:
	if not _using:
		call_deferred(&"_sync_owned")


func _sync_owned() -> void:
	if not is_holding() or _using:
		return
	var visual: HenryUALAnimation = _animation()
	var owns: bool = _zone_item() == _item_id if _source_zone != &"" else inventory != null and inventory.has_item(_item_id)
	if not owns or visual == null or visual.get_held_prop() != _prop:
		put_away()


func _zone_item() -> StringName:
	var parts: PackedStringArray = String(_source_zone).split(EquipmentComponent.POCKET_SEPARATOR)
	return equipment.get_pocket_item(StringName(parts[0]), StringName(parts[1])) \
		if equipment != null and parts.size() == 2 else &""


func _show_hint(message: String = "") -> void:
	if not is_instance_valid(_hint):
		var layer := CanvasLayer.new()
		layer.layer = 15
		add_child(layer)
		_hint = Label.new()
		_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
		_hint.add_theme_font_size_override("font_size", 20)
		_hint.add_theme_constant_override("outline_size", 4)
		layer.add_child(_hint)
	var item: ItemResource = ItemCatalog.get_item(_item_id)
	var action: String = tr("HAND_TOOL_HINT")
	if item.water_capacity_ml > 0:
		action = tr("CONSUME_REFUSED_EMPTY_FLASK") if item.water_remaining_ml == 0 else "LMB · " + tr("FLASK_DRINK_ACTION")
	elif item.opens_into != &"":
		action = "LMB · " + tr("PINEAPPLE_OPEN_ACTION")
	elif item.consumable != null:
		action = "LMB · " + tr("HAND_EAT_ACTION")
	elif _item_id == &"axe":
		action = tr("AXE_BOARD_HINT")
	elif _item_id == &"knife":
		action = tr("KNIFE_PURPOSE")
	elif _item_id == &"empty_tin":
		action = tr("EMPTY_TIN_HELD_HINT")
	_hint.text = "%s\n%s" % [tr(item.display_name), message if message != "" else action]
	if item.water_capacity_ml > 0:
		_hint.text += "\n" + item.get_status_text()
	_message_left = 3.0 if message != "" else 0.0
	_hint.visible = true


func _process(delta: float) -> void:
	if not is_holding() or not is_instance_valid(_hint):
		return
	var view_size: Vector2 = get_viewport().get_visible_rect().size
	_hint.size.x = minf(640.0, view_size.x - 32.0)
	_hint.position = Vector2((view_size.x - _hint.size.x) * 0.5, view_size.y * 0.84)
	if _message_left > 0.0:
		_message_left -= delta
		if _message_left <= 0.0:
			_show_hint()


func _animation() -> HenryUALAnimation:
	return get_parent().get_node_or_null(^"HenryUALVisual") as HenryUALAnimation
