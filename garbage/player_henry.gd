extends CharacterBody3D
class_name Player1

# === ПАРАМЕТРЫ ДВИЖЕНИЯ ===
@export_group("Параметры движения")
@export var walk_speed: float = 4.0
@export var sprint_speed: float = 8.0
@export var jump_velocity: float = 5.0
@export var gravity: float = 9.8

# === ПОВОРОТ — ФРОНТ ===
@export_group("Поворот — фронт")
@export var mouse_ray_length: float = 1000.0
@export var base_rotation_speed: float = 6.0
@export var max_rotation_speed: float = 12.0
@export var yaw_sector_deg: float = 60.0
@export var front_sector_deg: float = 120.0
@export var rotation_delay_min: float = 0.05
@export var rotation_delay_max: float = 0.25

# === ПОВОРОТ — СПИНА ===
@export_group("Поворот — спина")
@export var back_slow_sector_deg: float = 120.0
@export var back_deadzone_deg: float = 60.0
@export var back_rotation_speed: float = 2.0
@export var back_rotation_delay: float = 0.15

# === УСТОЙЧИВОСТЬ ===
@export_group("Устойчивость")
@export var front_hysteresis_deg: float = 8.0
@export var angle_smoothing_speed: float = 12.0
@export var min_mouse_distance: float = 0.6
@export var noise_floor_deg: float = 0.35

# === ФИКСАЦИЯ ЦЕЛИ ===
@export_group("Фиксация цели")
@export var lock_enabled: bool = true
@export var lock_epsilon_deg: float = 2.0
@export var lock_min_dwell: float = 0.05

# === SNAP 180° ===
@export_group("Snap 180° (умный, анимированный)")
@export var snap_double_tap_time: float = 0.25
@export var snap_turn_time: float = 0.25
@export var snap_jump_strength: float = 1.2

# === УЛУЧШЕНИЯ ПЛАВНОСТИ ПОВОРОТА ===
@export_group("Улучшения плавности поворота")
@export var mouse_prediction_strength: float = 0.3
@export var speed_transition_rate: float = 8.0
@export var adaptive_delay_factor: float = 0.5
@export var momentum_decay: float = 0.85
@export var exponential_smoothing: bool = true

# === ЖИВОЙ РАЗГОН / ТОРМОЖЕНИЕ ===
@export_group("Живой разгон / торможение")
@export var accel_rate: float = 8.0
@export var decel_rate: float = 12.0
@export var start_jump_impulse: float = 0.1

# === ПАРАМЕТРЫ СПРИНТА ===
@export_group("Параметры спринта")
@export var sprint_ramp_time: float = 0.35
@export var sprint_inertia_time: float = 0.22
@export var sprint_release_boost: float = 0.5

# === ПАРАМЕТРЫ ДЕБАГА ===
@export_group("Дебаггинг")
@onready var debug_visuals_node: MeshInstance3D = $"../DebugVisuals"
@export var show_debug: bool = false
var _debug_material: StandardMaterial3D = null
var _debug_mesh: ImmediateMesh = null
var _debug_labels: Array = []
var _debug_label_map := {}  # key = sector name, value = Label3D


# =========================
# === СЛУЖЕБНЫЕ ПЕРЕМЕННЫЕ ДВИЖЕНИЯ ===
# =========================
var _was_idle: bool = true
var _sprint_blend: float = 1.0
var _sprint_inertia_timer: float = 0.0

# =========================
# === СОСТОЯНИЕ ПОВОРОТА ===
# =========================
var last_look_dir: Vector3 = Vector3.FORWARD
var yaw_timer: float = 0.0
var _in_front_sector: bool = true
var _smoothed_target_yaw: float = 0.0
var _have_smoothed: bool = false
var _rotation_enabled: bool = true #main 

# === КЕШИРОВАНИЕ ===
var _cached_camera: Camera3D = null
var _viewport: Viewport = null
# =========================
# === ДОП. СОСТОЯНИЕ ПОВОРОТА ===
# =========================
var mouse_velocity: Vector2 = Vector2.ZERO
var last_mouse_pos: Vector2 = Vector2.ZERO
var current_rotation_speed: float = 0.0
var speed_momentum: float = 0.0
#var last_frame_time: float = 0.0

# =========================
# === ЛОК-РЕЖИМ ===
# =========================
enum Sector { NONE, FRONT, BACK }
var _is_locked: bool = false
var _locked_target_yaw: float = 0.0
var _lock_sector: int = Sector.NONE
var _lock_timer: float = 0.0

# =========================
# === SNAP СОСТОЯНИЕ ===
# =========================
var _snap_timer: float = 0.0
var _snap_ready: bool = false
var _snap_active: bool = false
var _snap_elapsed: float = 0.0
var _snap_start_yaw: float = 0.0
var _snap_target_yaw: float = 0.0

var cam_jump_hold_active: bool = false
var cam_jump_release_fired: bool = false
var cam_landed_this_frame: bool = false

var _jump_hold_armed: bool = false
var _was_on_floor_for_cam: bool = false



func _ready() -> void:
	var fwd: Vector3 = -global_transform.basis.z
	fwd.y = 0.0
	if fwd.length() > 0.0001:
		last_look_dir = fwd.normalized()
	_smoothed_target_yaw = rotation.y
	_have_smoothed = true
	
	# Инициализация новых переменных
	last_mouse_pos = get_viewport().get_mouse_position()
	current_rotation_speed = base_rotation_speed
	#last_frame_time = Time.get_time_dict_from_system()["hour"] * 3600.0 + Time.get_time_dict_from_system()["minute"] * 60.0 + Time.get_time_dict_from_system()["second"]
	
	# Инициализация ImmediateMesh и назначение узлу MeshInstance3D
	_debug_mesh = ImmediateMesh.new()
	if debug_visuals_node:
		debug_visuals_node.mesh = _debug_mesh
		debug_visuals_node.visible = show_debug  # Изменено с true на show_debug
	else:
		push_warning("DebugVisuals node not found")
	
	_viewport = get_viewport()
	_cached_camera = _viewport.get_camera_3d() if _viewport else null
	
	# Проверка диапазонов углов
	front_sector_deg = clamp(front_sector_deg, 10.0, 180.0)
	yaw_sector_deg = clamp(yaw_sector_deg, 0.0, front_sector_deg)
	back_slow_sector_deg = clamp(back_slow_sector_deg, 0.0, 360.0)
	back_deadzone_deg = clamp(back_deadzone_deg, 0.0, back_slow_sector_deg)
			
func _physics_process(delta: float) -> void:
	
	# Защита от некорректных значений
	if walk_speed <= 0.0:
		push_warning("Walk speed must be positive, setting to 4.0")
		walk_speed = 4.0
	if sprint_speed <= walk_speed:
		push_warning("Sprint speed must be greater than walk speed")
		sprint_speed = walk_speed * 2.0
	
	# Теперь безопасно вычислять
	var sprint_multiplier: float = sprint_speed / walk_speed
	# === Double‑tap детектор для snap ===
	if _snap_ready:
		_snap_timer += delta
		if _snap_timer > snap_double_tap_time:
			_snap_ready = false
			_snap_timer = 0.0

	if Input.is_action_just_pressed("move_backward"):
		if _snap_ready:
			_start_snap_180()
		else:
			_snap_ready = true
			_snap_timer = 0.0

	## === Гравитация / прыжок ===
	#if not is_on_floor():
		#velocity.y -= gravity * delta
	#else:
		#if Input.is_action_just_pressed("jump"):
			#velocity.y = jump_velocity
			
	# 1) Гравитация
	if not is_on_floor():
		velocity.y -= gravity * delta

	# 2) Готовность -> прыжок на отпускание (импульс В ЭТОМ кадре)
	cam_jump_release_fired = false
	if is_on_floor():
		if Input.is_action_pressed("jump"):
			_jump_hold_armed = true
		if _jump_hold_armed and Input.is_action_just_released("jump"):
			velocity.y = jump_velocity
			cam_jump_release_fired = true
			_jump_hold_armed = false
	else:
		if Input.is_action_just_released("jump"):
			_jump_hold_armed = false

	# === Движение с плавным разгоном и спринтом ===
	var input_dir: Vector3 = Vector3(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		0.0,
		Input.get_action_strength("move_backward") - Input.get_action_strength("move_forward")
	)
	var has_input: bool = input_dir.length() > 0.0
	if input_dir.length() > 1.0:
		input_dir = input_dir.normalized()

	var planar_dir: Vector3 = global_transform.basis * input_dir
	planar_dir.y = 0.0
	#if planar_dir.length() > 1.0:
		#planar_dir = planar_dir.normalized()
	var planar_length = planar_dir.length()
	if planar_length > 1.0:
		planar_dir = planar_dir / planar_length

	# Плавный спринт
	var sprint_pressed: bool = Input.is_action_pressed("sprint")
	var sprint_just_released: bool = Input.is_action_just_released("sprint")
	#var sprint_multiplier: float = sprint_speed / max(walk_speed, 0.001)

	if sprint_pressed and has_input:
		var up_rate: float = (delta / sprint_ramp_time) if sprint_ramp_time > 0.0 else 1.0
		_sprint_blend = lerp(_sprint_blend, sprint_multiplier, clamp(up_rate, 0.0, 1.0))
		_sprint_inertia_timer = 0.0
	else:
		if sprint_just_released and has_input and is_on_floor():
			_sprint_inertia_timer = sprint_inertia_time
			if planar_dir.length() > 0.0 and sprint_release_boost > 0.0:
				var dir: Vector3 = planar_dir.normalized()
				velocity.x += dir.x * sprint_release_boost
				velocity.z += dir.z * sprint_release_boost

		if _sprint_inertia_timer > 0.0:
			var down_rate_inertia: float = (delta / sprint_inertia_time) if sprint_inertia_time > 0.0 else 1.0
			_sprint_blend = lerp(_sprint_blend, 1.0, clamp(down_rate_inertia, 0.0, 1.0))
			_sprint_inertia_timer = max(0.0, _sprint_inertia_timer - delta)
		else:
			var down_rate: float = (delta / (sprint_ramp_time * 0.75)) if sprint_ramp_time > 0.0 else 1.0
			_sprint_blend = lerp(_sprint_blend, 1.0, clamp(down_rate, 0.0, 1.0))

	# Целевая скорость с учётом бленда спринта
	var target_speed: float = walk_speed * _sprint_blend
	var target_vel: Vector3 = planar_dir * target_speed

	# Разгон или торможение (по XZ)
	var current_planar_speed: float = Vector3(velocity.x, 0.0, velocity.z).length()
	var rate: float = accel_rate if target_vel.length() > current_planar_speed else decel_rate

	velocity.x = lerp(velocity.x, target_vel.x, clamp(rate * delta, 0.0, 1.0))
	velocity.z = lerp(velocity.z, target_vel.z, clamp(rate * delta, 0.0, 1.0))

	# Лёгкий толчок вверх при старте
	if _was_idle and has_input and is_on_floor():
		velocity.y += start_jump_impulse
	_was_idle = not has_input

	# === Плавная анимация snap‑поворота ===
	if _snap_active:
		_snap_elapsed += delta
		var t: float = clamp(_snap_elapsed / snap_turn_time, 0.0, 1.0)
		rotation.y = lerp_angle(_snap_start_yaw, _snap_target_yaw, t)

		# Гасим «память» поворота и таймеры
		_smoothed_target_yaw = rotation.y
		_have_smoothed = true
		current_rotation_speed = 0.0
		yaw_timer = 0.0

		move_and_slide()

		if _snap_elapsed >= snap_turn_time:
			_snap_active = false
			_have_smoothed = false
			_smoothed_target_yaw = rotation.y
		return

	# === Обычная логика ===
	move_and_slide()
	if _rotation_enabled:
		_face_mouse(delta)
		
	# === ВЫЗОВ ОТРИСОВКИ ДЕБАГА  ===
	if show_debug:
		_draw_debug_visuals()
		#debug_visuals_node.global_transform = Transform3D(debug_visuals_node.global_transform.basis, global_transform.origin)
	
	
	# 4) Флаги ДЛЯ КАМЕРЫ — строго после move_and_slide
	var on_floor_now := is_on_floor()
	cam_landed_this_frame = (not _was_on_floor_for_cam and on_floor_now)
	_was_on_floor_for_cam = on_floor_now
	cam_jump_hold_active = on_floor_now and Input.is_action_pressed("jump")

func _start_snap_180() -> void:
	_snap_active = true
	_snap_elapsed = 0.0
	_snap_start_yaw = rotation.y

	# Если хочешь «умный» выбор стороны — оставь по мыши,
	# если строго 180 независимо от мыши — используй просто +PI.
	var current_mouse_angle := _get_mouse_angle_to_player()
	var snap_direction := 1.0 if current_mouse_angle > 0.0 else -1.0
	_snap_target_yaw = wrapf(rotation.y + PI * snap_direction, -PI, PI)
	# Альтернатива без привязки к мыши:
	# _snap_target_yaw = wrapf(rotation.y + PI, -PI, PI)

	# Лёгкий подпрыг — только на земле
	if is_on_floor():
		velocity.y = max(velocity.y, snap_jump_strength)

	# Полный сброс любых влияний поворота
	_is_locked = false
	_lock_sector = Sector.NONE
	_lock_timer = 0.0
	yaw_timer = 0.0
	current_rotation_speed = 0.0

	# Сглаживатель «пришпилить» к текущему yaw на старте
	_smoothed_target_yaw = rotation.y
	_have_smoothed = true

	# Закрываем окно двойного тапа
	_snap_ready = false
	_snap_timer = 0.0


func _get_mouse_angle_to_player() -> float:
	var camera = _cached_camera if _cached_camera else get_viewport().get_camera_3d()
	if not camera:
		return 0.0
	
	var mouse_pos = get_viewport().get_mouse_position()
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_dir = camera.project_ray_normal(mouse_pos)
	
	var player_y = global_transform.origin.y
	if abs(ray_dir.y) > 0.0001:
		var t = (player_y - ray_origin.y) / ray_dir.y
		if t > 0.0:
			var target_world = ray_origin + ray_dir * t
			var to_target = target_world - global_transform.origin
			to_target.y = 0.0
			var fwd = -global_transform.basis.z
			fwd.y = 0.0
			if fwd.length() > 0.0001 and to_target.length() > 0.001:
				return atan2(fwd.cross(to_target.normalized()).y, fwd.dot(to_target.normalized()))
	return 0.0

func _face_mouse(delta: float) -> void:
	# Двойная защита: если snap активен — немедленный выход
	if _snap_active:
		return

	# НОВОЕ: Вычисляем скорость мыши для адаптации
	var mouse_pos: Vector2 = _viewport.get_mouse_position() if _viewport else get_viewport().get_mouse_position()
	mouse_velocity = (mouse_pos - last_mouse_pos) / delta if delta > 0.0 else Vector2.ZERO
	last_mouse_pos = mouse_pos
	var mouse_speed = mouse_velocity.length()
	
	# НОВОЕ: Адаптивные задержки на основе скорости мыши
	var speed_factor = clamp(mouse_speed / 100.0, 0.1, 2.0)  # 100 пикселей/сек как базовая скорость
	var adaptive_delay_mult = lerp(1.0, adaptive_delay_factor, clamp(speed_factor - 0.5, 0.0, 1.0))

	# Полный игнор мыши при активном локе
	if _is_locked and lock_enabled:
		_lock_timer += delta
		var remaining: float = wrapf(_locked_target_yaw - rotation.y, -PI, PI)
		var remaining_deg: float = abs(rad_to_deg(remaining))
		
		# УЛУЧШЕНО: Плавный переход скорости с моментумом
		var target_speed: float = back_rotation_speed if _lock_sector == Sector.BACK else lerp(base_rotation_speed, max_rotation_speed, clamp(remaining_deg / 180.0, 0.0, 1.0))
		current_rotation_speed = lerp(current_rotation_speed, target_speed, speed_transition_rate * delta)
		
		var max_step: float = current_rotation_speed * delta
		rotation.y += clamp(remaining, -max_step, max_step)
		if remaining_deg <= lock_epsilon_deg and _lock_timer >= lock_min_dwell:
			_is_locked = false
			_lock_sector = Sector.NONE
			_lock_timer = 0.0
		return

	var camera: Camera3D = _cached_camera if _cached_camera else get_viewport().get_camera_3d()
	if not _cached_camera:
		_cached_camera = camera
	if camera == null:
		current_rotation_speed *= momentum_decay
		return

	var ray_origin: Vector3 = camera.project_ray_origin(mouse_pos)
	var ray_dir: Vector3 = camera.project_ray_normal(mouse_pos)

	# НОВОЕ: Предсказание позиции мыши для более плавного следования
	var predicted_mouse_pos = mouse_pos + mouse_velocity * mouse_prediction_strength
	var predicted_ray_origin = camera.project_ray_origin(predicted_mouse_pos)
	var predicted_ray_dir = camera.project_ray_normal(predicted_mouse_pos)

	# Проекция на Y = y игрока
	var player_y: float = global_transform.origin.y
	var target_world: Vector3
	var have_target: bool = false
	
	# Используем предсказанную позицию для расчета цели
	if absf(predicted_ray_dir.y) > 0.0001:
		var t: float = (player_y - predicted_ray_origin.y) / predicted_ray_dir.y
		if t > 0.0 and t <= mouse_ray_length:
			target_world = predicted_ray_origin + predicted_ray_dir * t
			have_target = true
	if not have_target:
		current_rotation_speed *= momentum_decay
		return

	# Вектор до цели в XZ
	var to_target: Vector3 = target_world - global_transform.origin
	to_target.y = 0.0
	if to_target.length() < min_mouse_distance:
		to_target = last_look_dir
	else:
		last_look_dir = to_target.normalized()

	# Текущее направление вперёд
	var fwd: Vector3 = -global_transform.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.0001 or to_target.length() < 0.001:
		current_rotation_speed *= momentum_decay
		return
	fwd = fwd.normalized()
	var tgt: Vector3 = to_target.normalized()

	# Подписанный угол и целевой yaw
	var cross_y: float = fwd.cross(tgt).y
	var dot_ft: float = clamp(fwd.dot(tgt), -1.0, 1.0)
	var delta_yaw_raw: float = atan2(cross_y, dot_ft)
	var target_yaw_raw: float = rotation.y + delta_yaw_raw

	# УЛУЧШЕНО: Экспоненциальное или линейное сглаживание
	if not _have_smoothed:
		_smoothed_target_yaw = target_yaw_raw
		_have_smoothed = true
	else:
		if exponential_smoothing:
			# Экспоненциальное сглаживание - более естественное
			var smooth_rate = angle_smoothing_speed * (1.0 + speed_factor * 0.5) # Быстрее при быстром движении мыши
			var smooth_factor = 1.0 - exp(-smooth_rate * delta)
			_smoothed_target_yaw = lerp_angle(_smoothed_target_yaw, target_yaw_raw, smooth_factor)
		else:
			# Оригинальное линейное сглаживание
			_smoothed_target_yaw = lerp_angle(_smoothed_target_yaw, target_yaw_raw, angle_smoothing_speed * delta)

	var delta_yaw: float = wrapf(_smoothed_target_yaw - rotation.y, -PI, PI)
	var angle_diff_deg: float = abs(rad_to_deg(delta_yaw))
	if angle_diff_deg < noise_floor_deg:
		yaw_timer = 0.0
		current_rotation_speed *= momentum_decay
		return

	# Сектора и мёртвые зоны
	var front_half: float = front_sector_deg * 0.5
	var front_dead_half: float = yaw_sector_deg * 0.5
	var in_front_now: bool = angle_diff_deg <= front_half
	var in_front_dead: bool = angle_diff_deg <= front_dead_half

	var back_offset: float = absf(angle_diff_deg - 180.0)
	var back_active_half: float = back_slow_sector_deg * 0.5
	var back_dead_half: float = back_deadzone_deg * 0.5
	var in_back_now: bool = back_offset <= back_active_half
	var in_back_dead: bool = back_offset <= back_dead_half

	# Гистерезис фронта
	var enter_th: float = max(0.0, front_half - front_hysteresis_deg)
	var exit_th: float = front_half + front_hysteresis_deg
	if _in_front_sector:
		if angle_diff_deg > exit_th:
			_in_front_sector = false
	else:
		if angle_diff_deg < enter_th:
			_in_front_sector = true

	# Мёртвые зоны — без поворота
	if in_front_now and in_front_dead:
		yaw_timer = 0.0
		current_rotation_speed *= momentum_decay
		return
	if in_back_now and in_back_dead:
		yaw_timer = 0.0
		current_rotation_speed *= momentum_decay
		return

	# УЛУЧШЕНО: Фронт актив: задержка -> лок -> первый шаг с плавными переходами
	if in_front_now:
		var dyn_delay_front: float = lerp(rotation_delay_min, rotation_delay_max, clamp(angle_diff_deg / 180.0, 0.0, 1.0)) * adaptive_delay_mult
		yaw_timer += delta
		if yaw_timer < dyn_delay_front:
			current_rotation_speed *= momentum_decay
			return
		if lock_enabled:
			_is_locked = true
			_locked_target_yaw = rotation.y + delta_yaw
			_lock_sector = Sector.FRONT
			_lock_timer = 0.0

		var speed_factor_front: float = clamp((angle_diff_deg - front_dead_half) / max(0.001, (front_half - front_dead_half)), 0.0, 1.0)
		var t_factor: float = clamp(angle_diff_deg / 180.0, 0.0, 1.0)
		var target_speed_front: float = lerp(base_rotation_speed, max_rotation_speed, t_factor) * speed_factor_front
		
		# НОВОЕ: Плавный переход к целевой скорости
		current_rotation_speed = lerp(current_rotation_speed, target_speed_front, speed_transition_rate * delta)
		var max_step: float = current_rotation_speed * delta
		rotation.y += clamp(delta_yaw, -max_step, max_step)
		yaw_timer = 0.0
		return

	# УЛУЧШЕНО: Спина актив: задержка -> лок -> первый шаг (медленно) с плавными переходами
	if in_back_now:
		var back_delay = back_rotation_delay * adaptive_delay_mult
		yaw_timer += delta
		if yaw_timer < back_delay:
			current_rotation_speed *= momentum_decay
			return
		if lock_enabled:
			_is_locked = true
			_locked_target_yaw = rotation.y + delta_yaw
			_lock_sector = Sector.BACK
			_lock_timer = 0.0

		var back_factor: float = clamp((back_offset - back_dead_half) / max(0.001, (back_active_half - back_dead_half)), 0.0, 1.0)
		var target_back_speed: float = max(0.1, back_rotation_speed * (0.35 + 0.65 * back_factor))
		
		# НОВОЕ: Плавный переход к задней скорости
		current_rotation_speed = lerp(current_rotation_speed, target_back_speed, speed_transition_rate * delta)
		var max_step_back: float = current_rotation_speed * delta
		rotation.y += clamp(delta_yaw, -max_step_back, max_step_back)
		yaw_timer = 0.0
		return

	# Боковые зоны — игнор с затуханием моментума
	yaw_timer = 0.0
	current_rotation_speed *= momentum_decay

func set_rotation_enabled(enabled: bool) -> void:
	_rotation_enabled = enabled
	
# Добавить в конец Player.gd:
func get_sprint_blend() -> float:
	return _sprint_blend

func is_currently_sprinting() -> bool:
	return Input.is_action_pressed("sprint") and Vector2(velocity.x, velocity.z).length() > walk_speed * 1.1

func _draw_debug_visuals() -> void:
	if not debug_visuals_node or _debug_mesh == null or not show_debug:
		# Скрываем узел если дебаг выключен
		if debug_visuals_node:
			debug_visuals_node.visible = false
		return

	# Показываем DebugVisuals и позиционируем относительно игрока
	debug_visuals_node.visible = show_debug
	debug_visuals_node.global_transform.origin = global_transform.origin

	_debug_mesh.clear_surfaces()
	_debug_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _debug_material)

	var origin: Vector3 = Vector3.ZERO
	var segments: int = 36
	var base_radius: float = 3.5

	# Направление вперед и назад
	var forward: Vector3 = -global_transform.basis.z
	forward.y = 0
	if forward.length() < 0.0001:
		forward = Vector3.FORWARD
	else:
		forward = forward.normalized()
	var backward: Vector3 = -forward

	# Определяем сектора: направление, радиус, угол, имя, цвет
	var sectors = [
		{"dir": forward, "radius": base_radius, "angle": front_sector_deg, "name": "Front", "color": Color(0,1,0,1)},
		{"dir": forward, "radius": base_radius * 1.05, "angle": yaw_sector_deg, "name": "Yaw", "color": Color(1,1,0,1)},
		{"dir": backward, "radius": base_radius, "angle": back_slow_sector_deg, "name": "BackSlow", "color": Color(1,0.5,0,1)},
		{"dir": backward, "radius": base_radius * 1.05, "angle": back_deadzone_deg, "name": "BackDead", "color": Color(1,0,0,1)}
	]

	for i in range(sectors.size()):
		var s = sectors[i]
		_draw_debug_arc_with_label(origin, s.dir, s.radius, s.angle, s.name, s.color, segments, i)

	# Длинная линия вперед
	_debug_mesh.surface_set_color(Color(0.8,0.8,0.8,1))
	_debug_mesh.surface_add_vertex(origin)
	_debug_mesh.surface_add_vertex(origin + forward * (base_radius * 1.5))

	_debug_mesh.surface_end()


func _draw_debug_arc_with_label(origin: Vector3, direction: Vector3, radius: float, angle_deg: float, name: String, color: Color, segments: int, index: int) -> void:
	if segments < 2:
		segments = 2

	var angle_rad: float = deg_to_rad(angle_deg)
	var half: float = angle_rad * 0.5
	var base_angle: float = atan2(direction.x, direction.z)

	var first_point: Vector3 = origin + Vector3(sin(base_angle - half), 0, cos(base_angle - half)) * radius
	var prev_point: Vector3 = first_point

	# ---- линии дуги ----
	for i in range(1, segments + 1):
		var t: float = float(i) / float(segments)
		var ang: float = base_angle + lerp(-half, half, t)
		var curr: Vector3 = origin + Vector3(sin(ang), 0, cos(ang)) * radius

		_debug_mesh.surface_set_color(color)
		_debug_mesh.surface_add_vertex(prev_point)
		_debug_mesh.surface_set_color(color)
		_debug_mesh.surface_add_vertex(curr)

		prev_point = curr

	# ---- лучи от центра ----
	_debug_mesh.surface_set_color(color)
	_debug_mesh.surface_add_vertex(origin)
	_debug_mesh.surface_add_vertex(first_point)

	_debug_mesh.surface_set_color(color)
	_debug_mesh.surface_add_vertex(origin)
	_debug_mesh.surface_add_vertex(prev_point)

	# ---- Лейбл ----
	_draw_debug_label(origin, direction, radius, angle_deg, name, color, index)


func _draw_debug_label(origin: Vector3, direction: Vector3, radius: float, angle_deg: float, name: String, color: Color, index: int) -> void:
	if not show_debug:
		return
	
	var lbl: Label3D
	if name in _debug_label_map:
		lbl = _debug_label_map[name]
	else:
		lbl = Label3D.new()
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.modulate = color
		lbl.font_size = 100
		debug_visuals_node.add_child(lbl)
		_debug_label_map[name] = lbl

	lbl.text = "%s: %d°" % [name, int(angle_deg)]
	lbl.visible = show_debug

	# Смещение лейбла, чтобы они не накладывались: радиальное + вертикальное + по индексу
	var radial_offset = direction * (radius + 1.0)
	var vertical_offset = Vector3(0, 0.5 + 0.25 * index, 0)
	var side_offset = Vector3(0.2 * index, 0, 0)  # небольшое смещение по X, если дуги близко
	lbl.global_transform.origin = debug_visuals_node.global_transform.origin + radial_offset + vertical_offset + side_offset
