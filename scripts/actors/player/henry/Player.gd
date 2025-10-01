# player.gd
extends CharacterBody3D
class_name Player

# === КОМПОНЕНТЫ ===
@onready var movement: MovementController = $MovementController
@onready var rotation_controller: RotationController = $RotationController
@onready var interactiom_manager: InteractionManager = $InteractionManager

# === ПАРАМЕТРЫ ДВИЖЕНИЯ, оставшиеся для управления движком ===
@export var jump_velocity: float = 5.0
@export var gravity: float = 9.8

# === Флаги для камеры ===
var cam_jump_hold_active: bool = false
var cam_jump_release_fired: bool = false
var cam_landed_this_frame: bool = false

# === Служебные переменные ===
var _was_on_floor_for_cam: bool = false

# === SNAP: Детектор двойного нажатия ===
var _snap_timer: float = 0.0
var _snap_ready: bool = false


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
	
	# Детектор двойного нажатия для Snap-поворота
	_snap_double_tap_check(delta)
	var snap_just_activated: bool = false
	if Input.is_action_just_pressed("move_backward"):
		if _snap_ready:
			snap_just_activated = true
		_snap_ready = true
		_snap_timer = 0.0
	
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
	
	rotation_controller.process_rotation(self, delta, snap_just_activated)

	move_and_slide()
	
	var on_floor_now := is_on_floor()
	cam_landed_this_frame = (not _was_on_floor_for_cam and on_floor_now)
	_was_on_floor_for_cam = on_floor_now
	cam_jump_hold_active = on_floor_now and jump_is_pressed
	cam_jump_release_fired = movement.get_jump_release_fired()


func _snap_double_tap_check(delta: float) -> void:
	# Если таймер активен, считаем время
	if _snap_ready:
		_snap_timer += delta
		if _snap_timer > rotation_controller.snap_double_tap_time:
			_snap_ready = false
			_snap_timer = 0.0
