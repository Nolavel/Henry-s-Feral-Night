extends Control
class_name MouseCursorUI

# === НАСТРОЙКИ КУРСОРА ===
@export var cursor_radius: float = 8.0
@export var cursor_thickness: float = 2.0
@export var front_zone_color: Color = Color.WHITE
@export var neutral_zone_color: Color = Color(0.5, 0.5, 0.5, 0.8)
@export var color_transition_speed: float = 8.0

# === НАСТРОЙКИ ИНДИКАЦИИ ДВИЖЕНИЯ ===
@export_group("Индикация движения")
@export var movement_dot_radius: float = 4.0
@export var movement_dot_color: Color = Color.GRAY
@export var movement_dot_bright_color: Color = Color.WHITE
@export var sprint_arc_thickness: float = 4.0
@export var sprint_arc_color: Color = Color(0.8, 0.9, 1.0, 1.0)
@export var sprint_animation_speed: float = 2.0

# === НАСТРОЙКИ ЛЕЙБЛА ===
@export var label_text: String = "Double-tap S to snap turn"
@export var label_show_delay: float = 1.0
@export var label_fade_speed: float = 6.0
@export var label_offset: Vector2 = Vector2(0, 30)

# === ЗОНЫ ПОВОРОТА (синхронизировать с Player) ===
@export var front_sector_deg: float = 120.0
@export var yaw_sector_deg: float = 60.0
@export var back_slow_sector_deg: float = 120.0
@export var back_deadzone_deg: float = 60.0
@export var min_mouse_distance: float = 0.6
@export var noise_floor_deg: float = 0.35

# === ПОРОГИ СТАТИЧНОСТИ ===
@export var mouse_stationary_px: float = 2.0
@export var player_move_stationary_speed: float = 0.05
@export var player_rot_stationary_deg_per_s: float = 10.0

# === ССЫЛКИ ===
@export var player: CharacterBody3D

# === СОСТОЯНИЕ ===
var current_cursor_color: Color
var label_alpha: float = 0.0
var cursor_position: Vector2 = Vector2.ZERO

var is_back_zone: bool = false
var is_front_zone: bool = false
var is_behind: bool = false

var mouse_stationary_timer: float = 0.0
var last_mouse_pos: Vector2 = Vector2.ZERO

var last_player_pos: Vector3 = Vector3.ZERO
var last_player_yaw: float = 0.0

# === СОСТОЯНИЕ ИНДИКАЦИИ ДВИЖЕНИЯ ===
var is_player_moving: bool = false
var is_player_sprinting: bool = false
var sprint_progress: float = 0.0  # 0.0 - 1.0
var sprint_arc_angle: float = 0.0  # Для анимации дуг
var movement_dot_alpha: float = 0.0
var sprint_arcs_alpha: float = 0.0

# === UI ЭЛЕМЕНТЫ ===
var label: Label
var tween: Tween

func _ready() -> void:
	current_cursor_color = neutral_zone_color

	label = Label.new()
	label.text = label_text
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.visible = false
	add_child(label)

	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)

	if player:
		last_player_pos = player.global_transform.origin
		last_player_yaw = player.rotation.y
	last_mouse_pos = get_viewport().get_mouse_position()

func _process(delta: float) -> void:
	if not player:
		return

	cursor_position = get_viewport().get_mouse_position()

	# 1) Курсор стоит?
	var mouse_moved: bool = cursor_position.distance_to(last_mouse_pos) > mouse_stationary_px
	if mouse_moved:
		mouse_stationary_timer = 0.0
		last_mouse_pos = cursor_position
	else:
		mouse_stationary_timer += delta

	# 2) Игрок стоит?
	var player_pos: Vector3 = player.global_transform.origin
	var lin_speed: float = (player_pos - last_player_pos).length() / max(delta, 0.0001)
	last_player_pos = player_pos

	var yaw_now: float = player.rotation.y
	var yaw_delta: float = abs(rad_to_deg(wrapf(yaw_now - last_player_yaw, -PI, PI))) / max(delta, 0.0001)
	last_player_yaw = yaw_now

	var player_stationary: bool = (lin_speed <= player_move_stationary_speed) and (yaw_delta <= player_rot_stationary_deg_per_s)

	# 3) Обновление состояния движения
	_update_movement_state(delta, lin_speed, player_stationary)

	# 4) Анализ зоны
	_analyze_cursor_zone()

	# 5) Цвет курсора
	_update_cursor_color(delta)

	# 6) Лейбл: за спиной + курсор стоит + игрок статичен
	var should_show_label: bool = is_behind and (mouse_stationary_timer >= label_show_delay) and player_stationary
	_update_label(delta, should_show_label)

	queue_redraw()

func _update_movement_state(delta: float, lin_speed: float, player_stationary: bool) -> void:
	var was_moving: bool = is_player_moving
	var was_sprinting: bool = is_player_sprinting
	
	is_player_moving = not player_stationary
	is_player_sprinting = is_player_moving and Input.is_action_pressed("sprint")
	
	# Получаем прогресс спринта из игрока
	if player.has_method("get_sprint_blend"):
		sprint_progress = (player.get_sprint_blend() - 1.0) / max(0.001, player.sprint_speed / player.walk_speed - 1.0)
	else:
		# Fallback - используем _sprint_blend напрямую если доступен
		if "sprint_blend" in player:
			sprint_progress = (player.sprint_blend - 1.0) / max(0.001, player.sprint_speed / player.walk_speed - 1.0)
		else:
			sprint_progress = 1.0 if is_player_sprinting else 0.0
	
	sprint_progress = clamp(sprint_progress, 0.0, 1.0)
	
	# Анимация точки движения
	var target_dot_alpha: float = 1.0 if is_player_moving else 0.0
	movement_dot_alpha = lerp(movement_dot_alpha, target_dot_alpha, 8.0 * delta)
	
	# Анимация дуг спринта
	var target_arcs_alpha: float = sprint_progress
	sprint_arcs_alpha = lerp(sprint_arcs_alpha, target_arcs_alpha, 6.0 * delta)
	
	# Анимация вращения дуг
	if is_player_sprinting:
		sprint_arc_angle += sprint_animation_speed * delta * (0.5 + sprint_progress * 0.5)
		if sprint_arc_angle > TAU:
			sprint_arc_angle -= TAU
	else:
		# Плавная остановка анимации
		sprint_arc_angle = lerp_angle(sprint_arc_angle, 0.0, 4.0 * delta)
	
	# Твин эффект при начале/остановке спринта
	if was_sprinting != is_player_sprinting:
		_animate_sprint_transition(is_player_sprinting)

func _animate_sprint_transition(starting_sprint: bool) -> void:
	if tween:
		tween.kill()
	tween = create_tween()
	
	if starting_sprint:
		# При начале спринта - быстрое появление дуг
		tween.tween_method(_set_sprint_arcs_alpha, 0.0, 1.0, 0.2)
	else:
		# При остановке - плавное исчезновение
		tween.tween_method(_set_sprint_arcs_alpha, sprint_arcs_alpha, 0.0, 0.4)

func _set_sprint_arcs_alpha(value: float) -> void:
	sprint_arcs_alpha = value

func _analyze_cursor_zone() -> void:
	is_front_zone = false
	is_back_zone = false
	is_behind = false

	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return

	var mouse_pos: Vector2 = cursor_position
	var ray_origin: Vector3 = camera.project_ray_origin(mouse_pos)
	var ray_dir: Vector3 = camera.project_ray_normal(mouse_pos)

	var player_y: float = player.global_transform.origin.y
	var target_world: Vector3 = Vector3.ZERO
	var have_target: bool = false

	if absf(ray_dir.y) > 0.0001:
		var t: float = (player_y - ray_origin.y) / ray_dir.y
		if t > 0.0 and t <= 1000.0:
			target_world = ray_origin + ray_dir * t
			have_target = true

	if not have_target:
		return

	var to_target: Vector3 = target_world - player.global_transform.origin
	to_target.y = 0.0
	if to_target.length() < min_mouse_distance:
		return

	var fwd: Vector3 = -player.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.0001:
		return
	fwd = fwd.normalized()

	var tgt: Vector3 = to_target.normalized()

	var cross_y: float = fwd.cross(tgt).y
	var dot_ft: float = clamp(fwd.dot(tgt), -1.0, 1.0)
	var delta_yaw: float = atan2(cross_y, dot_ft)
	var angle_diff_deg: float = abs(rad_to_deg(delta_yaw))

	if angle_diff_deg < noise_floor_deg:
		return

	# Новый флаг: курсор за спиной (угол > 90°)
	is_behind = angle_diff_deg > 90.0

	# Фронтальная активная зона
	var front_half: float = front_sector_deg * 0.5
	var front_dead_half: float = yaw_sector_deg * 0.5
	var in_front_active: bool = (angle_diff_deg <= front_half) and (angle_diff_deg > front_dead_half)

	# Задняя активная зона
	var back_offset: float = absf(angle_diff_deg - 180.0)
	var back_active_half: float = back_slow_sector_deg * 0.5
	var back_dead_half: float = back_deadzone_deg * 0.5
	var in_back_active: bool = (back_offset <= back_active_half) and (back_offset > back_dead_half)

	is_front_zone = in_front_active
	is_back_zone = in_back_active

func _update_cursor_color(delta: float) -> void:
	var target_color: Color
	if is_back_zone:
		target_color = neutral_zone_color
	elif is_front_zone:
		target_color = front_zone_color
	else:
		target_color = neutral_zone_color

	current_cursor_color = current_cursor_color.lerp(target_color, clamp(color_transition_speed * delta, 0.0, 1.0))

func _update_label(delta: float, should_show_label: bool) -> void:
	var target_alpha: float = 1.0 if should_show_label else 0.0
	if target_alpha > label_alpha:
		label_alpha = min(1.0, label_alpha + label_fade_speed * delta)
	else:
		label_alpha = max(0.0, label_alpha - label_fade_speed * delta)

	if label_alpha > 0.0:
		label.position = cursor_position + label_offset - label.size * 0.5
		var m: Color = label.modulate
		m.a = label_alpha
		label.modulate = m
		label.visible = true
	else:
		label.visible = false

func _draw() -> void:
	var color: Color = current_cursor_color
	# За спиной — приглушаем альфу
	if is_back_zone:
		color.a = min(color.a, 0.6)

	# Внешний контур основного курсора
	_draw_circle_outline(cursor_position, cursor_radius, color, cursor_thickness)

	# Внутренний мягкий круг
	var inner_color: Color = color
	inner_color.a *= 0.3
	draw_circle(cursor_position, cursor_radius * 0.3, inner_color)

	# === ИНДИКАЦИЯ ДВИЖЕНИЯ ===
	
	# Маленькая точка ниже курсора при движении
	if movement_dot_alpha > 0.0:
		var dot_color: Color = movement_dot_color.lerp(movement_dot_bright_color, movement_dot_alpha)
		dot_color.a *= movement_dot_alpha
		var dot_position: Vector2 = cursor_position + Vector2(0, cursor_radius + 8.5)
		draw_circle(dot_position, 1.5, dot_color)

	# Дуги спринта
	if sprint_arcs_alpha > 0.0:
		_draw_sprint_arcs()

func _draw_sprint_arcs() -> void:
	var arc_color: Color = sprint_arc_color
	arc_color.a *= sprint_arcs_alpha
	
	# Рисуем 4 четверти окружности как дуги
	var arc_radius: float = cursor_radius + 4.0
	var quarter_length: float = PI * 0.5 * sprint_progress  # Длина дуги зависит от прогресса спринта
	
	# 4 дуги, каждая в своей четверти
	for i in range(4):
		var base_angle: float = i * PI * 0.5 + sprint_arc_angle
		_draw_arc(cursor_position, arc_radius, base_angle, base_angle + quarter_length, arc_color, sprint_arc_thickness)

func _draw_arc(center: Vector2, radius: float, start_angle: float, end_angle: float, color: Color, thickness: float) -> void:
	var segments: int = max(8, int(abs(end_angle - start_angle) * radius * 0.5))
	var angle_step: float = (end_angle - start_angle) / segments
	
	for i in range(segments):
		var angle1: float = start_angle + i * angle_step
		var angle2: float = start_angle + (i + 1) * angle_step
		
		var point1: Vector2 = center + Vector2(cos(angle1), sin(angle1)) * radius
		var point2: Vector2 = center + Vector2(cos(angle2), sin(angle2)) * radius
		
		draw_line(point1, point2, color, thickness)

func _draw_circle_outline(center: Vector2, radius: float, color: Color, thickness: float) -> void:
	var segments: int = 32
	var points: Array[Vector2] = []
	points.resize(segments + 1)

	# Вычисляем точки окружности
	for i in range(segments + 1):
		var angle: float = (i / float(segments)) * TAU
		points[i] = center + Vector2(cos(angle), sin(angle)) * radius

	# Соединяем точки линиями
	for i in range(segments):
		draw_line(points[i], points[i + 1], color, thickness)
