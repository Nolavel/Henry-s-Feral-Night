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
const CROUCH_IDLE_ALIASES: Array[StringName] = [&"Crouch_Idle_Loop", &"Crouch_Idle"]
const CROUCH_FWD_ALIASES: Array[StringName] = [&"Crouch_Fwd_Loop", &"Crouch_Fwd"]
const JUMP_START_ALIASES: Array[StringName] = [&"Jump_Start"]
const JUMP_LOOP_ALIASES: Array[StringName] = [&"Jump_Loop"]
const JUMP_LAND_ALIASES: Array[StringName] = [&"Jump_Land"]

const ACTION_ALIASES: Dictionary = {
	&"interact": [&"Interact"],
	&"pickup": [&"PickUp_Table", &"Pickup_Table"],
	&"fix": [&"Fixing_Kneeling"],
	&"consume": [&"Consume", &"UAL2/Consume"],
	&"chest_open": [&"Chest_Open", &"UAL2/Chest_Open"],
	&"hit_chest": [&"Hit_Chest"],
	&"hit_head": [&"Hit_Head"],
	&"sit_enter": [&"Sitting_Enter"],
	&"sit_exit": [&"Sitting_Exit"],
}

@export_group("Locomotion Blend")
## Position of the authored walk cycle in normalized 0..1 real speed.
## Henry walks at 1.5 m/s and sprints at 4.5 m/s, so 0.33 is physical.
@export_range(0.1, 0.75, 0.01) var walk_blend_position: float = 0.33
## Jog sits between walk and full sprint. This is a feel point rather than a
## separate gameplay speed tier: MovementController still owns actual speed.
@export_range(0.5, 0.95, 0.01) var jog_blend_position: float = 0.67

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
## Greybox clothing: pieces per garment mesh name, built on the rest pose.
## "seg" [bone, to_bone, radius, pad]; "blob" [bone, offset, radii]; "block" [bone, offset, size].
const GARMENT_PIECES: Dictionary = {
	&"Hat": {"color": Color(0.55, 0.24, 0.2), "pieces": [
		["blob", &"Head", Vector3(0.0, 0.13, 0.0), Vector3(0.115, 0.085, 0.12)],
		["blob", &"Head", Vector3(0.0, 0.08, 0.0), Vector3(0.12, 0.035, 0.125)]]},
	&"Coat": {"color": Color(0.33, 0.35, 0.28), "pieces": [
		["block", &"spine_02", Vector3(0.0, 0.02, 0.0), Vector3(0.4, 0.62, 0.27)],
		["block", &"pelvis", Vector3(0.0, -0.08, 0.0), Vector3(0.38, 0.26, 0.26)],
		["blob", &"neck_01", Vector3(0.0, -0.02, 0.0), Vector3(0.1, 0.06, 0.1)],
		["seg", &"upperarm_l", &"lowerarm_l", 0.075, 0.02],
		["seg", &"lowerarm_l", &"hand_l", 0.066, -0.03],
		["seg", &"upperarm_r", &"lowerarm_r", 0.075, 0.02],
		["seg", &"lowerarm_r", &"hand_r", 0.066, -0.03]]},
	&"Trousers": {"color": Color(0.27, 0.29, 0.35), "pieces": [
		["block", &"pelvis", Vector3(0.0, -0.02, 0.0), Vector3(0.34, 0.2, 0.24)],
		["seg", &"thigh_l", &"calf_l", 0.085, 0.02],
		["seg", &"calf_l", &"foot_l", 0.07, -0.08],
		["seg", &"thigh_r", &"calf_r", 0.085, 0.02],
		["seg", &"calf_r", &"foot_r", 0.07, -0.08]]},
	&"Boots": {"color": Color(0.2, 0.16, 0.13), "pieces": [
		["block", &"foot_l", Vector3(0.0, -0.04, 0.08), Vector3(0.12, 0.13, 0.3)],
		["block", &"foot_l", Vector3(0.0, 0.08, -0.01), Vector3(0.13, 0.18, 0.14)],
		["block", &"foot_r", Vector3(0.0, -0.04, 0.08), Vector3(0.12, 0.13, 0.3)],
		["block", &"foot_r", Vector3(0.0, 0.08, -0.01), Vector3(0.13, 0.18, 0.14)]]},
}
## How much fully soaked clothing darkens.
@export_range(0.0, 1.0, 0.05) var wet_darkening: float = 0.45
## Kenny's faded plush, lighter than the pack so the silhouette separates.
@export var kenny_color: Color = Color(0.55, 0.45, 0.34)

@onready var player: CharacterBody3D = get_parent() as CharacterBody3D
@onready var model: Node = $Model

var animation_player: AnimationPlayer
var skeleton: Skeleton3D
var animation_tree: AnimationTree
var _state_playback: AnimationNodeStateMachinePlayback
var _action_node: AnimationNodeAnimation

## Placeholder meshes a garment names in GarmentData.mesh_node_name.
var _garment_meshes: Dictionary = {}
## Garment name to its material, darkened by wetness.
var _garment_materials: Dictionary = {}
var _wetness: float = 0.0
var _equipment: EquipmentComponent
var _head_lookat: LookAtModifier3D
var _head_target: Node3D
var _head_influence: float = 0.0

var _blend_position: float = 0.0
var _resolved_idle: StringName = &""
var _resolved_walk: StringName = &""
var _resolved_jog: StringName = &""
var _resolved_sprint: StringName = &""
var _resolved_crouch_idle: StringName = &""
var _resolved_crouch_fwd: StringName = &""
var _resolved_jump_start: StringName = &""
var _resolved_jump_loop: StringName = &""
var _resolved_jump_land: StringName = &""


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
	_attach_garments()
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
		_blend_position = clampf(planar_speed / 4.5, 0.0, 1.0)

	if Vector2(player.velocity.x, player.velocity.z).length() < MOVEMENT_EPSILON:
		_blend_position = 0.0

	animation_tree.set("parameters/base/Grounded/blend_position", _blend_position)
	var crouch_blend: float = 0.0
	if player.has_method("get_crouch_speed_ratio"):
		crouch_blend = float(player.call("get_crouch_speed_ratio"))
	animation_tree.set("parameters/base/Crouch/blend_position", crouch_blend)


func update_animation_state(jump_started: bool, landed: bool) -> void:
	if _state_playback == null or player == null:
		return
	var current: StringName = _state_playback.get_current_node()
	if landed:
		_state_playback.travel(&"Land")
		return
	if current == &"Land":
		return
	if jump_started:
		_state_playback.travel(&"JumpStart")
		return
	if current == &"JumpStart":
		return
	if not player.is_on_floor():
		_state_playback.travel(&"AirLoop")
		return
	var crouching: bool = player.has_method("is_crouching") and bool(player.call("is_crouching"))
	_state_playback.travel(&"Crouch" if crouching else &"Grounded")


func play_action(action: StringName) -> bool:
	if animation_tree == null or _action_node == null:
		return false
	var clip_name: StringName = _resolve_action_clip(action)
	if clip_name == &"":
		return false
	var animation: Animation = animation_player.get_animation(clip_name)
	if animation != null:
		animation.loop_mode = Animation.LOOP_NONE
	_action_node.animation = clip_name
	animation_tree.set("parameters/actions/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	return true


func abort_action() -> void:
	if animation_tree != null:
		animation_tree.set("parameters/actions/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)


func _resolve_action_clip(action: StringName) -> StringName:
	if not ACTION_ALIASES.has(action):
		return &""
	var aliases: Array[StringName] = []
	for value: Variant in ACTION_ALIASES[action]:
		aliases.append(StringName(value))
	return _resolve_clip(aliases)


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
	_attach_kenny(attachment, pack)


## Kenny strapped to the outside of the pack: a teddy silhouette facing back,
## sat on the pack's lower half. Shown only while he rides on his fixture.
func _attach_kenny(attachment: BoneAttachment3D, pack: MeshInstance3D) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = kenny_color
	material.roughness = 1.0
	var kenny := Node3D.new()
	kenny.name = "Kenny"
	kenny.transform = pack.transform * Transform3D(Basis.IDENTITY, Vector3(0.0, -0.04, -backpack_size.z * 0.5 - 0.07))
	kenny.visible = false
	attachment.add_child(kenny)
	## [centre, radii] in pack space; +Y up, -Z away from Henry's back.
	var parts: Array = [
		[Vector3(0.0, 0.0, 0.0), Vector3(0.1, 0.12, 0.07)],
		[Vector3(0.0, 0.17, -0.01), Vector3(0.075, 0.07, 0.065)],
		[Vector3(-0.06, 0.235, -0.01), Vector3(0.025, 0.025, 0.015)],
		[Vector3(0.06, 0.235, -0.01), Vector3(0.025, 0.025, 0.015)],
		[Vector3(0.0, 0.16, -0.07), Vector3(0.03, 0.022, 0.02)],
		[Vector3(-0.11, 0.02, -0.01), Vector3(0.03, 0.07, 0.03)],
		[Vector3(0.11, 0.02, -0.01), Vector3(0.03, 0.07, 0.03)],
		[Vector3(-0.05, -0.14, -0.03), Vector3(0.035, 0.05, 0.035)],
		[Vector3(0.05, -0.14, -0.03), Vector3(0.035, 0.05, 0.035)],
	]
	for part: Array in parts:
		var sphere := SphereMesh.new()
		sphere.radius = 1.0
		sphere.height = 2.0
		sphere.radial_segments = 12
		sphere.rings = 6
		sphere.material = material
		var blob := MeshInstance3D.new()
		blob.mesh = sphere
		blob.layers = portrait_render_layers
		blob.transform = Transform3D(Basis.from_scale(part[1]), part[0])
		kenny.add_child(blob)
	var strap := BoxMesh.new()
	strap.size = Vector3(backpack_size.x + 0.02, 0.025, 0.2)
	var strap_mat := StandardMaterial3D.new()
	strap_mat.albedo_color = Color(0.15, 0.14, 0.13)
	strap.material = strap_mat
	var band := MeshInstance3D.new()
	band.mesh = strap
	band.layers = portrait_render_layers
	band.position = Vector3(0.0, 0.02, 0.07)
	kenny.add_child(band)
	_garment_meshes[&"Kenny"] = kenny


## Greybox clothes from GARMENT_PIECES, each on the bone it moves with. Hidden
## until the equipment shows them.
func _attach_garments() -> void:
	if skeleton == null:
		return
	for garment_name: StringName in GARMENT_PIECES:
		var spec: Dictionary = GARMENT_PIECES[garment_name]
		var material := StandardMaterial3D.new()
		material.albedo_color = spec["color"]
		material.roughness = 1.0
		material.set_meta(&"dry_color", spec["color"])
		_garment_materials[garment_name] = material
		var group := Node3D.new()
		group.name = String(garment_name)
		group.visible = false
		skeleton.add_child(group)
		for piece: Array in spec["pieces"]:
			var bone: int = skeleton.find_bone(piece[1])
			if bone < 0:
				continue
			## Not a direct skeleton child, so it follows the bone by reference.
			var attachment := BoneAttachment3D.new()
			group.add_child(attachment)
			attachment.use_external_skeleton = true
			attachment.external_skeleton = attachment.get_path_to(skeleton)
			attachment.bone_name = piece[1]
			var rest: Transform3D = skeleton.get_bone_global_rest(bone)
			var mesh_inst := MeshInstance3D.new()
			mesh_inst.layers = portrait_render_layers
			var global_xf := Transform3D.IDENTITY
			match String(piece[0]):
				"seg":
					var to: Vector3 = skeleton.get_bone_global_rest(skeleton.find_bone(piece[2])).origin
					var along: Vector3 = to - rest.origin
					var length: float = along.length() + float(piece[4])
					var capsule := CapsuleMesh.new()
					capsule.radius = float(piece[3])
					capsule.height = maxf(length, capsule.radius * 2.0)
					capsule.material = material
					mesh_inst.mesh = capsule
					var y: Vector3 = along.normalized()
					var x: Vector3 = y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
					global_xf = Transform3D(Basis(x, y, x.cross(y)), rest.origin + y * length * 0.5)
				"blob":
					var sphere := SphereMesh.new()
					sphere.radius = 1.0
					sphere.height = 2.0
					sphere.material = material
					mesh_inst.mesh = sphere
					global_xf = Transform3D(Basis.from_scale(piece[3]), rest.origin + piece[2])
				"block":
					var box := BoxMesh.new()
					box.size = piece[3]
					box.material = material
					mesh_inst.mesh = box
					global_xf = Transform3D(Basis.IDENTITY, rest.origin + piece[2])
			mesh_inst.transform = rest.affine_inverse() * global_xf
			attachment.add_child(mesh_inst)
		_garment_meshes[garment_name] = group


## Soaked clothing reads darker; 0 dry to 1 soaked.
func set_wetness(wetness: float) -> void:
	_wetness = clampf(wetness, 0.0, 1.0)
	for material: StandardMaterial3D in _garment_materials.values():
		var dry: Color = material.get_meta(&"dry_color")
		material.albedo_color = dry.darkened(wet_darkening * _wetness)


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
			elif item != null and item.attached_mesh_node_name != &"":
				worn[item.attached_mesh_node_name] = true
	for mesh_name: StringName in _garment_meshes:
		(_garment_meshes[mesh_name] as Node3D).visible = worn.has(mesh_name)


## ADT convention: build the complete graph in code. No editor-authored
## AnimationTree resource exists to drift away from clip names or component code.
func _setup_animation_tree() -> void:
	_resolved_idle = _resolve_clip(IDLE_ALIASES)
	_resolved_walk = _resolve_clip(WALK_ALIASES)
	_resolved_jog = _resolve_clip(JOG_ALIASES)
	_resolved_sprint = _resolve_clip(SPRINT_ALIASES)
	_resolved_crouch_idle = _resolve_clip(CROUCH_IDLE_ALIASES)
	_resolved_crouch_fwd = _resolve_clip(CROUCH_FWD_ALIASES)
	_resolved_jump_start = _resolve_clip(JUMP_START_ALIASES)
	_resolved_jump_loop = _resolve_clip(JUMP_LOOP_ALIASES)
	_resolved_jump_land = _resolve_clip(JUMP_LAND_ALIASES)

	if _resolved_idle == &"":
		_resolved_idle = _first_available_clip()
	if _resolved_idle == &"":
		push_error("HenryUALAnimation: no usable UAL animations found.")
		return
	if _resolved_walk == &"": _resolved_walk = _resolved_idle
	if _resolved_jog == &"": _resolved_jog = _resolved_walk
	if _resolved_sprint == &"": _resolved_sprint = _resolved_jog
	if _resolved_crouch_idle == &"": _resolved_crouch_idle = _resolved_idle
	if _resolved_crouch_fwd == &"": _resolved_crouch_fwd = _resolved_crouch_idle
	if _resolved_jump_start == &"": _resolved_jump_start = _resolved_idle
	if _resolved_jump_loop == &"": _resolved_jump_loop = _resolved_jump_start
	if _resolved_jump_land == &"": _resolved_jump_land = _resolved_idle

	for clip_name: StringName in [
		_resolved_idle, _resolved_walk, _resolved_jog, _resolved_sprint,
		_resolved_crouch_idle, _resolved_crouch_fwd, _resolved_jump_loop,
	]:
		_force_locomotion_loop(clip_name)
	_force_clip_once(_resolved_jump_start)
	_force_clip_once(_resolved_jump_land)

	var locomotion := AnimationNodeBlendSpace1D.new()
	locomotion.min_space = 0.0
	locomotion.max_space = 1.0
	locomotion.value_label = "real speed"
	locomotion.sync = true
	locomotion.add_blend_point(_clip(_resolved_idle), 0.0, -1, &"idle")
	locomotion.add_blend_point(_clip(_resolved_walk), walk_blend_position, -1, &"walk")
	locomotion.add_blend_point(_clip(_resolved_jog), jog_blend_position, -1, &"jog")
	locomotion.add_blend_point(_clip(_resolved_sprint), 1.0, -1, &"sprint")

	var crouch := AnimationNodeBlendSpace1D.new()
	crouch.min_space = 0.0
	crouch.max_space = 1.0
	crouch.value_label = "crouch speed"
	crouch.sync = true
	crouch.add_blend_point(_clip(_resolved_crouch_idle), 0.0, -1, &"idle")
	crouch.add_blend_point(_clip(_resolved_crouch_fwd), 1.0, -1, &"forward")

	var base := AnimationNodeStateMachine.new()
	base.add_node(&"Grounded", locomotion, Vector2(0.0, 0.0))
	base.add_node(&"Crouch", crouch, Vector2(0.0, 180.0))
	base.add_node(&"JumpStart", _clip(_resolved_jump_start), Vector2(260.0, -120.0))
	base.add_node(&"AirLoop", _clip(_resolved_jump_loop), Vector2(520.0, -120.0))
	base.add_node(&"Land", _clip(_resolved_jump_land), Vector2(780.0, 0.0))
	_add_state_transition(base, &"Grounded", &"Crouch", 0.12)
	_add_state_transition(base, &"Crouch", &"Grounded", 0.12)
	_add_state_transition(base, &"Grounded", &"JumpStart", 0.06)
	_add_state_transition(base, &"Crouch", &"JumpStart", 0.06)
	_add_state_transition(base, &"Grounded", &"AirLoop", 0.08)
	_add_state_transition(base, &"Crouch", &"AirLoop", 0.08)
	_add_state_transition(base, &"JumpStart", &"AirLoop", 0.08, true)
	_add_state_transition(base, &"JumpStart", &"Land", 0.05)
	_add_state_transition(base, &"AirLoop", &"Land", 0.08)
	_add_state_transition(base, &"Land", &"Grounded", 0.10, true)
	_add_state_transition(base, &"Land", &"Crouch", 0.10)

	var default_action: StringName = _resolve_action_clip(&"interact")
	_action_node = _clip(default_action if default_action != &"" else _resolved_idle)
	var actions := AnimationNodeOneShot.new()
	actions.fadein_time = 0.08
	actions.fadeout_time = 0.12

	var tree_root := AnimationNodeBlendTree.new()
	tree_root.add_node(&"base", base, Vector2(-360.0, 0.0))
	tree_root.add_node(&"action_clip", _action_node, Vector2(-360.0, 220.0))
	tree_root.add_node(&"actions", actions, Vector2(-80.0, 0.0))
	tree_root.connect_node(&"actions", 0, &"base")
	tree_root.connect_node(&"actions", 1, &"action_clip")
	tree_root.connect_node(&"output", 0, &"actions")

	animation_tree = AnimationTree.new()
	animation_tree.name = "AnimationTree"
	animation_tree.tree_root = tree_root
	add_child(animation_tree)
	animation_tree.anim_player = animation_tree.get_path_to(animation_player)
	animation_tree.active = true
	animation_tree.set("parameters/base/Grounded/blend_position", 0.0)
	animation_tree.set("parameters/base/Crouch/blend_position", 0.0)
	_state_playback = animation_tree.get("parameters/base/playback") as AnimationNodeStateMachinePlayback
	if _state_playback != null:
		_state_playback.start(&"Grounded")


func _add_state_transition(state_machine: AnimationNodeStateMachine, from: StringName, to: StringName, xfade: float, auto_advance: bool = false) -> void:
	var transition := AnimationNodeStateMachineTransition.new()
	transition.xfade_time = xfade
	if auto_advance:
		transition.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
		transition.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_AT_END
	state_machine.add_transition(from, to, transition)


func _force_locomotion_loop(animation_name: StringName) -> void:
	if animation_name == &"":
		return
	var animation: Animation = animation_player.get_animation(animation_name)
	if animation != null:
		animation.loop_mode = Animation.LOOP_LINEAR


func _force_clip_once(animation_name: StringName) -> void:
	if animation_name == &"":
		return
	var animation: Animation = animation_player.get_animation(animation_name)
	if animation != null:
		animation.loop_mode = Animation.LOOP_NONE


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
	if normalized.contains("/"):
		normalized = normalized.get_slice("/", normalized.get_slice_count("/") - 1)
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
