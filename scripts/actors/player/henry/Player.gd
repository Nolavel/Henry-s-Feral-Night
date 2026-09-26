# player.gd
extends CharacterBody3D
class_name Player

## Emitted when a scripted walk ends: arrived, stopped, or taken over by WASD.
signal movement_stopped

const THERMAL_SCRIPT: GDScript = preload("res://scripts/systems/survival/thermal_manager.gd")

# === КОМПОНЕНТЫ ===
@onready var movement: MovementController = $MovementController
@onready var animation_component: HenryUALAnimation = $HenryUALVisual
var _hold_until_ms: int = 0
@onready var hub: PlayerHubComponent = get_node_or_null(^"PlayerHubComponent") as PlayerHubComponent
@onready var rest: RestComponent = get_node_or_null(^"RestComponent") as RestComponent
@onready var main_collision: CollisionShape3D = $Main_Collision
@onready var health_system: PlayerHealthSystem = $PlayerHealthSystem
@onready var consumption_controller: ConsumptionController = $ConsumptionController

# === ПАРАМЕТРЫ ДВИЖЕНИЯ, оставшиеся для управления движком ===
@export var jump_velocity: float = 5.0
@export var gravity: float = 9.8

## How fast Henry turns to face where he walks, as a damping rate.
@export_range(1.0, 30.0, 0.5) var turn_rate: float = 10.0

@export_group("Crouch")
@export_range(0.5, 1.0, 0.05) var crouch_height_ratio: float = 0.65
@export_range(0.01, 0.15, 0.01) var stand_clearance_margin: float = 0.05

# === Флаги для камеры ===
var cam_jump_hold_active: bool = false
var cam_jump_release_fired: bool = false
var cam_landed_this_frame: bool = false

## Point a scripted walk heads for, e.g. InteractComponent's approach.
var _walk_target: Vector3 = Vector3.ZERO
var _walking_to_target: bool = false

# === Служебные переменные ===
var _was_on_floor_for_cam: bool = false
var _floor_sample_initialized: bool = false
var _crouching: bool = false
var _standing_collision_height: float = 0.0
var _standing_collision_position: Vector3 = Vector3.ZERO



func _ready() -> void:
	if main_collision != null and main_collision.shape is CylinderShape3D:
		main_collision.shape = main_collision.shape.duplicate()
		_standing_collision_height = (main_collision.shape as CylinderShape3D).height
		_standing_collision_position = main_collision.position
	if health_system != null:
		health_system.damage_taken.connect(_on_damage_taken_for_animation)
	var carry := get_node_or_null(^"CarryComponent") as CarryComponent
	if carry != null and animation_component != null:
		carry.carry_changed.connect(animation_component.set_carried_item)
		animation_component.set_carried_item(carry.get_carried_item())
	if consumption_controller != null:
		consumption_controller.consumed.connect(
			func(_item_id: StringName, _item: ItemResource) -> void:
				if animation_component != null:
					animation_component.play_action(&"consume")
		)


func _on_damage_taken_for_animation(_amount: float, source: String) -> void:
	if source != "fall" and source != "impact":
		return
	if animation_component != null:
		animation_component.play_action(&"hit_chest")


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
	## Working actions (pickup, repair, opening), the Hub and sitting root Henry.
	var in_hub: bool = (is_instance_valid(hub) and hub.is_open()) or (is_instance_valid(rest) and rest.is_sitting()) \
		or Time.get_ticks_msec() < _hold_until_ms
	if in_hub or (is_instance_valid(animation_component) and animation_component.is_action_locking()):
		world_dir = Vector3.ZERO
		jump_just_pressed = false
		sprint_is_pressed = false
	_face_towards(world_dir, delta)
	input_dir = global_transform.basis.orthonormalized().inverse() * world_dir

	_update_crouch()
	movement.set_crouching(_crouching)

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

	var on_floor_now := is_on_floor()
	cam_landed_this_frame = _floor_sample_initialized and (not _was_on_floor_for_cam and on_floor_now)
	var jump_started: bool = movement.get_jump_release_fired()
	_was_on_floor_for_cam = on_floor_now
	_floor_sample_initialized = true

	if is_instance_valid(animation_component):
		animation_component.update_animation_blend(delta)
		animation_component.update_animation_state(jump_started, cam_landed_this_frame)
		animation_component.update_head_look(delta)

	cam_jump_hold_active = on_floor_now and jump_is_pressed
	cam_jump_release_fired = jump_started


func _update_crouch() -> void:
	var input_systems: Node = get_node_or_null(^"/root/InputSystems")
	var wants_crouch: bool = (
		input_systems != null
		and input_systems.has_method(&"is_crouching")
		and bool(input_systems.call(&"is_crouching"))
	)
	if _crouching and not wants_crouch and not _can_stand_up():
		return
	if wants_crouch == _crouching:
		return
	_crouching = wants_crouch
	_apply_collision_stance()


func _apply_collision_stance() -> void:
	if main_collision == null or not (main_collision.shape is CylinderShape3D) or _standing_collision_height <= 0.0:
		return
	var shape := main_collision.shape as CylinderShape3D
	var target_height: float = _standing_collision_height * (crouch_height_ratio if _crouching else 1.0)
	shape.height = target_height
	var height_delta: float = _standing_collision_height - target_height
	main_collision.position = _standing_collision_position - Vector3.UP * height_delta * 0.5


func _can_stand_up() -> bool:
	if main_collision == null or not (main_collision.shape is CylinderShape3D) or _standing_collision_height <= 0.0:
		return true
	var current := main_collision.shape as CylinderShape3D
	var added_height: float = _standing_collision_height - current.height
	if added_height <= 0.001:
		return true

	var margin: float = minf(stand_clearance_margin, added_height * 0.5)
	var headroom_height: float = maxf(added_height - margin, 0.01)
	var headroom := CylinderShape3D.new()
	headroom.radius = current.radius
	headroom.height = headroom_height

	var standing_top_y: float = _standing_collision_position.y + _standing_collision_height * 0.5
	var headroom_center_y: float = standing_top_y - headroom_height * 0.5
	var local_transform := Transform3D(
		main_collision.transform.basis,
		Vector3(_standing_collision_position.x, headroom_center_y, _standing_collision_position.z)
	)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = headroom
	query.transform = global_transform * local_transform
	query.exclude = [get_rid()]
	query.collision_mask = collision_mask
	query.collide_with_bodies = true
	query.collide_with_areas = false
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func is_crouching() -> bool:
	return _crouching


func get_crouch_speed_ratio() -> float:
	return movement.get_crouch_speed_ratio(velocity) if movement != null else 0.0


## Roots Henry for a staged act (lighting the stove) that outlasts its clip.
func hold_still(seconds: float) -> void:
	_hold_until_ms = maxi(_hold_until_ms, Time.get_ticks_msec() + int(seconds * 1000.0))


func is_holding_still() -> bool:
	return Time.get_ticks_msec() < _hold_until_ms


func play_action_animation(action: StringName) -> bool:
	return animation_component.play_action(action) if animation_component != null else false


## Flat direction the active camera looks, for the head look; Henry's facing
## when there is no camera.
## Wet clothes show on the body: the thermal model's wetness darkens them.
func on_world_ready(context: WorldContext) -> void:
	var held_light := get_node_or_null(^"HeldLightComponent") as HeldLightComponent
	if held_light != null:
		held_light.on_world_ready(context)
	var snow_scoop := get_node_or_null(^"SnowScoopComponent") as SnowScoopComponent
	if snow_scoop != null:
		snow_scoop.on_world_ready(context)
	var steam := get_node_or_null(^"DryingSteamComponent") as DryingSteamComponent
	if steam != null:
		steam.set_thermal(context.get_system(THERMAL_SCRIPT) as ThermalManager)
	var thermal := context.get_system(THERMAL_SCRIPT) as ThermalManager
	if thermal == null or animation_component == null:
		return
	thermal.wetness_changed.connect(animation_component.set_wetness)
	animation_component.set_wetness(thermal.get_wetness())


func get_view_direction() -> Vector3:
	var camera: Camera3D = get_viewport().get_camera_3d()
	var forward: Vector3 = -(camera.global_transform.basis.z if camera != null else global_transform.basis.z)
	forward.y = 0.0
	return forward.normalized() if forward.length() > 0.001 else -global_transform.basis.z


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
