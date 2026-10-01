@tool
extends Control

## Hoarbound-specific authoring layer over ADT's Item Fitter.
##
## Runtime Henry builds his AnimationTree and hand sockets from GDScript, so the
## editor deliberately does NOT run HenryUALAnimation as a @tool script. Godot's
## edited scene exposes the imported GLB instance root without the runtime
## AnimationPlayer, so this dock instantiates a complete unowned copy of Henry's
## GLB for authoring, mounts the same UAL2 library, and scrubs that real skeleton.
## The item preview itself still uses the real HeldPropFactory + HeldFit contract.
const DEFAULT_HENRY_MODEL_SCENE: PackedScene = preload(
	"res://assets/characters/henry/henry_outfit.glb"
)
const DEFAULT_LEFT_BONE: StringName = &"hand_l"
const DEFAULT_RIGHT_BONE: StringName = &"hand_r"
const DEFAULT_SECONDARY_LIBRARY_NAME: StringName = &"UAL2"
const DEFAULT_SECONDARY_LIBRARY_SCENE: PackedScene = preload(
	"res://assets/animation/ual/Unreal-Godot_2/UAL2_Standard.glb"
)
const HENRY_SCRIPT_SUFFIX: String = "HenryUALAnimation.gd"

var _item: ItemResource
var _preview: Node3D
var _preview_socket: BoneAttachment3D

var _authoring_root: Node
var _henry_visual: Node
var _authoring_model: Node3D
var _skeleton: Skeleton3D
var _animation_player: AnimationPlayer
var _selected_animation: StringName = &""
var _preview_playing: bool = false

@onready var _item_picker: EditorResourcePicker = $Layout/ItemPicker
@onready var _hand_button: OptionButton = $Layout/HandRow/HandButton
@onready var _animation_button: OptionButton = $Layout/AnimationRow/AnimationButton
@onready var _time_slider: HSlider = $Layout/TimeSlider
@onready var _play_button: Button = $Layout/PlaybackRow/PlayButton
@onready var _time_label: Label = $Layout/PlaybackRow/TimeLabel
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
	_play_button.pressed.connect(_on_play_pressed)
	_save_button.pressed.connect(_on_save_pressed)
	_revert_button.pressed.connect(_on_revert_pressed)
	_set_preview_playing(false)
	_update_time_label()
	_set_status("Open HenryUALVisual.tscn (or Player), then pick an ItemResource.")


func _process(delta: float) -> void:
	## A dock survives scene switches. Never leave editor-only nodes attached to
	## the previous scene and never keep a stale AnimationPlayer reference.
	var edited_root: Node = EditorInterface.get_edited_scene_root()
	if is_instance_valid(_authoring_root) and edited_root != _authoring_root:
		clear_preview()
		_set_status("Scene changed. Open HenryUALVisual.tscn (or Player) and pick the item again.")
		return

	if not _preview_playing or _selected_animation == &"" or not is_instance_valid(_animation_player):
		return
	var animation: Animation = _animation_player.get_animation(_selected_animation)
	if animation == null:
		_set_preview_playing(false)
		return

	var length: float = maxf(animation.length, 0.01)
	var next_time: float = _time_slider.value + delta
	if next_time > length:
		if animation.loop_mode == Animation.LOOP_NONE:
			next_time = length
			_set_preview_playing(false)
		else:
			next_time = fmod(next_time, length)

	_time_slider.set_value_no_signal(next_time)
	_animation_player.seek(next_time, true)
	_update_time_label()


func clear_preview() -> void:
	_clear_item_preview()
	_clear_authoring_context()


func _clear_item_preview() -> void:
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


func _clear_authoring_context() -> void:
	_set_preview_playing(false)
	_selected_animation = &""
	if is_instance_valid(_animation_player):
		_animation_player.stop()
	if is_instance_valid(_skeleton):
		_skeleton.reset_bone_poses()
	_animation_player = null
	_skeleton = null
	if is_instance_valid(_authoring_model):
		if _authoring_model.get_parent() != null:
			_authoring_model.get_parent().remove_child(_authoring_model)
		_authoring_model.queue_free()
	_authoring_model = null
	_henry_visual = null
	_authoring_root = null
	_animation_button.clear()
	_time_slider.max_value = 1.0
	_time_slider.set_value_no_signal(0.0)
	_update_time_label()


func _rebuild_preview() -> void:
	_clear_item_preview()
	if _item == null:
		_set_status("Pick an item.")
		return
	if not _ensure_authoring_context():
		return

	var hand: int = _hand_button.get_selected_id()
	var bone_name: StringName = _bone_name(_henry_visual, hand)
	if _skeleton.find_bone(bone_name) < 0:
		_set_status("Henry skeleton has no bone '%s'." % bone_name)
		return

	_preview_socket = BoneAttachment3D.new()
	_preview_socket.name = "ItemFitSocket"
	_preview_socket.bone_name = bone_name
	_skeleton.add_child(_preview_socket)
	## Unowned editor-only node: Ctrl+S cannot serialize it into Henry.
	_preview_socket.owner = null

	_preview = HeldPropFactory.make(_item.id, _item)
	if _preview == null:
		_set_status("No held prop visual exists for '%s'." % _item.id)
		_clear_item_preview()
		return
	_preview.name = "ItemFitPreview"
	_preview_socket.add_child(_preview)
	_preview.owner = null

	if _item.held_fit != null:
		_item.held_fit.apply_to(_preview)
	else:
		_preview.transform = _socket_base_transform(_henry_visual, hand)
		HeldFit.apply_legacy_adjustment(_preview, _item.id)

	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(_preview)
	_refresh_animations()
	_set_status(
		"Henry authoring copy is live. Pick/scrub a pose, move ItemFitPreview with the 3D gizmo, then Save to item."
	)


## Builds a safe authoring AnimationPlayer beside the imported one. It copies
## UAL1 and mounts the same UAL2 library production uses, but does not create or
## touch Henry's runtime AnimationTree.
func _ensure_authoring_context() -> bool:
	var root: Node = EditorInterface.get_edited_scene_root()
	if root == null:
		_set_status("Open HenryUALVisual.tscn or the Player scene first.")
		return false
	if is_instance_valid(_animation_player) and is_instance_valid(_authoring_model) and root == _authoring_root:
		return true

	_clear_authoring_context()
	_authoring_root = root
	_henry_visual = _find_henry_visual(root)
	if _henry_visual == null:
		_set_status("No HenryUALAnimation visual found in the edited scene.")
		return false

	## Imported sub-scenes are intentionally opaque while editing their parent:
	## the Model node is visible to EditorInterface, but its imported
	## AnimationPlayer is not. Instantiate the exact same GLB as an unowned
	## authoring copy so its full runtime node tree exists in the editor.
	_authoring_model = DEFAULT_HENRY_MODEL_SCENE.instantiate() as Node3D
	if _authoring_model == null:
		_set_status("Could not instantiate Henry's authoring model.")
		return false
	_authoring_model.name = "ItemFitHenryPreview"
	var scene_model := _henry_visual.get_node_or_null(^"Model") as Node3D
	if scene_model != null:
		_authoring_model.transform = scene_model.transform
	_henry_visual.add_child(_authoring_model)
	_authoring_model.owner = null

	_skeleton = _find_skeleton(_authoring_model)
	_animation_player = _find_animation_player(_authoring_model)
	if _skeleton == null:
		_set_status("Henry authoring copy has no Skeleton3D.")
		_clear_authoring_context()
		return false
	if _animation_player == null:
		_set_status("Henry authoring copy has no AnimationPlayer.")
		_clear_authoring_context()
		return false

	_add_secondary_library()
	return true


func _add_secondary_library() -> void:
	if _animation_player == null:
		return
	var secondary_scene: PackedScene = DEFAULT_SECONDARY_LIBRARY_SCENE
	var secondary_name: StringName = DEFAULT_SECONDARY_LIBRARY_NAME

	if _henry_visual != null:
		var configured_scene: Variant = _henry_visual.get(&"secondary_library_scene")
		if configured_scene is PackedScene:
			secondary_scene = configured_scene as PackedScene
		var configured_name: Variant = _henry_visual.get(&"secondary_library_name")
		if configured_name != null and String(configured_name) != "":
			secondary_name = StringName(configured_name)

	if secondary_scene == null or _animation_player.has_animation_library(secondary_name):
		return

	var source: Node = secondary_scene.instantiate()
	var source_player: AnimationPlayer = _find_animation_player(source)
	if source_player != null and source_player.has_animation_library(&""):
		var source_library: AnimationLibrary = source_player.get_animation_library(&"")
		var library := source_library.duplicate(true) as AnimationLibrary
		if library != null:
			_animation_player.add_animation_library(secondary_name, library)
	source.free()


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


func _find_animation_player(root: Node) -> AnimationPlayer:
	for node: Node in _all_nodes(root):
		if node is AnimationPlayer:
			return node as AnimationPlayer
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
	_animation_button.add_item("(rest pose)", 0)
	if _animation_player == null:
		return

	var selected_index: int = 0
	var index: int = 1
	for clip_text: String in _animation_player.get_animation_list():
		var clip: StringName = StringName(clip_text)
		if clip == &"RESET":
			continue
		_animation_button.add_item(clip_text, index)
		if clip == _selected_animation:
			selected_index = index
		index += 1

	_animation_button.select(selected_index)
	if selected_index == 0:
		_show_rest_pose()
	else:
		_on_animation_selected(selected_index)


func _on_animation_selected(index: int) -> void:
	if _animation_player == null:
		return
	_set_preview_playing(false)
	if index <= 0:
		_show_rest_pose()
		return

	var clip: StringName = StringName(_animation_button.get_item_text(index))
	var animation: Animation = _animation_player.get_animation(clip)
	if animation == null:
		return
	_selected_animation = clip
	_time_slider.max_value = maxf(animation.length, 0.01)
	_time_slider.set_value_no_signal(0.0)
	_animation_player.play(clip)
	_animation_player.pause()
	_animation_player.seek(0.0, true)
	_update_time_label()


func _show_rest_pose() -> void:
	_selected_animation = &""
	_time_slider.max_value = 1.0
	_time_slider.set_value_no_signal(0.0)
	if _animation_player != null:
		_animation_player.stop()
	if is_instance_valid(_skeleton):
		_skeleton.reset_bone_poses()
	_update_time_label()


func _on_time_changed(value: float) -> void:
	if _animation_player == null or _selected_animation == &"":
		_update_time_label()
		return
	_animation_player.seek(value, true)
	_update_time_label()


func _on_play_pressed() -> void:
	if _selected_animation == &"" or _animation_player == null:
		_set_status("Pick an animation first.")
		return
	var animation: Animation = _animation_player.get_animation(_selected_animation)
	if animation == null:
		return
	if not _preview_playing and _time_slider.value >= animation.length:
		_time_slider.set_value_no_signal(0.0)
		_animation_player.seek(0.0, true)
	_set_preview_playing(not _preview_playing)


func _set_preview_playing(playing: bool) -> void:
	_preview_playing = playing
	if is_instance_valid(_play_button):
		_play_button.text = "Pause" if playing else "Play"


func _update_time_label() -> void:
	if not is_instance_valid(_time_label):
		return
	var length: float = 0.0
	if _animation_player != null and _selected_animation != &"":
		var animation: Animation = _animation_player.get_animation(_selected_animation)
		if animation != null:
			length = animation.length
	_time_label.text = "%.2f / %.2f s" % [_time_slider.value if is_instance_valid(_time_slider) else 0.0, length]


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
	_set_status("Saved HeldFit to %s. Runtime will use this exact local transform." % path.get_file())


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
