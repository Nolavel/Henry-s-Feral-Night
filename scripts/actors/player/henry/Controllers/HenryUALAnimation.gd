class_name HenryUALAnimation
extends Node3D

## Henry locomotion animation component.
##
## Same ownership rule as ADT's PlayerAnimationComponent:
## - the AnimationTree is assembled entirely in GDScript (no .tres tree),
## - the component only READS Player state,
## - it has no _process/_physics_process of its own,
## - Player.gd explicitly calls update_animation_blend() after move_and_slide(),
##   so animation sees the velocity that actually survived collision/slope handling.
##
## UAL is strictly in-place. CharacterBody3D remains authoritative for motion.

const MOVEMENT_EPSILON: float = 0.05

const IDLE_ALIASES: Array[StringName] = [&"Idle_Loop", &"Idle"]
const WALK_ALIASES: Array[StringName] = [&"Walk_Loop", &"Walk"]
const JOG_ALIASES: Array[StringName] = [&"Jog_Fwd_Loop", &"Jog_Fwd"]
const SPRINT_ALIASES: Array[StringName] = [&"Sprint_Loop", &"Sprint"]

@export_group("Locomotion Blend")
## Position of the authored walk cycle in normalized 0..1 real speed.
## Henry currently walks at 4 m/s and sprints at 8 m/s, so 0.50 is physical.
@export_range(0.1, 0.75, 0.01) var walk_blend_position: float = 0.50
## Jog sits between walk and full sprint. This is a feel point rather than a
## separate gameplay speed tier: MovementController still owns actual speed.
@export_range(0.5, 0.95, 0.01) var jog_blend_position: float = 0.78

@export_group("Visual")
@export var portrait_render_layers: int = 16

@onready var player: CharacterBody3D = get_parent() as CharacterBody3D
@onready var model: Node = $Model

var animation_player: AnimationPlayer
var skeleton: Skeleton3D
var animation_tree: AnimationTree

var _blend_position: float = 0.0
var _resolved_idle: StringName = &""
var _resolved_walk: StringName = &""
var _resolved_jog: StringName = &""
var _resolved_sprint: StringName = &""


func _ready() -> void:
	if player == null:
		push_error("HenryUALAnimation must be a direct child of Player.")
		return

	animation_player = _find_animation_player(model)
	skeleton = _find_skeleton(model)
	_set_mesh_layers_recursive(model, portrait_render_layers)

	if animation_player == null:
		push_error("HenryUALAnimation: rigged Henry has no AnimationPlayer.")
		return

	if skeleton == null:
		push_warning("HenryUALAnimation: rigged Henry has no Skeleton3D.")
	else:
		print("Henry UAL skeleton ready: %d bones" % skeleton.get_bone_count())

	_make_animation_library_local()
	_setup_animation_tree()


## Called explicitly from Player.gd AFTER move_and_slide().
## No input intent is used here: only real horizontal velocity, the same
## principle ADT uses so animation cannot visually outrun physics.
func update_animation_blend(_delta: float) -> void:
	if animation_tree == null or player == null:
		return

	_blend_position = 0.0
	if player.has_method("get_locomotion_speed_ratio"):
		_blend_position = float(player.call("get_locomotion_speed_ratio"))
	else:
		var planar_speed: float = Vector2(player.velocity.x, player.velocity.z).length()
		_blend_position = clampf(planar_speed / 8.0, 0.0, 1.0)

	if Vector2(player.velocity.x, player.velocity.z).length() < MOVEMENT_EPSILON:
		_blend_position = 0.0

	animation_tree.set("parameters/locomotion/blend_position", _blend_position)


func get_locomotion_blend_position() -> float:
	return _blend_position


func get_locomotion_label() -> String:
	if _blend_position <= 0.05:
		return "IDLE"
	if _blend_position < (walk_blend_position + jog_blend_position) * 0.5:
		return "WALK"
	if _blend_position < (jog_blend_position + 1.0) * 0.5:
		return "JOG"
	return "SPRINT"


func _make_animation_library_local() -> void:
	var source_library: AnimationLibrary = animation_player.get_animation_library(&"")
	if source_library == null:
		return

	var local_library := source_library.duplicate(true) as AnimationLibrary
	animation_player.remove_animation_library(&"")
	animation_player.add_animation_library(&"", local_library)


## ADT convention: build the complete graph in code. No editor-authored
## AnimationTree resource exists to drift away from clip names or component code.
func _setup_animation_tree() -> void:
	_resolved_idle = _resolve_clip(IDLE_ALIASES)
	_resolved_walk = _resolve_clip(WALK_ALIASES)
	_resolved_jog = _resolve_clip(JOG_ALIASES)
	_resolved_sprint = _resolve_clip(SPRINT_ALIASES)

	if _resolved_idle == &"":
		_resolved_idle = _first_available_clip()
	if _resolved_idle == &"":
		push_error("HenryUALAnimation: no usable UAL animations found.")
		return

	if _resolved_walk == &"":
		_resolved_walk = _resolved_idle
	if _resolved_jog == &"":
		_resolved_jog = _resolved_walk
	if _resolved_sprint == &"":
		_resolved_sprint = _resolved_jog

	_force_locomotion_loop(_resolved_idle)
	_force_locomotion_loop(_resolved_walk)
	_force_locomotion_loop(_resolved_jog)
	_force_locomotion_loop(_resolved_sprint)

	var locomotion := AnimationNodeBlendSpace1D.new()
	locomotion.min_space = 0.0
	locomotion.max_space = 1.0
	locomotion.value_label = "real speed"
	locomotion.sync = true
	locomotion.add_blend_point(_clip(_resolved_idle), 0.0, -1, &"idle")
	locomotion.add_blend_point(_clip(_resolved_walk), walk_blend_position, -1, &"walk")
	locomotion.add_blend_point(_clip(_resolved_jog), jog_blend_position, -1, &"jog")
	locomotion.add_blend_point(_clip(_resolved_sprint), 1.0, -1, &"sprint")

	var tree_root := AnimationNodeBlendTree.new()
	tree_root.add_node(&"locomotion", locomotion, Vector2(-280.0, 0.0))
	tree_root.connect_node(&"output", 0, &"locomotion")

	animation_tree = AnimationTree.new()
	animation_tree.name = "AnimationTree"
	animation_tree.tree_root = tree_root
	add_child(animation_tree)
	animation_tree.anim_player = animation_tree.get_path_to(animation_player)
	animation_tree.active = true
	animation_tree.set("parameters/locomotion/blend_position", 0.0)


func _force_locomotion_loop(animation_name: StringName) -> void:
	if animation_name == &"":
		return
	var animation: Animation = animation_player.get_animation(animation_name)
	if animation != null:
		animation.loop_mode = Animation.LOOP_LINEAR


func _clip(animation_name: StringName) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	node.animation = animation_name
	return node


func _resolve_clip(candidates: Array[StringName]) -> StringName:
	for candidate: StringName in candidates:
		if animation_player.has_animation(candidate):
			return candidate

	var available: PackedStringArray = animation_player.get_animation_list()
	for candidate: StringName in candidates:
		var expected: String = _normalize_clip_name(candidate)
		for actual_text: String in available:
			var actual := StringName(actual_text)
			if _normalize_clip_name(actual) == expected:
				return actual
	return &""


func _normalize_clip_name(animation_name: StringName) -> String:
	var normalized := String(animation_name).to_lower().replace(" ", "_")
	if normalized.ends_with("_armature"):
		normalized = normalized.trim_suffix("_armature")
	if normalized.contains("|"):
		normalized = normalized.get_slice("|", normalized.get_slice_count("|") - 1)
	return normalized


func _first_available_clip() -> StringName:
	for animation_name: StringName in animation_player.get_animation_list():
		if animation_name != &"RESET":
			return animation_name
	return &""


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child: Node in node.get_children():
		var found: AnimationPlayer = _find_animation_player(child)
		if found != null:
			return found
	return null


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child: Node in node.get_children():
		var found: Skeleton3D = _find_skeleton(child)
		if found != null:
			return found
	return null


func _set_mesh_layers_recursive(node: Node, layers: int) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).layers = layers
	for child: Node in node.get_children():
		_set_mesh_layers_recursive(child, layers)
