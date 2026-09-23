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
## Flat colour for the placeholder mannequin until Henry has a final model.
@export var body_color: Color = Color(0.55, 0.56, 0.58)
## Second UAL clip set, added to the player under its own library name.
@export var secondary_library_scene: PackedScene
@export var secondary_library_name: StringName = &"UAL2"

@export_group("Head look")
## Bone the procedural look turns; ADT's head look, on the UAL rig.
@export var head_bone: StringName = &"Head"
## Side-to-side head turn each way from straight ahead, degrees.
@export var head_look_primary_limit_deg: float = 55.0
## The UAL head's rest pose is yawed off the body; this re-centres the limit.
@export var head_rest_yaw_offset_deg: float = 13.0
@export var head_look_secondary_limit_deg: float = 45.0
@export var head_look_duration: float = 0.25
## Below this speed Henry counts as standing and the head follows the camera, m/s.
@export var head_look_idle_speed: float = 0.15
## How fast the look marker chases its point, and the influence fade per second.
@export var head_look_smooth: float = 8.0
@export var head_look_fade_speed: float = 4.0
## Distance the look point is held at, metres.
@export var head_look_distance: float = 5.0
## Head forward axis in bone space; flip it if the head looks sideways or back.
@export var head_forward_axis: SkeletonModifier3D.BoneAxis = SkeletonModifier3D.BONE_AXIS_PLUS_Z

@export_group("Backpack placeholder")
@export var backpack_bone: StringName = &"spine_03"
@export var backpack_size: Vector3 = Vector3(0.34, 0.44, 0.2)
## Offset from the bone in model space; the mannequin faces +Z, so back is -Z.
@export var backpack_offset: Vector3 = Vector3(0.0, 0.0, -0.2)
@export var backpack_color: Color = Color(0.36, 0.33, 0.28)

@onready var player: CharacterBody3D = get_parent() as CharacterBody3D
@onready var model: Node = $Model

var animation_player: AnimationPlayer
var skeleton: Skeleton3D
var animation_tree: AnimationTree

## Placeholder meshes a garment names in GarmentData.mesh_node_name.
var _garment_meshes: Dictionary = {}
var _equipment: EquipmentComponent
var _head_lookat: LookAtModifier3D
var _head_target: Node3D
var _head_influence: float = 0.0

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

	_paint_body()
	_attach_backpack()
	_bind_equipment()
	_setup_head_look()
	_make_animation_library_local()
	_add_secondary_library()
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


## ADT head look: standing, the head eases toward where the camera looks;
## moving, the clips own the head and the look fades out.
func update_head_look(delta: float) -> void:
	if _head_lookat == null or player == null:
		return
	var planar_speed: float = Vector2(player.velocity.x, player.velocity.z).length()
	var want: bool = planar_speed < head_look_idle_speed and player.has_method(&"get_view_direction")
	var eye: Vector3 = _head_bone_position()
	var direction: Vector3 = -player.global_transform.basis.z
	if want:
		direction = player.call(&"get_view_direction")
	direction.y = 0.0
	var target: Vector3 = eye + direction.normalized() * head_look_distance
	if want and _head_influence <= 0.001:
		_head_target.global_position = target
	else:
		_head_target.global_position = _head_target.global_position.lerp(target, clampf(delta * head_look_smooth, 0.0, 1.0))
	_head_influence = move_toward(_head_influence, 1.0 if want else 0.0, delta * head_look_fade_speed)
	_head_lookat.influence = _head_influence
	_head_lookat.active = _head_influence > 0.001


func _setup_head_look() -> void:
	if skeleton == null or skeleton.find_bone(head_bone) < 0:
		push_warning("HenryUALAnimation: no %s bone, head look disabled." % head_bone)
		return
	_head_target = Node3D.new()
	_head_target.name = "HeadLookTarget"
	add_child(_head_target)
	_head_lookat = LookAtModifier3D.new()
	_head_lookat.name = "HeadLook"
	skeleton.add_child(_head_lookat)
	_head_lookat.bone_name = head_bone
	_head_lookat.forward_axis = head_forward_axis
	## ADT: the flag is use_angle_limitation, and it needs explicit limits and duration.
	_head_lookat.use_angle_limitation = true
	_head_lookat.symmetry_limitation = false
	_head_lookat.primary_positive_limit_angle = deg_to_rad(head_look_primary_limit_deg + head_rest_yaw_offset_deg)
	_head_lookat.primary_negative_limit_angle = deg_to_rad(head_look_primary_limit_deg - head_rest_yaw_offset_deg)
	_head_lookat.secondary_limit_angle = deg_to_rad(head_look_secondary_limit_deg)
	_head_lookat.duration = head_look_duration
	_head_lookat.target_node = _head_lookat.get_path_to(_head_target)
	_head_lookat.influence = 0.0
	_head_lookat.active = false


func _head_bone_position() -> Vector3:
	var bone: int = skeleton.find_bone(head_bone)
	return (skeleton.global_transform * skeleton.get_bone_global_pose(bone)).origin


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


func _add_secondary_library() -> void:
	if secondary_library_scene == null or animation_player.has_animation_library(secondary_library_name):
		return
	var source: Node = secondary_library_scene.instantiate()
	var source_player: AnimationPlayer = _find_animation_player(source)
	if source_player != null and source_player.has_animation_library(&""):
		var library := source_player.get_animation_library(&"").duplicate(true) as AnimationLibrary
		animation_player.add_animation_library(secondary_library_name, library)
	source.free()


func _paint_body() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = body_color
	material.roughness = 0.85
	_override_materials(model, material)


func _override_materials(node: Node, material: Material) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = material
	for child: Node in node.get_children():
		_override_materials(child, material)


## A box on the upper spine standing in for the pack until it has a mesh.
func _attach_backpack() -> void:
	if skeleton == null:
		return
	var bone: int = skeleton.find_bone(backpack_bone)
	if bone < 0:
		push_warning("HenryUALAnimation: no bone %s for the backpack." % backpack_bone)
		return
	var attachment := BoneAttachment3D.new()
	attachment.name = "BackpackAttachment"
	attachment.bone_name = backpack_bone
	skeleton.add_child(attachment)
	var box := BoxMesh.new()
	box.size = backpack_size
	var material := StandardMaterial3D.new()
	material.albedo_color = backpack_color
	material.roughness = 0.9
	box.material = material
	var pack := MeshInstance3D.new()
	pack.name = "Backpack"
	pack.mesh = box
	pack.layers = portrait_render_layers
	var rest: Transform3D = skeleton.get_bone_global_rest(bone)
	pack.transform = rest.affine_inverse() * Transform3D(Basis.IDENTITY, rest.origin + backpack_offset)
	pack.visible = false
	attachment.add_child(pack)
	_garment_meshes[StringName(pack.name)] = pack


## Shows a garment's mesh only while that garment is worn.
func _bind_equipment() -> void:
	if player == null:
		return
	_equipment = player.get_node_or_null(^"EquipmentComponent") as EquipmentComponent
	if _equipment == null:
		return
	_equipment.slot_changed.connect(func(_path: StringName, _item: StringName) -> void: refresh_garment_meshes())
	refresh_garment_meshes()


func refresh_garment_meshes() -> void:
	var worn: Dictionary = {}
	if _equipment != null and _equipment.layout != null:
		for slot: EquipmentSlotDefinition in _equipment.layout.body_slots:
			var item: ItemResource = ItemCatalog.get_item(_equipment.get_equipped(slot.id))
			if item != null and item.garment != null and item.garment.mesh_node_name != &"":
				worn[item.garment.mesh_node_name] = true
	for mesh_name: StringName in _garment_meshes:
		(_garment_meshes[mesh_name] as Node3D).visible = worn.has(mesh_name)


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
