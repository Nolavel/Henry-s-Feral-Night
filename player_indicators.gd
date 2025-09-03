# ✅ Script: PlayerIndicators.gd
# (Eng) Visual indicator system with SpringArm3D rotation hell, constant tree searches and all that performance-destroying experimental bullshit
# (Rus) Система визуальных индикаторов с адом поворотов SpringArm3D, постоянными поисками по дереву и всей этой производительность-убивающей экспериментальной хуйнёй
# 🔧 WIP ⚡ Prototype 🐛 Not Optimized — raw, unfinished crap, demo mechanics, eats resources / сырая, незавершённая хуйня, демо-механика, жрёт ресурсы
# ⚠ WARNING: This part is experimental and unstable / ВНИМАНИЕ: Этот кусок экспериментальный и нестабильный

extends Node3D

class_name PlayerIndicators

# (Eng) Hover indicator configuration - bunch of exported variables because proper UI design is apparently too difficult
# (Rus) Конфигурация индикатора наведения - куча экспортируемых переменных потому что нормальный UI дизайн видимо слишком сложен
@export_group("Hover Indicator")
@export var hover_sprite: Sprite3D
@export var hover_show_duration: float = 0.3
@export var hover_hide_duration: float = 0.2
@export var hover_scale_from: Vector3 = Vector3(0.05, 0.05, 0.05)
@export var hover_scale_to: Vector3 = Vector3(0.25, 0.25, 0.25)
@export var hover_height_offset: float = 0.05  # Только 5 см над полом
@export var hover_pulse_enabled: bool = true
@export var hover_pulse_speed: float = 2.0
@export var hover_pulse_intensity: float = 0.01  # Очень мягкая пульсация

# (Eng) SpringArm movement indicator clusterfuck - overcomplicated 3D positioning for what could be simple 2D UI
# (Rus) Пиздец движкового индикатора со SpringArm - перекомплексное 3D позиционирование для того что могло быть простым 2D UI
@export_group("Movement Indicator SpringArm")
@export var movement_spring_arm: SpringArm3D  # SpringArm3D для movement индикатора
@export var movement_sprite: Sprite3D         # Sprite3D на конце SpringArm
@export var movement_distance: float = 2.0    # Базовая длина SpringArm (дистанция от игрока)
@export var movement_sprint_bonus: float = 1.0 # Дополнительная длина при спринте
@export var movement_rotation_speed: float = 5.0  # Скорость поворота SpringArm в градусах/сек
@export var movement_fade_speed: float = 5.0
@export var movement_scale: Vector3 = Vector3(0.2, 0.2, 0.2)

# (Eng) State tracking hell - bunch of variables to track because proper state machine is rocket science apparently
# (Rus) Ад отслеживания состояния - куча переменных для отслеживания потому что нормальная машина состояний видимо ракетостроение
var player_node: Node3D
var crosshair_controller: Control
var hover_tween: Tween
var movement_tween: Tween
var is_hover_visible: bool = false
var is_movement_visible: bool = false
var hover_pulse_time: float = 0.0

# (Eng) Movement state clusterfuck - duplicate player state because proper data flow is too hard
# (Rus) Пиздец состояния движения - дублируем состояние игрока потому что нормальный поток данных слишком сложен
var is_player_moving: bool = false
var player_input_direction: Vector2 = Vector2.ZERO
var player_movement_speed: float = 0.0
var is_trying_to_sprint: bool = false
var player_current_stamina: float = 1.0
var current_movement_alpha: float = 0.0

func _ready():
	# (Eng) Initialization clusterfuck - multiple setup functions because single responsibility is overrated
	# (Rus) Пиздец инициализации - несколько функций настройки потому что единственная ответственность переоценена
	
	find_required_nodes()
	setup_hover_indicator()
	setup_movement_spring_arm()
	connect_to_crosshair()

func find_required_nodes():
	# (Eng) Node finding nightmare - searches entire scene tree because proper dependency injection is too advanced
	# (Rus) Кошмар поиска узлов - обыскивает всё дерево сцены потому что нормальное внедрение зависимостей слишком продвинуто
	
	if not player_node:
		player_node = get_parent() if get_parent().is_in_group("player") else null
		if not player_node:
			player_node = get_tree().get_first_node_in_group("player")
	
	if player_node:
		pass
	else:
		printerr("PlayerIndicators: ❌ Player не найден!")
	
	# (Eng) Crosshair controller search hell - multiple search methods because consistency is dead
	# (Rus) Ад поиска контроллера прицела - несколько методов поиска потому что последовательность мертва
	crosshair_controller = get_tree().get_first_node_in_group("crosshair")
	if not crosshair_controller:
		crosshair_controller = get_tree().root.find_child("CrosshairController", true, false)
	
	if crosshair_controller:
		pass
	else:
		print("PlayerIndicators: ⚠️ CrosshairController не найден")

func setup_hover_indicator():
	# (Eng) Hover indicator setup - manual sprite configuration because proper initialization patterns are too complex
	# (Rus) Настройка индикатора наведения - ручная конфигурация спрайта потому что нормальные паттерны инициализации слишком сложны
	if not hover_sprite:
		return
	
	# (Eng) Manual state setup - hardcoded values because data-driven design is for professionals
	# (Rus) Ручная настройка состояния - хардкод значений потому что дата-дривен дизайн для профессионалов
	hover_sprite.visible = false
	hover_sprite.modulate = Color(1, 1, 1, 0)
	hover_sprite.scale = hover_scale_from
	
	# (Eng) Position synchronization - manually sync positions because proper parent-child relationships are too hard
	# (Rus) Синхронизация позиций - ручная синхронизация позиций потому что нормальные отношения родитель-дочка слишком сложны
	if player_node:
		hover_sprite.global_position = player_node.global_position
		hover_sprite.global_position.y += hover_height_offset

func setup_movement_spring_arm():
	# (Eng) SpringArm setup nightmare - overcomplicated 3D math for simple directional indicator
	# (Rus) Кошмар настройки SpringArm - перекомплексная 3D математика для простого направленного индикатора
	if not movement_spring_arm:
		create_movement_spring_arm()
		return
	
	if not movement_sprite:
		return
	
	# (Eng) SpringArm configuration hell - manual collision setup because automatic configuration would be too convenient
	# (Rus) Ад конфигурации SpringArm - ручная настройка коллизий потому что автоматическая конфигурация была бы слишком удобной
	movement_spring_arm.spring_length = movement_distance  # 2 метра длина
	movement_spring_arm.collision_mask = 1  # Слой земли для избегания коллизий
	movement_spring_arm.margin = 0.1  # Небольшой отступ от коллизий
	
	movement_spring_arm.rotation_degrees = Vector3(0, 0, 0)
	
	# (Eng) Sprite configuration clusterfuck - manual setup because component composition is rocket science
	# (Rus) Пиздец конфигурации спрайта - ручная настройка потому что композиция компонентов это ракетостроение
	movement_sprite.visible = false
	movement_sprite.modulate = Color(1, 1, 1, 0)
	movement_sprite.scale = movement_scale
	
	# (Eng) Parent-child reparenting hell - move nodes around because proper scene structure is too difficult
	# (Rus) Ад смены родителя - перемещаем узлы потому что нормальная структура сцены слишком сложна
	if movement_sprite.get_parent() != movement_spring_arm:
		if movement_sprite.get_parent():
			movement_sprite.get_parent().remove_child(movement_sprite)
		movement_spring_arm.add_child(movement_sprite)
	
	movement_sprite.position = Vector3(0, 0, 0)  # SpringArm сам позиционирует
	
	# (Eng) Rotation magic numbers - hardcoded rotation values because parametric design is overrated
	# (Rus) Магические числа поворотов - хардкод значений поворотов потому что параметрический дизайн переоценён
	movement_sprite.rotation_degrees = Vector3(-90, 180, 0)  # Лежит на полу + поворот для острия -Z

func create_movement_spring_arm():
	# (Eng) Dynamic node creation hell - create nodes at runtime because proper scene design is apparently impossible
	# (Rus) Ад динамического создания узлов - создаём узлы во время выполнения потому что нормальный дизайн сцены видимо невозможен
	movement_spring_arm = SpringArm3D.new()
	movement_spring_arm.name = "MovementSpringArm"
	add_child(movement_spring_arm)
	
	# (Eng) More dynamic creation because consistent initialization is too much work
	# (Rus) Больше динамического создания потому что последовательная инициализация слишком много работы
	if not movement_sprite:
		movement_sprite = Sprite3D.new()
		movement_sprite.name = "MovementSprite"
	
	movement_spring_arm.add_child(movement_sprite)
	
	setup_movement_spring_arm()

func connect_to_crosshair():
	# (Eng) Connection function that does absolutely fucking nothing - placeholder because implementation is optional apparently
	# (Rus) Функция подключения которая делает абсолютно нихуя - заглушка потому что реализация видимо опциональна
	if not crosshair_controller:
		return

func _process(delta):
	# (Eng) Main performance destroyer - runs three expensive update functions every fucking frame because optimization is for losers
	# (Rus) Основной убийца производительности - запускает три дорогие функции обновления каждый блядский кадр потому что оптимизация для лузеров
	update_hover_indicator(delta)
	update_movement_spring_arm(delta)
	update_hover_pulse(delta)

func update_hover_indicator(delta):
	# (Eng) Hover update nightmare - constant distance calculations and tree searches every frame like performance doesn't exist
	# (Rus) Кошмар обновления наведения - постоянные расчёты расстояния и поиски по дереву каждый кадр как будто производительности не существует
	if not hover_sprite or not player_node:
		return
	
	# (Eng) Cursor dead zone detection hell - multiple fallback methods because consistent API design is impossible
	# (Rus) Ад обнаружения мёртвой зоны курсора - несколько запасных методов потому что последовательный дизайн API невозможен
	var should_show_hover = false
	
	if crosshair_controller and crosshair_controller.has_method("is_cursor_in_dead_zone"):
		should_show_hover = crosshair_controller.is_cursor_in_dead_zone()
	else:
		# (Eng) Fallback distance calculation because proper integration is too hard
		# (Rus) Запасной расчёт расстояния потому что нормальная интеграция слишком сложна
		var camera = get_tree().get_first_node_in_group("game_camera_group")
		if camera:
			var mouse_pos = get_viewport().get_mouse_position()
			var player_screen_pos = camera.unproject_position(player_node.global_position)
			var distance = mouse_pos.distance_to(player_screen_pos)
			should_show_hover = distance < 80.0
	
	# (Eng) Show/hide logic with state tracking because proper state management is rocket science
	# (Rus) Логика показа/скрытия с отслеживанием состояния потому что нормальное управление состоянием это ракетостроение
	if should_show_hover and not is_hover_visible:
		show_hover_indicator()
	elif not should_show_hover and is_hover_visible:
		hide_hover_indicator()
	
	# (Eng) Manual position synchronization every frame - sync sprite position because proper parenting is too advanced
	# (Rus) Ручная синхронизация позиции каждый кадр - синхронизируем позицию спрайта потому что нормальное родительство слишком продвинуто
	if is_hover_visible:
		var target_pos = player_node.global_position
		target_pos.y += hover_height_offset
		hover_sprite.global_position = target_pos

func update_movement_spring_arm(delta):
	# (Eng) Movement update clusterfuck - polls input every frame and does complex calculations because efficiency is dead
	# (Rus) Пиздец обновления движения - опрашивает ввод каждый кадр и делает сложные вычисления потому что эффективность мертва
	if not movement_spring_arm or not movement_sprite or not player_node:
		return
	
	# (Eng) Direct input polling in update loop - get input every frame instead of using proper input events
	# (Rus) Прямой опрос ввода в цикле обновления - получаем ввод каждый кадр вместо использования нормальных событий ввода
	player_input_direction = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	is_trying_to_sprint = Input.is_action_pressed("run")
	
	# (Eng) Data fetching hell - get player data through multiple function calls because proper data flow is too hard
	# (Rus) Ад получения данных - получаем данные игрока через множественные вызовы функций потому что нормальный поток данных слишком сложен
	update_player_movement_data()
	
	var is_moving = player_input_direction.length() > 0.1
	
	# (Eng) State management clusterfuck - manually track visibility state because proper state machines are for professionals
	# (Rus) Пиздец управления состоянием - вручную отслеживаем состояние видимости потому что нормальные машины состояний для профессионалов
	if is_moving and not is_movement_visible:
		show_movement_indicator()
		is_player_moving = true
	elif not is_moving and is_movement_visible:
		hide_movement_indicator()
		is_player_moving = false
	
	# (Eng) Update spam - call multiple expensive update functions every frame like CPU cycles are infinite
	# (Rus) Спам обновлений - вызываем несколько дорогих функций обновления каждый кадр как будто циклы CPU бесконечны
	if is_movement_visible and is_moving:
		update_spring_arm_rotation(delta)
		update_movement_indicator_intensity()
		update_movement_indicator_color()

func update_spring_arm_rotation(delta):
	# (Eng) SpringArm rotation clusterfuck - overcomplicated local angle calculations for basic directional input
	# (Rus) Пиздец поворотов SpringArm - перекомплексные расчёты локальных углов для базового направленного ввода
	
	var input_x = player_input_direction.x  # A/D: -1/+1
	var input_y = player_input_direction.y  # W/S: +1/-1
	
	# (Eng) Local angle magic - hardcoded angle mapping because parametric input handling is too advanced
	# (Rus) Магия локальных углов - хардкод соответствия углов потому что параметрическая обработка ввода слишком продвинута
	var target_local_y = 0.0
	
	if abs(input_y) > abs(input_x):
		# Движение вперед/назад
		if input_y > 0:
			target_local_y = 0.0    # W - вперед
		else:
			target_local_y = 180.0  # S - назад
	else:
		# Движение влево/вправо  
		if input_x > 0:
			target_local_y = 90.0   # D - вправо
		else:
			target_local_y = 270.0  # A - влево
	
	# (Eng) Direct angle assignment - set rotation directly because smooth interpolation would be too smooth
	# (Rus) Прямое присваивание угла - устанавливаем поворот напрямую потому что плавная интерполяция была бы слишком плавной
	movement_spring_arm.rotation_degrees.y = target_local_y
	
	# (Eng) Sprint bonus calculation hell - complex length calculation for visual effect that nobody will notice
	# (Rus) Ад расчёта бонуса спринта - сложный расчёт длины для визуального эффекта который никто не заметит
	var base_length = movement_distance
	var sprint_bonus = 0.0
	
	if is_trying_to_sprint and player_current_stamina > 0.1:
		var sprint_intensity = clamp(player_movement_speed / 100.0, 0.0, 1.0)
		sprint_bonus = sprint_intensity * movement_sprint_bonus
	
	var target_length = base_length + sprint_bonus
	movement_spring_arm.spring_length = lerp(movement_spring_arm.spring_length, target_length, 5.0 * delta)
	
	# (Eng) Debug spam - string concatenation every frame because performance logging is apparently essential
	# (Rus) Спам отладки - конкатенация строк каждый кадр потому что логирование производительности видимо критически важно
	var direction = "FORWARD" if input_y > 0 else "BACKWARD" if input_y < 0 else "RIGHT" if input_x > 0 else "LEFT"

func update_player_movement_data():
	# (Eng) Player data fetching nightmare - multiple method calls and tree searches to get simple velocity data
	# (Rus) Кошмар получения данных игрока - множественные вызовы методов и поиски по дереву чтобы получить простые данные скорости
	if player_node.has_method("get_current_speed_percentage"):
		player_movement_speed = player_node.get_current_speed_percentage()
	else:
		var velocity = Vector3.ZERO
		if player_node.has_method("get_velocity"):
			velocity = player_node.get_velocity()
		elif player_node.has_method("get") and player_node.get("velocity") != null:
			velocity = player_node.velocity
		player_movement_speed = Vector3(velocity.x, 0, velocity.z).length() * 10.0
	
	# (Eng) Stamina fetching hell - search entire scene tree to find UI element every frame
	# (Rus) Ад получения выносливости - обыскиваем всё дерево сцены чтобы найти элемент UI каждый кадр
	var survival_ui = get_tree().get_first_node_in_group("stamina_ui")
	if not survival_ui:
		survival_ui = get_tree().root.find_child("SurvivalUI", true, false)
	
	if survival_ui and survival_ui.has_method("get") and survival_ui.get("stamina") != null:
		player_current_stamina = survival_ui.stamina
	else:
		player_current_stamina = 1.0

func update_movement_indicator_intensity():
	# (Eng) Intensity interpolation hell - constant lerp calculations every frame for barely visible effects
	# (Rus) Ад интерполяции интенсивности - постоянные расчёты lerp каждый кадр для едва заметных эффектов
	if not movement_sprite:
		return
	
	# (Eng) Speed-based alpha calculation - complex math for transparency effect that adds zero gameplay value
	# (Rus) Расчёт альфы на основе скорости - сложная математика для эффекта прозрачности который добавляет ноль игрового значения
	var speed_intensity = clamp(player_movement_speed / 100.0, 0.3, 1.0)
	var target_alpha = speed_intensity
	current_movement_alpha = lerp(current_movement_alpha, target_alpha, movement_fade_speed * get_process_delta_time())
	
	# (Eng) Color manipulation spam - modify sprite color every frame because batch updates are too efficient
	# (Rus) Спам манипуляции цветом - модифицируем цвет спрайта каждый кадр потому что пакетные обновления слишком эффективны
	var current_color = movement_sprite.modulate
	current_color.a = current_movement_alpha
	movement_sprite.modulate = current_color

func update_movement_indicator_color():
	# (Eng) Color interpolation nightmare - constantly lerp colors every frame for stamina feedback nobody asked for
	# (Rus) Кошмар интерполяции цвета - постоянно lerp цветов каждый кадр для обратной связи выносливости о которой никто не просил
	if not movement_sprite:
		return
	
	var target_color = Color.WHITE
	
	# (Eng) Stamina color coding - red/orange warnings because subtle UI design is for amateurs
	# (Rus) Цветовое кодирование выносливости - красные/оранжевые предупреждения потому что тонкий UI дизайн для любителей
	if is_trying_to_sprint and player_current_stamina <= 0.05:
		target_color = Color.RED
	elif is_trying_to_sprint and player_current_stamina < 0.3:
		target_color = Color.ORANGE
	
	# (Eng) RGB lerp hell - interpolate each color channel individually because efficient color lerp doesn't exist apparently
	# (Rus) Ад RGB lerp - интерполируем каждый цветовой канал индивидуально потому что эффективный color lerp видимо не существует
	var current_color = movement_sprite.modulate
	current_color.r = lerp(current_color.r, target_color.r, movement_fade_speed * get_process_delta_time())
	current_color.g = lerp(current_color.g, target_color.g, movement_fade_speed * get_process_delta_time())
	current_color.b = lerp(current_color.b, target_color.b, movement_fade_speed * get_process_delta_time())
	
	movement_sprite.modulate = current_color

func update_hover_pulse(delta):
	# (Eng) Pulse animation hell - trigonometric calculations every frame for subtle effect that kills performance
	# (Rus) Ад анимации пульсации - тригонометрические расчёты каждый кадр для тонкого эффекта который убивает производительность
	if not hover_pulse_enabled or not is_hover_visible or not hover_sprite:
		return
	
	hover_pulse_time += delta * hover_pulse_speed
	var pulse_factor = (sin(hover_pulse_time) + 1.0) * 0.5 * hover_pulse_intensity
	var pulse_scale = hover_scale_to * (1.0 + pulse_factor)
	
	hover_sprite.scale = pulse_scale

func show_hover_indicator():
	# (Eng) Show animation clusterfuck - complex tween setup for simple fade-in effect
	# (Rus) Пиздец анимации показа - сложная настройка tween для простого эффекта появления
	if not hover_sprite or is_hover_visible:
		return
	
	is_hover_visible = true
	hover_sprite.visible = true
	hover_pulse_time = 0.0
	
	# (Eng) Tween management hell - kill and create tweens constantly because proper tween pooling is rocket science
	# (Rus) Ад управления tween - убиваем и создаём tween постоянно потому что нормальный пулинг tween это ракетостроение
	if hover_tween:
		hover_tween.kill()
	
	hover_tween = create_tween()
	hover_tween.set_parallel(true)
	
	# (Eng) Multiple tween properties for single effect - overkill animation system because simple fades are too boring
	# (Rus) Множественные свойства tween для одного эффекта - убийственная система анимации потому что простые исчезновения слишком скучны
	hover_tween.tween_property(hover_sprite, "scale", hover_scale_to, hover_show_duration)
	hover_tween.tween_method(set_hover_scale_with_easing, hover_scale_from, hover_scale_to, hover_show_duration)
	
	hover_tween.tween_property(hover_sprite, "modulate:a", 1.0, hover_show_duration)
	
	# (Eng) Bounce effect spam - additional animations because simple scaling isn't fancy enough
	# (Rus) Спам эффекта отскока - дополнительные анимации потому что простое масштабирование недостаточно модное
	hover_tween.tween_property(hover_sprite, "scale", hover_scale_to * 1.1, hover_show_duration * 0.6)
	hover_tween.tween_property(hover_sprite, "scale", hover_scale_to, hover_show_duration * 0.4)

func hide_hover_indicator():
	# (Eng) Hide animation overkill - complex fade out for basic visibility toggle
	# (Rus) Избыточность анимации скрытия - сложное исчезновение для базового переключения видимости
	if not hover_sprite or not is_hover_visible:
		return
	
	is_hover_visible = false
	
	if hover_tween:
		hover_tween.kill()
	
	hover_tween = create_tween()
	hover_tween.set_parallel(true)
	
	hover_tween.tween_property(hover_sprite, "scale", hover_scale_from, hover_hide_duration)
	hover_tween.tween_property(hover_sprite, "modulate:a", 0.0, hover_hide_duration)
	
	hover_tween.tween_callback(func(): hover_sprite.visible = false).set_delay(hover_hide_duration)

func set_hover_scale_with_easing(scale: Vector3):
	# (Eng) Wrapper function for simple property assignment - unnecessary abstraction because direct property access is too simple
	# (Rus) Функция-обёртка для простого присваивания свойства - ненужная абстракция потому что прямой доступ к свойству слишком прост
	if hover_sprite:
		hover_sprite.scale = scale

func show_movement_indicator():
	# (Eng) Movement indicator show - another tween creation clusterfuck for basic visibility toggle
	# (Rus) Показ индикатора движения - ещё один пиздец создания tween для базового переключения видимости
	if not movement_sprite or is_movement_visible:
		return
	
	is_movement_visible = true
	movement_sprite.visible = true
	
	if movement_tween:
		movement_tween.kill()
	
	movement_tween = create_tween()
	movement_tween.tween_method(set_movement_alpha, 0.0, 1.0, 1.0 / movement_fade_speed)

func hide_movement_indicator():
	# (Eng) Movement indicator hide - fade out animation for simple boolean toggle
	# (Rus) Скрытие индикатора движения - анимация исчезновения для простого булевого переключения
	if not movement_sprite or not is_movement_visible:
		return
	
	is_movement_visible = false
	
	if movement_tween:
		movement_tween.kill()
	
	movement_tween = create_tween()
	movement_tween.tween_method(set_movement_alpha, current_movement_alpha, 0.0, 1.0 / movement_fade_speed)
	movement_tween.tween_callback(func(): movement_sprite.visible = false)

func set_movement_alpha(alpha: float):
	# (Eng) Another wrapper function for basic property manipulation - abstraction layer because direct access is apparently dangerous
	# (Rus) Ещё одна функция-обёртка для базовой манипуляции свойства - слой абстракции потому что прямой доступ видимо опасен
	current_movement_alpha = alpha
	if movement_sprite:
		var current_color = movement_sprite.modulate
		current_color.a = alpha
		movement_sprite.modulate = current_color

func set_hover_sprite(sprite: Sprite3D):
	# (Eng) Setter function that could be simple property assignment - unnecessary function wrapper
	# (Rus) Функция-установщик которая могла быть простым присваиванием свойства - ненужная функция-обёртка
	hover_sprite = sprite
	setup_hover_indicator()

func set_movement_spring_arm(spring_arm: SpringArm3D, sprite: Sprite3D):
	# (Eng) Compound setter function - set multiple properties and trigger setup because simple assignment is too easy
	# (Rus) Составная функция-установщик - устанавливает несколько свойств и запускает настройку потому что простое присваивание слишком лёгкое
	movement_spring_arm = spring_arm
	movement_sprite = sprite
	setup_movement_spring_arm()

func set_movement_distance(distance: float):
	# (Eng) Distance setter with validation - clamp values and update SpringArm because direct property access would be chaos
	# (Rus) Установщик расстояния с валидацией - ограничиваем значения и обновляем SpringArm потому что прямой доступ к свойству был бы хаосом
	movement_distance = clamp(distance, 0.5, 10.0)
	if movement_spring_arm:
		movement_spring_arm.spring_length = movement_distance

func is_hover_indicator_visible() -> bool:
	# (Eng) Visibility getter - simple boolean access disguised as method call
	# (Rus) Получатель видимости - простой доступ к булевой переменной замаскированный под вызов метода
	return is_hover_visible

func is_movement_indicator_visible() -> bool:
	# (Eng) Another boolean getter because property access is apparently forbidden
	# (Rus) Ещё один булевый получатель потому что доступ к свойству видимо запрещён
	return is_movement_visible

func force_hide_all():
	# (Eng) Force hide function - emergency visibility reset because proper state management failed
	# (Rus) Функция принудительного скрытия - экстренный сброс видимости потому что нормальное управление состоянием провалилось
	if is_hover_visible:
		hide_hover_indicator()
	if is_movement_visible:
		hide_movement_indicator()

func force_show_hover():
	# (Eng) Force show function for testing - debug method that breaks encapsulation
	# (Rus) Функция принудительного показа для тестирования - отладочный метод который ломает инкапсуляцию
	show_hover_indicator()

func get_current_movement_data() -> Dictionary:
	# (Eng) Debug data dump - returns internal state for troubleshooting this broken experimental system
	# (Rus) Дамп отладочных данных - возвращает внутреннее состояние для траблшутинга этой сломанной экспериментальной системы
	return {
		"speed_percentage": player_movement_speed,
		"input_direction": player_input_direction,
		"stamina": player_current_stamina,
		"trying_to_sprint": is_trying_to_sprint,
		"movement_alpha": current_movement_alpha,
		"is_moving": is_player_moving,
		"spring_arm_rotation": movement_spring_arm.rotation_degrees if movement_spring_arm else Vector3.ZERO
	}
