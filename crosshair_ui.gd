# ✅ Script: CrosshairController.gd
# (Eng) Crosshair system with fake optimization bullshit, dead zone clusterfuck and all that performance-destroying experimental crap disguised as "optimized"
# (Rus) Система прицела с поддельной оптимизационной хуйнёй, пиздецом мёртвой зоны и всем этим производительность-убивающим экспериментальным говном замаскированным под "оптимизированное"
# 🔧 WIP ⚡ Prototype 🐛 Not Optimized — raw, unfinished crap, demo mechanics, eats resources / сырая, незавершённая хуйня, демо-механика, жрёт ресурсы
# ⚠ WARNING: This part is experimental and unstable / ВНИМАНИЕ: Этот кусок экспериментальный и нестабильный

extends Control

# (Eng) Crosshair configuration explosion - dozens of exported variables because data-driven design is apparently illegal
# (Rus) Взрыв конфигурации прицела - дюжины экспортируемых переменных потому что дата-дривен дизайн видимо незаконен
@export_group("Crosshair Display")
@export var crosshair_color: Color = Color.LIME_GREEN
@export var crosshair_size: float = 8.0
@export var crosshair_thickness: float = 2.0
@export var crosshair_gap: float = 6.0
@export var show_center_dot: bool = true
@export var center_dot_size: float = 2.0

# (Eng) Dead zone settings nightmare - overcomplicated cursor detection system for what should be simple distance check
# (Rus) Кошмар настроек мёртвой зоны - перекомплексная система обнаружения курсора для того что должно быть простой проверкой расстояния
@export_group("Dead Zone")
@export var enable_dead_zone: bool = true
@export var dead_zone_radius: float = 80.0
@export var show_dead_zone_visual: bool = false
@export var show_zone_only_when_active: bool = true
@export var dead_zone_color: Color = Color(1.0, 0.0, 0.0, 0.2)
@export var smooth_dead_zone_transition: bool = true
@export var transition_zone_size: float = 20.0

# (Eng) Animation overkill - complex animation system for simple circle visibility toggle
# (Rus) Анимационный оверкилл - сложная система анимации для простого переключения видимости круга
@export_group("Dead Zone Animation")
@export var animate_dead_zone_appearance: bool = true
@export var zone_fade_in_duration: float = 0.3
@export var zone_fade_out_duration: float = 0.2
@export var zone_pulse_when_active: bool = true

# (Eng) More configuration hell because having reasonable defaults is too simple
# (Rus) Больше конфигурационного ада потому что иметь разумные значения по умолчанию слишком просто
@export_group("Behavior")
@export var enabled: bool = true
@export var crosshair_follows_mouse: bool = true

# (Eng) Look-at-cursor clusterfuck - overcomplicated head rotation for basic mouse following
# (Rus) Пиздец взгляда на курсор - перекомплексный поворот головы для базового следования за мышью
@export_group("Look-at-Cursor")
@export var enable_look_at_cursor: bool = true
@export var head_rotation_speed: float = 8.0
@export var smooth_head_rotation: bool = true

# (Eng) Direction smoothing hell - complex interpolation system because direct input is too responsive apparently
# (Rus) Ад сглаживания направления - сложная система интерполяции потому что прямой ввод видимо слишком отзывчив
@export_group("Direction Smoothing")
@export var enable_direction_smoothing: bool = true
@export var max_angle_change_per_frame: float = 5.0
@export var direction_lerp_speed: float = 10.0

# (Eng) FAKE OPTIMIZATION BULLSHIT - frame counters and periodic checks because constant computation is apparently the solution to performance
# (Rus) ПОДДЕЛЬНАЯ ОПТИМИЗАЦИОННАЯ ХУЙНЯ - счётчики кадров и периодические проверки потому что постоянные вычисления видимо решение для производительности
@export_group("Performance")
@export var raycast_check_frequency: int = 3  # Проверять raycast каждый N-й кадр
@export var dead_zone_check_frequency: int = 2  # Проверять dead zone каждый N-й кадр

# (Eng) Debug spam settings because apparently we need configuration for debug output too
# (Rus) Настройки спама отладки потому что видимо нам нужна конфигурация и для вывода отладки тоже
@export_group("Debug")
@export var show_debug_info: bool = false
@export var show_raycast_debug: bool = false

@export_group("Visual Effects")
@export var pulse_on_enemy_target: bool = true
@export var pulse_speed: float = 5.0
@export var pulse_intensity: float = 0.3
@export var change_color_on_target: bool = true
@export var target_color: Color = Color.RED

# (Eng) State tracking explosion - dozens of variables because proper state management is rocket science
# (Rus) Взрыв отслеживания состояния - дюжины переменных потому что нормальное управление состоянием это ракетостроение
var current_crosshair_pos: Vector2
var target_crosshair_pos: Vector2
var pulse_time: float = 0.0
var is_targeting_enemy: bool = false

# (Eng) Dead zone state hell - multiple boolean flags because single state enum would be too elegant
# (Rus) Ад состояния мёртвой зоны - множественные булевые флаги потому что единственный enum состояния был бы слишком элегантным
var is_in_dead_zone: bool = false
var was_in_dead_zone_last_frame: bool = false
var last_valid_direction: Vector3 = Vector3.FORWARD
var smoothed_direction: Vector3 = Vector3.FORWARD

# (Eng) Animation state clusterfuck - separate variables for every animation property because component composition is illegal
# (Rus) Пиздец состояния анимации - отдельные переменные для каждого свойства анимации потому что композиция компонентов незаконна
var dead_zone_alpha: float = 0.0
var target_dead_zone_alpha: float = 0.0
var zone_animation_tween: Tween = null

var can_interact_with_player: bool = false

# (Eng) FAKE OPTIMIZATION CACHE - "cached" references that get validated every 30 frames because real optimization is too hard
# (Rus) ПОДДЕЛЬНЫЙ ОПТИМИЗАЦИОННЫЙ КЕШ - "кешированные" ссылки которые валидируются каждые 30 кадров потому что реальная оптимизация слишком сложна
var cached_player_node: Node3D
var cached_camera_node: Camera3D
var cache_valid: bool = false
var is_game_mode: bool = true

# (Eng) Frame counter hell - multiple counters because single update cycle would be too simple
# (Rus) Ад счётчиков кадров - множественные счётчики потому что единственный цикл обновления был бы слишком простым
var frame_counter: int = 0
var raycast_frame_counter: int = 0

# (Eng) More "cached" computations that get recalculated constantly - fake optimization at its finest
# (Rus) Больше "кешированных" вычислений которые постоянно пересчитываются - поддельная оптимизация во всей красе
var cached_player_screen_pos: Vector2
var cached_cursor_world_pos: Vector3
var cached_raw_direction: Vector3
var needs_redraw: bool = true

# (Eng) "Reusable" variables that could just be local variables - premature optimization disguised as performance improvement
# (Rus) "Переиспользуемые" переменные которые могли быть просто локальными - преждевременная оптимизация замаскированная под улучшение производительности
var temp_distance: float
var temp_mouse_pos: Vector2

func _ready():
	# (Eng) UI setup with hardcoded presets because flexible layout systems are too advanced
	# (Rus) Настройка UI с хардкод пресетами потому что гибкие системы разметки слишком продвинуты
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# (Eng) Cursor hiding obsession - multiple attempts to hide cursor because doing it right the first time is impossible
	# (Rus) Одержимость скрытием курсора - множественные попытки скрыть курсор потому что сделать это правильно с первого раза невозможно
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	create_tween().tween_callback(force_hide_system_cursor).set_delay(1.0)
	
	# (Eng) FAKE OPTIMIZATION: Cache references that will be validated every 30 frames anyway
	# (Rus) ПОДДЕЛЬНАЯ ОПТИМИЗАЦИЯ: Кешируем ссылки которые всё равно будут валидироваться каждые 30 кадров
	cache_node_references()
	
	current_crosshair_pos = get_viewport().size / 2
	target_crosshair_pos = current_crosshair_pos
	
	print("CrosshairController: Система прицела готова (оптимизирована)")

func cache_node_references():
	# (Eng) "Optimization" that searches entire scene tree - caching that defeats its own purpose
	# (Rus) "Оптимизация" которая обыскивает всё дерево сцены - кеширование которое побеждает свою собственную цель
	cached_player_node = get_tree().get_first_node_in_group("player")
	cached_camera_node = get_tree().get_first_node_in_group("game_camera_group")
	
	cache_valid = is_instance_valid(cached_player_node) and is_instance_valid(cached_camera_node)
	
	if cache_valid:
		print("CrosshairController: Ссылки закешированы успешно")
	else:
		printerr("CrosshairController: Ошибка кеширования ссылок!")

func force_hide_system_cursor():
	# (Eng) Cursor hiding panic function - because the first attempt obviously failed
	# (Rus) Паническая функция скрытия курсора - потому что первая попытка очевидно провалилась
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	print("CrosshairController: Системный курсор принудительно скрыт")

func _process(delta):
	# (Eng) FAKE OPTIMIZED main loop - still runs every fucking frame with complex logic and multiple expensive function calls
	# (Rus) ПОДДЕЛЬНО ОПТИМИЗИРОВАННЫЙ основной цикл - всё ещё работает каждый блядский кадр со сложной логикой и множественными дорогими вызовами функций
	if not enabled or not is_game_mode:
		return
	
	# (Eng) Frame counter spam because apparently counting frames is optimization
	# (Rus) Спам счётчика кадров потому что видимо подсчёт кадров это оптимизация
	frame_counter += 1
	raycast_frame_counter += 1
	
	# (Eng) Periodic cache validation - validate "optimized" cache every 30 frames like idiots
	# (Rus) Периодическая валидация кеша - валидируем "оптимизированный" кеш каждые 30 кадров как дебилы
	if frame_counter % 30 == 0:  # Каждые полсекунды
		validate_cache()
	
	if not cache_valid:
		return
	
	update_crosshair_position(delta)
	
	# (Eng) FAKE OPTIMIZATION: Check dead zone every N frames - still expensive computation, just less frequent
	# (Rus) ПОДДЕЛЬНАЯ ОПТИМИЗАЦИЯ: Проверяем мёртвую зону каждые N кадров - всё ещё дорогие вычисления, просто реже
	if frame_counter % dead_zone_check_frequency == 0:
		update_dead_zone_state()
		needs_redraw = true
	
	update_direction_smoothing_optimized(delta)
	update_dead_zone_animation(delta)
	
	# (Eng) FAKE OPTIMIZATION: Raycast every N frames - because doing expensive operations less frequently is "optimization"
	# (Rus) ПОДДЕЛЬНАЯ ОПТИМИЗАЦИЯ: Raycast каждые N кадров - потому что делать дорогие операции реже это "оптимизация"
	if raycast_frame_counter % raycast_check_frequency == 0:
		update_visual_effects_optimized(delta)
		raycast_frame_counter = 0
	else:
		pulse_time += delta * pulse_speed
	
	# (Eng) Redraw flag system - because checking if we need to redraw is apparently cheaper than just redrawing
	# (Rus) Система флага перерисовки - потому что проверять нужна ли перерисовка видимо дешевле чем просто перерисовывать
	if needs_redraw:
		queue_redraw()
		needs_redraw = false

func validate_cache():
	# (Eng) Cache validation that defeats the purpose of caching - search scene tree again to validate cached search results
	# (Rus) Валидация кеша которая побеждает цель кеширования - снова ищем по дереву сцены чтобы валидировать кешированные результаты поиска
	if not cache_valid or not is_instance_valid(cached_player_node) or not is_instance_valid(cached_camera_node):
		cache_node_references()

func _input(event):
	# (Eng) Input handling mixed with game logic because separation of concerns is overrated
	# (Rus) Обработка ввода смешанная с игровой логикой потому что разделение ответственности переоценено
	if not event is InputEventMouseButton:
		return
	
	if event.is_action_pressed("shoot") and is_in_dead_zone and can_interact_with_player:
		handle_player_interaction()
		get_viewport().set_input_as_handled()
		return
	
	if event.is_action_pressed("shoot") and not is_in_dead_zone:
		check_enemy_click_targeting()

func check_enemy_click_targeting():
	# (Eng) Empty function because implementation is apparently optional
	# (Rus) Пустая функция потому что реализация видимо опциональна
	var enemies = get_tree().get_nodes_in_group("enemies")
	if enemies.size() > 0:
		pass

func _unhandled_input(event):
	# (Eng) Another empty input handler because we love redundant function stubs
	# (Rus) Ещё один пустой обработчик ввода потому что мы любим избыточные заглушки функций
	pass

func handle_player_interaction():
	# (Eng) Player interaction that just prints debug - actual interaction logic is too advanced apparently
	# (Rus) Взаимодействие с игроком которое просто печатает отладку - реальная логика взаимодействия видимо слишком продвинута
	print("CrosshairController: Клик по игроку в Dead Zone")

func update_crosshair_position(delta):
	# (Eng) "Optimized" position update that still runs every frame with clamping and distance checks
	# (Rus) "Оптимизированное" обновление позиции которое всё ещё работает каждый кадр с ограничениями и проверками расстояния
	if not crosshair_follows_mouse:
		return
	
	# (Eng) Mouse position fetching "optimization" - get position once per frame instead of... once per frame
	# (Rus) "Оптимизация" получения позиции мыши - получаем позицию один раз за кадр вместо... одного раза за кадр
	temp_mouse_pos = get_global_mouse_position()
	
	var screen_size = get_viewport().size
	temp_mouse_pos.x = clamp(temp_mouse_pos.x, 0, screen_size.x)
	temp_mouse_pos.y = clamp(temp_mouse_pos.y, 0, screen_size.y)
	
	target_crosshair_pos = temp_mouse_pos
	
	# (Eng) Distance check "optimization" - check distance to avoid assignment but still assign every time
	# (Rus) "Оптимизация" проверки расстояния - проверяем расстояние чтобы избежать присваивания но всё равно присваиваем каждый раз
	if current_crosshair_pos.distance_to(target_crosshair_pos) > 1.0:
		current_crosshair_pos = target_crosshair_pos
		needs_redraw = true

func update_dead_zone_state():
	# (Eng) "Optimized" dead zone update with cached calculations that still does complex math every call
	# (Rus) "Оптимизированное" обновление мёртвой зоны с кешированными вычислениями которое всё ещё делает сложную математику при каждом вызове
	if not enable_dead_zone or not cache_valid:
		is_in_dead_zone = false
		can_interact_with_player = false
		return
	
	# (Eng) "Cached" player screen position that gets calculated every dead zone update anyway
	# (Rus) "Кешированная" позиция игрока на экране которая всё равно вычисляется при каждом обновлении мёртвой зоны
	cached_player_screen_pos = cached_camera_node.unproject_position(cached_player_node.global_position)
	temp_distance = current_crosshair_pos.distance_to(cached_player_screen_pos)
	
	was_in_dead_zone_last_frame = is_in_dead_zone
	
	# (Eng) Smooth transition logic - complex math for simple boolean state
	# (Rus) Логика плавного перехода - сложная математика для простого булевого состояния
	if smooth_dead_zone_transition:
		var inner_radius = dead_zone_radius
		var outer_radius = dead_zone_radius + transition_zone_size
		
		if temp_distance < inner_radius:
			is_in_dead_zone = true
			can_interact_with_player = true
		elif temp_distance > outer_radius:
			is_in_dead_zone = false
			can_interact_with_player = false
	else:
		is_in_dead_zone = temp_distance < dead_zone_radius
		can_interact_with_player = is_in_dead_zone
	
	if was_in_dead_zone_last_frame != is_in_dead_zone:
		animate_dead_zone_visibility(is_in_dead_zone)
		needs_redraw = true
		
		if show_debug_info:
			print("CrosshairController: %s Dead Zone (distance: %.1fpx)" % [
				"ВОШЛИ в" if is_in_dead_zone else "ВЫШЛИ из",
				temp_distance
			])

func animate_dead_zone_visibility(show: bool):
	# (Eng) Animation overkill for simple visibility toggle - tween system for boolean state change
	# (Rus) Анимационный оверкилл для простого переключения видимости - система твинов для изменения булевого состояния
	if not animate_dead_zone_appearance:
		dead_zone_alpha = 1.0 if show else 0.0
		return
	
	if zone_animation_tween and zone_animation_tween.is_valid():
		zone_animation_tween.kill()
	
	zone_animation_tween = create_tween()
	
	var duration = zone_fade_in_duration if show else zone_fade_out_duration
	target_dead_zone_alpha = 1.0 if show else 0.0
	
	zone_animation_tween.tween_method(
		set_dead_zone_alpha,
		dead_zone_alpha,
		target_dead_zone_alpha,
		duration
	)

func set_dead_zone_alpha(alpha: float):
	# (Eng) Alpha setter with forced redraw flag - because property assignment needs a wrapper function apparently
	# (Rus) Установщик альфы с принудительным флагом перерисовки - потому что присваивание свойства видимо нуждается в функции-обёртке
	dead_zone_alpha = clamp(alpha, 0.0, 1.0)
	needs_redraw = true

func update_dead_zone_animation(delta):
	# (Eng) Pulse animation with trigonometric calculations - expensive sin() calls for subtle visual effect nobody notices
	# (Rus) Анимация пульсации с тригонометрическими вычислениями - дорогие вызовы sin() для тонкого визуального эффекта который никто не замечает
	if zone_pulse_when_active and is_in_dead_zone and dead_zone_alpha > 0.1:
		var pulse_factor = (sin(pulse_time * 2.0) + 1.0) * 0.5 * 0.3
		dead_zone_alpha = clamp(target_dead_zone_alpha + pulse_factor, 0.0, 1.0)
		needs_redraw = true

func update_direction_smoothing_optimized(delta):
	# (Eng) "Optimized" direction smoothing that still does complex interpolation math every frame
	# (Rus) "Оптимизированное" сглаживание направления которое всё ещё делает сложную математику интерполяции каждый кадр
	if is_in_dead_zone:
		smoothed_direction = last_valid_direction
		return
	
	# (Eng) "Reuse cached direction" - call expensive calculation function and call it optimized
	# (Rus) "Переиспользуем кешированное направление" - вызываем дорогую функцию вычисления и называем это оптимизацией
	cached_raw_direction = get_raw_look_direction_optimized()
	
	if cached_raw_direction != Vector3.ZERO and cached_raw_direction.length() > 0.1:
		if enable_direction_smoothing:
			var angle_diff = smoothed_direction.angle_to(cached_raw_direction)
			var max_change_rad = deg_to_rad(max_angle_change_per_frame)
			
			# (Eng) Complex lerp logic with angle limiting - overcomplicated interpolation for basic input smoothing
			# (Rus) Сложная логика lerp с ограничением углов - перекомплексная интерполяция для базового сглаживания ввода
			if angle_diff > max_change_rad:
				var lerp_factor = max_change_rad / angle_diff
				smoothed_direction = smoothed_direction.lerp(cached_raw_direction, lerp_factor).normalized()
			else:
				smoothed_direction = smoothed_direction.lerp(cached_raw_direction, direction_lerp_speed * delta).normalized()
		else:
			smoothed_direction = cached_raw_direction
		
		last_valid_direction = smoothed_direction

func get_raw_look_direction_optimized() -> Vector3:
	# (Eng) "Optimized" direction calculation that still calls expensive world position conversion
	# (Rus) "Оптимизированный" расчёт направления который всё ещё вызывает дорогое преобразование мировых координат
	cached_cursor_world_pos = get_cursor_world_position_optimized()
	if cached_cursor_world_pos == Vector3.ZERO:
		return Vector3.ZERO
	
	var player_pos = cached_player_node.global_position
	var direction = (cached_cursor_world_pos - player_pos)
	direction.y = 0
	
	if direction.length() < 0.5:
		return Vector3.ZERO
	
	return direction.normalized()

func get_cursor_world_position_optimized() -> Vector3:
	# (Eng) "Optimized" world position calculation with complex ray projection math - expensive calculations disguised as optimization
	# (Rus) "Оптимизированный" расчёт мировой позиции со сложной математикой проекции лучей - дорогие вычисления замаскированные под оптимизацию
	if not cache_valid:
		return Vector3.ZERO
	
	var player_y = cached_player_node.global_position.y
	var from = cached_camera_node.project_ray_origin(current_crosshair_pos)
	var direction = cached_camera_node.project_ray_normal(current_crosshair_pos)
	
	if abs(direction.y) < 0.001:
		return Vector3.ZERO
	
	var t = (player_y - from.y) / direction.y
	return from + direction * t

func update_visual_effects_optimized(delta):
	# (Eng) "Optimized" visual effects that still increment pulse time and do expensive enemy targeting checks
	# (Rus) "Оптимизированные" визуальные эффекты которые всё ещё увеличивают время пульсации и делают дорогие проверки нацеливания на врагов
	pulse_time += delta * pulse_speed
	check_enemy_targeting_optimized()

func check_enemy_targeting_optimized():
	# (Eng) "Optimized" enemy targeting with expensive raycast operations - because physics queries are apparently cheap
	# (Rus) "Оптимизированное" нацеливание на врагов с дорогими raycast операциями - потому что физические запросы видимо дешёвые
	is_targeting_enemy = false
	
	if is_in_dead_zone or not cache_valid:
		return
	
	# (Eng) Raycast hell - expensive physics queries every N frames disguised as optimization
	# (Rus) Ад raycast - дорогие физические запросы каждые N кадров замаскированные под оптимизацию
	var from = cached_camera_node.project_ray_origin(current_crosshair_pos)
	var to = from + cached_camera_node.project_ray_normal(current_crosshair_pos) * 1000.0
	
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 2
	query.collide_with_bodies = true
	
	var result = space_state.intersect_ray(query)
	
	if result.is_empty():
		return
	
	var hit_object = result.collider
	if not hit_object:
		return
	
	var target_node = find_enemy_in_hierarchy(hit_object)
	if target_node:
		is_targeting_enemy = true
		needs_redraw = true
		if show_debug_info:
			print("Наведение на врага: %s" % target_node.name)

func find_enemy_in_hierarchy(hit_node: Node) -> Node:
	# (Eng) Hierarchy traversal hell - walk up parent chain with loop limit because proper recursive search is too hard
	# (Rus) Ад обхода иерархии - поднимаемся по цепочке родителей с лимитом цикла потому что нормальный рекурсивный поиск слишком сложен
	var current_node = hit_node
	
	# (Eng) Magic number loop limit because infinite loops are scary
	# (Rus) Магическое число лимита цикла потому что бесконечные циклы страшные
	for i in range(10):
		if not current_node:
			break
		
		if current_node.is_in_group("enemies"):
			return current_node
		
		# (Eng) String-based enemy detection because proper type checking is too advanced
		# (Rus) Обнаружение врагов на основе строк потому что нормальная проверка типов слишком продвинута
		var node_name = current_node.name.to_lower()
		if "enemy" in node_name or "zombie" in node_name or "monster" in node_name:
			print("Найден враг '%s' НЕ в группе 'enemies'!" % current_node.name)
			return current_node
		
		current_node = current_node.get_parent()
	
	return null

func get_world_3d() -> World3D:
	# (Eng) World3D getter with multiple fallbacks because getting physics world is apparently rocket science
	# (Rus) Получатель World3D с множественными запасными вариантами потому что получение физического мира видимо ракетостроение
	if is_instance_valid(cached_camera_node):
		return cached_camera_node.get_world_3d()
	
	var viewport = get_viewport()
	if viewport and viewport.get_world_3d():
		return viewport.get_world_3d()
	
	return get_tree().current_scene.get_world_3d()

func _draw():
	# (Eng) Draw function that calls expensive rendering operations but only when needed - redraw flag system overhead
	# (Rus) Функция отрисовки которая вызывает дорогие операции рендеринга но только когда нужно - накладные расходы системы флагов перерисовки
	if not enabled or not is_game_mode:
		return
	
	draw_dead_zone_visual()
	draw_crosshair()

func draw_dead_zone_visual():
	# (Eng) "Optimized" dead zone drawing with complex visibility logic and expensive circle rendering
	# (Rus) "Оптимизированная" отрисовка мёртвой зоны со сложной логикой видимости и дорогим рендерингом кругов
	if not enable_dead_zone:
		return
	
	var should_draw = false
	if show_dead_zone_visual and not show_zone_only_when_active:
		should_draw = true
	elif show_zone_only_when_active and dead_zone_alpha > 0.01:
		should_draw = true
	
	if not should_draw or not cache_valid:
		return
	
	# (Eng) Screen bounds check using cached position - check if circle is visible before drawing expensive circle
	# (Rus) Проверка границ экрана используя кешированную позицию - проверяем виден ли круг перед отрисовкой дорогого круга
	var screen_rect = get_viewport().get_visible_rect()
	if not screen_rect.has_point(cached_player_screen_pos):
		return
	
	var circle_color = dead_zone_color
	circle_color.a = dead_zone_color.a * dead_zone_alpha
	
	if circle_color.a < 0.01:
		return
	
	# (Eng) Multiple draw calls for single visual effect - draw circle, arc, and transition arc separately because efficiency is overrated
	# (Rus) Множественные вызовы отрисовки для одного визуального эффекта - рисуем круг, дугу и переходную дугу отдельно потому что эффективность переоценена
	draw_circle(cached_player_screen_pos, dead_zone_radius, circle_color)
	
	var border_color = Color(circle_color.r, circle_color.g, circle_color.b, circle_color.a * 4.0)
	border_color.a = clamp(border_color.a, 0.0, 1.0)
	draw_arc(cached_player_screen_pos, dead_zone_radius, 0, TAU, 32, border_color, 2.0)
	
	if smooth_dead_zone_transition:
		var transition_color = Color(circle_color.r, circle_color.g, circle_color.b, circle_color.a * 0.3)
		draw_arc(cached_player_screen_pos, dead_zone_radius + transition_zone_size, 0, TAU, 32, transition_color, 1.0)

func draw_crosshair():
	# (Eng) "Optimized" crosshair drawing with complex color logic and expensive scaling calculations
	# (Rus) "Оптимизированная" отрисовка прицела со сложной логикой цветов и дорогими расчётами масштабирования
	var pos = current_crosshair_pos
	var color = crosshair_color
	
	# (Eng) Color selection hell - multiple if statements for simple state-based color changes
	# (Rus) Ад выбора цвета - множественные if утверждения для простых изменений цвета на основе состояния
	if is_in_dead_zone:
		if can_interact_with_player:
			color = Color.GOLD
		else:
			color = Color.ORANGE
	elif is_targeting_enemy and change_color_on_target:
		color = target_color
	
	# (Eng) Size calculation clusterfuck - complex pulse math for subtle visual effect
	# (Rus) Пиздец расчёта размера - сложная математика пульсации для тонкого визуального эффекта
	var size_modifier = 1.0
	if (is_targeting_enemy and pulse_on_enemy_target) or is_in_dead_zone:
		var pulse_factor = (sin(pulse_time) + 1.0) * 0.5 * pulse_intensity
		size_modifier = 1.0 + pulse_factor
	
	var final_size = crosshair_size * size_modifier
	var final_gap = crosshair_gap * size_modifier
	var final_thickness = crosshair_thickness
	
	# (Eng) More size scaling hell for dead zone state - because simple crosshair isn't fancy enough
	# (Rus) Больше ада масштабирования размера для состояния мёртвой зоны - потому что простой прицел недостаточно модный
	if is_in_dead_zone:
		final_size *= 1.3
		final_thickness *= 1.5
		
		if can_interact_with_player:
			final_size *= 1.1
			final_thickness *= 1.2
	
	# (Eng) Multiple draw_line calls for simple crosshair - four separate draw calls because single crosshair sprite would be too efficient
	# (Rus) Множественные вызовы draw_line для простого прицела - четыре отдельных вызова отрисовки потому что единственный спрайт прицела был бы слишком эффективным
	draw_line(
		Vector2(pos.x - final_size - final_gap, pos.y),
		Vector2(pos.x - final_gap, pos.y),
		color, final_thickness
	)
	draw_line(
		Vector2(pos.x + final_gap, pos.y),
		Vector2(pos.x + final_size + final_gap, pos.y),
		color, final_thickness
	)
	
	draw_line(
		Vector2(pos.x, pos.y - final_size - final_gap),
		Vector2(pos.x, pos.y - final_gap),
		color, final_thickness
	)
	draw_line(
		Vector2(pos.x, pos.y + final_gap),
		Vector2(pos.x, pos.y + final_size + final_gap),
		color, final_thickness
	)
	
	if show_center_dot:
		var dot_size = center_dot_size * size_modifier
		if is_in_dead_zone:
			dot_size *= 1.5
		draw_circle(pos, dot_size, color)
	
	# (Eng) Additional interaction ring drawing - even more draw calls for subtle visual effect
	# (Rus) Дополнительная отрисовка кольца взаимодействия - ещё больше вызовов отрисовки для тонкого визуального эффекта
	if is_in_dead_zone and can_interact_with_player:
		var interaction_ring_radius = final_size * 2.0
		var ring_color = Color(color.r, color.g, color.b, 0.4)
		draw_arc(pos, interaction_ring_radius, 0, TAU, 16, ring_color, 1.0)

func get_look_direction_for_head() -> Vector3:
	# (Eng) Direction getter with dead zone logic - returns zero direction but with complex conditional logic
	# (Rus) Получатель направления с логикой мёртвой зоны - возвращает нулевое направление но со сложной условной логикой
	if is_in_dead_zone or not enable_look_at_cursor:
		return Vector3.ZERO
	
	return smoothed_direction

func get_look_direction_for_body() -> Vector3:
	# (Eng) Another direction getter with identical logic - code duplication because DRY principle is overrated
	# (Rus) Ещё один получатель направления с идентичной логикой - дублирование кода потому что принцип DRY переоценён
	if is_in_dead_zone:
		return Vector3.ZERO
	
	return smoothed_direction

func is_cursor_in_dead_zone() -> bool:
	# (Eng) Simple boolean getter disguised as method - property access through function call for no reason
	# (Rus) Простой булевый получатель замаскированный под метод - доступ к свойству через вызов функции без причины
	return is_in_dead_zone

func get_distance_to_player() -> float:
	# (Eng) Distance calculation using cached position - "optimized" function that still does distance calculation every call
	# (Rus) Расчёт расстояния используя кешированную позицию - "оптимизированная" функция которая всё ещё делает расчёт расстояния при каждом вызове
	if not cache_valid:
		return 0.0
	
	return current_crosshair_pos.distance_to(cached_player_screen_pos)

func set_dead_zone_radius(radius: float):
	# (Eng) Radius setter with validation and forced redraw - because simple property assignment needs validation apparently
	# (Rus) Установщик радиуса с валидацией и принудительной перерисовкой - потому что простое присваивание свойства видимо нуждается в валидации
	dead_zone_radius = clamp(radius, 10.0, 200.0)
	needs_redraw = true
	print("CrosshairController: Dead Zone радиус установлен: %.1fpx" % dead_zone_radius)

func toggle_dead_zone_visual():
	# (Eng) Toggle function with complex state cycling - because simple boolean toggle would be too easy
	# (Rus) Функция переключения со сложной циклической сменой состояния - потому что простое булевое переключение было бы слишком лёгким
	if not show_dead_zone_visual:
		show_dead_zone_visual = true
		show_zone_only_when_active = false
	elif not show_zone_only_when_active:
		show_zone_only_when_active = true
	else:
		show_dead_zone_visual = false
		show_zone_only_when_active = false
	needs_redraw = true

func can_player_be_clicked() -> bool:
	# (Eng) Another boolean property getter because direct access to can_interact_with_player would be chaos
	# (Rus) Ещё один булевый получатель свойства потому что прямой доступ к can_interact_with_player был бы хаосом
	return can_interact_with_player

func get_dead_zone_alpha() -> float:
	# (Eng) Alpha getter because accessing dead_zone_alpha directly would violate encapsulation apparently
	# (Rus) Получатель альфы потому что прямой доступ к dead_zone_alpha видимо нарушил бы инкапсуляцию
	return dead_zone_alpha

func set_crosshair_enabled(enabled: bool):
	# (Eng) Enable/disable setter with property synchronization - set three different properties for single boolean state
	# (Rus) Установщик включения/выключения с синхронизацией свойств - устанавливаем три разных свойства для одного булевого состояния
	self.enabled = enabled
	visible = enabled
	needs_redraw = true

func reset_to_center():
	# (Eng) Reset function that manually sets multiple properties to default values - because proper state initialization is too hard
	# (Rus) Функция сброса которая вручную устанавливает множественные свойства к значениям по умолчанию - потому что нормальная инициализация состояния слишком сложна
	var center = get_viewport().size / 2
	current_crosshair_pos = center
	target_crosshair_pos = center
	is_in_dead_zone = false
	last_valid_direction = Vector3.FORWARD
	smoothed_direction = Vector3.FORWARD
	needs_redraw = true

func _notification(what):
	# (Eng) Cursor hiding obsession continues - handle window focus events to force hide cursor again
	# (Rus) Одержимость скрытием курсора продолжается - обрабатываем события фокуса окна чтобы принудительно скрыть курсор снова
	match what:
		NOTIFICATION_WM_MOUSE_ENTER, NOTIFICATION_WM_WINDOW_FOCUS_IN:
			Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
		NOTIFICATION_WM_MOUSE_EXIT, NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			pass  # Ничего не делаем

func debug_cursor_state():
	# (Eng) Debug function that prints system state - console spam disguised as diagnostic tool
	# (Rus) Отладочная функция которая печатает состояние системы - консольный спам замаскированный под диагностический инструмент
	print("=== CURSOR DEBUG INFO ===")
	print("Mouse Mode: %s" % Input.mouse_mode)
	print("Crosshair Position: %s" % current_crosshair_pos)
	print("Mouse Position: %s" % get_global_mouse_position())
	print("Is in Dead Zone: %s" % is_in_dead_zone)
	print("Dead Zone Alpha: %.2f" % dead_zone_alpha)
	print("Can Interact: %s" % can_interact_with_player)
	if cache_valid:
		print("Distance to Player: %.1fpx" % get_distance_to_player())
	print("========================")

func force_cursor_update():
	# (Eng) Force update function for debugging - manual state reset because automatic state management failed
	# (Rus) Функция принудительного обновления для отладки - ручной сброс состояния потому что автоматическое управление состоянием провалилось
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	current_crosshair_pos = get_global_mouse_position()
	target_crosshair_pos = current_crosshair_pos
	needs_redraw = true
	print("CrosshairController: Принудительное обновление курсора")
	
# Добавить метод:
func set_game_mode(enabled: bool):
	is_game_mode = enabled
	needs_redraw = true
