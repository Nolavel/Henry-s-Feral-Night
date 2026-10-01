@tool
extends Control

## Hoarbound port of ADT's Item Fitter. Unlike ADT, Henry's hand sockets are
## runtime-created, so this dock creates an unowned temporary BoneAttachment3D
## on the real editor skeleton and puts the real SurvivalItemVisual under it.
const DEFAULT_LEFT_BONE: StringName = &"hand_l"
const DEFAULT_RIGHT_BONE: StringName = &"hand_r"
const HENRY_SCRIPT_SUFFIX: String = "HenryUALAnimation.gd"

var _item: ItemResource
var _preview: Node3D
var _preview_socket: BoneAttachment3D
var _animation_player: AnimationPlayer

@onready var _item_picker: EditorResourcePicker = $Layout/ItemPicker
@onready var _hand_button: OptionButton = $Layout/HandRow/HandButton
@onready var _animation_button: OptionButton = $Layout/AnimationRow/AnimationButton
@onready var _time_slider: HSlider = $Layout/TimeSlider
@onready var _status: Label = $Layout/Status
@onready var _save_button: Button = $Layout/Buttons/SaveButton
@onready var _revert_button: Button = $Layout/Buttons/RevertButton


func _ready() -> void:
	name = "Item Fit"
	_item_picker.base_type = "ItemResource"
	_item_picker.resource_changed.connect(_on_item_changed)
	_hand_button.clear()
	_hand_button.add_item("Left / primary", HeldFit.Hand.LEFT)
	_hand_button.add_item("Right / offhand", HeldFit.Hand.RIGHT)
	_hand_button.item_selected.connect(_on_hand_selected)
	_animation_button.item_selected.connect(_on_animation_selected)
	_time_slider.value_changed.connect(_on_time_changed)
	_save_button.pressed.connect(_on_save_pressed)
	_revert_button.pressed.connect(_on_revert_pressed)
	_set_status("Open HenryUALVisual (or Player), then pick an ItemResource.")


func clear_preview() -> void:
	if is_instance_valid(_preview):
		if _preview.get_parent() != null:
			_preview.get_parent().remove_child(_preview)
		_preview.queue_free()
	_preview = null
	if is_instance_valid(_preview_socket):
		if _preview_socket.get_parent() != null:
			_preview_socket.get_parent().remove_child(_preview_socket)
		_preview_socket.queue_free()
	_preview_socket = null


func _rebuild_preview() -> void:
	clear_preview()
	if _item == null:
		_set_status("Pick an item.")
		return
	var root: Node = EditorInterface.get_edited_scene_root()
	if root == null:
		_set_status("Open HenryUALVisual.tscn or the Player scene first.")
		return
	var skeleton: Skeleton3D = _find_skeleton(root)
	if skeleton == null:
		_set_status("No Skeleton3D found in the edited scene.")
		return
	var henry: Node = _find_henry_visual(root)
	var hand: int = _hand_button.get_selected_id()
	_preview_socket = BoneAttachment3D.new()
	_preview_socket.name = "ItemFitSocket"
	_preview_socket.bone_name = _bone_name(henry, hand)
	skeleton.add_child(_preview_socket)
	_preview_socket.owner = null

	_preview = SurvivalItemVisual.make(_item.id, _item)
	_preview.name = "ItemFitPreview"
	_preview_socket.add_child(_preview)
	_preview.owner = null

	if _item.held_fit != null:
		_item.held_fit.apply_to(_preview)
	else:
		_preview.transform = _socket_base_transform(henry, hand)
		HeldFit.apply_legacy_adjustment(_preview, _item.id)

	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(_preview)
	_refresh_animations()
	_set_status("Use the normal 3D gizmo, scrub a pose, then Save to item.")


func _find_henry_visual(root: Node) -> Node:
	for node: Node in _all_nodes(root):
		var script: Script = node.get_script() as Script
		if script != null and String(script.resource_path).ends_with(HENRY_SCRIPT_SUFFIX):
			return node
	return null


func _find_skeleton(root: Node) -> Skeleton3D:
	for node: Node in _all_nodes(root):
		if node is Skeleton3D:
			return node as Skeleton3D
	return null


func _bone_name(henry: Node, hand: int) -> StringName:
	if henry == null:
		return DEFAULT_RIGHT_BONE if hand == HeldFit.Hand.RIGHT else DEFAULT_LEFT_BONE
	var property_name: StringName = &"offhand_bone" if hand == HeldFit.Hand.RIGHT else &"hand_bone"
	var value: Variant = henry.get(property_name)
	return StringName(value) if value != null else (DEFAULT_RIGHT_BONE if hand == HeldFit.Hand.RIGHT else DEFAULT_LEFT_BONE)


func _socket_base_transform(henry: Node, hand: int) -> Transform3D:
	if henry == null:
		return Transform3D.IDENTITY
	var offset_name: StringName = &"offhand_prop_offset" if hand == HeldFit.Hand.RIGHT else &"hand_prop_offset"
	var rotation_name: StringName = &"offhand_prop_rotation_deg" if hand == HeldFit.Hand.RIGHT else &"hand_prop_rotation_deg"
	var offset: Vector3 = henry.get(offset_name)
	var rotation_deg: Vector3 = henry.get(rotation_name)
	return Transform3D(Basis.from_euler(rotation_deg * (PI / 180.0)), offset)


func _refresh_animations() -> void:
	_animation_button.clear()
	_animation_player = null
	var root: Node = EditorInterface.get_edited_scene_root()
	if root == null:
		return
	for node: Node in _all_nodes(root):
		if node is AnimationPlayer:
			_animation_player = node as AnimationPlayer
			break
	_animation_button.add_item("(rest pose)", 0)
	if _animation_player == null:
		return
	var index: int = 1
	for clip_text: String in _animation_player.get_animation_list():
		var clip: StringName = StringName(clip_text)
		if clip == &"RESET":
			continue
		_animation_button.add_item(clip_text, index)
		index += 1


func _on_animation_selected(index: int) -> void:
	if _animation_player == null:
		return
	if index <= 0:
		_animation_player.stop()
		_time_slider.max_value = 1.0
		_time_slider.value = 0.0
		return
	var clip: StringName = StringName(_animation_button.get_item_text(index))
	var animation: Animation = _animation_player.get_animation(clip)
	if animation == null:
		return
	_time_slider.max_value = maxf(animation.length, 0.01)
	_time_slider.value = 0.0
	_animation_player.play(clip)
	_animation_player.pause()
	_animation_player.seek(0.0, true)


func _on_time_changed(value: float) -> void:
	if _animation_player != null:
		_animation_player.seek(value, true)


func _on_save_pressed() -> void:
	if _item == null or not is_instance_valid(_preview):
		_set_status("Nothing to save.")
		return
	var fit: HeldFit = _item.held_fit
	if fit == null:
		fit = HeldFit.new()
		_item.held_fit = fit
	fit.hand = _hand_button.get_selected_id()
	fit.offset = _preview.position
	fit.rotation_deg = _preview.rotation_degrees
	fit.scale = _preview.scale
	var path: String = _item.resource_path
	if path.is_empty():
		_set_status("Save the ItemResource as a .tres first.")
		return
	var error: Error = ResourceSaver.save(_item, path)
	if error != OK:
		_set_status("Save failed (%d): %s" % [error, path])
		return
	_set_status("Saved HeldFit to %s" % path.get_file())


func _on_revert_pressed() -> void:
	if _item == null:
		return
	_rebuild_preview()
	_set_status("Reverted to the fit stored on the item.")


func _on_item_changed(resource: Resource) -> void:
	_item = resource as ItemResource
	if _item != null and _item.held_fit != null:
		var index: int = _hand_button.get_item_index(_item.held_fit.hand)
		if index >= 0:
			_hand_button.select(index)
	_rebuild_preview()


func _on_hand_selected(_index: int) -> void:
	_rebuild_preview()


func _all_nodes(root: Node) -> Array[Node]:
	var result: Array[Node] = [root]
	for child: Node in root.get_children():
		result.append_array(_all_nodes(child))
	return result


func _set_status(message: String) -> void:
	_status.text = message
