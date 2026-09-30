class_name HingedDoor
extends InteractiveArea

## Physics door backed by Godot's actual rigid-body solver.
##
## Legacy HFN scenes still author:
##   Hinge(Node3D) -> DoorLeaf(MeshInstance3D) -> StaticBody3D
## At runtime that layout is upgraded once to:
##   HingeAnchor(Node3D)
##     -> DoorBody(RigidBody3D) -> DoorLeaf + CollisionShape3D + handles
##     -> HingeJoint3D
##
## Henry never drives a synthetic target angle. His real CharacterBody3D slide
## collision applies an impulse at the actual contact point, so Godot creates
## the torque around the hinge. The joint owns a symmetric angular range, which
## is why the same body push works from both sides of the doorway.

signal door_toggled(open: bool)
signal latch_changed(latched: bool)

const OPEN_KEY: String = "HOUSE_DOOR_OPEN"
const CLOSE_KEY: String = "HOUSE_DOOR_CLOSE"
const WEATHER_GROUP: StringName = &"weather_controller"

@export_group("Door")
## Public API kept for existing scenes/tools. After _ready this points at the
## physical RigidBody3D rather than the legacy fixed Node3D anchor.
@export var door_hinge: Node3D
## Maximum swing in either direction from closed.
@export_range(70.0, 125.0, 1.0) var open_angle_deg: float = 105.0
@export var starts_open: bool = false
@export_range(0.0, 1.0, 0.05) var hand_delay: float = 0.2
## Kept only for old scene compatibility; there is no Tween-driven leaf motion.
@export_range(0.1, 1.5, 0.05) var swing_time: float = 0.45
@export_range(0.0, 1.0, 0.05) var closed_breach_multiplier: float = 0.05
@export var breach: ShelterBreach
@export var opening_size: Vector2 = Vector2(1.5, 2.25)
@export var latch_audio: AudioStreamPlayer3D

@export_group("Rigid hinge")
## A timber exterior door is not weightless, but gameplay must let Henry's walk
## move it without repeated shoves.
@export_range(4.0, 40.0, 0.5) var door_mass_kg: float = 14.0
@export_range(0.0, 10.0, 0.1) var angular_damping: float = 2.2
@export_range(0.1, 8.0, 0.1) var body_push_impulse_scale: float = 2.8
@export_range(1.0, 12.0, 0.25) var max_body_push_impulse: float = 7.0
@export_range(30.0, 120.0, 1.0) var assumed_player_mass_kg: float = 75.0
## Lower relaxation removes energy at the joint stop instead of making the door
## chatter against the frame.
@export_range(0.1, 1.0, 0.05) var limit_relaxation: float = 0.65
@export_range(0.05, 0.8, 0.05) var limit_bias: float = 0.25
@export_range(3.0, 20.0, 0.5) var soft_stop_zone_deg: float = 10.0
@export_range(0.0, 80.0, 0.5) var soft_stop_spring: float = 18.0
@export_range(0.0, 20.0, 0.5) var soft_stop_damping: float = 5.0
@export_range(0.0, 3.0, 0.05) var rest_velocity_deg: float = 0.35

@export_group("Latch / handle")
@export_range(0.2, 8.0, 0.1) var handle_release_impulse: float = 3.0
@export_range(1.0, 10.0, 0.5) var latch_angle_deg: float = 5.0
@export_range(0.5, 6.0, 0.25) var closed_threshold_deg: float = 2.0
@export_range(0.05, 0.35, 0.01) var handle_focus_radius: float = 0.18

@export_group("Wind")
@export var weather_controller: WeatherController
## Maps v^2 pressure into a deliberately weak force at the leaf centre.
@export_range(0.0, 0.10, 0.001) var wind_force_scale: float = 0.018

var current_angle_rad: float = 0.0
var angular_velocity: float = 0.0

var _hinge_anchor: Node3D
var _door_body: RigidBody3D
var _joint: HingeJoint3D
var _leaf: MeshInstance3D
var _latched: bool = true
var _semantic_open: bool = false


func _ready() -> void:
	interaction_type = InteractionType.DOOR
	_latched = not starts_open
	_hinge_anchor = door_hinge
	if _hinge_anchor != null:
		_leaf = _hinge_anchor.get_node_or_null(^"DoorLeaf") as MeshInstance3D
		if _leaf == null:
			_leaf = _hinge_anchor.find_child("DoorLeaf", true, false) as MeshInstance3D
		_upgrade_to_rigid_hinge()
		_ensure_two_sided_handles()
		_add_snow_blockers()
		StylizedEnvironmentMaterial.apply_to_tree(_door_body if _door_body != null else _hinge_anchor)
	if breach != null:
		add_to_group(&"snow_doors")
		breach.boardable = false
		breach.closure = self
		breach.opening_width_m = opening_size.x
		breach.opening_height_m = opening_size.y
		breach.global_transform = global_transform * Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
	super()
	if _door_body != null:
		if starts_open:
			_latched = false
			_set_body_angle(deg_to_rad(minf(open_angle_deg * 0.75, 80.0)))
			_door_body.freeze = false
			_door_body.can_sleep = false
			_door_body.sleeping = false
		else:
			_set_latched_physics(true)
	_update_motion_state()
	_semantic_open = is_open()
	_sync_breach_exposure()
	_refresh_prompt()
	call_deferred("_sync_breach")
	call_deferred("_resolve_weather_controller")


func _upgrade_to_rigid_hinge() -> void:
	if _hinge_anchor == null:
		return
	if _hinge_anchor is RigidBody3D:
		_door_body = _hinge_anchor as RigidBody3D
		door_hinge = _door_body
		_joint = _door_body.get_parent().find_child("DoorHingeJoint", false, false) as HingeJoint3D
		_configure_body()
		return
	if _leaf == null:
		push_error("HingedDoor: DoorLeaf missing under hinge")
		return

	var legacy_body := _leaf.find_child("*", "StaticBody3D", true, false) as StaticBody3D
	var legacy_shape: CollisionShape3D = null
	var legacy_shape_global := Transform3D.IDENTITY
	var shape_resource: Shape3D = null
	if legacy_body != null:
		legacy_shape = legacy_body.find_child("*", "CollisionShape3D", true, false) as CollisionShape3D
		if legacy_shape != null:
			legacy_shape_global = legacy_shape.global_transform
			shape_resource = legacy_shape.shape
			legacy_shape.disabled = true

	_door_body = RigidBody3D.new()
	_door_body.name = "DoorBody"
	_door_body.transform = Transform3D.IDENTITY
	_hinge_anchor.add_child(_door_body)
	_configure_body()

	var leaf_global: Transform3D = _leaf.global_transform
	_leaf.reparent(_door_body, true)
	_leaf.global_transform = leaf_global

	var physical_shape := CollisionShape3D.new()
	physical_shape.name = "DoorCollision"
	if shape_resource != null:
		physical_shape.shape = shape_resource
	else:
		var fallback := BoxShape3D.new()
		fallback.size = _leaf.get_aabb().size
		physical_shape.shape = fallback
		legacy_shape_global = _leaf.global_transform * Transform3D(
			Basis.IDENTITY,
			_leaf.get_aabb().get_center()
		)
	_door_body.add_child(physical_shape)
	physical_shape.global_transform = legacy_shape_global

	if legacy_body != null:
		legacy_body.queue_free()

	_joint = HingeJoint3D.new()
	_joint.name = "DoorHingeJoint"
	_hinge_anchor.add_child(_joint)
	## HingeJoint3D's hinge axis is its local Z axis. Rotate local Z onto the
	## authored vertical Y hinge.
	_joint.rotation.x = -PI * 0.5
	_joint.node_a = _joint.get_path_to(_door_body)
	_joint.set_flag(HingeJoint3D.FLAG_USE_LIMIT, true)
	var limit: float = deg_to_rad(absf(open_angle_deg))
	_joint.set_param(HingeJoint3D.PARAM_LIMIT_LOWER, -limit)
	_joint.set_param(HingeJoint3D.PARAM_LIMIT_UPPER, limit)
	_joint.set_param(HingeJoint3D.PARAM_LIMIT_RELAXATION, limit_relaxation)
	_joint.set_param(HingeJoint3D.PARAM_LIMIT_BIAS, limit_bias)
	_joint.exclude_nodes_from_collision = true

	## Preserve the old public field: callers reading door_hinge.rotation.y now
	## read the actual rigid leaf angle.
	door_hinge = _door_body


func _configure_body() -> void:
	if _door_body == null:
		return
	_door_body.mass = door_mass_kg
	_door_body.gravity_scale = 0.0
	_door_body.angular_damp = angular_damping
	_door_body.linear_damp = 8.0
	_door_body.can_sleep = false
	_door_body.continuous_cd = true
	var material := PhysicsMaterial.new()
	material.friction = 0.35
	material.bounce = 0.0
	_door_body.physics_material_override = material


func is_open() -> bool:
	return absf(current_angle_rad) > deg_to_rad(closed_threshold_deg)


func is_latched() -> bool:
	return _latched


func get_current_angle_deg() -> float:
	return rad_to_deg(current_angle_rad)


func is_swinging() -> bool:
	return (
		not _latched
		and _door_body != null
		and absf(_door_body.angular_velocity.dot(_hinge_axis())) > deg_to_rad(rest_velocity_deg)
	)


func can_interact() -> bool:
	if not super() or _door_body == null:
		return false
	return _latched or absf(current_angle_rad) <= deg_to_rad(latch_angle_deg)


func _on_interaction_performed() -> void:
	if _door_body == null:
		return
	if _latched:
		_set_latched_physics(false)
		_release_handle_away_from_player()
		_refresh_prompt()
		return
	if absf(current_angle_rad) <= deg_to_rad(latch_angle_deg):
		_set_latched_physics(true)


func _get_interaction_text() -> String:
	return "[%s] %s" % [_interact_key_label(), tr(OPEN_KEY if _latched else CLOSE_KEY)]


func _physics_process(_delta: float) -> void:
	if _door_body == null:
		return
	_update_motion_state()
	if not _latched:
		_apply_wind_force()
		_apply_soft_stop_force()
	_sync_breach_exposure()
	_update_semantic_open()


func _update_motion_state() -> void:
	if _door_body == null:
		current_angle_rad = 0.0
		angular_velocity = 0.0
		return
	current_angle_rad = wrapf(_door_body.rotation.y, -PI, PI)
	angular_velocity = _door_body.angular_velocity.dot(_hinge_axis())


## CharacterBody3D does not need to become a physics-driven player. It reports
## the collision; the rigid door receives an impulse at that real contact point.
static func apply_character_collisions(body: CharacterBody3D, attempted_velocity: Vector3) -> void:
	if body == null:
		return
	var seen: Dictionary = {}
	for index: int in range(body.get_slide_collision_count()):
		var collision: KinematicCollision3D = body.get_slide_collision(index)
		if collision == null:
			continue
		var door: HingedDoor = _door_from_collider(collision.get_collider())
		if door == null:
			continue
		var id: int = door.get_instance_id()
		if seen.has(id):
			continue
		seen[id] = true
		door.apply_body_contact(
			body,
			collision.get_position(),
			attempted_velocity,
			collision.get_normal()
		)


static func _door_from_collider(collider: Variant) -> HingedDoor:
	var node := collider as Node
	while node != null:
		if node is HingedDoor:
			return node as HingedDoor
		node = node.get_parent()
	return null


func apply_body_contact(
		_body: CharacterBody3D,
		contact_point: Vector3,
		attempted_velocity: Vector3,
		collision_normal: Vector3
	) -> void:
	if _latched or _door_body == null:
		return
	var normal: Vector3 = collision_normal
	normal.y = 0.0
	if normal.length_squared() < 0.0001:
		return
	normal = normal.normalized()
	var push_dir: Vector3 = -normal

	var player_velocity: Vector3 = attempted_velocity
	player_velocity.y = 0.0
	var body_velocity: Vector3 = _door_body.linear_velocity
	body_velocity.y = 0.0
	var velocity_difference: float = player_velocity.dot(push_dir) - body_velocity.dot(push_dir)
	if velocity_difference <= 0.01:
		return

	var mass_ratio: float = minf(1.0, assumed_player_mass_kg / maxf(_door_body.mass, 0.01))
	var magnitude: float = minf(
		velocity_difference * body_push_impulse_scale * mass_ratio,
		max_body_push_impulse
	)
	if magnitude <= 0.001:
		return
	_door_body.sleeping = false
	_door_body.apply_impulse(push_dir * magnitude, contact_point - _door_body.global_position)


## Test/environment seam. Production wind uses apply_force below.
func apply_external_torque(torque: float) -> void:
	if _latched or _door_body == null:
		return
	_door_body.sleeping = false
	_door_body.apply_torque(_hinge_axis() * torque)


func _release_handle_away_from_player() -> void:
	if _door_body == null or _leaf == null:
		return
	var normal: Vector3 = _door_body.global_basis.z
	normal.y = 0.0
	normal = normal.normalized() if normal.length_squared() > 0.0001 else global_basis.z.normalized()
	var side: float = 1.0
	if is_instance_valid(player_reference):
		side = signf((player_reference.global_position - _door_body.global_position).dot(normal))
		if is_zero_approx(side):
			side = 1.0
	var away: Vector3 = -normal * side
	var bounds: AABB = _leaf.get_aabb()
	var free_edge_local := Vector3(bounds.end.x - 0.04, bounds.get_center().y, bounds.get_center().z)
	var free_edge: Vector3 = _leaf.to_global(free_edge_local)
	_door_body.apply_impulse(away * handle_release_impulse, free_edge - _door_body.global_position)


func _apply_wind_force() -> void:
	if not is_instance_valid(weather_controller) or _door_body == null or _leaf == null:
		return
	var speed: float = maxf(weather_controller.get_wind_speed_mps(), 0.0)
	if speed < 0.1:
		return
	var wind: Vector3 = weather_controller.get_wind_direction()
	wind.y = 0.0
	if wind.length_squared() < 0.0001:
		return
	wind = wind.normalized()
	var normal: Vector3 = _door_body.global_basis.z
	normal.y = 0.0
	if normal.length_squared() < 0.0001:
		return
	normal = normal.normalized()
	var incidence: float = wind.dot(normal)
	if absf(incidence) < 0.01:
		return
	var bounds: AABB = _leaf.get_aabb()
	var centre: Vector3 = _leaf.to_global(bounds.get_center())
	var force: Vector3 = normal * incidence * speed * speed * wind_force_scale
	_door_body.apply_force(force, centre - _door_body.global_position)


func _apply_soft_stop_force() -> void:
	if _door_body == null:
		return
	var limit: float = deg_to_rad(absf(open_angle_deg))
	var zone: float = minf(deg_to_rad(soft_stop_zone_deg), limit)
	var start: float = limit - zone
	var magnitude: float = absf(current_angle_rad)
	if magnitude <= start:
		return
	var outward_sign: float = signf(current_angle_rad)
	if is_zero_approx(outward_sign):
		return
	var outward_speed: float = angular_velocity * outward_sign
	var restoring: float = (magnitude - start) * soft_stop_spring
	if outward_speed > 0.0:
		restoring += outward_speed * soft_stop_damping
	_door_body.apply_torque(_hinge_axis() * (-outward_sign * restoring))


func _hinge_axis() -> Vector3:
	var anchor: Node3D = _hinge_anchor if is_instance_valid(_hinge_anchor) else self
	var axis: Vector3 = anchor.global_basis.y
	return axis.normalized() if axis.length_squared() > 0.0001 else Vector3.UP


func _set_latched_physics(value: bool) -> void:
	if _door_body == null:
		return
	var changed: bool = _latched != value
	_latched = value
	if _latched:
		_door_body.freeze = true
		_door_body.linear_velocity = Vector3.ZERO
		_door_body.angular_velocity = Vector3.ZERO
		_set_body_angle(0.0)
	else:
		_door_body.freeze = false
		_door_body.can_sleep = false
		_door_body.sleeping = false
	_update_motion_state()
	_sync_breach_exposure()
	_update_semantic_open()
	_refresh_prompt()
	if changed:
		_pulse_handles(_latched)
		if is_instance_valid(latch_audio):
			latch_audio.play()
		latch_changed.emit(_latched)


func _set_body_angle(angle: float) -> void:
	if _door_body == null:
		return
	var clamped: float = clampf(angle, -deg_to_rad(absf(open_angle_deg)), deg_to_rad(absf(open_angle_deg)))
	var t: Transform3D = _door_body.transform
	t.basis = Basis(Vector3.UP, clamped)
	_door_body.transform = t
	current_angle_rad = clamped


func _update_semantic_open() -> void:
	var now_open: bool = is_open()
	if now_open == _semantic_open:
		return
	_semantic_open = now_open
	_refresh_prompt()
	door_toggled.emit(_semantic_open)


func _resolve_weather_controller() -> void:
	if is_instance_valid(weather_controller) or not is_inside_tree():
		return
	weather_controller = get_tree().get_first_node_in_group(WEATHER_GROUP) as WeatherController


func set_weather_controller(controller: WeatherController) -> void:
	weather_controller = controller


func _pulse_handles(latched: bool) -> void:
	if _door_body == null or not is_inside_tree():
		return
	for handle_name: StringName in [&"HandleOutside", &"HandleInside"]:
		var handle := _door_body.get_node_or_null(NodePath(handle_name)) as Node3D
		if handle == null:
			continue
		var lever := handle.get_node_or_null(^"Lever") as Node3D
		if lever == null:
			continue
		var side: float = signf(handle.position.z)
		lever.rotation.z = deg_to_rad((10.0 if latched else -12.0) * side)
		var tween := create_tween()
		tween.tween_property(lever, ^"rotation:z", 0.0, maxf(hand_delay, 0.08)) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func get_preferred_handle_position(from: Vector3) -> Vector3:
	if _door_body == null:
		return global_position
	var outside := _door_body.get_node_or_null(^"HandleOutside") as Node3D
	var inside := _door_body.get_node_or_null(^"HandleInside") as Node3D
	if outside == null:
		return inside.global_position if inside != null else global_position
	if inside == null:
		return outside.global_position
	return outside.global_position if from.distance_squared_to(outside.global_position) <= from.distance_squared_to(inside.global_position) else inside.global_position


func get_handle_aim_distance(from: Vector3, direction: Vector3) -> float:
	if _door_body == null or direction.length_squared() < 0.0001:
		return INF
	var ray: Vector3 = direction.normalized()
	var best: float = INF
	for handle_name: StringName in [&"HandleOutside", &"HandleInside"]:
		var handle := _door_body.get_node_or_null(NodePath(handle_name)) as Node3D
		if handle == null:
			continue
		var offset: Vector3 = handle.global_position - from
		var distance_along: float = offset.dot(ray)
		if distance_along < 0.0:
			continue
		var closest: Vector3 = from + ray * distance_along
		if closest.distance_to(handle.global_position) <= handle_focus_radius:
			best = minf(best, distance_along)
	return best


func get_door_save_data() -> Dictionary:
	_update_motion_state()
	return {
		"angle_deg": rad_to_deg(current_angle_rad),
		"angular_velocity_deg": rad_to_deg(angular_velocity),
		"latched": _latched,
	}


func load_door_save_data(data: Dictionary) -> void:
	if _door_body == null:
		return
	var loaded_latched: bool = bool(data.get("latched", true))
	var limit: float = absf(open_angle_deg)
	var loaded_angle: float = clampf(float(data.get("angle_deg", 0.0)), -limit, limit)
	_door_body.freeze = true
	_set_body_angle(deg_to_rad(loaded_angle))
	var loaded_speed: float = clampf(float(data.get("angular_velocity_deg", 0.0)), -90.0, 90.0)
	_door_body.angular_velocity = _hinge_axis() * deg_to_rad(loaded_speed)
	_latched = loaded_latched
	if _latched:
		_set_body_angle(0.0)
		_door_body.angular_velocity = Vector3.ZERO
	else:
		_door_body.freeze = false
		_door_body.can_sleep = false
		_door_body.sleeping = false
	_update_motion_state()
	_semantic_open = is_open()
	_sync_breach_exposure()
	_refresh_prompt()


func _sync_breach() -> void:
	_sync_breach_exposure()
	_refresh_prompt()


func _sync_breach_exposure() -> void:
	if breach != null:
		var aperture: float = 1.0 - clampf(cos(absf(current_angle_rad)), 0.0, 1.0)
		breach.set_exposure_multiplier(lerpf(closed_breach_multiplier, 1.0, aperture))


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
	if not _leaf.has_node(^"SnowLeafCollider"):
		var collider := GPUParticlesCollisionBox3D.new()
		collider.name = "SnowLeafCollider"
		collider.size = _leaf.get_aabb().size
		collider.position = _leaf.get_aabb().get_center()
		_leaf.add_child(collider)
	if has_node(^"SnowFrame0"):
		return
	var frame_sizes: Array[Vector3] = [Vector3(0.12, opening_size.y + 0.12, 0.20), Vector3(0.12, opening_size.y + 0.12, 0.20), Vector3(opening_size.x, 0.12, 0.20)]
	var frame_positions: Array[Vector3] = [Vector3(-(opening_size.x + 0.12) * 0.5, 0.0, 0.0), Vector3((opening_size.x + 0.12) * 0.5, 0.0, 0.0), Vector3(0.0, (opening_size.y + 0.12) * 0.5, 0.0)]
	for index: int in range(3):
		var frame := GPUParticlesCollisionBox3D.new()
		frame.name = "SnowFrame%d" % index
		frame.size = frame_sizes[index]
		frame.position = frame_positions[index]
		add_child(frame)


func _refresh_prompt() -> void:
	set_item_name(tr(OPEN_KEY if _latched else CLOSE_KEY))
	var damaged_and_closed: bool = breach != null and not is_open() and not breach.is_boarded()
	set_description(tr("HOUSE_DOOR_DRAFTING") if damaged_and_closed else "")
	if info_label != null and info_label.visible:
		info_label.text = _get_interaction_text()


func _ensure_two_sided_handles() -> void:
	if _door_body == null or _leaf == null or _leaf.mesh == null:
		return
	var bounds := _leaf.get_aabb()
	var free_edge_global: Vector3 = _leaf.to_global(
		Vector3(bounds.end.x - 0.18, bounds.get_center().y, bounds.get_center().z)
	)
	var free_edge_local: Vector3 = _door_body.to_local(free_edge_global)
	var face_offset: float = maxf(bounds.size.z * 0.5 + 0.025, 0.065)
	var face_axis: Vector3 = _door_body.global_basis.z.normalized()
	if not _door_body.has_node(^"HandleOutside"):
		_make_handle_side(&"HandleOutside", free_edge_local, face_axis * face_offset)
	if not _door_body.has_node(^"HandleInside"):
		_make_handle_side(&"HandleInside", free_edge_local, -face_axis * face_offset)


func _make_handle_side(node_name: StringName, base_local: Vector3, world_face_offset: Vector3) -> void:
	var root := Node3D.new()
	root.name = node_name
	var offset_local: Vector3 = _door_body.global_basis.inverse() * world_face_offset
	root.position = base_local + offset_local
	_door_body.add_child(root)
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
	lever.position = Vector3(-0.11, 0.0, signf(root.position.z) * 0.035)
	var lever_mesh := BoxMesh.new()
	lever_mesh.size = Vector3(0.28, 0.055, 0.055)
	lever.mesh = lever_mesh
	lever.material_override = brass
	root.add_child(lever)


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
