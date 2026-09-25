class_name QuickAccessComponent
extends Node

## Reaching into a pocket without the Hub: the wheel picks a pocket, a wheel click
## uses what is in it (a flare lights in hand; a second click drops it). 1–4 only pick a pocket.

signal selection_changed(index: int, zone: Dictionary)

const NEXT_ACTION: StringName = &"quick_next"
const PREV_ACTION: StringName = &"quick_prev"
const USE_ACTION: StringName = &"quick_use"
const DIRECT_ACTIONS: Array[StringName] = [&"select item slot 1", &"select item slot 2",
	&"select item slot 3", &"select item slot 4"]
## Seconds the pocket readout stays up after the last change.
const READOUT_TIME: float = 2.0

@export var hub: PlayerHubComponent

var _index: int = 0
var _readout: Label
var _readout_left: float = 0.0


func _ready() -> void:
	if hub == null and get_parent() != null:
		hub = get_parent().get_node_or_null(^"PlayerHubComponent") as PlayerHubComponent


func _unhandled_input(event: InputEvent) -> void:
	if hub == null or hub.is_open() or not event.is_pressed() or event.is_echo():
		return
	if _pressed(event, NEXT_ACTION):
		select(_index + 1)
	elif _pressed(event, PREV_ACTION):
		select(_index - 1)
	elif _pressed(event, USE_ACTION):
		use_selected()
	else:
		for slot: int in range(DIRECT_ACTIONS.size()):
			if _pressed(event, DIRECT_ACTIONS[slot]):
				select(slot)  # selecting never spends; the wheel click uses
				break


func _process(delta: float) -> void:
	if _readout_left > 0.0:
		_readout_left -= delta
		if _readout_left <= 0.0 and is_instance_valid(_readout):
			_readout.visible = false


func get_selected_index() -> int:
	return _index


## Selects a pocket by position, wrapping around; shows which pocket and what is in it.
func select(index: int) -> void:
	if hub == null:
		return
	var zones: Array[Dictionary] = hub.get_quick_access_zones()
	if zones.is_empty():
		return
	_index = posmod(index, zones.size())
	_show_readout(zones[_index])
	selection_changed.emit(_index, zones[_index])


## A held item is put away first; otherwise the selected pocket's item is used.
func use_selected() -> bool:
	if hub == null:
		return false
	for child: Node in get_parent().get_children():
		if child.has_method(&"release_held") and bool(child.call(&"release_held")):
			return true
	var zones: Array[Dictionary] = hub.get_quick_access_zones()
	if zones.is_empty():
		return false
	var zone: Dictionary = zones[clampi(_index, 0, zones.size() - 1)]
	var item_id: StringName = zone["item_id"]
	if item_id == &"":
		_show_readout(zone)
		return false
	return hub.use_from_zone(zone["path"])


func _pressed(event: InputEvent, action: StringName) -> bool:
	return InputMap.has_action(action) and event.is_action_pressed(action)


func _show_readout(zone: Dictionary) -> void:
	if not is_inside_tree():
		return
	if not is_instance_valid(_readout):
		var layer := CanvasLayer.new()
		layer.layer = 15
		add_child(layer)
		_readout = Label.new()
		_readout.anchor_left = 0.5
		_readout.anchor_right = 0.5
		_readout.anchor_top = 0.82
		_readout.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		layer.add_child(_readout)
	var held: ItemResource = ItemCatalog.get_item(zone["item_id"]) if zone["item_id"] != &"" else null
	_readout.text = "%s: %s" % [tr(zone["name"]), tr(held.display_name) if held != null else tr("HUB_EMPTY")]
	_readout.visible = true
	_readout_left = READOUT_TIME
