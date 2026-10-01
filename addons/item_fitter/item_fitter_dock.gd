@tool
extends Control

## Safe Hoarbound Item Fitter.
##
## The preview lives entirely inside this dock's private SubViewport. It never
## adds or removes nodes from EditorInterface.get_edited_scene_root(), so fitting
## an item cannot mutate or free nodes owned by the editor.
const HENRY_MODEL_SCENE: PackedScene = preload(
	"res://assets/characters/henry/henry_outfit.glb"
)
const SECONDARY_LIBRARY_SCENE: PackedScene = preload(
	"res://assets/animation/ual/Unreal-Godot_2/UAL2_Standard.glb"
)
const SECONDARY_LIBRARY_NAME: StringName = &"UAL2"

const LEFT_BONE: StringName = &"hand_l"
const RIGHT_BONE: StringName = &"hand_r"
const LEFT_BASE_OFFSET := Vector3(0.0, 0.12, 0.06)
const LEFT_BASE_ROTATION := Vector3(-55.0, 0.0, 0.0)
const RIGHT_BASE_OFFSET := Vector3(0.02, 0.16, 0.04)
const RIGHT_BASE_ROTATION := Vector3(0.0, 0.0, 90.0)

var _item: ItemResource
var _henry_model: Node3D
var _skeleton: Skeleton3D
var _animation_player: AnimationPlayer
var _preview_socket: BoneAttachment3D
var _preview: Node3D
var _selected_animation: StringName = &""
var _preview_playing: bool = false
var _updating_transform_controls: bool = false

var _orbit_dragging: bool = false
var _orbit_yaw_deg: float = 18.0
var _orbit_pitch_deg: float = -4.0
var _orbit_distance: float = 2.35
var _orbit_focus := Vector3(0.0, 1.05, 0.0)

@onready var _item_picker: EditorResourcePicker = $Layout/ItemPicker
@onready var _hand_button: OptionButton = $Layout/HandRow/HandButton
@onready var _animation_button: OptionButton = $Layout/AnimationRow/AnimationButton
@onready var _time_slider: HSlider = $Layout/TimeSlider
@onready var _play_button: Button = $Layout/PlaybackRow/PlayButton
@onready var _time_label: Label = $Layout/PlaybackRow/TimeLabel
@onready var _preview_container: SubViewportContainer = $Layout/PreviewFrame
@onready var _world_root: Node3D = $Layout/PreviewFrame/Preview/WorldRoot
@onready var _camera: Camera3D = $Layout/PreviewFrame/Preview/WorldRoot/Camera3D
@onready var _reset_view_button: Button = $Layout/ViewRow/ResetViewButton

@onready var _pos_x: SpinBox = $Layout/TransformGrid/PosX
@onready var _pos_y: SpinBox = $Layout/TransformGrid/PosY
@onready var _pos_z: SpinBox = $Layout/TransformGrid/PosZ
@onready var _rot_x: SpinBox = $Layout/TransformGrid/RotX
@onready var _rot_y: SpinBox = $Layout/TransformGrid/RotY
@onready var _rot_z: SpinBox = $Layout/TransformGrid/RotZ
@onready var _scale_x: SpinBox = $Layout/TransformGrid/ScaleX
@onready var _scale_y: SpinBox = $Layout/TransformGrid/ScaleY
@onready var _scale_z: SpinBox = $Layout/TransformGrid/ScaleZ

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
	_reset_view_button.pressed.connect(_reset_view)
	_preview_container.gui_input.connect(_on_preview_gui_input)
	_save_button.pressed.connect(_on_save_pressed)
	_revert_button.pressed.connect(_on_revert_pressed)

	for control: SpinBox in _transform_controls():
		control.value_changed.connect(_on_transform_value_changed)

	_build_henry_preview()
	_reset_view()
	_set_preview_playing(false)
	_update_time_label()
	_set_status("Pick an ItemResource. Preview is isolated from the edited scene.")


func _process(delta: float) -> void:
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
	## Called when the plugin unloads. These nodes belong to our private
	## SubViewport, never to the user's edited scene.
	_clear_item_preview()
	_set_preview_playing(false)


func _build_henry_preview() -> void:
	if is_instance_valid(_henry_model):
		return

	_henry_model = HENRY_MODEL_SCENE.instantiate() as Node3D
	if _henry_model == null:
		_set_status("Could not instantiate Henry preview model.")
		return
	_henry_model.name = "ItemFitHenryPreview"
	_world_root.add_child(_henry_model)

	_skeleton = _find_skeleton(_henry_model)
	_animation_player = _find_animation_player(_henry_model)
	if _skeleton == null or _animation_player == null:
		_set_status("Henry preview asset is missing Skeleton3D or AnimationPlayer.")
		return

	_add_secondary_library()
	_preview_socket = BoneAttachment3D.new()
	_preview_socket.name = "ItemFitSocket"
	_preview_socket.bone_name = LEFT_BONE
	_skeleton.add_child(_preview_socket)
	_refresh_animations()


func _add_secondary_library() -> void:
	if _animation_player == null or _animation_player.has_animation_library(SECONDARY_LIBRARY_NAME):
		return
	var source: Node = SECONDARY_LIBRARY_SCENE.instantiate()
	var source_player: AnimationPlayer = _find_animation_player(source)
	if source_player != null and source_player.has_animation_library(&""):
		var source_library: AnimationLibrary = source_player.get_animation_library(&"")
		var library := source_library.duplicate(true) as AnimationLibrary
		if library != null:
			_animation_player.add_animation_library(SECONDARY_LIBRARY_NAME, library)
	source.free()


func _rebuild_item_preview() -> void:
	_clear_item_preview()
	if _item == null:
		_set_status("Pick an ItemResource.")
		return
	if _skeleton == null or _preview_socket == null:
		_set_status("Henry preview is not ready.")
		return

	var hand: int = _hand_button.get_selected_id()
	_preview_socket.bone_name = RIGHT_BONE if hand == HeldFit.Hand.RIGHT else LEFT_BONE

	_preview = HeldPropFactory.make(_item.id, _item)
	if _preview == null:
		_set_status("No held prop visual exists for '%s'." % _item.id)
		return
	_preview.name = "ItemFitPreview"
	_preview_socket.add_child(_preview)

	if _item.held_fit != null:
		_item.held_fit.apply_to(_preview)
	else:
		_apply_default_fit(_preview, hand, _item.id)

	_sync_transform_controls_from_preview()
	_set_status("Preview ready. Adjust XYZ / rotation / scale, then Save to item.")


func _clear_item_preview() -> void:
	if not is_instance_valid(_preview):
		_preview = null
		return
	var old: Node3D = _preview
	_preview = null
	if old.get_parent() != null:
		old.get_parent().remove_child(old)
	old.queue_free()


func _apply_default_fit(prop: Node3D, hand: int, item_id: StringName) -> void:
	var offset: Vector3 = RIGHT_BASE_OFFSET if hand == HeldFit.Hand.RIGHT else LEFT_BASE_OFFSET
	var rotation: Vector3 = RIGHT_BASE_ROTATION if hand == HeldFit.Hand.RIGHT else LEFT_BASE_ROTATION
	prop.transform = Transform3D(Basis.from_euler(rotation * (PI / 180.0)), offset)
	HeldFit.apply_legacy_adjustment(prop, item_id)


func _refresh_animations() -> void:
	_animation_button.clear()
	_animation_button.add_item("(rest pose)", 0)
	if _animation_player == null:
		return

	var index: int = 1
	for clip_text: String in _animation_player.get_animation_list():
		var clip := StringName(clip_text)
		if clip == &"RESET":
			continue
		_animation_button.add_item(clip_text, index)
		index += 1
	_animation_button.select(0)
	_show_rest_pose()


func _on_animation_selected(index: int) -> void:
	if _animation_player == null:
		return
	_set_preview_playing(false)
	if index <= 0:
		_show_rest_pose()
		return

	var clip := StringName(_animation_button.get_item_text(index))
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
	if _skeleton != null:
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
		_set_status("Pick a Pose first.")
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
	_time_label.text = "%.2f / %.2f s" % [_time_slider.value, length]


func _on_item_changed(resource: Resource) -> void:
	_item = resource as ItemResource
	if _item != null and _item.held_fit != null:
		var index: int = _hand_button.get_item_index(_item.held_fit.hand)
		if index >= 0:
			_hand_button.select(index)
	_rebuild_item_preview()


func _on_hand_selected(_index: int) -> void:
	_rebuild_item_preview()


func _on_transform_value_changed(_value: float) -> void:
	if _updating_transform_controls or not is_instance_valid(_preview):
		return
	_preview.position = Vector3(_pos_x.value, _pos_y.value, _pos_z.value)
	_preview.rotation_degrees = Vector3(_rot_x.value, _rot_y.value, _rot_z.value)
	_preview.scale = Vector3(_scale_x.value, _scale_y.value, _scale_z.value)


func _sync_transform_controls_from_preview() -> void:
	if not is_instance_valid(_preview):
		return
	_updating_transform_controls = true
	_pos_x.value = _preview.position.x
	_pos_y.value = _preview.position.y
	_pos_z.value = _preview.position.z
	_rot_x.value = _preview.rotation_degrees.x
	_rot_y.value = _preview.rotation_degrees.y
	_rot_z.value = _preview.rotation_degrees.z
	_scale_x.value = _preview.scale.x
	_scale_y.value = _preview.scale.y
	_scale_z.value = _preview.scale.z
	_updating_transform_controls = false


func _transform_controls() -> Array[SpinBox]:
	return [_pos_x, _pos_y, _pos_z, _rot_x, _rot_y, _rot_z, _scale_x, _scale_y, _scale_z]


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
	_set_status("Saved HeldFit to %s." % path.get_file())


func _on_revert_pressed() -> void:
	_rebuild_item_preview()
	_set_status("Reverted to the fit stored on the item.")


func _on_preview_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT:
			_orbit_dragging = button.pressed
			_preview_container.accept_event()
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_orbit_distance = maxf(0.65, _orbit_distance * 0.88)
			_update_camera()
			_preview_container.accept_event()
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_orbit_distance = minf(6.0, _orbit_distance / 0.88)
			_update_camera()
			_preview_container.accept_event()
	elif event is InputEventMouseMotion and _orbit_dragging:
		var motion := event as InputEventMouseMotion
		_orbit_yaw_deg -= motion.relative.x * 0.35
		_orbit_pitch_deg = clampf(_orbit_pitch_deg - motion.relative.y * 0.35, -65.0, 65.0)
		_update_camera()
		_preview_container.accept_event()


func _reset_view() -> void:
	_orbit_yaw_deg = 18.0
	_orbit_pitch_deg = -4.0
	_orbit_distance = 2.35
	_orbit_focus = Vector3(0.0, 1.05, 0.0)
	_update_camera()


func _update_camera() -> void:
	if not is_instance_valid(_camera):
		return
	var yaw := deg_to_rad(_orbit_yaw_deg)
	var pitch := deg_to_rad(_orbit_pitch_deg)
	var direction := Vector3(
		sin(yaw) * cos(pitch),
		sin(pitch),
		cos(yaw) * cos(pitch)
	)
	_camera.position = _orbit_focus + direction * _orbit_distance
	_camera.look_at(_orbit_focus, Vector3.UP)


func _find_skeleton(root: Node) -> Skeleton3D:
	if root is Skeleton3D:
		return root as Skeleton3D
	for child: Node in root.get_children():
		var found: Skeleton3D = _find_skeleton(child)
		if found != null:
			return found
	return null


func _find_animation_player(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root as AnimationPlayer
	for child: Node in root.get_children():
		var found: AnimationPlayer = _find_animation_player(child)
		if found != null:
			return found
	return null


func _set_status(message: String) -> void:
	_status.text = message
