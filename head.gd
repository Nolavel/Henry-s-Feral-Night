# Head.gd - Оптимизированная версия на основе рабочего кода
extends Node3D

# === MOUSE SENSITIVITY ===
@export var mouse_sensitivity = 0.002

# === TOP-DOWN SPECIFIC SETTINGS ===
@export_group("Top-Down Mode")
@export var use_topdown_mode = true
@export var instant_body_rotation = false
@export var body_follows_movement = false  
@export var body_follows_look = true      

# === HEAD CONSTRAINTS ===
@export_group("Head Limits")
@export var max_head_turn_degrees = 90.0  
@export var head_return_speed = 5.0       

# === FPS SETTINGS ===
@export_group("FPS Mode") 
@export var max_head_yaw_degrees = 60.0
@export var body_turn_threshold_degrees = 35.0
@export var body_turn_speed_degrees = 120.0
@export var body_rotation_delay = 0.3  

# === DEAD ZONE SETTINGS ===
@export_group("Dead Zone")
@export var head_return_to_center_in_dead_zone = true
@export var head_center_return_speed = 8.0
@export var direct_dead_zone_radius = 80.0

# === БЫСТРЫЙ ПОВОРОТ ===
@export_group("Fast Behind Rotation")
@export var behind_angle_threshold = 135.0
@export var instant_head_snap = false        # Быстрый, но не мгновенный
@export var ultra_fast_body_speed = 800.0    # Умеренно быстрая скорость
@export var fast_head_speed = 20.0           # Скорость головы для больших углов

# === DEBUG ===
@export_group("Debug")
@export var show_debug_info = false

# === INTERNAL VARIABLES ===
var current_head_yaw = 0.0
var current_head_pitch = 0.0
var accumulated_head_yaw = 0.0
var body_rotation_timer = 0.0
var should_rotate_body = false
var target_body_rotation = 0.0
var last_movement_direction = Vector3.ZERO

var head_control_enabled: bool = true

# Dead zone variables
var is_in_dead_zone_state = false
var head_center_target = 0.0

# Rotation state
var is_behind_rotation = false

# ОПТИМИЗАЦИЯ: Кешированные ссылки (создаются только один раз)
var cached_camera: Camera3D
var cached_player: Node3D
var crosshair_controller: Node

func _ready():
	print("Head.gd: Система инициализирована для %s режима" % ("Top-Down" if use_topdown_mode else "FPS"))
	auto_detect_camera_mode()
	# ОПТИМИЗАЦИЯ: Кешируем ссылки один раз
	cache_node_references()

func cache_node_references():
	"""ОПТИМИЗАЦИЯ: Кешируем ссылки на часто используемые узлы"""
	cached_camera = get_tree().get_first_node_in_group("game_camera_group")
	cached_player = get_parent()
	crosshair_controller = get_parent().get_node_or_null("CrosshairUI")

func auto_detect_camera_mode():
	"""Автоматически определяет режим камеры"""
	var camera = get_tree().get_first_node_in_group("game_camera_group")
	if camera and camera.has_method("get") and camera.get("is_isometric") != null:
		use_topdown_mode = true
		print("Head.gd: Обнаружен top-down режим")
	else:
		use_topdown_mode = false
		print("Head.gd: Обнаружен FPS режим")

func handle_mouse_input(event: InputEventMouseMotion):
	"""Обрабатывает ввод мыши в зависимости от режима"""
	if not head_control_enabled:
		return
	if use_topdown_mode:
		return
	else:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			handle_fps_mouse_input(event)

func handle_fps_mouse_input(event: InputEventMouseMotion):
	"""Обработка мыши для FPS режима"""
	var mouse_delta_x = -event.relative.x * mouse_sensitivity
	accumulated_head_yaw += mouse_delta_x
	
	var max_yaw_rad = deg_to_rad(max_head_yaw_degrees)
	accumulated_head_yaw = clamp(accumulated_head_yaw, -max_yaw_rad, max_yaw_rad)
	
	var mouse_delta_y = -event.relative.y * mouse_sensitivity
	current_head_pitch += mouse_delta_y
	var max_pitch_rad = deg_to_rad(80.0)
	current_head_pitch = clamp(current_head_pitch, -max_pitch_rad, max_pitch_rad)
	
	rotation.y = accumulated_head_yaw
	rotation.x = current_head_pitch
	
	check_fps_body_rotation_trigger()

func check_fps_body_rotation_trigger():
	"""Проверяет триггер поворота тела для FPS режима"""
	var threshold_rad = deg_to_rad(body_turn_threshold_degrees)
	
	if abs(accumulated_head_yaw) > threshold_rad:
		if not should_rotate_body:
			body_rotation_timer = body_rotation_delay
			should_rotate_body = true
			
			if show_debug_info:
				print("Head.gd: FPS триггер поворота тела (голова: %.1f°)" % rad_to_deg(accumulated_head_yaw))
	else:
		should_rotate_body = false
		body_rotation_timer = 0.0

func _physics_process(delta):
	"""Основной цикл обработки"""
	if not head_control_enabled:
		return
	if use_topdown_mode and is_instance_valid(crosshair_controller) and crosshair_controller.enable_look_at_cursor:
		handle_lightning_fast_rotation(delta)
	
	# Обрабатываем таймер поворота тела для FPS режима
	if should_rotate_body and not use_topdown_mode:
		handle_body_rotation_timer(delta)
		if body_rotation_timer <= 0.0:
			execute_fps_body_rotation(delta)

func handle_lightning_fast_rotation(delta):
	"""Быстрый поворот с прямым вычислением углов"""
	# ОПТИМИЗАЦИЯ: Используем кешированные ссылки
	if not is_instance_valid(cached_player) or not is_instance_valid(cached_camera):
		return
	
	# ПРЯМОЕ получение позиции курсора
	var mouse_pos = get_viewport().get_mouse_position()
	
	# БЫСТРАЯ проверка dead zone
	var player_screen_pos = cached_camera.unproject_position(cached_player.global_position)
	var distance_to_player = mouse_pos.distance_to(player_screen_pos)
	
	if distance_to_player < direct_dead_zone_radius:
		is_in_dead_zone_state = true
		if head_return_to_center_in_dead_zone:
			handle_head_return_to_center(delta)
		should_rotate_body = false
		is_behind_rotation = false
		return
	
	is_in_dead_zone_state = false
	
	# ПРЯМОЕ вычисление направления
	var cursor_world_pos = get_direct_cursor_world_position(mouse_pos)
	if cursor_world_pos == Vector3.ZERO:
		return
	
	var look_dir = (cursor_world_pos - cached_player.global_position)
	look_dir.y = 0
	
	if look_dir.length() < 0.1:
		return
	
	look_dir = look_dir.normalized()
	
	# Вычисление углов
	var target_head_yaw = atan2(-look_dir.x, -look_dir.z)
	var player_body_yaw = cached_player.global_rotation.y
	var relative_head_yaw = target_head_yaw - player_body_yaw
	
	# Нормализация угла
	if relative_head_yaw > PI:
		relative_head_yaw -= 2 * PI
	elif relative_head_yaw < -PI:
		relative_head_yaw += 2 * PI
	
	var head_angle_degrees = abs(rad_to_deg(relative_head_yaw))
	
	# КЛЮЧЕВАЯ ЛОГИКА: За спиной = быстро
	if head_angle_degrees > behind_angle_threshold:
		if not is_behind_rotation:
			is_behind_rotation = true
			if show_debug_info:
				print("Head.gd: Быстрый поворот за спину %.1f°" % head_angle_degrees)
		
		# ГОЛОВА: Быстрый поворот
		if instant_head_snap:
			rotation.y = relative_head_yaw
			current_head_yaw = relative_head_yaw
		else:
			rotation.y = lerp_angle(rotation.y, relative_head_yaw, fast_head_speed * delta)
			current_head_yaw = rotation.y
		
		# ТЕЛО: Быстрый поворот без задержки
		should_rotate_body = true
		body_rotation_timer = 0.0
		execute_ultra_fast_body_rotation_direct(delta, target_head_yaw)
		
	else:
		# Малые углы - обычная логика
		is_behind_rotation = false
		current_head_yaw = relative_head_yaw
		rotation.y = lerp_angle(rotation.y, current_head_yaw, 100.0 * delta)
		
		if head_angle_degrees > body_turn_threshold_degrees:
			if not should_rotate_body:
				should_rotate_body = true
				body_rotation_timer = body_rotation_delay
		
		if should_rotate_body:
			handle_body_rotation_timer(delta)
			if body_rotation_timer <= 0.0:
				execute_normal_body_rotation_direct(delta, target_head_yaw)
	
	rotation.x = 0

func get_direct_cursor_world_position(mouse_pos: Vector2) -> Vector3:
	"""ОПТИМИЗИРОВАННОЕ вычисление мировой позиции курсора"""
	var player_y = cached_player.global_position.y
	var from = cached_camera.project_ray_origin(mouse_pos)
	var direction = cached_camera.project_ray_normal(mouse_pos)
	
	if abs(direction.y) < 0.001:
		return Vector3.ZERO
	
	var t = (player_y - from.y) / direction.y
	return from + direction * t

func execute_ultra_fast_body_rotation_direct(delta: float, target_yaw: float):
	"""Быстрый поворот тела для больших углов"""
	var current_body_yaw = cached_player.global_rotation.y
	var rotation_diff = target_yaw - current_body_yaw
	
	# Нормализация
	if rotation_diff > PI:
		rotation_diff -= 2 * PI
	elif rotation_diff < -PI:
		rotation_diff += 2 * PI
	
	# Быстрая скорость
	var ultra_fast_speed = deg_to_rad(ultra_fast_body_speed)
	var max_rotation = ultra_fast_speed * delta
	var rotation_amount = clamp(rotation_diff, -max_rotation, max_rotation)
	
	cached_player.rotate_y(rotation_amount)
	current_head_yaw -= rotation_amount
	rotation.y = current_head_yaw
	
	if abs(rotation_diff) < deg_to_rad(2.0):
		should_rotate_body = false
		is_behind_rotation = false
		if show_debug_info:
			print("Head.gd: Быстрый поворот завершен")

func execute_normal_body_rotation_direct(delta: float, target_yaw: float):
	"""Обычный поворот тела для малых углов"""
	var current_body_yaw = cached_player.global_rotation.y
	var rotation_diff = target_yaw - current_body_yaw
	
	if rotation_diff > PI:
		rotation_diff -= 2 * PI
	elif rotation_diff < -PI:
		rotation_diff += 2 * PI
	
	var rotation_speed = deg_to_rad(body_turn_speed_degrees)
	var max_rotation = rotation_speed * delta
	var rotation_amount = clamp(rotation_diff, -max_rotation, max_rotation)
	
	cached_player.rotate_y(rotation_amount)
	current_head_yaw -= rotation_amount
	rotation.y = current_head_yaw
	
	if abs(rotation_diff) < deg_to_rad(5.0):
		should_rotate_body = false

func handle_head_return_to_center(delta):
	"""Плавно возвращает голову к центру в мертвой зоне"""
	head_center_target = 0.0
	var current_rotation = rotation.y
	var rotation_diff = head_center_target - current_rotation
	
	if rotation_diff > PI:
		rotation_diff -= 2 * PI
	elif rotation_diff < -PI:
		rotation_diff += 2 * PI
	
	var return_speed = head_center_return_speed * delta
	var rotation_step = clamp(rotation_diff, -return_speed, return_speed)
	
	rotation.y += rotation_step
	current_head_yaw = rotation.y
	rotation.x = 0.0

func handle_body_rotation_timer(delta):
	"""Обрабатывает таймер задержки поворота"""
	if body_rotation_timer > 0.0:
		body_rotation_timer -= delta

func execute_fps_body_rotation(delta):
	"""Выполняет поворот тела в FPS режиме"""
	if not is_instance_valid(cached_player):
		return
	
	var threshold_rad = deg_to_rad(body_turn_threshold_degrees)
	var excess_rotation = 0.0
	
	if accumulated_head_yaw > threshold_rad:
		excess_rotation = accumulated_head_yaw - threshold_rad
	elif accumulated_head_yaw < -threshold_rad:
		excess_rotation = accumulated_head_yaw + threshold_rad
	else:
		should_rotate_body = false
		return
	
	var rotation_speed = deg_to_rad(body_turn_speed_degrees)
	if abs(excess_rotation) > deg_to_rad(10.0):
		rotation_speed = deg_to_rad(200.0)
	
	var max_rotation_this_frame = rotation_speed * delta
	var rotation_amount = min(abs(excess_rotation), max_rotation_this_frame) * sign(excess_rotation)
	
	cached_player.rotate_y(rotation_amount)
	accumulated_head_yaw -= rotation_amount
	rotation.y = accumulated_head_yaw
	
	if abs(accumulated_head_yaw) <= threshold_rad:
		should_rotate_body = false
		if show_debug_info:
			print("Head.gd: FPS поворот тела завершен")

# === UTILITY FUNCTIONS ===

func get_look_direction() -> Vector3:
	"""Возвращает направление взгляда"""
	return -global_transform.basis.z

func get_current_mode() -> String:
	"""Возвращает текущий режим"""
	return "TopDown" if use_topdown_mode else "FPS"

func switch_mode():
	"""Переключает между режимами"""
	use_topdown_mode = !use_topdown_mode
	reset_rotation_state()

func reset_rotation_state():
	"""Сбрасывает состояние поворота"""
	accumulated_head_yaw = 0.0
	current_head_yaw = 0.0
	current_head_pitch = 0.0
	should_rotate_body = false
	body_rotation_timer = 0.0
	is_in_dead_zone_state = false
	head_center_target = 0.0
	is_behind_rotation = false
	rotation = Vector3.ZERO

func is_in_dead_zone() -> bool:
	"""Возвращает состояние мертвой зоны"""
	return is_in_dead_zone_state

func set_dead_zone_head_return_speed(speed: float):
	"""Устанавливает скорость возврата головы в мертвой зоне"""
	head_center_return_speed = clamp(speed, 1.0, 20.0)
	
func set_head_control_enabled(enabled: bool):
	head_control_enabled = enabled
	if not enabled:
		reset_head_state()

func reset_head_state():
	should_rotate_body = false
	rotation = Vector3.ZERO
	current_head_yaw = 0.0
