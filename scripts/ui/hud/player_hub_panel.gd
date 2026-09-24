class_name PlayerHubPanel
extends CanvasLayer

## Temporary Hub readout beside Henry: pack contents, Quick Access zones, weight.
## Reads and moves through PlayerHubComponent only; keeps no item state.

const SIZE_KEYS: Array[String] = ["HUB_SIZE_POCKET", "HUB_SIZE_CARRIED", "HUB_SIZE_BULKY"]
const REFUSAL_KEYS: Dictionary = {
	EquipmentComponent.Refusal.TOO_LARGE: "HUB_REFUSED_TOO_LARGE",
	EquipmentComponent.Refusal.SLOT_OCCUPIED: "HUB_REFUSED_OCCUPIED",
}

var hub: PlayerHubComponent

var _pack_list: ItemList
var _zone_list: ItemList
var _weight: Label
var _status: Label
var _pack_ids: Array[StringName] = []
var _zone_paths: Array[StringName] = []


func _ready() -> void:
	layer = 20
	_build()
	hub.contents_changed.connect(_refresh)
	_refresh()


func _build() -> void:
	var panel := PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.08
	panel.anchor_bottom = 0.92
	panel.offset_left = -380.0
	panel.offset_right = -24.0
	add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 8)
	panel.add_child(column)
	column.add_child(_label(tr("HUB_PACK")))
	_pack_list = _list()
	column.add_child(_pack_list)
	_weight = _label("")
	column.add_child(_weight)
	column.add_child(_label(tr("HUB_QUICK_ACCESS")))
	_zone_list = _list()
	column.add_child(_zone_list)
	var buttons := HBoxContainer.new()
	column.add_child(buttons)
	buttons.add_child(_button(tr("HUB_TO_POCKET"), _on_to_pocket))
	buttons.add_child(_button(tr("HUB_TO_PACK"), _on_to_pack))
	_status = _label("")
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	column.add_child(_status)
	column.add_child(_label(tr("HUB_CLOSE_HINT")))


func _refresh() -> void:
	_pack_list.clear()
	_pack_ids.clear()
	for item: Dictionary in hub.get_pack_items():
		var count: String = " ×%d" % item["count"] if int(item["count"]) > 1 else ""
		_pack_list.add_item("%s%s  ·  %s  ·  %.1f kg" % [tr(item["name"]), count, tr(SIZE_KEYS[item["size"]]), item["weight"]])
		_pack_ids.append(item["id"])
	_zone_list.clear()
	_zone_paths.clear()
	for zone: Dictionary in hub.get_quick_access_zones():
		var held: ItemResource = ItemCatalog.get_item(zone["item_id"]) if zone["item_id"] != &"" else null
		var content: String = tr(held.display_name) if held != null else tr("HUB_EMPTY")
		_zone_list.add_item("%s (%s): %s" % [tr(zone["name"]), tr(SIZE_KEYS[zone["max_size"]]), content])
		_zone_paths.append(zone["path"])
	_weight.text = tr("HUB_WEIGHT") % [hub.get_weight(), hub.get_max_weight()]


## Selected pack item into the selected zone, or the first free one it fits.
func _on_to_pocket() -> void:
	var picked: PackedInt32Array = _pack_list.get_selected_items()
	if picked.is_empty():
		return
	var item_id: StringName = _pack_ids[picked[0]]
	var zones: PackedInt32Array = _zone_list.get_selected_items()
	var refusal: EquipmentComponent.Refusal = EquipmentComponent.Refusal.NO_SUCH_SLOT
	if not zones.is_empty():
		refusal = hub.move_to_zone(item_id, _zone_paths[zones[0]])
	else:
		for path: StringName in _zone_paths:
			refusal = hub.move_to_zone(item_id, path)
			if refusal == EquipmentComponent.Refusal.NONE:
				break
	_status.text = "" if refusal == EquipmentComponent.Refusal.NONE else tr(REFUSAL_KEYS.get(refusal, "HUB_REFUSED_NO_ZONE"))


func _on_to_pack() -> void:
	var zones: PackedInt32Array = _zone_list.get_selected_items()
	if zones.is_empty():
		return
	var reason: StringName = hub.move_to_pack(_zone_paths[zones[0]])
	_status.text = tr("HUB_REFUSED_OVERWEIGHT") if reason == PlayerHubComponent.OVERWEIGHT else ""


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label


func _list() -> ItemList:
	var list := ItemList.new()
	list.custom_minimum_size = Vector2(0.0, 150.0)
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return list


func _button(text: String, pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(pressed)
	return button
