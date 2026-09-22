extends Camera3D
class_name PlayerCamera

@export var player: CharacterBody3D

@export_group("Base Camera")
@export var base_follow_distance: float = 8.0
@export var height: float = 6.0
@export var look_at_height: float = 1.5
@export_range(1.0, 40.0, 0.5) var yaw_response: float = 13.0
@export_range(1.0, 40.0, 0.5) var position_response: float = 16.0
@export_range(1.0, 40.0, 0.5) var collision_in_response: float = 32.0

@export_group("Sprint Feedback")
@export var sprint_zoom_distance: float = 6.4
@export var base_fov: float = 75.0
@export var sprint_fov: float = 94.0
@export_range(1.0, 30.0, 0.5) var fov_response: float = 10.0
@export var sprint_height_offset: float = -0.35
@export var sprint_pitch_deg: float = -3.0
@export var sprint_roll_deg: float = 2.5

@export_group("Orbit")
@export var orbit_angle_max: float = 35.0
@export_range(1.0, 30.0, 0.5) var orbit_response: float = 10.0

@export_group("Turn Feedback")
@export var turn_roll_max_deg: float = 3.0
@export_range(0.0, 0.3, 0.01) var turn_roll_gain: float = 0.08
@export_range(1.0, 30.0, 0.5) var roll_response: float = 12.0

@export_group("Jump / Landing")
@export var jump_hold_drop: float = 0.25
@export_range(1.0, 30.0, 0.5) var jump_response: float = 12.0
@export var land_min_impact_speed: float = 4.0
@export var land_max_drop: float = 0.32
@export_range(1.0, 30.0, 0.5) var land_recovery_response: float = 14.0

@export_group("Collision")
@export var collision_radius: float = 0.28
@export var collision_margin: float = 0.08
@export_flags_3d_physics var collision_mask: int = 0xFFFFFFFF

@export_group("Hand Drawn Outline")
@export var outline_enabled: bool = true
@export var outline_edge_color: Color = Color(0.012, 0.016, 0.022, 1.0)
@export_range(0.0, 1.0, 0.01) var outline_opacity: float = 0.58
@export_range(0.5, 3.0, 0.05) var outline_width_px: float = 1.05
@export_range(0.001, 0.25, 0.001) var outline_depth_threshold: float = 0.018
@export_range(0.005, 0.6, 0.005) var outline_normal_threshold: float = 0.085
@export_range(0.0, 1.0, 0.05) var outline_jitter_px: float = 0.30
@export_range(0.0, 100.0, 0.5) var outline_fade_start: float = 18.0
@export_range(1.0, 200.0, 0.5) var outline_fade_end: float = 60.0

var current_yaw: float = 0.0

var _orbit_offset: float = 0.0
var _current_distance: float = 8.0
var _current_height_offset: float = 0.0
var _current_pitch_deg: float = 0.0
var _current_roll_deg: float = 0.0
var _jump_offset: float = 0.0
var _land_offset: float = 0.0
var _was_on_floor: bool = true
var _previous_vertical_velocity: float = 0.0
var _collision_shape: SphereShape3D
var _outline_effect: HandDrawnOutlineCompositorEffect


func _ready() -> void:
	_setup_hand_drawn_outline()

	if not is_instance_valid(player):
		push_warning("PlayerCamera: player is not assigned.")
		return

	base_follow_distance = maxf(base_follow_distance, 0.5)
	sprint_zoom_distance = maxf(sprint_zoom_distance, 0.5)
	collision_radius = maxf(collision_radius, 0.05)
	base_fov = clampf(base_fov, 30.0, 120.0)
	sprint_fov = clampf(sprint_fov, 30.0, 120.0)

	current_yaw = player.rotation.y
	_current_distance = base_follow_distance
	fov = base_fov
	_was_on_floor = player.is_on_floor()
	_previous_vertical_velocity = player.velocity.y

	_collision_shape = SphereShape3D.new()
	_collision_shape.radius = collision_radius

	# Start at the desired position so the first frame does not spend a second catching up.
	var start_pivot: Vector3 = _camera_pivot()
	global_position = _resolve_collision(start_pivot, _desired_position(start_pivot))


func _physics_process(delta: float) -> void:
	if not is_instance_valid(player):
		return

	var planar_velocity := Vector3(player.velocity.x, 0.0, player.velocity.z)
	var moving: bool = planar_velocity.length_squared() > 0.01
	var sprinting: bool = moving and Input.is_action_pressed("sprint")

	var facing_yaw: float = player.rotation.y
	current_yaw = lerp_angle(current_yaw, facing_yaw, _response(yaw_response, delta))

	var orbit_input: float = 0.0
	if InputMap.has_action("orbit_right"):
		orbit_input += Input.get_action_strength("orbit_right")
	if InputMap.has_action("orbit_left"):
		orbit_input -= Input.get_action_strength("orbit_left")
	var orbit_target: float = deg_to_rad(orbit_angle_max) * orbit_input
	_orbit_offset = lerp_angle(_orbit_offset, orbit_target, _response(orbit_response, delta))

	var target_distance: float = sprint_zoom_distance if sprinting else base_follow_distance
	_current_distance = lerpf(_current_distance, target_distance, _response(position_response, delta))

	var target_height_offset: float = sprint_height_offset if sprinting else 0.0
	_current_height_offset = lerpf(
		_current_height_offset,
		target_height_offset,
		_response(position_response, delta)
	)

	var target_fov: float = sprint_fov if sprinting else base_fov
	fov = lerpf(fov, target_fov, _response(fov_response, delta))

	_update_jump_and_landing(delta)
	_update_orientation_feedback(facing_yaw, planar_velocity, sprinting, delta)

	var pivot: Vector3 = _camera_pivot()
	var desired: Vector3 = _desired_position(pivot)
	var safe_position: Vector3 = _resolve_collision(pivot, desired)

	# Move inward aggressively to prevent wall clipping, restore outward with normal follow response.
	var current_distance_to_pivot: float = global_position.distance_to(pivot)
	var safe_distance_to_pivot: float = safe_position.distance_to(pivot)
	var response_speed: float = collision_in_response if safe_distance_to_pivot < current_distance_to_pivot else position_response
	global_position = global_position.lerp(safe_position, _response(response_speed, delta))

	var look_point: Vector3 = player.global_position + Vector3.UP * look_at_height
	if global_position.distance_squared_to(look_point) > 0.0001:
		look_at(look_point, Vector3.UP)
		rotate_object_local(Vector3.RIGHT, deg_to_rad(_current_pitch_deg))
		rotate_object_local(Vector3.FORWARD, deg_to_rad(_current_roll_deg))


func _camera_pivot() -> Vector3:
	return player.global_position + Vector3.UP * look_at_height


func _desired_position(pivot: Vector3) -> Vector3:
	var yaw: float = current_yaw + _orbit_offset
	var forward: Vector3 = Vector3.FORWARD.rotated(Vector3.UP, yaw)
	var position: Vector3 = player.global_position - forward * _current_distance
	position.y += height + _current_height_offset + _jump_offset + _land_offset
	return position


func _resolve_collision(pivot: Vector3, desired: Vector3) -> Vector3:
	if _collision_shape == null:
		return desired

	var motion: Vector3 = desired - pivot
	var motion_length: float = motion.length()
	if motion_length <= 0.001:
		return desired

	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _collision_shape
	query.transform = Transform3D(Basis.IDENTITY, pivot)
	query.motion = motion
	query.collision_mask = collision_mask
	query.collide_with_areas = false
	query.collide_with_bodies = true
	query.exclude = [player.get_rid()]

	var cast: PackedFloat32Array = get_world_3d().direct_space_state.cast_motion(query)
	if cast.size() < 1:
		return desired

	var safe_fraction: float = cast[0]
	if safe_fraction >= 1.0:
		return desired

	var margin_fraction: float = collision_margin / motion_length
	safe_fraction = maxf(0.0, safe_fraction - margin_fraction)
	return pivot + motion * safe_fraction


func _update_jump_and_landing(delta: float) -> void:
	var hold_active: bool = false
	var hold_value: Variant = player.get("cam_jump_hold_active")
	if hold_value != null:
		hold_active = bool(hold_value)

	var jump_target: float = -jump_hold_drop if hold_active else 0.0
	_jump_offset = lerpf(_jump_offset, jump_target, _response(jump_response, delta))

	var on_floor: bool = player.is_on_floor()
	if not _was_on_floor and on_floor and _previous_vertical_velocity <= -land_min_impact_speed:
		var impact: float = absf(_previous_vertical_velocity)
		_land_offset = -minf(land_max_drop, impact * 0.035)

	_land_offset = lerpf(_land_offset, 0.0, _response(land_recovery_response, delta))
	_was_on_floor = on_floor
	_previous_vertical_velocity = player.velocity.y


func _update_orientation_feedback(
	facing_yaw: float,
	planar_velocity: Vector3,
	sprinting: bool,
	delta: float
) -> void:
	var target_pitch: float = sprint_pitch_deg if sprinting else 0.0
	_current_pitch_deg = lerpf(_current_pitch_deg, target_pitch, _response(roll_response, delta))

	var yaw_error_deg: float = rad_to_deg(wrapf(facing_yaw - current_yaw, -PI, PI))
	var target_roll: float = clampf(
		yaw_error_deg * turn_roll_gain,
		-turn_roll_max_deg,
		turn_roll_max_deg
	)

	if sprinting and planar_velocity.length_squared() > 0.001:
		var movement_dir: Vector3 = planar_velocity.normalized()
		var side_amount: float = clampf(player.global_transform.basis.x.dot(movement_dir), -1.0, 1.0)
		target_roll += -side_amount * sprint_roll_deg

	_current_roll_deg = lerpf(_current_roll_deg, target_roll, _response(roll_response, delta))


func _response(speed: float, delta: float) -> float:
	return 1.0 - exp(-maxf(speed, 0.001) * delta)



func _setup_hand_drawn_outline() -> void:
	if not outline_enabled:
		compositor = null
		_outline_effect = null
		return

	_outline_effect = HandDrawnOutlineCompositorEffect.new()
	_outline_effect.edge_color = outline_edge_color
	_outline_effect.edge_opacity = outline_opacity
	_outline_effect.edge_width_px = outline_width_px
	_outline_effect.depth_threshold = outline_depth_threshold
	_outline_effect.normal_threshold = outline_normal_threshold
	_outline_effect.jitter_amount_px = outline_jitter_px
	_outline_effect.distance_fade_start = outline_fade_start
	_outline_effect.distance_fade_end = maxf(outline_fade_end, outline_fade_start + 0.5)

	var outline_compositor := Compositor.new()
	var effects: Array[CompositorEffect] = []
	effects.append(_outline_effect)
	outline_compositor.compositor_effects = effects
	compositor = outline_compositor
