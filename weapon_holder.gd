# ✅ Script: WeaponHolder.gd
# (Eng) "Independent" weapon rotation system with complex angle math, constant tree searches and all that trigonometric clusterfuck bullshit
# (Rus) "Независимая" система поворота оружия со сложной математикой углов, постоянными поисками по дереву и всем этим тригонометрическим пиздецом
# 🔧 WIP ⚡ Prototype 🐛 Not Optimized — raw, unfinished crap, demo mechanics, eats resources / сырая, незавершённая хуйня, демо-механика, жрёт ресурсы
# ⚠ WARNING: This part is experimental and unstable / ВНИМАНИЕ: Этот кусок экспериментальный и нестабильный

extends Node3D

# (Eng) Configuration explosion - dozens of exported variables because having sensible defaults is apparently illegal
# (Rus) Взрыв конфигурации - дюжины экспортируемых переменных потому что иметь разумные значения по умолчанию видимо незаконно
@export_group("WeaponHolder Constraints")
@export var max_weapon_turn_degrees = 30.0  # Максимальный поворот WeaponHolder от БАЗОВОГО положения (РЕГУЛИРУЕМО)
@export var base_weapon_rotation_y = -90.0  # Базовый поворот WeaponHolder (начальное положение)
@export var weapon_sensitivity = 0.5        # Чувствительность WeaponHolder к поворотам головы (0.0-1.0)
@export var weapon_follows_cursor = true    # WeaponHolder смотрит на курсор (своя логика)
@export var instant_rotation = true         # Мгновенный поворот (как голова)

# (Eng) More configuration hell because apparently every boolean needs to be configurable
# (Rus) Больше конфигурационного ада потому что видимо каждый булев должен быть настраиваемым
@export_group("Behavior")
@export var enabled = true                  # Включить/выключить систему
@export var use_topdown_mode = true         # Работать в top-down режиме

@export_group("Debug")
@export var show_debug_info = false         # Показывать отладочную информацию

# (Eng) State tracking hell - "independent" system that depends on half the fucking scene tree
# (Rus) Ад отслеживания состояния - "независимая" система которая зависит от половины блядского дерева сцены
var current_weapon_yaw = 0.0
var player_node: Node3D
var crosshair_controller: Node

# (Eng) Node reference acquisition through parent traversal because proper dependency injection is rocket science
# (Rus) Получение ссылок на узлы через обход родителей потому что нормальное внедрение зависимостей это ракетостроение
@onready var head_node = get_parent()  # WeaponHolder находится под Head

func _ready():
	print("WeaponHolder.gd: 🔫 Инициализация системы поворота оружия")
	
	# (Eng) Node finding clusterfuck - search entire scene tree for dependencies
	# (Rus) Пиздец поиска узлов - обыскиваем всё дерево сцены в поисках зависимостей
	find_required_nodes()
	validate_setup()
	
	# (Eng) Base rotation setup with hardcoded angle conversions because parametric systems are too advanced
	# (Rus) Настройка базового поворота с хардкод преобразованиями углов потому что параметрические системы слишком продвинуты
	rotation.y = deg_to_rad(base_weapon_rotation_y)
	current_weapon_yaw = deg_to_rad(base_weapon_rotation_y)
	
	print("WeaponHolder.gd: ✅ Система готова (база: %.1f°, лимит: ±%.1f°)" % [base_weapon_rotation_y, max_weapon_turn_degrees])

func find_required_nodes():
	# (Eng) Dependency resolution nightmare - "independent" system that requires manual node linking
	# (Rus) Кошмар разрешения зависимостей - "независимая" система которая требует ручной привязки узлов
	
	if is_instance_valid(head_node):
		player_node = head_node.get_parent()
		if player_node:
			print("WeaponHolder.gd: ✅ Player найден: %s" % player_node.name)
		else:
			printerr("WeaponHolder.gd: ❌ Player не найден!")
	else:
		printerr("WeaponHolder.gd: ❌ Head node не найден!")
	
	# (Eng) More scene tree searching because proper component registration is too hard
	# (Rus) Больше поисков по дереву сцены потому что нормальная регистрация компонентов слишком сложна
	if player_node:
		crosshair_controller = player_node.get_node_or_null("CrosshairUI")
		if crosshair_controller:
			print("WeaponHolder.gd: ✅ CrosshairController найден")
		else:
			printerr("WeaponHolder.gd: ❌ CrosshairController не найден!")

func validate_setup():
	# (Eng) Configuration validation hell - manual parameter checking because proper validation systems are too complex
	# (Rus) Ад валидации конфигурации - ручная проверка параметров потому что нормальные системы валидации слишком сложны
	if max_weapon_turn_degrees <= 0:
		printerr("WeaponHolder.gd: ⚠️ max_weapon_turn_degrees должно быть > 0!")
		max_weapon_turn_degrees = 60.0
	
	if max_weapon_turn_degrees > 180:
		printerr("WeaponHolder.gd: ⚠️ max_weapon_turn_degrees слишком большое! Устанавливаю 180°")
		max_weapon_turn_degrees = 180.0

func _physics_process(delta):
	# (Eng) Main performance destroyer - runs complex trigonometric calculations every physics frame like CPU cycles are infinite
	# (Rus) Основной убийца производительности - запускает сложные тригонометрические вычисления каждый физический кадр как будто циклы CPU бесконечны
	
	if not enabled or not weapon_follows_cursor:
		return
	
	if not use_topdown_mode:
		# (Eng) FPS mode fallback with simple head following - because having consistent rotation logic would be too elegant
		# (Rus) Запасной режим FPS с простым следованием за головой - потому что иметь последовательную логику поворотов было бы слишком элегантно
		if is_instance_valid(head_node):
			rotation.y = head_node.rotation.y
		return
	
	# (Eng) Top-down rotation clusterfuck - complex angle math every physics frame
	# (Rus) Пиздец поворотов top-down - сложная математика углов каждый физический кадр
	handle_topdown_weapon_rotation(delta)

func handle_topdown_weapon_rotation(delta):
	# (Eng) Trigonometric hell - complex angle calculations with clamping, scaling, and normalization every frame
	# (Rus) Тригонометрический ад - сложные вычисления углов с ограничениями, масштабированием и нормализацией каждый кадр
	
	if not is_instance_valid(head_node):
		return
	
	# (Eng) Head rotation tracking - get rotation from another system because direct input would be too simple
	# (Rus) Отслеживание поворота головы - получаем поворот из другой системы потому что прямой ввод был бы слишком простым
	var head_local_rotation = head_node.rotation.y
	
	# (Eng) Sensitivity scaling - multiply rotation by arbitrary factor because direct control is too responsive apparently
	# (Rus) Масштабирование чувствительности - умножаем поворот на произвольный фактор потому что прямое управление видимо слишком отзывчивое
	var scaled_head_rotation = head_local_rotation * weapon_sensitivity
	
	# (Eng) Angle clamping hell - complex deviation calculation with degree-to-radian conversions
	# (Rus) Ад ограничения углов - сложный расчёт отклонения с преобразованиями градус-радиан
	var max_deviation_rad = deg_to_rad(max_weapon_turn_degrees)
	var target_deviation = clamp(scaled_head_rotation, -max_deviation_rad, max_deviation_rad)
	
	# (Eng) Base angle arithmetic - add base rotation to deviation because simple direct angles would be too straightforward
	# (Rus) Арифметика базовых углов - добавляем базовый поворот к отклонению потому что простые прямые углы были бы слишком прямолинейными
	var base_rad = deg_to_rad(base_weapon_rotation_y)
	var final_rotation = base_rad + target_deviation
	
	# (Eng) Rotation application with instant/smooth toggle - because having consistent behavior is overrated
	# (Rus) Применение поворота с переключением мгновенный/плавный - потому что иметь последовательное поведение переоценено
	if instant_rotation:
		rotation.y = final_rotation
		current_weapon_yaw = final_rotation
	else:
		var target_rotation = lerp_angle(rotation.y, final_rotation, 10.0 * delta)
		rotation.y = target_rotation
		current_weapon_yaw = target_rotation
	
	# (Eng) Forced axis reset - manually zero X and Z rotation because proper quaternion math is too advanced
	# (Rus) Принудительный сброс осей - вручную обнуляем поворот X и Z потому что нормальная математика кватернионов слишком продвинута
	rotation.x = 0
	rotation.z = 0
	
	# (Eng) Debug spam - complex string formatting and console output every physics frame because performance logging is essential
	# (Rus) Спам отладки - сложное форматирование строк и вывод в консоль каждый физический кадр потому что логирование производительности критически важно
	if show_debug_info:
		var head_deg = rad_to_deg(head_local_rotation)
		var scaled_head_deg = rad_to_deg(scaled_head_rotation)
		var deviation_deg = rad_to_deg(target_deviation)
		var final_deg = rad_to_deg(final_rotation)
		var is_limited = abs(scaled_head_rotation) > max_deviation_rad
		var limit_info = " [ОГРАНИЧЕН]" if is_limited else ""
		
		print("WeaponHolder: 🔫 Голова: %.1f° × %.1f = %.1f° → WeaponHolder: %.1f° (база %.1f°)%s" % [
			head_deg,
			weapon_sensitivity,
			scaled_head_deg,
			final_deg,
			base_weapon_rotation_y,
			limit_info
		])

func set_max_turn_degrees(degrees: float):
	# (Eng) Parameter setter with validation and console spam - because simple property assignment needs logging apparently
	# (Rus) Установщик параметра с валидацией и консольным спамом - потому что простое присваивание свойства видимо нуждается в логировании
	max_weapon_turn_degrees = clamp(degrees, 0.0, 180.0)
	print("WeaponHolder: 🎛️ Лимит поворота установлен: ±%.1f°" % max_weapon_turn_degrees)

func get_max_turn_degrees() -> float:
	# (Eng) Simple getter disguised as method - property access through function call because direct access would be chaos
	# (Rus) Простой получатель замаскированный под метод - доступ к свойству через вызов функции потому что прямой доступ был бы хаосом
	return max_weapon_turn_degrees

func enable_weapon_rotation(enable: bool):
	# (Eng) Boolean setter with console logging - because changing a flag requires user notification apparently
	# (Rus) Булев установщик с консольным логированием - потому что изменение флага видимо требует уведомления пользователя
	weapon_follows_cursor = enable
	print("WeaponHolder: %s поворот оружия" % ("✅ Включен" if enable else "❌ Отключен"))

func is_at_rotation_limit() -> bool:
	# (Eng) Rotation limit detection hell - complex trigonometric calculations to determine if weapon is at constraint boundary
	# (Rus) Ад обнаружения лимита поворота - сложные тригонометрические вычисления чтобы определить находится ли оружие на границе ограничения
	if not is_instance_valid(player_node) or not is_instance_valid(crosshair_controller):
		return false
	
	var look_dir = crosshair_controller.get_look_direction_for_head()
	if look_dir == Vector3.ZERO:
		return false
	
	# (Eng) Angle calculation clusterfuck - atan2, global rotation subtraction, and manual angle normalization
	# (Rus) Пиздец вычисления углов - atan2, вычитание глобального поворота и ручная нормализация углов
	var target_weapon_yaw = atan2(-look_dir.x, -look_dir.z)
	var player_body_yaw = player_node.global_rotation.y
	var relative_weapon_yaw = target_weapon_yaw - player_body_yaw
	
	# (Eng) Manual angle normalization because proper angle utilities don't exist apparently
	# (Rus) Ручная нормализация углов потому что нормальные утилиты работы с углами видимо не существуют
	while relative_weapon_yaw > PI:
		relative_weapon_yaw -= 2 * PI
	while relative_weapon_yaw < -PI:
		relative_weapon_yaw += 2 * PI
	
	var max_weapon_rad = deg_to_rad(max_weapon_turn_degrees)
	return abs(relative_weapon_yaw) > max_weapon_rad

func get_current_rotation_degrees() -> float:
	# (Eng) Rotation getter with unit conversion - radian-to-degree conversion because consistent units are optional
	# (Rus) Получатель поворота с преобразованием единиц - конверсия радиан-градус потому что последовательные единицы опциональны
	return rad_to_deg(current_weapon_yaw)

func reset_rotation():
	# (Eng) Manual rotation reset - set multiple properties to zero because proper state reset methods don't exist
	# (Rus) Ручной сброс поворота - устанавливаем множественные свойства в ноль потому что нормальные методы сброса состояния не существуют
	current_weapon_yaw = 0.0
	rotation.y = 0.0
	rotation.x = 0.0
	rotation.z = 0.0
	print("WeaponHolder: 🔄 Поворот сброшен")
