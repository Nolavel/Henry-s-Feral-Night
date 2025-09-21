extends Camera3D
class_name PlayerCamera

@export var player: CharacterBody3D

# === Базовые параметры камеры ===
@export_group("Base Camera Settings")
@export var base_follow_distance: float = 8.0
@export var height: float = 6.0
@export var look_at_height: float = 1.5

@export var rotation_lag_speed: float = 4.0
@export var follow_speed_base: float = 5.0
@export var follow_speed_max: float = 8.0
@export var yaw_deadzone_deg: float = 2.0

# === Эффекты движения ===
@export_group("Sprint Effects")
@export var sprint_zoom_distance: float = 2.5
@export var sprint_zoom_speed: float = 5.0
@export var sprint_tilt_amount: float = 15.0
@export var sprint_tilt_speed: float = 5.0
@export var sprint_height_offset: float = -2.5
@export var sprint_pitch_up: float = -25.0
@export var sprint_transition_speed: float = 5.0

@export_group("Jump Effects")
@export var jump_tilt_amount: float = 15.0
@export var jump_tilt_speed: float = 8.0
var _jump_tilt_angle: float = 0.0
var _was_on_floor: bool = true

# === Орбитальный режим ===
@export_group("Orbit Settings")
@export var orbit_angle_max: float = 180.0
@export var orbit_speed: float = 6.0
var _orbit_offset: float = 0.0
var _orbit_active: bool = false

# === Сглаживание и кинематографичность ===
@export_group("Smoothing & Cinematic")
@export var yaw_smooth_time: float = 0.95
@export var fov_smooth_time: float = 0.45
@export var position_smooth_time: float = 0.6
var _pos_velocity := Vector3.ZERO

@export var turn_tilt_amount: float = 10.0
@export var turn_tilt_speed: float = 5.0
var _turn_tilt: float = 0.0

# === Параметры FOV ===
@export_group("FOV Settings")
@export var base_fov: float = 75.0
@export var sprint_fov: float = 90.0
@export var fov_change_speed: float = 5.0

# === Коллизии камеры ===
@export_group("Collision Settings")
@export var collision_margin: float = 0.2

# === Автофокус и дыхание ===
@export_group("Idle Autofocus")
@export var idle_time_before_autofocus: float = 1.0
@export var autofocus_breath_amp: float = 0.05
@export var autofocus_breath_speed: float = 0.25
var _idle_timer: float = 0.0
var _breath_time: float = 0.0

# === Прозрачность объектов ===
@export_group("Transparency System")
@export var transparency_enabled: bool = true
@export var transparency_distance: float = 2.0
@export var transparency_value: float = 0.3
var _transparent_objects: Array = []
var _original_materials: Dictionary = {}

# === Внутреннее состояние ===
var current_yaw: float = 0.0
var _current_follow_distance: float
var _current_height_offset: float = 0.0
var _current_pitch_offset: float = 0.0
var _sprint_tilt_angle: float = 0.0
var _yaw_velocity: float = 0.0
var _fov_velocity: float = 0.0
var _current_pivot_offset: Vector3 = Vector3.ZERO
var _collision_raycast: RayCast3D = null



func _ready() -> void:
	if player:
		var fwd: Vector3 = -player.global_transform.basis.z
		current_yaw = atan2(fwd.x, fwd.z)
	else:
		current_yaw = 0.0
		push_warning("PlayerCamera: No player assigned!")
	_current_follow_distance = base_follow_distance
	fov = base_fov
	# Создаем RayCast для коллизий
	_collision_raycast = RayCast3D.new()
	add_child(_collision_raycast)
	_collision_raycast.enabled = true
	_collision_raycast.exclude_parent = true
	if player:
		_collision_raycast.add_exception(player)
		
	_validate_parameters()
	
func _validate_parameters() -> void:
	base_follow_distance = max(0.1, base_follow_distance)
	height = max(0.0, height)
	sprint_zoom_distance = max(0.1, sprint_zoom_distance)
	base_fov = clamp(base_fov, 30.0, 120.0)
	sprint_fov = clamp(sprint_fov, base_fov, 120.0)

func _physics_process(delta: float) -> void:
	if not player:
		return
	
	# Кеш инпута в начале
	var input_cache = {
		"orbit_right": Input.get_action_strength("orbit_right"),
		"orbit_left": Input.get_action_strength("orbit_left"),
		"sprint": Input.is_action_pressed("sprint")
	}
	
	var orbit_input: float = input_cache.orbit_right - input_cache.orbit_left
	var player_velocity_length = Vector3(player.velocity.x, 0, player.velocity.z).length()
	var is_sprinting: bool = input_cache.sprint and player_velocity_length > 0.1
	
	# ВАЖНО: Объявляем player_speed здесь, чтобы она была доступна везде в функции
	var player_speed: float = player_velocity_length
		
	# === Орбитальный поворот Q/E ===
	var target_orbit: float = deg_to_rad(orbit_angle_max) * orbit_input
	_orbit_offset = lerp(_orbit_offset, target_orbit, clamp(orbit_speed * delta, 0.0, 1.0))

	# Блокировка поворота игрока при орбите
	var orbit_now: bool = abs(orbit_input) > 0.01
	if orbit_now != _orbit_active:
		_orbit_active = orbit_now
		if "set_rotation_enabled" in player:
			player.set_rotation_enabled(not _orbit_active)

	# === Динамическое FOV ===
	var target_fov: float = base_fov
	if is_sprinting:
		target_fov = sprint_fov
	var fov_result = _smooth_damp(fov, target_fov, _fov_velocity, fov_smooth_time, delta)
	fov = fov_result[0]
	_fov_velocity = fov_result[1]



	# Дистанция
	var target_distance: float = sprint_zoom_distance if is_sprinting else base_follow_distance
	_current_follow_distance = lerp(_current_follow_distance, target_distance, clamp(sprint_zoom_speed * delta, 0.0, 1.0))

	# Вертикальное смещение
	var target_height_offset: float = sprint_height_offset if is_sprinting else 0.0
	_current_height_offset = lerp(_current_height_offset, target_height_offset, clamp(sprint_transition_speed * delta, 0.0, 1.0))

	# Pitch вверх
	var target_pitch_offset: float = sprint_pitch_up if is_sprinting else 0.0
	_current_pitch_offset = lerp(_current_pitch_offset, target_pitch_offset, clamp(sprint_transition_speed * delta, 0.0, 1.0))

	# Roll в сторону движения
	var target_sprint_tilt: float = 0.0
	if is_sprinting:
		var move_dir: Vector3 = Vector3.ZERO
		if player.velocity.length() > 0.001:
			move_dir = player.velocity.normalized()
		var right: Vector3 = player.global_transform.basis.x
		var side_dot: float = clamp(right.dot(move_dir), -1.0, 1.0)
		target_sprint_tilt = -side_dot * sprint_tilt_amount
	_sprint_tilt_angle = lerp(_sprint_tilt_angle, target_sprint_tilt, clamp(sprint_tilt_speed * delta, 0.0, 1.0))

	# === Прыжковый наклон (pitch) ===
	var on_floor: bool = player.is_on_floor()
	if _was_on_floor and not on_floor:
		_jump_tilt_angle = -jump_tilt_amount
	elif not _was_on_floor and on_floor:
		_jump_tilt_angle = jump_tilt_amount
	_was_on_floor = on_floor
	_jump_tilt_angle = lerp(_jump_tilt_angle, 0.0, clamp(jump_tilt_speed * delta, 0.0, 1.0))

	# === Базовое слежение с лагом ===
	#var facing_yaw: float = player.rotation.y
	# === Базовое слежение с лагом (инерция) ===
	#var facing_yaw: float = player.rotation.y
	#current_yaw = _smooth_damp_angle(current_yaw, facing_yaw, _yaw_velocity, 0.25, delta)
#
	#var angle_err: float = _angle_diff(current_yaw, facing_yaw)
	#var speed_factor: float = clamp(angle_err / deg_to_rad(yaw_deadzone_deg), 0.0, 1.0)
	#if angle_err > deg_to_rad(yaw_deadzone_deg):
		#current_yaw = lerp_angle(current_yaw, facing_yaw, rotation_lag_speed * delta * speed_factor)
	var facing_yaw: float = player.rotation.y
	#current_yaw = lerp_angle(current_yaw, facing_yaw, clamp(1.0 * delta, 0.0, 1.0)) # 2.0 — скорость догонки
	var yaw_result = _smooth_damp_angle(current_yaw, facing_yaw, _yaw_velocity, yaw_smooth_time, delta)
	current_yaw = yaw_result[0]
	_yaw_velocity = yaw_result[1]


	# Горизонтальный оффсет с учётом орбиты
	var forward_dir: Vector3 = Vector3.FORWARD.rotated(Vector3.UP, current_yaw + _orbit_offset)
	var horizontal_offset: Vector3 = -forward_dir.normalized() * _current_follow_distance

	# follow_speed зависит от скорости игрока
	var player_sprint_speed = player.sprint_speed if "sprint_speed" in player else 8.0
	var dyn_follow_speed: float = lerp(follow_speed_base, follow_speed_max, clamp(player_speed / player_sprint_speed, 0.0, 1.0))
	
	# Позиция камеры
	var player_pos: Vector3 = player.global_transform.origin
	# Смещаем pivot в сторону при прицеливании
	var pivot_pos: Vector3 = player_pos + _current_pivot_offset
	var target_pos: Vector3 = pivot_pos + horizontal_offset
	target_pos.y = player_pos.y + height + _current_height_offset
	
	var final_pos = _check_camera_collision(player_pos, target_pos, delta)
	#global_transform.origin = global_transform.origin.lerp(final_pos, dyn_follow_speed * delta)
	var pos_result = _smooth_damp_vec3(global_transform.origin, final_pos, _pos_velocity, position_smooth_time, delta)
	global_transform.origin = pos_result[0]
	_pos_velocity = pos_result[1]

	
	# === Auto‑focus ===
	var is_camera_colliding = _collision_raycast and _collision_raycast.is_colliding()
	if player_speed < 0.1 and not is_camera_colliding:
		_idle_timer += delta
		if _idle_timer > idle_time_before_autofocus:
			_breath_time += delta * autofocus_breath_speed
			var breath = sin(_breath_time) * autofocus_breath_amp
			global_transform.origin.y += breath
	else:
		_idle_timer = 0.0
		_breath_time = 0.0

	## === Применяем наклоны ===
	#rotation_degrees.x = _jump_tilt_angle + _current_pitch_offset
	#rotation_degrees.z = _sprint_tilt_angle
	# === Применяем наклоны ===
	rotation_degrees.x = _jump_tilt_angle + _current_pitch_offset

	# Вычисляем наклон при повороте
	var yaw_delta = wrapf(facing_yaw - current_yaw, -PI, PI)
	var target_turn_tilt = clamp(yaw_delta * turn_tilt_amount, -turn_tilt_amount, turn_tilt_amount)
	_turn_tilt = lerp(_turn_tilt, target_turn_tilt, clamp(turn_tilt_speed * delta, 0.0, 1.0))

	# Суммируем наклон от спринта и от поворота
	rotation_degrees.z = _sprint_tilt_angle + _turn_tilt


	# Смотрим на игрока
	var look_point: Vector3 = player_pos + Vector3.UP * look_at_height
	if global_position.distance_to(look_point) > 0.01:
		look_at(look_point, Vector3.UP)
		


func _angle_diff(a: float, b: float) -> float:
	return absf(atan2(sin(b - a), cos(b - a)))

#func smooth_damp(current: float, target: float, speed: float, delta: float) -> float:
	#return lerp(current, target, 1.0 - exp(-speed * delta))
	
#func smooth_damp(current: float, target: float, speed: float, delta: float) -> float:
	#if is_nan(current) or is_nan(target):
		#push_error("NaN detected in smooth_damp")
		#return target
	#
	#var factor = 1.0 - exp(-speed * delta)
	#return lerp(current, target, clamp(factor, 0.0, 1.0))
	
# Плавное сглаживание угла с учётом перехода через 360°
func _smooth_damp_angle(current: float, target: float, velocity: float, smooth_time: float, delta: float) -> Array:
	var num = fmod((target - current + PI), TAU)
	if num < 0.0:
		num += TAU
	num -= PI
	target = current + num
	return _smooth_damp(current, target, velocity, smooth_time, delta)


# Плавное сглаживание значения с инерцией (возвращает [новое_значение, новая_скорость])
func _smooth_damp(current: float, target: float, velocity: float, smooth_time: float, delta: float) -> Array:
	smooth_time = max(0.0001, smooth_time)
	var omega = 2.0 / smooth_time
	var x = omega * delta
	var exp = 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)
	var change = current - target
	var temp = (velocity + omega * change) * delta
	velocity = (velocity - omega * temp) * exp
	var output = target + (change + temp) * exp
	return [output, velocity]

func _smooth_damp_vec3(current: Vector3, target: Vector3, velocity: Vector3, smooth_time: float, delta: float) -> Array:
	return [
		Vector3(
			_smooth_damp(current.x, target.x, velocity.x, smooth_time, delta)[0],
			_smooth_damp(current.y, target.y, velocity.y, smooth_time, delta)[0],
			_smooth_damp(current.z, target.z, velocity.z, smooth_time, delta)[0]
		),
		Vector3(
			_smooth_damp(current.x, target.x, velocity.x, smooth_time, delta)[1],
			_smooth_damp(current.y, target.y, velocity.y, smooth_time, delta)[1],
			_smooth_damp(current.z, target.z, velocity.z, smooth_time, delta)[1]
		)
	]



func _check_camera_collision(from: Vector3, to: Vector3, delta: float) -> Vector3:
	if not _collision_raycast:
		return to
	
	_collision_raycast.global_position = from
	_collision_raycast.target_position = _collision_raycast.to_local(to)
	_collision_raycast.force_raycast_update()
	
	if _collision_raycast.is_colliding():
		var collision_point = _collision_raycast.get_collision_point()
		var collision_normal = _collision_raycast.get_collision_normal()
		
		# Плавно подтягиваем камеру с учетом margin
		var safe_point = collision_point + collision_normal * collision_margin
		
		# Дополнительно корректируем дистанцию следования
		var dist_to_player = from.distance_to(safe_point)
		_current_follow_distance = min(_current_follow_distance, dist_to_player)
		
		return safe_point
	
	# Восстанавливаем дистанцию когда коллизии нет
	var target_dist = sprint_zoom_distance if Input.is_action_pressed("sprint") else base_follow_distance
	_current_follow_distance = lerp(_current_follow_distance, target_dist, 2.0 * delta)
	
	return to
	
func _handle_transparency() -> void:
	if not transparency_enabled or not player:
		return
	
	# Восстанавливаем предыдущие объекты
	for obj in _transparent_objects:
		_restore_object_opacity(obj)
	_transparent_objects.clear()
	
	# Проверяем объекты между камерой и игроком
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		global_position,
		player.global_position + Vector3.UP * look_at_height
	)
	query.exclude = [self, player]
	query.collision_mask = 1  # Настроить под вашу маску коллизий
	
	var results = space_state.intersect_ray(query)
	if results:
		var collider = results.collider
		if collider is MeshInstance3D:
			_make_object_transparent(collider)

func _make_object_transparent(obj: MeshInstance3D) -> void:
	if not obj in _original_materials:
		_original_materials[obj] = obj.material_override
	
	# Создаем полупрозрачный материал
	var transparent_mat = StandardMaterial3D.new()
	if obj.material_override:
		transparent_mat = obj.material_override.duplicate()
	transparent_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	transparent_mat.albedo_color.a = transparency_value
	
	obj.material_override = transparent_mat
	_transparent_objects.append(obj)

func _restore_object_opacity(obj: MeshInstance3D) -> void:
	if obj in _original_materials:
		obj.material_override = _original_materials[obj]
		_original_materials.erase(obj)
