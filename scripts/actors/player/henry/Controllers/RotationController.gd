# rotation_controller.gd
extends Node3D
class_name RotationController

# === ПОВОРОТ — ФРОНТ ===
@export_group("Поворот — фронт")
@export var mouse_ray_length: float = 1000.0
@export var base_rotation_speed: float = 8.0
@export var max_rotation_speed: float = 15.0
@export var yaw_sector_deg: float = 45.0
@export var front_sector_deg: float = 140.0
@export var rotation_delay_min: float = 0.02
@export var rotation_delay_max: float = 0.15

# === ПОВОРОТ — СПИНА ===
@export_group("Поворот — спина")
@export var back_slow_sector_deg: float = 90.0
@export var back_deadzone_deg: float = 60.0
@export var back_rotation_speed: float = 3.0
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

# === НОВАЯ ГРУППА: ФИКСАЦИЯ КУРСОРА В ПРОСТРАНСТВЕ ===
@export_group("Фиксация курсора в пространстве")
@export var world_cursor_lock_enabled: bool = true
@export var cursor_lock_threshold_deg: float = 3.0  # Минимальный угол для активации блокировки
@export var cursor_lock_smooth_factor: float = 9.0   # Скорость перемещения курсора к зафиксированной точке
@export var cursor_unlock_threshold_deg: float = 1.5 # Угол, при котором снимается блокировка
@export var mouse_movement_threshold: float = 2.0    # Минимальное движение мыши в пикселях для разблокировки

# === ПАРАМЕТРЫ ДЕБАГА ===
@export_group("Дебаггинг")
@export var debug_visuals_node: MeshInstance3D
@export var show_debug: bool = false
var _debug_material: StandardMaterial3D = null
var _debug_mesh: ImmediateMesh = null
var _debug_labels: Array = []
var _debug_label_map := {}  # key = sector name, value = Label3D

# === СОСТОЯНИЕ ПОВОРОТА ===
var last_look_dir: Vector3 = Vector3.FORWARD
var yaw_timer: float = 0.0
var _in_front_sector: bool = true
var _smoothed_target_yaw: float = 0.0
var _have_smoothed: bool = false
var _rotation_enabled: bool = true

# === ДОП. СОСТОЯНИЕ ПОВОРОТА ===
var mouse_velocity: Vector2 = Vector2.ZERO
var last_mouse_pos: Vector2 = Vector2.ZERO
var current_rotation_speed: float = 0.0

# === ЛОК-РЕЖИМ ===
enum Sector { NONE, FRONT, BACK }
var _is_locked: bool = false
var _locked_target_yaw: float = 0.0
var _lock_sector: int = Sector.NONE
var _lock_timer: float = 0.0

# === SNAP СОСТОЯНИЕ ===
var _snap_active: bool = false
var _snap_elapsed: float = 0.0
var _snap_start_yaw: float = 0.0
var _snap_target_yaw: float = 0.0

# === НОВОЕ: СОСТОЯНИЕ ФИКСАЦИИ КУРСОРА В ПРОСТРАНСТВЕ ===
var _world_cursor_locked: bool = false
var _locked_world_position: Vector3 = Vector3.ZERO
var _target_mouse_pos: Vector2 = Vector2.ZERO
var _rotation_start_yaw: float = 0.0

# === КЕШИРОВАНИЕ ===
var _cached_camera: Camera3D = null
var _viewport: Viewport = null

var _mouse_locked: bool = false
var _lock_target_yaw: float = 0.0
var _saved_mouse_pos: Vector2
var _lock_complete_threshold_deg: float = 1.0

func _ready() -> void:
	var fwd: Vector3 = -global_transform.basis.z
	fwd.y = 0.0
	if fwd.length() > 0.0001:
		last_look_dir = fwd.normalized()
	_smoothed_target_yaw = rotation.y
	_have_smoothed = true
	
	_viewport = get_viewport()
	_cached_camera = _viewport.get_camera_3d() if _viewport else null

	front_sector_deg = clamp(front_sector_deg, 10.0, 180.0)
	yaw_sector_deg = clamp(yaw_sector_deg, 0.0, front_sector_deg)
	back_slow_sector_deg = clamp(back_slow_sector_deg, 0.0, 360.0)
	back_deadzone_deg = clamp(back_deadzone_deg, 0.0, back_slow_sector_deg)
	
	last_mouse_pos = _viewport.get_mouse_position()
	
	# Инициализация ImmediateMesh и назначение узлу MeshInstance3D
	_debug_mesh = ImmediateMesh.new()
	if debug_visuals_node:
		debug_visuals_node.mesh = _debug_mesh
		debug_visuals_node.visible = show_debug
	else:
		push_warning("DebugVisuals node not found")

func process_rotation(player: CharacterBody3D, delta: float, snap_just_activated: bool) -> void:
	if snap_just_activated:
		_start_snap_180(player)

	if _snap_active:
		_snap_elapsed += delta
		var t: float = clamp(_snap_elapsed / snap_turn_time, 0.0, 1.0)
		player.rotation.y = lerp_angle(_snap_start_yaw, _snap_target_yaw, t)

		_smoothed_target_yaw = player.rotation.y
		_have_smoothed = true
		current_rotation_speed = 0.0
		yaw_timer = 0.0
		
		if player.is_on_floor():
			player.velocity.y = max(player.velocity.y, snap_jump_strength)

		if _snap_elapsed >= snap_turn_time:
			_snap_active = false
			_have_smoothed = false
			_smoothed_target_yaw = player.rotation.y
		return

	if _rotation_enabled:
		_face_mouse_with_world_lock(player, delta)
		
	if show_debug and debug_visuals_node:
		_draw_debug_visuals()

func _start_snap_180(player: CharacterBody3D) -> void:
	_snap_active = true
	_snap_elapsed = 0.0
	_snap_start_yaw = player.rotation.y
	
	var current_mouse_angle := _get_mouse_angle_to_player(player)
	var snap_direction := 1.0 if current_mouse_angle > 0.0 else -1.0
	_snap_target_yaw = wrapf(player.rotation.y + PI * snap_direction, -PI, PI)

	_is_locked = false
	_lock_sector = Sector.NONE
	_lock_timer = 0.0
	yaw_timer = 0.0
	current_rotation_speed = 0.0

	_smoothed_target_yaw = player.rotation.y
	_have_smoothed = true
	
	# Сбрасываем блокировку курсора при снапе
	_reset_world_cursor_lock()

func _get_mouse_angle_to_player(player: CharacterBody3D) -> float:
	if not _cached_camera: return 0.0
	var mouse_pos = _viewport.get_mouse_position()
	
	# ИСПРАВЛЕНИЕ - использовать _cached_camera вместо несуществующей camera:
	var ray_origin = _cached_camera.project_ray_origin(mouse_pos)
	var ray_dir = _cached_camera.project_ray_normal(mouse_pos)
	
	var player_y = player.global_transform.origin.y
	if abs(ray_dir.y) > 0.0001:
		var t = (player_y - ray_origin.y) / ray_dir.y
		if t > 0.0:
			var target_world = ray_origin + ray_dir * t
			var to_target = target_world - player.global_transform.origin
			to_target.y = 0.0
			var fwd = -player.global_transform.basis.z
			fwd.y = 0.0
			if fwd.length_squared() > 0.00000001 and to_target.length_squared() > 0.000001:
				return atan2(fwd.cross(to_target.normalized()).y, fwd.dot(to_target.normalized()))
	return 0.0

func _face_mouse_with_world_lock(player: CharacterBody3D, delta: float) -> void:
	if _snap_active: return

	var mouse_pos: Vector2 = _viewport.get_mouse_position()
	mouse_velocity = (mouse_pos - last_mouse_pos) / delta if delta > 0.0 else Vector2.ZERO
	last_mouse_pos = mouse_pos
	var mouse_speed = mouse_velocity.length()
	
	# КЛЮЧЕВОЕ ИЗМЕНЕНИЕ: Проверяем движение мыши для мгновенной разблокировки
	if _world_cursor_locked and mouse_speed > mouse_movement_threshold:
		_reset_world_cursor_lock()
		if show_debug:
			print("World cursor lock released due to mouse movement")
	
	var speed_factor = clamp(mouse_speed / 100.0, 0.1, 2.0)
	var adaptive_delay_mult = lerp(1.0, adaptive_delay_factor, clamp(speed_factor - 0.5, 0.0, 1.0))

	# Обработка заблокированного состояния
	if _is_locked and lock_enabled:
		_handle_locked_rotation(player, delta)
		return

	var camera: Camera3D = _cached_camera if _cached_camera else get_viewport().get_camera_3d()
	if not _cached_camera: _cached_camera = camera
	if camera == null:
		current_rotation_speed *= momentum_decay
		return

	# Определяем, какую позицию мыши использовать
	var effective_mouse_pos = mouse_pos
	if world_cursor_lock_enabled and _world_cursor_locked:
		effective_mouse_pos = _get_effective_mouse_position(player, camera, delta)

	var ray_origin: Vector3 = camera.project_ray_origin(effective_mouse_pos)
	var ray_dir: Vector3 = camera.project_ray_normal(effective_mouse_pos)

	# Кэшируем предсказание только если есть движение
	var predicted_ray_origin: Vector3
	var predicted_ray_dir: Vector3
	if mouse_velocity.length_squared() > 0.01:
		var predicted_mouse_pos = effective_mouse_pos + mouse_velocity * mouse_prediction_strength
		predicted_ray_origin = camera.project_ray_origin(predicted_mouse_pos)
		predicted_ray_dir = camera.project_ray_normal(predicted_mouse_pos)
	else:
		predicted_ray_origin = ray_origin
		predicted_ray_dir = ray_dir

	var player_y: float = player.global_transform.origin.y
	var target_world: Vector3
	var have_target: bool = false
	
	if absf(predicted_ray_dir.y) > 0.0001:
		var t: float = (player_y - predicted_ray_origin.y) / predicted_ray_dir.y
		if t > 0.0 and t <= mouse_ray_length:
			target_world = predicted_ray_origin + predicted_ray_dir * t
			have_target = true
	
	if not have_target:
		current_rotation_speed *= momentum_decay
		return

	var to_target: Vector3 = target_world - player.global_transform.origin
	to_target.y = 0.0
	if to_target.length() < min_mouse_distance:
		to_target = last_look_dir
	else:
		last_look_dir = to_target.normalized()

	var fwd: Vector3 = -player.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.0001 or to_target.length() < 0.001:
		current_rotation_speed *= momentum_decay
		return
	fwd = fwd.normalized()
	var tgt: Vector3 = to_target.normalized()

	var cross_y: float = fwd.cross(tgt).y
	var dot_ft: float = clamp(fwd.dot(tgt), -1.0, 1.0)
	var delta_yaw_raw: float = atan2(cross_y, dot_ft)
	var target_yaw_raw: float = player.rotation.y + delta_yaw_raw

	if not _have_smoothed:
		_smoothed_target_yaw = target_yaw_raw
		_have_smoothed = true
	else:
		if exponential_smoothing:
			var smooth_rate = angle_smoothing_speed * (1.0 + speed_factor * 0.5)
			var smooth_factor = 1.0 - exp(-smooth_rate * delta)
			_smoothed_target_yaw = lerp_angle(_smoothed_target_yaw, target_yaw_raw, smooth_factor)
		else:
			_smoothed_target_yaw = lerp_angle(_smoothed_target_yaw, target_yaw_raw, angle_smoothing_speed * delta)

	var delta_yaw: float = wrapf(_smoothed_target_yaw - player.rotation.y, -PI, PI)
	var angle_diff_deg: float = abs(rad_to_deg(delta_yaw))
	
	if angle_diff_deg < noise_floor_deg:
		yaw_timer = 0.0
		current_rotation_speed *= momentum_decay
		_check_world_cursor_unlock(angle_diff_deg)
		return

	# Активация блокировки курсора в пространстве ТОЛЬКО если курсор неподвижен
	if world_cursor_lock_enabled and not _world_cursor_locked and angle_diff_deg >= cursor_lock_threshold_deg and mouse_speed <= mouse_movement_threshold:
		_activate_world_cursor_lock(player, camera, mouse_pos, target_world)

	var front_half: float = front_sector_deg * 0.5
	var front_dead_half: float = yaw_sector_deg * 0.5
	var in_front_now: bool = angle_diff_deg <= front_half
	#var in_front_dead: bool = (angle_diff_deg <= front_dead_half) and in_front_now
	var in_front_dead: bool = angle_diff_deg <= front_dead_half

	var back_offset: float = absf(angle_diff_deg - 180.0)
	var back_active_half: float = back_slow_sector_deg * 0.5
	var back_dead_half: float = back_deadzone_deg * 0.5
	var in_back_now: bool = back_offset <= back_active_half
	#var in_back_dead: bool = (back_offset <= back_dead_half) and in_back_now
	var in_back_dead: bool = back_offset <= back_dead_half

	var enter_th: float = max(0.0, front_half - front_hysteresis_deg)
	var exit_th: float = front_half + front_hysteresis_deg
	if _in_front_sector:
		if angle_diff_deg > exit_th:
			_in_front_sector = false
	else:
		if angle_diff_deg < enter_th:
			_in_front_sector = true

	if in_front_now and in_front_dead:
		yaw_timer = 0.0
		current_rotation_speed *= momentum_decay
		_check_world_cursor_unlock(angle_diff_deg)
		return  # ЭТО ПРАВИЛЬНО - НО ПРОБЛЕМА В ПЕРЕМЕННОЙ in_front_dead
	if in_back_now and in_back_dead:
		yaw_timer = 0.0
		current_rotation_speed *= momentum_decay
		_check_world_cursor_unlock(angle_diff_deg)
		return

	#if in_front_now:
		#_handle_front_rotation(player, delta, angle_diff_deg, delta_yaw, front_dead_half, front_half, adaptive_delay_mult)
		#return
#
	#if in_back_now:
		#_handle_back_rotation(player, delta, angle_diff_deg, delta_yaw, back_offset, back_dead_half, back_active_half, adaptive_delay_mult)
		#return
		#
		## Если не в активной зоне - останавливаем поворот
	#if not in_front_now and not in_back_now:
		#yaw_timer = 0.0
		#current_rotation_speed *= momentum_decay
		#_check_world_cursor_unlock(angle_diff_deg)
		#return

	#yaw_timer = 0.0
	#current_rotation_speed *= momentum_decay
	#_check_world_cursor_unlock(angle_diff_deg)
	if in_front_now:
		_handle_front_rotation(player, delta, angle_diff_deg, delta_yaw, front_dead_half, front_half, adaptive_delay_mult)
	elif in_back_now:
		_handle_back_rotation(player, delta, angle_diff_deg, delta_yaw, back_offset, back_dead_half, back_active_half, adaptive_delay_mult)
	else:
		# Не в активной зоне - останавливаем поворот
		yaw_timer = 0.0
		current_rotation_speed *= momentum_decay
		_check_world_cursor_unlock(angle_diff_deg)
# === НОВЫЕ МЕТОДЫ ДЛЯ РАБОТЫ С БЛОКИРОВКОЙ КУРСОРА ===

func _activate_world_cursor_lock(player: CharacterBody3D, camera: Camera3D, mouse_pos: Vector2, target_world: Vector3) -> void:
	_world_cursor_locked = true
	_locked_world_position = target_world
	_rotation_start_yaw = player.rotation.y
	
	# Запоминаем текущую позицию мыши как начальную целевую
	_target_mouse_pos = mouse_pos
	
	if show_debug:
		print("World cursor lock activated at: ", _locked_world_position)

func _get_effective_mouse_position(player: CharacterBody3D, camera: Camera3D, delta: float) -> Vector2:
	# Проецируем зафиксированную мировую точку обратно на экран
	var projected_pos = camera.unproject_position(_locked_world_position)
	
	# Плавно перемещаем целевую позицию курсора к проекции
	_target_mouse_pos = _target_mouse_pos.lerp(projected_pos, cursor_lock_smooth_factor * delta)
	
	return _target_mouse_pos

func _check_world_cursor_unlock(current_angle_diff_deg: float) -> void:
	if _world_cursor_locked and current_angle_diff_deg <= cursor_unlock_threshold_deg:
		_reset_world_cursor_lock()
		if show_debug:
			print("World cursor lock released")

func _reset_world_cursor_lock() -> void:
	_world_cursor_locked = false
	_locked_world_position = Vector3.ZERO
	_target_mouse_pos = get_viewport().get_mouse_position()

func _handle_locked_rotation(player: CharacterBody3D, delta: float) -> void:
	_lock_timer += delta
	var remaining: float = wrapf(_locked_target_yaw - player.rotation.y, -PI, PI)
	var remaining_deg: float = abs(rad_to_deg(remaining))
	
	var target_speed: float = back_rotation_speed if _lock_sector == Sector.BACK else lerp(base_rotation_speed, max_rotation_speed, clamp(remaining_deg / 180.0, 0.0, 1.0))
	current_rotation_speed = lerp(current_rotation_speed, target_speed, speed_transition_rate * delta)
	
	var max_step: float = current_rotation_speed * delta
	player.rotation.y += clamp(remaining, -max_step, max_step)
	
	if remaining_deg <= lock_epsilon_deg and _lock_timer >= lock_min_dwell:
		_is_locked = false
		_lock_sector = Sector.NONE
		_lock_timer = 0.0
		_check_world_cursor_unlock(remaining_deg)

func _handle_front_rotation(player: CharacterBody3D, delta: float, angle_diff_deg: float, delta_yaw: float, front_dead_half: float, front_half: float, adaptive_delay_mult: float) -> void:
	var dyn_delay_front: float = lerp(rotation_delay_min, rotation_delay_max, clamp(angle_diff_deg / 180.0, 0.0, 1.0)) * adaptive_delay_mult
	yaw_timer += delta
	if yaw_timer < dyn_delay_front:
		current_rotation_speed *= momentum_decay
		return
		
	if lock_enabled:
		_is_locked = true
		_locked_target_yaw = player.rotation.y + delta_yaw
		_lock_sector = Sector.FRONT
		_lock_timer = 0.0

	var speed_factor_front: float = clamp((angle_diff_deg - front_dead_half) / max(0.001, (front_half - front_dead_half)), 0.0, 1.0)
	var t_factor: float = clamp(angle_diff_deg / 180.0, 0.0, 1.0)
	var target_speed_front: float = lerp(base_rotation_speed, max_rotation_speed, t_factor) * speed_factor_front
	
	current_rotation_speed = lerp(current_rotation_speed, target_speed_front, speed_transition_rate * delta)
	var max_step: float = current_rotation_speed * delta
	player.rotation.y += clamp(delta_yaw, -max_step, max_step)
	yaw_timer = 0.0

func _handle_back_rotation(player: CharacterBody3D, delta: float, angle_diff_deg: float, delta_yaw: float, back_offset: float, back_dead_half: float, back_active_half: float, adaptive_delay_mult: float) -> void:
	var back_delay = back_rotation_delay * adaptive_delay_mult
	yaw_timer += delta
	if yaw_timer < back_delay:
		current_rotation_speed *= momentum_decay
		return
		
	if lock_enabled:
		_is_locked = true
		_locked_target_yaw = player.rotation.y + delta_yaw
		_lock_sector = Sector.BACK
		_lock_timer = 0.0

	var back_factor: float = clamp((back_offset - back_dead_half) / max(0.001, (back_active_half - back_dead_half)), 0.0, 1.0)
	var target_back_speed: float = max(0.1, back_rotation_speed * (0.35 + 0.65 * back_factor))
	
	current_rotation_speed = lerp(current_rotation_speed, target_back_speed, speed_transition_rate * delta)
	var max_step_back: float = current_rotation_speed * delta
	player.rotation.y += clamp(delta_yaw, -max_step_back, max_step_back)
	yaw_timer = 0.0

func set_rotation_enabled(enabled: bool) -> void:
	_rotation_enabled = enabled

func _draw_debug_visuals() -> void:
	if not show_debug: return
	if not debug_visuals_node or _debug_mesh == null:
		return

	debug_visuals_node.visible = show_debug
	debug_visuals_node.global_transform.origin = global_transform.origin

	_debug_mesh.clear_surfaces()
	_debug_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _debug_material)

	var origin: Vector3 = Vector3.ZERO
	var segments: int = 36
	var base_radius: float = 3.5

	var forward: Vector3 = -global_transform.basis.z
	forward.y = 0
	if forward.length() < 0.0001:
		forward = Vector3.FORWARD
	else:
		forward = forward.normalized()
	var backward: Vector3 = -forward

	var sectors = [
		{"dir": forward, "radius": base_radius, "angle": front_sector_deg, "name": "Front", "color": Color(0,1,0,1)},
		{"dir": forward, "radius": base_radius * 1.05, "angle": yaw_sector_deg, "name": "Yaw", "color": Color(1,1,0,1)},
		{"dir": backward, "radius": base_radius, "angle": back_slow_sector_deg, "name": "BackSlow", "color": Color(1,0.5,0,1)},
		{"dir": backward, "radius": base_radius * 1.05, "angle": back_deadzone_deg, "name": "BackDead", "color": Color(1,0,0,1)}
	]

	for i in range(sectors.size()):
		var s = sectors[i]
		_draw_debug_arc_with_label(origin, s.dir, s.radius, s.angle, s.name, s.color, segments, i)

	_debug_mesh.surface_set_color(Color(0.8,0.8,0.8,1))
	_debug_mesh.surface_add_vertex(origin)
	_debug_mesh.surface_add_vertex(origin + forward * (base_radius * 1.5))

	# Отображаем зафиксированную точку курсора, если активна
	if _world_cursor_locked:
		var to_locked = _locked_world_position - global_transform.origin
		to_locked.y = 0
		if to_locked.length() > 0.001:
			to_locked = to_locked.normalized() * (base_radius * 0.8)
			_debug_mesh.surface_set_color(Color(1, 0, 1, 1))  # Magenta
			_debug_mesh.surface_add_vertex(origin)
			_debug_mesh.surface_add_vertex(origin + to_locked)

	_debug_mesh.surface_end()

func _draw_debug_arc_with_label(origin: Vector3, direction: Vector3, radius: float, angle_deg: float, name: String, color: Color, segments: int, index: int) -> void:
	if segments < 2:
		segments = 2

	var angle_rad: float = deg_to_rad(angle_deg)
	var half: float = angle_rad * 0.5
	var base_angle: float = atan2(direction.x, direction.z)

	var first_point: Vector3 = origin + Vector3(sin(base_angle - half), 0, cos(base_angle - half)) * radius
	var prev_point: Vector3 = first_point

	for i in range(1, segments + 1):
		var t: float = float(i) / float(segments)
		var ang: float = base_angle + lerp(-half, half, t)
		var curr: Vector3 = origin + Vector3(sin(ang), 0, cos(ang)) * radius

		_debug_mesh.surface_set_color(color)
		_debug_mesh.surface_add_vertex(prev_point)
		_debug_mesh.surface_set_color(color)
		_debug_mesh.surface_add_vertex(curr)

		prev_point = curr

	_debug_mesh.surface_set_color(color)
	_debug_mesh.surface_add_vertex(origin)
	_debug_mesh.surface_add_vertex(first_point)

	_debug_mesh.surface_set_color(color)
	_debug_mesh.surface_add_vertex(origin)
	_debug_mesh.surface_add_vertex(prev_point)

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

	var radial_offset = direction * (radius + 1.0)
	var vertical_offset = Vector3(0, 0.5 + 0.25 * index, 0)
	var side_offset = Vector3(0.2 * index, 0, 0)
	lbl.global_transform.origin = debug_visuals_node.global_transform.origin + radial_offset + vertical_offset + side_offset

#func _face_target(player: CharacterBody3D, delta: float) -> void:
#
	#if not _have_smoothed:
		#_smoothed_target_yaw = target_yaw
		#_have_smoothed = true
	#else:
		#if exponential_smoothing:
			#var smooth_rate = angle_smoothing_speed
			#var smooth_factor = 1.0 - exp(-smooth_rate * delta)
			#_smoothed_target_yaw = lerp_angle(_smoothed_target_yaw, target_yaw, smooth_factor)
		#else:
			#_smoothed_target_yaw = lerp_angle(_smoothed_target_yaw, target_yaw, angle_smoothing_speed * delta)
#
	#var delta_yaw = wrapf(_smoothed_target_yaw - player.rotation.y, -PI, PI)
	#var max_step = base_rotation_speed * delta
	#player.rotation.y += clamp(delta_yaw, -max_step, max_step)
