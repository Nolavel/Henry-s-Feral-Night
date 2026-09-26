class_name ActionPrompt3D
extends Node3D

## ADT HoldPrompt's production shape adapted to HFN:
## - world-space SubViewport carried by a billboarded Sprite3D;
## - no depth test, because the prompt is a game statement;
## - rises from the target instead of fading on the glass;
## - reflects InteractComponent/InteractiveArea and never owns interaction.
##
## HFN adds the requested readable frame: key cap + current action + one short
## factual detail. The old per-object Label3D is suppressed while this exists.

const GROUP_ACTION_PROMPT: StringName = &"action_prompt_3d"

@export_group("World placement")
@export var canvas_size: Vector2i = Vector2i(384, 160)
@export var billboard_pixel_size: float = 0.0020
@export var risen_offset: Vector3 = Vector3(0.0, 0.62, 0.0)
@export var seated_offset: Vector3 = Vector3(0.0, 0.12, 0.0)
@export var seated_scale: float = 0.58

@export_group("Motion")
@export var appear_rate: float = 5.5
@export var disappear_rate: float = 7.0
@export var press_decay_rate: float = 5.5

@onready var _viewport: SubViewport = $Face
@onready var _face: ActionPromptFace = $Face/Prompt
@onready var _billboard: Sprite3D = $Billboard

var _interact: InteractComponent
var _target: InteractiveArea
var _follow_target: InteractiveArea
var _appear: float = 0.0
var _press: float = 0.0
var _refresh_left: float = 0.0


func _ready() -> void:
	add_to_group(GROUP_ACTION_PROMPT)
	_viewport.size = canvas_size
	_billboard.texture = _viewport.get_texture()
	_billboard.pixel_size = billboard_pixel_size
	_billboard.visible = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED


func on_world_ready(context: WorldContext) -> void:
	if context == null or context.player == null:
		return
	_interact = context.player.get_node_or_null(^"InteractComponent") as InteractComponent
	if _interact != null and not _interact.interaction_performed.is_connected(_on_interaction_performed):
		_interact.interaction_performed.connect(_on_interaction_performed)


func _process(delta: float) -> void:
	var candidate: InteractiveArea = null
	if _interact != null and is_instance_valid(_interact.current_target):
		candidate = _interact.current_target

	var should_show := (
		candidate != null
		and candidate.shape_cast_detected
		and candidate.can_interact()
	)

	if should_show:
		if candidate != _target:
			_target = candidate
			_follow_target = candidate
			_sync_prompt()
		_refresh_left = maxf(_refresh_left - delta, 0.0)
		if _refresh_left <= 0.0:
			_refresh_left = 0.12
			_sync_prompt()
	else:
		_target = null

	var target_value := 1.0 if should_show else 0.0
	var rate := appear_rate if target_value > _appear else disappear_rate
	_appear = move_toward(_appear, target_value, rate * delta)
	_press = move_toward(_press, 0.0, press_decay_rate * delta)
	_face.set_press_amount(_press)

	if _appear <= 0.001:
		_billboard_visible(false)
		if not should_show:
			_follow_target = null
		return
	if not is_instance_valid(_follow_target):
		_billboard_visible(false)
		return

	var t := 1.0 - (1.0 - _appear) * (1.0 - _appear)
	_billboard.global_position = (
		_follow_target.global_position + seated_offset.lerp(risen_offset, t)
	)
	var s := lerpf(seated_scale, 1.0, t)
	_billboard.scale = Vector3(s, s, s)
	_billboard.modulate.a = t
	_billboard_visible(true)


func _sync_prompt() -> void:
	if not is_instance_valid(_target):
		return
	var data := _target.get_interaction_prompt_data()
	_face.set_prompt(
		tr("PROMPT_HEADER_INTERACT"),
		String(data.get("key", "F")),
		String(data.get("action", tr("INTERACT_USE"))),
		String(data.get("detail", ""))
	)


func _on_interaction_performed(target: InteractiveArea) -> void:
	if target != _follow_target:
		return
	_press = 1.0
	# Door/cabinet state may flip inside interact(); refresh after that fact.
	call_deferred("_sync_prompt")


func _billboard_visible(on: bool) -> void:
	if _billboard.visible == on:
		return
	_billboard.visible = on
	_viewport.render_target_update_mode = (
		SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	)
