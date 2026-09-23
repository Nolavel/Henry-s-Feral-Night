class_name TpsCamera
extends Camera3D

## Third-person mouse-look camera ported from ADT's on-foot camera, minus its
## view toggle, lock-on and aim. Distance adapts to the space around Henry.

## ADT BodyMetrics ratios of body height.
const EYE_RATIO: float = 0.94
const SHOULDER_RATIO: float = 0.82

@export var player: CharacterBody3D

@export_group("Look")
@export var look_sensitivity_x: float = 0.65
@export var look_sensitivity_y: float = 0.65
@export var invert_look_x: bool = false
@export var invert_look_y: bool = false
@export var start_pitch_deg: float = -10.0
@export var pitch_min_deg: float = -70.0
@export var pitch_max_deg: float = 60.0
## Vertical look feels heavier than horizontal, as in ADT.
@export_range(0.1, 1.0, 0.05) var pitch_sensitivity_ratio: float = 0.7

@export_group("Body")
## Character height; pivot and probe heights are ADT's body ratios of it.
@export var body_height: float = 1.8
## How far the player origin sits above the feet (capsule centre).
@export var origin_above_feet: float = 1.0

@export_group("Shoulder")
@export var shoulder_offset: float = 0.85
## Share of the shoulder offset done as a lens shift; the rest moves the camera.
@export_range(0.0, 1.0, 0.05) var shoulder_frustum_ratio: float = 0.6
@export_range(1.0, 30.0, 0.5) var lens_offset_smoothing: float = 8.0

@export_group("Lean")
@export var lean_camera_offset: float = 0.45
@export_range(0.5, 20.0, 0.5) var lean_rate: float = 5.0
@export_range(0.5, 20.0, 0.5) var lean_return_rate: float = 8.0

@export_group("Breathing")
@export var breathing_amplitude_deg: float = 0.4
@export var breathing_speed: float = 0.6

@export_group("Follow")
@export_range(1.0, 40.0, 0.5) var follow_speed: float = 16.0
@export_range(1.0, 60.0, 0.5) var look_smoothing: float = 30.0
@export var lead_distance: float = 0.6
@export_range(0.5, 20.0, 0.5) var lead_smoothing: float = 2.5
@export var sprint_pullback: float = 0.4
@export_range(0.5, 20.0, 0.5) var pullback_smoothing: float = 3.0

@export_group("Adaptive distance")
## Boom length in the tightest space and in the open.
@export var near_distance: float = 1.2
@export var far_distance: float = 3.0
## Rods cast around Henry's head to judge how open the space is.
@export_range(4, 16) var probe_count: int = 8
@export var probe_length: float = 4.0
## A ceiling closer than this above the eyes pulls the camera in.
@export var ceiling_clearance: float = 3.0
## Above 1 favours closing in: half-open space sits nearer the near distance.
@export_range(0.5, 4.0, 0.1) var openness_exponent: float = 2.0
@export_range(1.0, 60.0, 1.0) var probe_rate_hz: float = 10.0
@export_range(0.1, 20.0, 0.1) var close_in_rate: float = 4.0
@export_range(0.1, 20.0, 0.1) var open_out_rate: float = 1.2

@export_group("Collision")
@export var collision_radius: float = 0.3
@export var collision_min_distance: float = 0.7
@export var collision_surface_margin: float = 0.25
@export_range(0.1, 20.0, 0.1) var collision_restore_rate: float = 2.5
@export_flags_3d_physics var collision_mask: int = 0xFFFFFFFF

## 0..1 unease that widens the breathing sway; free for survival state to drive.
var tension: float = 0.0

var _yaw: float = 0.0
var _pitch_deg: float = -12.0
var _current_yaw: float = 0.0
var _current_pitch_deg: float = -12.0
var _current_pos: Vector3 = Vector3.ZERO
var _lead: Vector3 = Vector3.ZERO
var _pullback: float = 0.0
var _openness: float = 1.0
var _boom: float = 3.0
var _collision_distance: float = -1.0
var _probe_timer: float = 0.0
var _has_position: bool = false
var _lean: float = 0.0
var _noise := FastNoiseLite.new()
var _noise_time: float = 0.0
var _shoulder := TpsShoulderState.new()
var _collision_shape := SphereShape3D.new()
var _collision_query := PhysicsShapeQueryParameters3D.new()


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_noise.frequency = breathing_speed
	_shoulder.right_offset = shoulder_offset
	_shoulder.left_offset = -shoulder_offset
	_pitch_deg = start_pitch_deg
	_current_pitch_deg = start_pitch_deg
	_boom = far_distance
	if is_instance_valid(player):
		_yaw = player.global_rotation.y
		_current_yaw = _yaw
	_set_look_capture(true)
	make_current()


func _exit_tree() -> void:
	_set_look_capture(false)


func _physics_process(delta: float) -> void:
	if not is_instance_valid(player):
		return
	_apply_look_input()
	_apply_lean_and_shoulder_input(delta)
	_probe_timer -= delta
	if _probe_timer <= 0.0:
		_probe_timer = 1.0 / probe_rate_hz
		_openness = measure_openness()
	var wanted: float = get_target_distance()
	var rate: float = close_in_rate if wanted < _boom else open_out_rate
	_boom = lerpf(_boom, wanted, _damp(rate, delta))
	_update_transform(delta)


## Camera yaw in radians; movement input is turned by it.
func get_yaw() -> float:
	return _yaw


## Aims the camera directly, for spawn and tests.
func set_look(yaw: float, pitch_deg: float) -> void:
	_yaw = yaw
	_current_yaw = yaw
	_pitch_deg = clampf(pitch_deg, pitch_min_deg, pitch_max_deg)
	_current_pitch_deg = _pitch_deg


## 0 in a tight doorway, 1 in the open; last value from the rods.
func get_openness() -> float:
	return _openness


## Boom length the rods ask for, before wall collision.
func get_target_distance() -> float:
	return lerpf(near_distance, far_distance, pow(_openness, openness_exponent))


## Current smoothed boom length, before wall collision.
func get_boom_length() -> float:
	return _boom


## Casts the rods now and returns 0..1; horizontal free space times ceiling room.
func measure_openness() -> float:
	var space := get_world_3d().direct_space_state
	if space == null:
		return 1.0
	var origin: Vector3 = _eye_position()
	var exclude: Array[RID] = [player.get_rid()]
	var free_sum: float = 0.0
	for i: int in range(probe_count):
		var angle: float = TAU * float(i) / float(probe_count)
		var dir := Vector3(sin(angle), 0.0, cos(angle))
		free_sum += _free_length(space, origin, dir * probe_length, exclude)
	var horizontal: float = free_sum / (probe_length * float(probe_count))
	var ceiling: float = _free_length(space, origin, Vector3.UP * ceiling_clearance, exclude)
	return clampf(horizontal * (ceiling / ceiling_clearance), 0.0, 1.0)


func _free_length(space: PhysicsDirectSpaceState3D, from: Vector3, motion: Vector3, exclude: Array[RID]) -> float:
	var query := PhysicsRayQueryParameters3D.create(from, from + motion, collision_mask, exclude)
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return motion.length()
	return from.distance_to(hit["position"])


func _apply_look_input() -> void:
	var input_systems: Node = get_node_or_null(^"/root/InputSystems")
	if input_systems == null:
		return
	var look: Vector2 = input_systems.call(&"get_look_delta")
	var x_sign: float = -1.0 if invert_look_x else 1.0
	var y_sign: float = -1.0 if invert_look_y else 1.0
	_yaw = wrapf(_yaw - look.x * look_sensitivity_x * x_sign, -PI, PI)
	_pitch_deg -= rad_to_deg(look.y) * look_sensitivity_y * pitch_sensitivity_ratio * y_sign
	_pitch_deg = clampf(_pitch_deg, pitch_min_deg, pitch_max_deg)


func _update_transform(delta: float) -> void:
	var speed_ratio: float = _player_speed_ratio()
	_pullback = lerpf(_pullback, speed_ratio * sprint_pullback, _damp(pullback_smoothing, delta))
	var planar := Vector3(player.velocity.x, 0.0, player.velocity.z)
	var move_dir: Vector3 = planar.normalized() if planar.length() > 0.05 else Vector3.ZERO
	_lead = _lead.lerp(move_dir * speed_ratio * lead_distance, _damp(lead_smoothing, delta))

	_noise_time += delta
	var sway: float = _noise.get_noise_1d(_noise_time * 20.0) * breathing_amplitude_deg * (0.4 + tension)
	var pitch_rad: float = deg_to_rad(_pitch_deg)
	var distance: float = _boom + _pullback
	var back := Vector3(sin(_yaw), 0.0, cos(_yaw))
	var right := Vector3(cos(_yaw), 0.0, -sin(_yaw))
	var shoulder: float = _shoulder.update(delta)
	var side: Vector3 = right * (shoulder * (1.0 - shoulder_frustum_ratio) + _lean * lean_camera_offset)
	var pivot: Vector3 = _feet_position() + Vector3.UP * body_height * SHOULDER_RATIO + _lead
	var target_pos: Vector3 = pivot + back * distance * cos(pitch_rad) \
			+ Vector3.UP * (-distance * sin(pitch_rad)) + side

	h_offset = lerpf(h_offset, shoulder * shoulder_frustum_ratio, _damp(lens_offset_smoothing, delta))

	if not _has_position:
		_current_pos = target_pos
		_has_position = true
	_current_pos = _current_pos.lerp(target_pos, _damp(follow_speed, delta))
	## Wall safety is the last layer so a retract is immediate, not filtered.
	_current_pos = _clamp_to_walls(delta, _current_pos)

	_current_pitch_deg = lerpf(_current_pitch_deg, _pitch_deg + sway, _damp(look_smoothing, delta))
	_current_yaw = lerp_angle(_current_yaw, _yaw, _damp(look_smoothing, delta))
	global_position = _current_pos
	global_rotation = Vector3(deg_to_rad(_current_pitch_deg), _current_yaw, 0.0)


func _apply_lean_and_shoulder_input(delta: float) -> void:
	var input_systems: Node = get_node_or_null(^"/root/InputSystems")
	if input_systems == null:
		return
	if input_systems.call(&"consume_switch_shoulder"):
		_shoulder.toggle()
	var axis: float = input_systems.call(&"get_lean_axis")
	if axis != 0.0:
		_lean = clampf(_lean + axis * lean_rate * delta, -1.0, 1.0)
	else:
		_lean = lerpf(_lean, 0.0, _damp(lean_return_rate, delta))


func _feet_position() -> Vector3:
	return player.global_position - Vector3.UP * origin_above_feet


func _eye_position() -> Vector3:
	return _feet_position() + Vector3.UP * body_height * EYE_RATIO


## Sphere-casts from the eyes to the camera; retracts at once, returns slowly.
func _clamp_to_walls(delta: float, position: Vector3) -> Vector3:
	var probe_pivot: Vector3 = _eye_position()
	var to_camera: Vector3 = position - probe_pivot
	var desired: float = to_camera.length()
	if desired < 0.001:
		return position
	var direction: Vector3 = to_camera / desired
	var safe: float = _probe_camera_distance(probe_pivot, direction, desired)
	if _collision_distance < 0.0 or safe < _collision_distance:
		_collision_distance = safe
	else:
		_collision_distance = lerpf(_collision_distance, safe, _damp(collision_restore_rate, delta))
	return probe_pivot + direction * minf(desired, _collision_distance)


func _probe_camera_distance(pivot: Vector3, direction: Vector3, desired: float) -> float:
	if desired <= collision_min_distance:
		return desired
	var space := get_world_3d().direct_space_state
	if space == null:
		return desired
	_collision_shape.radius = collision_radius
	_collision_query.shape = _collision_shape
	_collision_query.transform = Transform3D(Basis.IDENTITY, pivot)
	_collision_query.motion = direction * desired
	_collision_query.collision_mask = collision_mask
	_collision_query.collide_with_areas = false
	_collision_query.exclude = [player.get_rid()]
	var result: PackedFloat32Array = space.cast_motion(_collision_query)
	if result.is_empty() or result[0] >= 1.0:
		return desired
	return maxf(desired * result[0] - collision_surface_margin, collision_min_distance)


func _player_speed_ratio() -> float:
	if player.has_method(&"get_locomotion_speed_ratio"):
		return float(player.call(&"get_locomotion_speed_ratio"))
	return 0.0


func _set_look_capture(active: bool) -> void:
	var input_systems: Node = get_node_or_null(^"/root/InputSystems")
	if input_systems != null and input_systems.has_method(&"set_look_capture"):
		input_systems.call(&"set_look_capture", active)


## Frame-rate independent exponential damping, as ADT's Smoothing.damp_factor.
static func _damp(rate: float, delta: float) -> float:
	return 1.0 - exp(-rate * delta)
