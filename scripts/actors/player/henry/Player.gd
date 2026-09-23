# player.gd
extends CharacterBody3D
class_name Player

## Emitted when a scripted walk ends: arrived, stopped, or taken over by WASD.
signal movement_stopped

# === КОМПОНЕНТЫ ===
@onready var movement: MovementController = $MovementController
@onready var animation_component: HenryUALAnimation = $HenryUALVisual

# === ПАРАМЕТРЫ ДВИЖЕНИЯ, оставшиеся для управления движком ===
@export var jump_velocity: float = 5.0
@export var gravity: float = 9.8

## How fast Henry turns to face where he walks, as a damping rate.
@export_range(1.0, 30.0, 0.5) var turn_rate: float = 10.0

# === Флаги для камеры ===
var cam_jump_hold_active: bool = false
var cam_jump_release_fired: bool = false
var cam_landed_this_frame: bool = false

## Point a scripted walk heads for, e.g. InteractComponent's approach.
var _walk_target: Vector3 = Vector3.ZERO
var _walking_to_target: bool = false

# === Служебные переменные ===
var _was_on_floor_for_cam: bool = false



func _physics_process(delta: float) -> void:

	# --- 1) ОБРАБОТКА ВВОДА ---
	
	# Получение направления движения из ввода
	var input_dir: Vector3 = Vector3(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		0.0,
		Input.get_action_strength("move_backward") - Input.get_action_strength("move_forward")
	)
	
	# Обработка прыжка (клавиши)
	var jump_just_pressed: bool = Input.is_action_just_pressed("jump")
	var jump_is_pressed: bool = Input.is_action_pressed("jump")
	var jump_just_released: bool = Input.is_action_just_released("jump")
	
	# Обработка спринта (клавиши)
	var sprint_is_pressed: bool = Input.is_action_pressed("sprint")
	var sprint_just_released: bool = Input.is_action_just_released("sprint")
	
	## Input is camera-relative; movement still takes it in Henry's own frame.
	var world_dir: Vector3 = _camera_relative(input_dir)
	if _walking_to_target:
		if world_dir != Vector3.ZERO:
			stop_moving()
		else:
			world_dir = _walk_direction()
			sprint_is_pressed = false
	_face_towards(world_dir, delta)
	input_dir = global_transform.basis.orthonormalized().inverse() * world_dir

	# Обновление движения
	movement.process_movement(
		self,
		delta,
		input_dir,
		jump_just_pressed,
		jump_is_pressed,
		jump_just_released,
		sprint_is_pressed,
		sprint_just_released
	)
	
	move_and_slide()

	# ADT-style explicit animation ordering: the component sees the REAL
	# post-collision velocity, not input intent and not scene-tree process order.
	if is_instance_valid(animation_component):
		animation_component.update_animation_blend(delta)
	
	var on_floor_now := is_on_floor()
	cam_landed_this_frame = (not _was_on_floor_for_cam and on_floor_now)
	_was_on_floor_for_cam = on_floor_now
	cam_jump_hold_active = on_floor_now and jump_is_pressed
	cam_jump_release_fired = movement.get_jump_release_fired()


## Starts a walk to a point; WASD takes control back at once.
func move_to_position(point: Vector3) -> void:
	_walk_target = point
	_walking_to_target = true


func stop_moving() -> void:
	if not _walking_to_target:
		return
	_walking_to_target = false
	movement_stopped.emit()


func is_walking_to_target() -> bool:
	return _walking_to_target


func _walk_direction() -> Vector3:
	var offset: Vector3 = _walk_target - global_position
	offset.y = 0.0
	if offset.length() < 0.05:
		stop_moving()
		return Vector3.ZERO
	return offset.normalized()


## Turns a local WASD vector into a world direction by the active camera yaw.
func _camera_relative(input_dir: Vector3) -> Vector3:
	if input_dir.length_squared() < 0.0001:
		return Vector3.ZERO
	var camera := get_viewport().get_camera_3d() as TpsCamera
	var yaw: float = camera.get_yaw() if camera != null else global_rotation.y
	return input_dir.rotated(Vector3.UP, yaw)


func _face_towards(world_dir: Vector3, delta: float) -> void:
	if world_dir.length_squared() < 0.0001:
		return
	var target_yaw: float = atan2(-world_dir.x, -world_dir.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-turn_rate * delta))


## Horizontal movement ratio for the animation component, 0..1.
## Uses the actual CharacterBody3D velocity after move_and_slide().
func get_locomotion_speed_ratio() -> float:
	var horizontal_speed: float = Vector2(velocity.x, velocity.z).length()
	var max_speed: float = maxf(movement.sprint_speed, 0.001)
	return clampf(horizontal_speed / max_speed, 0.0, 1.0)
