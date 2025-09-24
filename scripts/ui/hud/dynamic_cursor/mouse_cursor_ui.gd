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
@export var movement_controller: MovementController
@export var stamina_manager: StaminaManager

# === СОСТОЯНИЕ КУРСОРА ===
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

# === СОСТОЯНИЕ СТАМИНЫ ДЛЯ UI ===
var current_stamina_ratio: float = 1.0
var sprint_arc_start_angle: float = 0.0  # Угол начала дуг (для обратной анимации)
var sprint_arc_end_angle: float = 0.0    # Угол конца дуг
var sprint_arc_reverse_speed: float = 3.0

# === СОСТОЯНИЕ ПРЫЖКА ===
var jump_arc_alpha: float = 0.0
var jump_arc_progress: float = 0.0  # 0 = дуга внизу, 1 = полный круг
var jump_is_charging: bool = false
var jump_animation_tween: Tween
var jump_time: float = 0.0

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
		
		# Проверяем ссылки на компоненты
		if movement_controller == null:
			movement_controller = player.get_node_or_null("MovementController")
			if movement_controller == null:
				push_warning("MovementController reference is not valid. Make sure the Player node has a child named 'MovementController' and the export variable is set.")
		
		if stamina_manager == null:
			stamina_manager = player.get_node_or_null("StaminaManager")
			if stamina_manager == null:
				push_warning("StaminaManager reference is not valid. Sprint UI indicators will not work correctly.")
		
		# Подключаемся к сигналам стамины
		if stamina_manager:
			stamina_manager.stamina_changed.connect(_on_stamina_changed)
			stamina_manager.stamina_depleted.connect(_on_stamina_depleted)
			stamina_manager.stamina_recovered.connect(_on_stamina_recovered)
			stamina_manager.jump_performed.connect(_on_jump_performed)
			
	last_mouse_pos = get_viewport().get_mouse_position()

func _process(delta: float) -> void:
	if not player or not movement_controller:
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
	
	if jump_is_charging:
		jump_time += delta
	else:
		jump_time = 0.0

	queue_redraw()

func _update_movement_state(delta: float, lin_speed: float, player_stationary: bool) -> void:
	var was_sprinting: bool = is_player_sprinting
	
	is_player_moving = not player_stationary
	is_player_sprinting = movement_controller.is_currently_sprinting(player.velocity)
	
	# Получаем прогресс спринта из MovementController
	sprint_progress = movement_controller.get_sprint_blend()
	
	# Обновляем стамину из StaminaManager
	if stamina_manager:
		current_stamina_ratio = stamina_manager.get_stamina_ratio()
	
	sprint_progress = clamp(sprint_progress, 0.0, 1.0)
	
	# Анимация точки движения
	var target_dot_alpha: float = 1.0 if is_player_moving else 0.0
	movement_dot_alpha = lerp(movement_dot_alpha, target_dot_alpha, 8.0 * delta)
	
	var target_arcs_alpha: float = sprint_progress * current_stamina_ratio
	sprint_arcs_alpha = lerp(sprint_arcs_alpha, target_arcs_alpha, 6.0 * delta)
	
	if is_player_sprinting:
		sprint_arc_angle += sprint_animation_speed * delta * (0.5 + sprint_progress * 0.5)
		if sprint_arc_angle > TAU:
			sprint_arc_angle -= TAU
	else:
		sprint_arc_angle = lerp_angle(sprint_arc_angle, 0.0, 4.0 * delta)
	
	if was_sprinting != is_player_sprinting:
		_animate_sprint_transition(is_player_sprinting)

	# Обратная анимация дуг
	sprint_arc_end_angle -= sprint_arc_reverse_speed * delta
	if sprint_arc_end_angle < 0.0:
		sprint_arc_end_angle += TAU
	else:
		# Плавное возвращение дуг в норму
		sprint_arc_end_angle = lerp_angle(sprint_arc_end_angle, sprint_arc_angle, 4.0 * delta)
		
		# Отслеживание зарядки прыжка
	var player_on_floor = player.is_on_floor()
	var jump_charging = Input.is_action_pressed("jump") and player_on_floor

	if jump_charging and not jump_is_charging:
		# Начали заряжать прыжок
		jump_is_charging = true
		jump_arc_alpha = 0.6
	elif not jump_charging and jump_is_charging:
		# Перестали заряжать (но не факт что прыгнули)
		jump_is_charging = false
		if player_on_floor:
			jump_arc_alpha = 0.0

	jump_is_charging = jump_charging
	
	
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
		
	# Дуга прыжка (после основных дуг спринта)
	if jump_arc_alpha > 0.0:
		_draw_jump_arc()

func _draw_sprint_arcs() -> void:
	var base_color: Color = sprint_arc_color

	# Меняем цвет в зависимости от уровня стамины
	if current_stamina_ratio > 0.5:
		var t: float = (1.0 - current_stamina_ratio) * 2.0
		base_color = base_color.lerp(Color(1.0, 1.0, 0.0), t)
	elif current_stamina_ratio > 0.25:
		var t: float = (0.5 - current_stamina_ratio) * 4.0
		base_color = Color(1.0, 1.0, 0.0).lerp(Color(1.0, 0.5, 0.0), t)
	else:
		var t: float = (0.25 - current_stamina_ratio) * 4.0
		base_color = Color(1.0, 0.5, 0.0).lerp(Color(1.0, 0.0, 0.0), t)

	base_color.a *= current_stamina_ratio

	var arc_radius: float = cursor_radius + 4.0
	var quarter_length: float = PI * 0.5 * sprint_progress * current_stamina_ratio

	for i in range(4):
		var base_angle: float = i * PI * 0.5 + sprint_arc_end_angle
		_draw_arc(cursor_position, arc_radius, base_angle, base_angle + quarter_length, base_color, sprint_arc_thickness)

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
		
func _draw_jump_arc() -> void:
	var jump_radius = cursor_radius + 12.0
	var jump_color: Color = Color(0.4, 0.8, 1.0, jump_arc_alpha)

	# Меняем цвет в зависимости от стамины
	if current_stamina_ratio > 0.5:
		jump_color = jump_color.lerp(Color(1, 1, 0), (1.0 - current_stamina_ratio) * 2.0)
	elif current_stamina_ratio > 0.25:
		jump_color = Color(1, 1, 0).lerp(Color(1, 0.5, 0), (0.5 - current_stamina_ratio) * 4.0)
	else:
		jump_color = Color(1, 0.5, 0).lerp(Color(1, 0, 0), (0.25 - current_stamina_ratio) * 4.0)

	jump_color.a *= jump_arc_alpha

	if jump_is_charging:
		# Зарядка — дуга снизу с импульсом
		var base_arc_length = PI * 0.2
		var pulse = sin(jump_time * 20.0) * 0.1
		var total_arc_length = base_arc_length + pulse + (PI * 0.3 * jump_arc_progress)
		var center_angle = PI * 0.5  # низ
		var start_angle = center_angle - total_arc_length * 0.5
		var end_angle = center_angle + total_arc_length * 0.5
		_draw_arc(cursor_position, jump_radius, start_angle, end_angle, jump_color, 2.0)
	else:
		# Если отпустили — растём к полному кругу, замкнутому сверху
		var full_progress = clamp(jump_arc_progress, 0.0, 1.0)
		var circle_center_angle = PI * 1.5  # верхняя точка
		var start_angle = circle_center_angle - TAU * 0.5 * full_progress
		var end_angle = circle_center_angle + TAU * 0.5 * full_progress

		if full_progress >= 1.0:
			_draw_circle_outline(cursor_position, jump_radius, jump_color, 2.0)
		else:
			_draw_arc(cursor_position, jump_radius, start_angle, end_angle, jump_color, 2.0)

		
func _on_jump_performed() -> void:
	# Анимация расширения и сжатия дуги прыжка
	if jump_animation_tween:
		jump_animation_tween.kill()
	jump_animation_tween = create_tween()
	jump_animation_tween.set_parallel(true)  # параллельные анимации
	
	# Расширение до круга и обратно
	jump_animation_tween.tween_method(_set_jump_arc_progress, 0.0, 1.0, 0.15)
	jump_animation_tween.tween_method(_set_jump_arc_progress, 1.0, 0.0, 0.25).set_delay(0.15)
	
	# Затухание альфы
	jump_animation_tween.tween_method(_set_jump_arc_alpha, 0.8, 0.0, 0.4)

func _set_jump_arc_progress(value: float) -> void:
	jump_arc_progress = value

func _set_jump_arc_alpha(value: float) -> void:
	jump_arc_alpha = value

func _on_stamina_changed(current_stamina: float, max_stamina: float) -> void:
	current_stamina_ratio = current_stamina / max_stamina

func _on_stamina_depleted() -> void:
	# Можно добавить специальные эффекты когда стамина заканчивается
	# Например, вспышка красного цвета или дрожание курсора
	pass

func _on_stamina_recovered() -> void:
	# Можно добавить эффекты восстановления стамины
	# Например, зеленую вспышку
	pass
