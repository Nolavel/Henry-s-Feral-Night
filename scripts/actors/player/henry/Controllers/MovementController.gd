extends Node3D
class_name MovementController

# === ССЫЛКИ НА КОМПОНЕНТЫ ===
@export var stamina_manager: StaminaManager

# === ПАРАМЕТРЫ ДВИЖЕНИЯ ===
@export_group("Параметры движения")
@export var walk_speed: float = 4.0
@export var sprint_speed: float = 8.0
@export var gravity: float = 9.8
@export var max_floor_angle: float = 45.0  # НОВОЕ: максимальный угол подъёма (в градусах)
@export var floor_snap_length: float = 0.1  # НОВОЕ: "прилипание" к полу

# === ПАРАМЕТРЫ СПРИНТА ===
@export_group("Параметры спринта")
@export var sprint_ramp_time: float = 1.0
@export var sprint_inertia_time: float = 0.6
@export var sprint_release_boost: float = 0.5

# === ПАРАМЕТРЫ ПРЫЖКА НА УДЕРЖАНИЕ ===
@export_group("Прыжок на удержание")
@export var jump_velocity: float = 5.0
@export var start_jump_impulse: float = 0.1

# === ЖИВОЙ РАЗГОН / ТОРМОЖЕНИЕ ===
@export_group("Живой разгон / торможение")
@export var accel_rate: float = 8.0
@export var decel_rate: float = 12.0
@export var slope_speed_multiplier: float = 1.3  # ИЗМЕНЕНО: множитель скорости на спуске
@export var slope_slowdown_multiplier: float = 0.7  # НОВОЕ: замедление при подъёме

# === DEBUG ===
@export_group("Debug")
@export var debug_show_speed: bool = false
@export var debug_label_path: NodePath

# === СЛУЖЕБНЫЕ ПЕРЕМЕННЫЕ ===
var _was_idle: bool = true
var _sprint_blend: float = 1.0
var _sprint_inertia_timer: float = 0.0
var _jump_hold_armed: bool = false
var _jump_release_fired_this_frame: bool = false
var _sprint_allowed: bool = true
var _debug_label: Label = null
var _was_on_floor_last_frame: bool = false

func _ready() -> void:
	if walk_speed <= 0.0:
		push_warning("Walk speed must be positive, setting to 4.0")
		walk_speed = 4.0
	if sprint_speed <= walk_speed:
		push_warning("Sprint speed must be greater than walk speed")
		sprint_speed = walk_speed * 2.0
		
	if stamina_manager:
		stamina_manager.sprint_allowed_changed.connect(_on_sprint_allowed_changed)

	if debug_show_speed and debug_label_path != NodePath():
		_debug_label = get_node_or_null(debug_label_path)
		if _debug_label == null:
			push_warning("Debug label path is invalid — speed display will not work.")

func process_movement(
	player: CharacterBody3D,
	delta: float,
	input_dir: Vector3,
	jump_just_pressed: bool,
	jump_is_pressed: bool,
	jump_just_released: bool,
	sprint_is_pressed: bool,
	sprint_just_released: bool
) -> void:
	_jump_release_fired_this_frame = false
	
	# Сохраняем состояние пола
	var was_on_floor = _was_on_floor_last_frame
	var on_floor_now = player.is_on_floor()
	_was_on_floor_last_frame = on_floor_now

	# === 1) Настройка физики CharacterBody3D ===
	player.floor_max_angle = deg_to_rad(max_floor_angle)
	player.floor_snap_length = floor_snap_length if on_floor_now else 0.0
	player.floor_stop_on_slope = true  # Предотвращает скольжение вниз

	# === 2) Гравитация ===
	if not on_floor_now:
		player.velocity.y -= gravity * delta
	else:
		# На полу - обнуляем вертикальную скорость (кроме прыжка)
		if player.velocity.y < 0:
			player.velocity.y = 0.0

	# === 3) Прыжок на удержание ===
	if on_floor_now:
		if jump_is_pressed:
			_jump_hold_armed = true
		if _jump_hold_armed and jump_just_released:
			if stamina_manager == null or stamina_manager.try_jump():
				player.velocity.y = jump_velocity
				_jump_release_fired_this_frame = true
				player.floor_snap_length = 0.0  # Отключаем snap при прыжке
			_jump_hold_armed = false
	if jump_just_released:
		_jump_hold_armed = false

	# === 4) Планарное направление движения ===
	var has_input: bool = input_dir.length() > 0.0
	var planar_dir: Vector3 = player.global_transform.basis * input_dir
	planar_dir.y = 0.0
	if planar_dir.length() > 1.0:
		planar_dir = planar_dir.normalized()

	# === 5) Влияние уклона (ИСПРАВЛЕНО) ===
	var slope_modifier: float = 1.0
	if on_floor_now and has_input:
		var floor_normal = player.get_floor_normal()
		var floor_angle_rad = acos(clamp(floor_normal.y, 0.0, 1.0))
		var floor_angle_deg = rad_to_deg(floor_angle_rad)
		
		# Проверяем, движемся ли мы вверх или вниз по склону
		if floor_angle_deg > 1.0:  # Есть наклон
			var movement_dot = planar_dir.normalized().dot(-floor_normal.slide(Vector3.UP).normalized())
			
			if movement_dot > 0.1:  # Движемся ВНИЗ по склону
				# Ускоряемся на спуске (чем круче, тем быстрее)
				var slope_factor = clamp(floor_angle_deg / max_floor_angle, 0.0, 1.0)
				slope_modifier = lerp(1.0, slope_speed_multiplier, slope_factor)
			elif movement_dot < -0.1:  # Движемся ВВЕРХ по склону
				# Замедляемся при подъёме (чем круче, тем медленнее)
				var slope_factor = clamp(floor_angle_deg / max_floor_angle, 0.0, 1.0)
				slope_modifier = lerp(1.0, slope_slowdown_multiplier, slope_factor)

	# === 6) Плавный спринт с системой стамины ===
	var sprint_multiplier: float = sprint_speed / max(walk_speed, 0.001)
	var should_sprint: bool = sprint_is_pressed and has_input and _sprint_allowed

	if should_sprint and stamina_manager:
		if not stamina_manager.is_consuming_stamina:
			stamina_manager.start_consuming_stamina()
	elif stamina_manager and stamina_manager.is_consuming_stamina:
		stamina_manager.stop_consuming_stamina()

	if should_sprint:
		var up_rate: float = delta / sprint_ramp_time
		_sprint_blend = lerp(_sprint_blend, sprint_multiplier, up_rate)
		_sprint_inertia_timer = 0.0
	elif _sprint_blend > 1.0:
		if sprint_just_released and has_input and on_floor_now:
			_sprint_inertia_timer = sprint_inertia_time
			if planar_dir.length() > 0.0 and sprint_release_boost > 0.0:
				var dir: Vector3 = planar_dir.normalized()
				player.velocity.x += dir.x * sprint_release_boost
				player.velocity.z += dir.z * sprint_release_boost

		if not _sprint_allowed and _sprint_inertia_timer <= 0.0:
			_sprint_inertia_timer = sprint_inertia_time * 1.5

		var down_rate: float = delta / (_sprint_inertia_timer if _sprint_inertia_timer > 0.0 else sprint_inertia_time)
		_sprint_blend = lerp(_sprint_blend, 1.0, down_rate)
		_sprint_inertia_timer = max(0.0, _sprint_inertia_timer - delta)
	else:
		var down_rate: float = delta / sprint_inertia_time
		_sprint_blend = lerp(_sprint_blend, 1.0, down_rate)

	# === 7) Целевая скорость С учётом уклона ===
	var target_speed: float = walk_speed * _sprint_blend * slope_modifier
	var target_vel: Vector3 = planar_dir * target_speed

	# === 8) Разгон / торможение ===
	var current_planar_speed: float = Vector3(player.velocity.x, 0.0, player.velocity.z).length()
	var rate: float = accel_rate if target_vel.length() > current_planar_speed else decel_rate

	# ВАЖНО: используем move_toward для более точного контроля
	var current_planar_vel = Vector3(player.velocity.x, 0.0, player.velocity.z)
	var new_planar_vel = current_planar_vel.move_toward(target_vel, rate * delta * max(walk_speed, 1.0))
	
	player.velocity.x = new_planar_vel.x
	player.velocity.z = new_planar_vel.z

	# === 9) Лёгкий толчок при старте ===
	if _was_idle and has_input and on_floor_now:
		player.velocity.y += start_jump_impulse
	_was_idle = not has_input

	# === 10) DEBUG: вывод скорости ===
	if debug_show_speed and _debug_label != null:
		var speed: float = Vector3(player.velocity.x, 0.0, player.velocity.z).length()
		var floor_angle: float = 0.0
		if on_floor_now:
			floor_angle = rad_to_deg(acos(clamp(player.get_floor_normal().y, 0.0, 1.0)))
		_debug_label.text = "Speed: %.2f | Angle: %.1f° | Slope: %.2fx" % [speed, floor_angle, slope_modifier]

func get_sprint_blend() -> float:
	var sprint_multiplier: float = sprint_speed / max(walk_speed, 0.001)
	var blend_progress: float = (_sprint_blend - 1.0) / (sprint_multiplier - 1.0)
	return clamp(blend_progress, 0.0, 1.0)

func is_currently_sprinting(player_velocity: Vector3) -> bool:
	return Input.is_action_pressed("sprint") and Vector2(player_velocity.x, player_velocity.z).length() > walk_speed

func get_jump_release_fired() -> bool:
	return _jump_release_fired_this_frame

func set_sprint_allowed(allowed: bool) -> void:
	_sprint_allowed = allowed

func get_stamina_ratio() -> float:
	if stamina_manager:
		return stamina_manager.get_stamina_ratio()
	return 1.0

func is_sprint_available() -> bool:
	if stamina_manager:
		return stamina_manager.is_sprint_allowed()
	return true

func is_stamina_recovering() -> bool:
	if stamina_manager:
		return stamina_manager.is_recovering()
	return false
	
func _on_sprint_allowed_changed(is_allowed: bool) -> void:
	_sprint_allowed = is_allowed
