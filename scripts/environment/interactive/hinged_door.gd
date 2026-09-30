class_name HingedDoor
extends InteractiveArea

## A full-size exterior door. The leaf and its StaticBody are children of the
## same hinge, so the visible swing and the passage collision cannot disagree.

signal door_toggled(open: bool)

const OPEN_KEY: String = "HOUSE_DOOR_OPEN"
const CLOSE_KEY: String = "HOUSE_DOOR_CLOSE"

@export_group("Door")
@export var door_hinge: Node3D
@export var open_angle_deg: float = 105.0
@export_range(0.0, 1.0, 0.05) var hand_delay: float = 0.2
@export_range(0.1, 1.5, 0.05) var swing_time: float = 0.45
@export var starts_open: bool = false
## A shut damaged door still leaks around its frame, but much less than an open
## doorway. One multiplier drives both ThermalZone exposure and BreachDraft VFX.
@export_range(0.0, 1.0, 0.05) var closed_breach_multiplier: float = 0.05
## The doorway remains operable; its frame leaks gently when the leaf is closed.
@export var breach: ShelterBreach
@export var opening_size: Vector2 = Vector2(1.5, 2.25)
var _leaf: MeshInstance3D

var _open: bool = false
var _tween: Tween


func _ready() -> void:
	interaction_type = InteractionType.DOOR
	_open = starts_open
	if door_hinge != null:
		door_hinge.rotation.y = deg_to_rad(open_angle_deg) if _open else 0.0
		_ensure_two_sided_handles()
	if door_hinge != null:
		_leaf = door_hinge.get_node_or_null(^"DoorLeaf") as MeshInstance3D
		_add_snow_blockers()
		StylizedEnvironmentMaterial.apply_to_tree(door_hinge)
	if breach != null:
		add_to_group(&"snow_doors")
		breach.boardable = false
		breach.closure = self
		breach.opening_width_m = opening_size.x
		breach.opening_height_m = opening_size.y
		breach.global_transform = global_transform * Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
	super()
	_sync_breach_exposure()
	_refresh_prompt()
	call_deferred("_sync_breach")


func is_open() -> bool:
	return _open


func is_swinging() -> bool:
	return _tween != null and _tween.is_running()


func can_interact() -> bool:
	return (
		super()
		and door_hinge != null
		and not is_swinging()
	)


func _on_interaction_performed() -> void:
	_open = not _open
	var target: float = deg_to_rad(open_angle_deg) if _open else 0.0
	_tween = create_tween()
	_tween.tween_interval(hand_delay)
	_tween.tween_property(door_hinge, ^"rotation:y", target, swing_time) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT if _open else Tween.EASE_IN_OUT)
	_sync_breach_exposure()
	_refresh_prompt()
	door_toggled.emit(_open)


func _get_interaction_text() -> String:
	return "[%s] %s" % [_interact_key_label(), tr(CLOSE_KEY if _open else OPEN_KEY)]


func _process(_delta: float) -> void:
	if is_swinging():
		_sync_breach_exposure()


func _sync_breach() -> void:
	_sync_breach_exposure()
	_refresh_prompt()


func _sync_breach_exposure() -> void:
	if breach != null and door_hinge != null:
		var aperture: float = 1.0 - clampf(cos(door_hinge.rotation.y), 0.0, 1.0)
		breach.set_exposure_multiplier(lerpf(closed_breach_multiplier, 1.0, aperture))


## Four non-overlapping strips subtract the projected leaf from the actual doorway.
func get_draft_regions() -> Array[AABB]:
	var result: Array[AABB] = []
	if breach == null or _leaf == null:
		return result
	var opening := AABB(Vector3(-opening_size.x * 0.5, -opening_size.y * 0.5, -0.075), Vector3(opening_size.x, opening_size.y, 0.01))
	var leaf_bounds: AABB = (breach.global_transform.affine_inverse() * _leaf.global_transform) * _leaf.get_aabb()
	var left: float = clampf(leaf_bounds.position.x, opening.position.x, opening.end.x)
	var right: float = clampf(leaf_bounds.end.x, left, opening.end.x)
	var bottom: float = clampf(leaf_bounds.position.y, opening.position.y, opening.end.y)
	var top: float = clampf(leaf_bounds.end.y, bottom, opening.end.y)
	_append_region(result, Vector3(opening.position.x, opening.position.y, opening.position.z), Vector3(left - opening.position.x, opening.size.y, opening.size.z))
	_append_region(result, Vector3(right, opening.position.y, opening.position.z), Vector3(opening.end.x - right, opening.size.y, opening.size.z))
	_append_region(result, Vector3(left, opening.position.y, opening.position.z), Vector3(right - left, bottom - opening.position.y, opening.size.z))
	_append_region(result, Vector3(left, top, opening.position.z), Vector3(right - left, opening.end.y - top, opening.size.z))
	return result


func _append_region(regions: Array[AABB], at: Vector3, size: Vector3) -> void:
	if size.x > 0.006 and size.y > 0.006:
		regions.append(AABB(at + Vector3(0.003, 0.003, 0.0), size - Vector3(0.006, 0.006, 0.0)))


func _add_snow_blockers() -> void:
	if _leaf == null or breach == null:
		return
	var collider := GPUParticlesCollisionBox3D.new()
	collider.name = "SnowLeafCollider"
	collider.size = _leaf.get_aabb().size
	collider.position = _leaf.get_aabb().get_center()
	_leaf.add_child(collider)
	var frame_sizes: Array[Vector3] = [Vector3(0.12, opening_size.y + 0.12, 0.20), Vector3(0.12, opening_size.y + 0.12, 0.20), Vector3(opening_size.x, 0.12, 0.20)]
	var frame_positions: Array[Vector3] = [Vector3(-(opening_size.x + 0.12) * 0.5, 0.0, 0.0), Vector3((opening_size.x + 0.12) * 0.5, 0.0, 0.0), Vector3(0.0, (opening_size.y + 0.12) * 0.5, 0.0)]
	for index: int in range(3):
		var frame := GPUParticlesCollisionBox3D.new()
		frame.name = "SnowFrame%d" % index
		frame.size = frame_sizes[index]
		frame.position = frame_positions[index]
		add_child(frame)


func _refresh_prompt() -> void:
	set_item_name(tr(CLOSE_KEY if _open else OPEN_KEY))
	var damaged_and_closed: bool = breach != null and not _open and not breach.is_boarded()
	set_description(tr("HOUSE_DOOR_DRAFTING") if damaged_and_closed else "")
	if info_label != null and info_label.visible:
		info_label.text = _get_interaction_text()


func _ensure_two_sided_handles() -> void:
	if door_hinge == null or door_hinge.has_node(^"HandleOutside"):
		return
	var leaf := door_hinge.get_node_or_null(^"DoorLeaf") as MeshInstance3D
	if leaf == null or leaf.mesh == null:
		return
	var bounds := leaf.get_aabb()
	var free_edge_x: float = leaf.position.x + bounds.position.x + bounds.size.x - 0.18
	var face_z: float = maxf(bounds.size.z * 0.5 + 0.025, 0.065)
	_make_handle_side(&"HandleOutside", free_edge_x, face_z)
	_make_handle_side(&"HandleInside", free_edge_x, -face_z)


func _make_handle_side(node_name: StringName, x: float, z: float) -> void:
	var root := Node3D.new()
	root.name = node_name
	root.position = Vector3(x, 0.0, z)
	door_hinge.add_child(root)
	var brass := StylizedEnvironmentMaterial.make(
		Color(0.40, 0.31, 0.16),
		0.38,
		false,
		false,
		0.65
	)
	var plate := MeshInstance3D.new()
	plate.name = "Plate"
	var plate_mesh := BoxMesh.new()
	plate_mesh.size = Vector3(0.16, 0.28, 0.025)
	plate.mesh = plate_mesh
	plate.material_override = brass
	root.add_child(plate)
	var lever := MeshInstance3D.new()
	lever.name = "Lever"
	lever.position = Vector3(-0.11, 0.0, signf(z) * 0.035)
	var lever_mesh := BoxMesh.new()
	lever_mesh.size = Vector3(0.28, 0.055, 0.055)
	lever.mesh = lever_mesh
	lever.material_override = brass
	root.add_child(lever)


## Both snowfall layers and aperture drafts share the current leaf/frame transforms.
func apply_snow_barrier(material: ShaderMaterial) -> void:
	material.set_shader_parameter("snow_door_enabled", is_instance_valid(_leaf))
	if not is_instance_valid(_leaf):
		return
	var bounds: AABB = _leaf.get_aabb()
	material.set_shader_parameter("snow_leaf_inverse", _leaf.global_transform.affine_inverse())
	material.set_shader_parameter("snow_leaf_min", bounds.position)
	material.set_shader_parameter("snow_leaf_max", bounds.end)
	material.set_shader_parameter("snow_frame_inverse", global_transform.affine_inverse())
	material.set_shader_parameter("snow_opening_size", opening_size)
