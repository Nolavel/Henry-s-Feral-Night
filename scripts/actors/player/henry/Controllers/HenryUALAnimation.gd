class_name HenryUALAnimation
extends Node3D

## Visual-only humanoid animation adapter.
## CharacterBody3D / MovementController remain the source of truth for motion.
## UAL is used in-place: this component never applies root motion.

const MOVEMENT_EPSILON: float = 0.05

const IDLE_ALIASES := [&"Idle_Loop", &"Idle"]
const WALK_ALIASES := [&"Walk_Loop", &"Walk"]
const JOG_ALIASES := [&"Jog_Fwd_Loop", &"Jog_Fwd"]
const SPRINT_ALIASES := [&"Sprint_Loop", &"Sprint"]

@export var portrait_render_layers: int = 16

@onready var player: CharacterBody3D = get_parent() as CharacterBody3D
@onready var model: Node = $Model

var movement: MovementController
var animation_player: AnimationPlayer
var skeleton: Skeleton3D
var animation_tree: AnimationTree


func _ready() -> void:
	if player == null:
		push_error("HenryUALAnimation must be a direct child of the Player CharacterBody3D.")
		set_physics_process(false)
		return

	movement = player.get_node_or_null("MovementController") as MovementController
	animation_player = _find_animation_player(model)
	skeleton = _find_skeleton(model)
	_set_mesh_layers_recursive(model, portrait_render_layers)

	if animation_player == null:
		push_error("HenryUALAnimation: UAL model has no AnimationPlayer.")
		set_physics_process(false)
		return

	if skeleton == null:
		push_warning("HenryUALAnimation: UAL model has no Skeleton3D.")
	else:
		print("Henry UAL skeleton ready: %d bones" % skeleton.get_bone_count())

	_make_animation_library_local()
	_build_locomotion_tree()


func _physics_process(_delta: float) -> void:
	if animation_tree == null or player == null:
		return

	var planar_speed: float = Vector2(player.velocity.x, player.velocity.z).length()
	var max_speed: float = 8.0
	if movement != null:
		max_speed = maxf(movement.sprint_speed, 0.001)

	var normalized_speed: float = clampf(planar_speed / max_speed, 0.0, 1.0)
	if planar_speed < MOVEMENT_EPSILON:
		normalized_speed = 0.0

	animation_tree.set("parameters/locomotion/blend_position", normalized_speed)


func _make_animation_library_local() -> void:
	var source_library: AnimationLibrary = animation_player.get_animation_library(&"")
	if source_library == null:
		return

	var local_library := source_library.duplicate(true) as AnimationLibrary
	animation_player.remove_animation_library(&"")
	animation_player.add_animation_library(&"", local_library)


func _build_locomotion_tree() -> void:
	var idle_name: StringName = _resolve_clip(IDLE_ALIASES)
	if idle_name == &"":
		idle_name = _first_available_clip()
	if idle_name == &"":
		push_error("HenryUALAnimation: no usable animations found in UAL1.")
		return

	var walk_name: StringName = _resolve_clip(WALK_ALIASES)
	var jog_name: StringName = _resolve_clip(JOG_ALIASES)
	var sprint_name: StringName = _resolve_clip(SPRINT_ALIASES)

	if walk_name == &"":
		walk_name = idle_name
	if jog_name == &"":
		jog_name = walk_name
	if sprint_name == &"":
		sprint_name = jog_name

	var locomotion := AnimationNodeBlendSpace1D.new()
	locomotion.min_space = 0.0
	locomotion.max_space = 1.0
	locomotion.value_label = "speed"
	locomotion.sync = true
	locomotion.add_blend_point(_clip(idle_name), 0.0, -1, &"idle")
	locomotion.add_blend_point(_clip(walk_name), 0.5, -1, &"walk")
	locomotion.add_blend_point(_clip(jog_name), 0.78, -1, &"jog")
	locomotion.add_blend_point(_clip(sprint_name), 1.0, -1, &"sprint")

	var blend_tree := AnimationNodeBlendTree.new()
	blend_tree.add_node(&"locomotion", locomotion, Vector2(-280.0, 0.0))
	blend_tree.connect_node(&"output", 0, &"locomotion")

	animation_tree = AnimationTree.new()
	animation_tree.name = "AnimationTree"
	animation_tree.tree_root = blend_tree
	add_child(animation_tree)
	animation_tree.anim_player = animation_tree.get_path_to(animation_player)
	animation_tree.active = true
	animation_tree.set("parameters/locomotion/blend_position", 0.0)


func _clip(animation_name: StringName) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	node.animation = animation_name
	return node


func _resolve_clip(candidates: Array) -> StringName:
	# First prefer the exact Godot import name.
	for candidate: Variant in candidates:
		var animation_name := StringName(candidate)
		if animation_player.has_animation(animation_name):
			return animation_name

	# Blender/glTF may preserve the action suffix as "_Armature".
	# Compare normalized names rather than falling back to an unrelated clip.
	var available: PackedStringArray = animation_player.get_animation_list()
	for candidate: Variant in candidates:
		var expected: String = _normalize_clip_name(StringName(candidate))
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
