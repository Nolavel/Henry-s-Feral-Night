class_name HingedDoor
extends InteractiveArea

## Continuous kinematic door model.
##
## The leaf keeps its authored StaticBody3D under the same hinge as the mesh, so
## Henry always collides with the actual visible leaf. The door itself integrates
## one angular degree of freedom: real CharacterBody3D slide contacts, weather
## pressure, hinge damping and the soft open stop all feed torque into the same
## angular velocity. F only operates the latch; it is not an open/close animation.
##
## This is deliberately not a RigidBody3D/HingeJoint3D. A deterministic scalar
## hinge stays stable in headless tests, survives streaming/save restoration, and
## keeps ShelterBreach/snow projection driven by the exact rendered transform.

signal door_toggled(open: bool)
signal latch_changed(latched: bool)

const OPEN_KEY: String = "HOUSE_DOOR_OPEN"
const CLOSE_KEY: String = "HOUSE_DOOR_CLOSE"
const WEATHER_GROUP: StringName = &"weather_controller"

@export_group("Door")
@export var door_hinge: Node3D
## Signed authored end stop. Positive is the current shelter-door swing direction;
## a negative value supports a mirrored door without changing the dynamics code.
@export_range(-140.0, 140.0, 1.0) var open_angle_deg: float = 105.0
@export var starts_open: bool = false
## Kept for scene compatibility. It now controls the little lever feedback only.
@export_range(0.0, 1.0, 0.05) var hand_delay: float = 0.2
## Kept for older authored scenes; the leaf no longer uses a Tween.
@export_range(0.1, 1.5, 0.05) var swing_time: float = 0.45
## A shut damaged door still leaks around its frame, but much less than an open
## doorway. One multiplier drives both ThermalZone exposure and BreachDraft VFX.
@export_range(0.0, 1.0, 0.05) var closed_breach_multiplier: float = 0.05
@export var breach: ShelterBreach
@export var opening_size: Vector2 = Vector2(1.5, 2.25)
@export var latch_audio: AudioStreamPlayer3D

@export_group("Hinge dynamics")
## Effective rotational inertia, not kilograms. Higher values make body pushes
## take longer to build angular speed.
@export_range(0.5, 12.0, 0.1) var angular_inertia: float = 1.8
## Viscous hinge friction in torque per rad/s.
@export_range(0.0, 30.0, 0.1) var hinge_damping: float = 5.0
## Converts Henry's real closing speed at a collision into force on the leaf.
@export_range(0.0, 30.0, 0.1) var body_push_force_scale: float = 24.0
## Prevents a moving kinematic collider from sweeping farther than Henry's capsule
## can reasonably resolve in one physics tick.
@export_range(20.0, 180.0, 1.0) var max_angular_speed_deg: float = 90.0
@export_range(2.0, 25.0, 0.5) var soft_stop_zone_deg: float = 10.0
@export_range(0.0, 100.0, 0.5) var soft_stop_spring: float = 34.0
@export_range(0.0, 30.0, 0.5) var soft_stop_damping: float = 8.0
@export_range(0.0, 0.5, 0.01) var stop_restitution: float = 0.08
@export_range(0.0, 3.0, 0.05) var rest_velocity_deg: float = 0.25

@export_group("Latch / handle")
@export_range(5.0, 20.0, 0.5) var handle_crack_deg: float = 11.0
@export_range(1.0, 10.0, 0.5) var latch_angle_deg: float = 5.0
@export_range(0.5, 6.0, 0.25) var closed_threshold_deg: float = 2.0
@export_range(0.05, 0.35, 0.01) var handle_focus_radius: float = 0.18

@export_group("Wind")
@export var weather_controller: WeatherController
## Scales v^2 pressure into a deliberately weak atmospheric torque.
@export_range(0.0, 0.03, 0.0005) var wind_torque_scale: float = 0.004

var current_angle_rad: float = 0.0
var angular_velocity: float = 0.0

var _leaf: MeshInstance3D
var _latched: bool = true
var _semantic_open: bool = false
var _pending_torque: float = 0.0


func _ready() -> void:
	interaction_type = InteractionType.DOOR
	_latched = not starts_open
	current_angle_rad = deg_to_rad(open_angle_deg) if starts_open else 0.0
	angular_velocity = 0.0
	if door_hinge != null:
		_ensure_two_sided_handles()
		_leaf = door_hinge.get_node_or_null(^"DoorLeaf") as MeshInstance3D
		if _leaf == null:
			_leaf = door_hinge.find_child("DoorLeaf", true, false) as MeshInstance3D
		_apply_hinge_angle()
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
	_semantic_open = is_open()
	_sync_breach_exposure()
	_refresh_prompt()
	call_deferred("_sync_breach")
	call_deferred("_resolve_weather_controller")


func is_open() -> bool:
	return absf(current_angle_rad) > deg_to_rad(closed_threshold_deg)


func is_latched() -> bool:
	return _latched


func get_current_angle_deg() -> float:
	return rad_to_deg(current_angle_rad)


func is_swinging() -> bool:
	return (
		not _latched
		and (
			absf(angular_velocity) > deg_to_rad(rest_velocity_deg)
			or absf(_pending_torque) > 0.001
		)
	)


func can_interact() -> bool:
	if not super() or door_hinge == null:
		return false
	## F belongs to the latch. Once the leaf is freely open, Henry controls it
	## with his body rather than repeatedly toggling an animation.
	return _latched or absf(current_angle_rad) <= deg_to_rad(latch_angle_deg)


func _on_interaction_performed() -> void:
	if _latched:
		_set_latched(false)
		## An ideal viscous hinge travels v0 / (damping / inertia) before resting.
		## Choose v0 from the authored crack angle so F naturally settles around
		## 8–15 degrees without a hidden Tween target.
		var damping_rate: float = hinge_damping / maxf(angular_inertia, 0.001)
		var crack_speed: float = deg_to_rad(handle_crack_deg) * maxf(damping_rate, 0.5)
		var sign_open: float = _open_sign()
		var along_open: float = angular_velocity * sign_open
		angular_velocity = maxf(along_open, crack_speed) * sign_open
		_refresh_prompt()
		return
	if absf(current_angle_rad) <= deg_to_rad(latch_angle_deg):
		_set_latched(true)


func _get_interaction_text() -> String:
	return "[%s] %s" % [_interact_key_label(), tr(OPEN_KEY if _latched else CLOSE_KEY)]


func _physics_process(delta: float) -> void:
	if door_hinge == null or delta <= 0.0:
		return
	if _latched:
		current_angle_rad = 0.0
		angular_velocity = 0.0
		_pending_torque = 0.0
		_apply_hinge_angle()
		return

	var torque: float = _pending_torque
	_pending_torque = 0.0
	torque += _wind_torque()
	torque += _soft_stop_torque()
	torque -= angular_velocity * hinge_damping

	angular_velocity += (torque / maxf(angular_inertia, 0.001)) * delta
	var max_speed: float = deg_to_rad(max_angular_speed_deg)
	angular_velocity = clampf(angular_velocity, -max_speed, max_speed)
	current_angle_rad += angular_velocity * delta
	_enforce_angle_limits()

	if absf(angular_velocity) < deg_to_rad(rest_velocity_deg) and absf(torque) < 0.01:
		angular_velocity = 0.0

	_apply_hinge_angle()
	_sync_breach_exposure()
	_update_semantic_open()


## Production contact seam. Player.gd calls this only after move_and_slide(), so
## merely holding W near the door cannot create torque without a real collision.
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


## Converts one actual CharacterBody contact into torque around the authored hinge.
func apply_body_contact(
		_body: CharacterBody3D,
		contact_point: Vector3,
		attempted_velocity: Vector3,
		collision_normal: Vector3
	) -> void:
	if _latched or door_hinge == null:
		return
	var normal: Vector3 = collision_normal
	normal.y = 0.0
	if normal.length_squared() < 0.0001:
		return
	normal = normal.normalized()
	var velocity_flat: Vector3 = attempted_velocity
	velocity_flat.y = 0.0
	var closing_speed: float = maxf(0.0, -velocity_flat.dot(normal))
	if closing_speed <= 0.01:
		return

	var force: Vector3 = -normal * closing_speed * body_push_force_scale
	var lever: Vector3 = contact_point - door_hinge.global_position
	lever.y = 0.0
	var axis: Vector3 = door_hinge.global_basis.y.normalized()
	_pending_torque += lever.cross(force).dot(axis)


## Deterministic seam for tests and authored environment impulses.
func apply_external_torque(torque: float) -> void:
	if not _latched:
		_pending_torque += torque


func _wind_torque() -> float:
	if _latched or not is_instance_valid(weather_controller) or door_hinge == null or _leaf == null:
		return 0.0
	var speed: float = maxf(weather_controller.get_wind_speed_mps(), 0.0)
	if speed < 0.1:
		return 0.0
	var wind: Vector3 = weather_controller.get_wind_direction()
	wind.y = 0.0
	if wind.length_squared() < 0.0001:
		return 0.0
	wind = wind.normalized()

	var normal: Vector3 = door_hinge.global_basis.z
	normal.y = 0.0
	if normal.length_squared() < 0.0001:
		return 0.0
	normal = normal.normalized()
	var incidence: float = wind.dot(normal)
	if absf(incidence) < 0.01:
		return 0.0

	var bounds: AABB = _leaf.get_aabb()
	var centre: Vector3 = _leaf.to_global(bounds.get_center())
	var lever: Vector3 = centre - door_hinge.global_position
	lever.y = 0.0
	var force: Vector3 = normal * incidence * speed * speed * wind_torque_scale
	return lever.cross(force).dot(door_hinge.global_basis.y.normalized())


func _soft_stop_torque() -> float:
	var maximum: float = absf(deg_to_rad(open_angle_deg))
	if maximum <= 0.0001:
		return 0.0
	var sign_open: float = _open_sign()
	var travel: float = current_angle_rad * sign_open
	var zone: float = minf(deg_to_rad(soft_stop_zone_deg), maximum)
	var start: float = maximum - zone
	if travel <= start:
		return 0.0
	var compression: float = travel - start
	var velocity_along: float = angular_velocity * sign_open
	var oppose: float = compression * soft_stop_spring
	if velocity_along > 0.0:
		oppose += velocity_along * soft_stop_damping
	return -oppose * sign_open


func _enforce_angle_limits() -> void:
	var sign_open: float = _open_sign()
	var maximum: float = absf(deg_to_rad(open_angle_deg))
	var travel: float = current_angle_rad * sign_open
	var velocity_along: float = angular_velocity * sign_open
	if travel < 0.0:
		current_angle_rad = 0.0
		if velocity_along < 0.0:
			velocity_along = -velocity_along * stop_restitution
			angular_velocity = velocity_along * sign_open
	elif travel > maximum:
		current_angle_rad = maximum * sign_open
		if velocity_along > 0.0:
			velocity_along = -velocity_along * stop_restitution
			angular_velocity = velocity_along * sign_open


func _open_sign() -> float:
	var value: float = signf(open_angle_deg)
	return value if not is_zero_approx(value) else 1.0


func _apply_hinge_angle() -> void:
	if door_hinge == null:
		return
	door_hinge.rotation.y = current_angle_rad
	if door_hinge.is_inside_tree():
		door_hinge.force_update_transform()
	_sync_leaf_body_velocity()


## StaticBody3D stays the collision authority. These velocities tell CharacterBody
## contacts how the manually rotated surface itself is moving around the hinge.
func _sync_leaf_body_velocity() -> void:
	if _leaf == null or door_hinge == null:
		return
	var axis: Vector3 = door_hinge.global_basis.y.normalized()
	var omega: Vector3 = axis * angular_velocity
	for child: Node in _leaf.find_children("*", "StaticBody3D", true, false):
		var body := child as StaticBody3D
		if body == null:
			continue
		body.constant_angular_velocity = omega
		body.constant_linear_velocity = omega.cross(body.global_position - door_hinge.global_position)


func _set_latched(value: bool) -> void:
	if _latched == value:
		return
	_latched = value
	if _latched:
		current_angle_rad = 0.0
		angular_velocity = 0.0
		_pending_torque = 0.0
		_apply_hinge_angle()
		_sync_breach_exposure()
	_update_semantic_open()
	_refresh_prompt()
	_pulse_handles(_latched)
	if is_instance_valid(latch_audio):
		latch_audio.play()
	latch_changed.emit(_latched)


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


## Small lever snap is the visual latch feedback. Audio is optional and can be
## authored later without coupling the mechanical model to a sound asset.
func _pulse_handles(latched: bool) -> void:
	if door_hinge == null or not is_inside_tree():
		return
	for handle_name: StringName in [&"HandleOutside", &"HandleInside"]:
		var handle := door_hinge.get_node_or_null(NodePath(handle_name)) as Node3D
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
	if door_hinge == null:
		return global_position
	var outside := door_hinge.get_node_or_null(^"HandleOutside") as Node3D
	var inside := door_hinge.get_node_or_null(^"HandleInside") as Node3D
	if outside == null:
		return inside.global_position if inside != null else global_position
	if inside == null:
		return outside.global_position
	return outside.global_position if from.distance_squared_to(outside.global_position) <= from.distance_squared_to(inside.global_position) else inside.global_position


## Ray/sphere test around the actual near-side handle. InteractComponent uses this
## instead of accepting a ray anywhere on the large door interaction Area.
func get_handle_aim_distance(from: Vector3, direction: Vector3) -> float:
	if door_hinge == null or direction.length_squared() < 0.0001:
		return INF
	var ray: Vector3 = direction.normalized()
	var best: float = INF
	for handle_name: StringName in [&"HandleOutside", &"HandleInside"]:
		var handle := door_hinge.get_node_or_null(NodePath(handle_name)) as Node3D
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


## Save seam: shelter persistence can keep a partially open, unlatched door without
## serializing physics nodes. Loaded angular speed is clamped to avoid a save
## spawning a violently moving leaf.
func get_door_save_data() -> Dictionary:
	return {
		"angle_deg": rad_to_deg(current_angle_rad),
		"angular_velocity_deg": rad_to_deg(angular_velocity),
		"latched": _latched,
	}


func load_door_save_data(data: Dictionary) -> void:
	_latched = bool(data.get("latched", true))
	var sign_open: float = _open_sign()
	var maximum: float = absf(open_angle_deg)
	var loaded_angle: float = float(data.get("angle_deg", 0.0))
	var travel: float = clampf(loaded_angle * sign_open, 0.0, maximum)
	current_angle_rad = deg_to_rad(travel * sign_open)
	var loaded_speed: float = float(data.get("angular_velocity_deg", 0.0))
	var safe_speed: float = max_angular_speed_deg * 0.35
	angular_velocity = deg_to_rad(clampf(loaded_speed, -safe_speed, safe_speed))
	if _latched:
		current_angle_rad = 0.0
		angular_velocity = 0.0
	_pending_torque = 0.0
	_apply_hinge_angle()
	_semantic_open = is_open()
	_sync_breach_exposure()
	_refresh_prompt()


func _sync_breach() -> void:
	_sync_breach_exposure()
	_refresh_prompt()


func _sync_breach_exposure() -> void:
	if breach != null and door_hinge != null:
		var aperture: float = 1.0 - clampf(cos(current_angle_rad), 0.0, 1.0)
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
	if door_hinge == null:
		return
	var leaf := door_hinge.get_node_or_null(^"DoorLeaf") as MeshInstance3D
	if leaf == null or leaf.mesh == null:
		return
	var bounds := leaf.get_aabb()
	var free_edge_x: float = leaf.position.x + bounds.position.x + bounds.size.x - 0.18
	var face_z: float = maxf(bounds.size.z * 0.5 + 0.025, 0.065)
	if not door_hinge.has_node(^"HandleOutside"):
		_make_handle_side(&"HandleOutside", free_edge_x, face_z)
	if not door_hinge.has_node(^"HandleInside"):
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
