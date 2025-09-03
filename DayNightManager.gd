# DayNightManager.gd - Autoload Singleton
extends Node

# ============================================================================
# SIGNALS & EXPORTS
# ============================================================================
signal day_started(day_number: int)
signal night_started(night_number: int)
signal time_changed(current_time_str: String, is_day_current: bool, day_num: int, time_of_day_description: String, game_hour_float_val: float)
signal critical_night_approaching # For Night 3 drama

@export var day_duration: float = 12.0 * 60.0 # Реальные секунды для игрового дня (6:00 до 18:00)
@export var night_duration: float = 12.0 * 60.0 # Реальные секунды для игровой ночи (18:00 до 6:00)

# Эти @onready переменные теперь только объявляются, но не инициализируются путями здесь,
# так как их поиск будет происходить позже в setup_scene_nodes().
@onready var directional_light: DirectionalLight3D
@onready var world_environment_node: WorldEnvironment

# Добавьте экспортируемые кривые/градиенты, если они нужны для настройки в инспекторе
@export var light_energy_curve: Curve
@export var ambient_color_curve: Gradient
@export var sky_color_curve: Gradient
@export var ground_color_curve: Gradient

var last_game_minute: int = -1 

# ============================================================================
# ВРЕМЯ И ПЕРИОДЫ ДНЯ - для красивого UI
# ============================================================================
enum TimeOfDay {
	MIDNIGHT, # ~00:00 - 04:00
	DAWN, # ~04:00 - 06:00 (Начало света)
	MORNING, # ~06:00 - 10:00 (Яркое утро)
	NOON, # ~10:00 - 14:00 (Полдень, самый яркий)
	AFTERNOON, # ~14:00 - 18:00 (День, послеполуденное солнце)
	EVENING, # ~18:00 - 20:00 (Начало сумерек)
	DUSK, # ~20:00 - 22:00 (Сумерки, темнеет)
	NIGHT # ~22:00 - 00:00 (Глубокая ночь)
}

# Текстовые описания времени (РУССКИЕ)
var time_descriptions_ru = {
	TimeOfDay.MIDNIGHT: "Полночь",
	TimeOfDay.DAWN: "Рассвет",
	TimeOfDay.MORNING: "Утро",
	TimeOfDay.NOON: "Полдень",
	TimeOfDay.AFTERNOON: "День",
	TimeOfDay.EVENING: "Вечер",
	TimeOfDay.DUSK: "Сумерки",
	TimeOfDay.NIGHT: "Ночь"
}

# Текстовые описания времени (АНГЛИЙСКИЕ)
var time_descriptions_en = {
	TimeOfDay.MIDNIGHT: "Midnight",
	TimeOfDay.DAWN: "Dawn",
	TimeOfDay.MORNING: "Morning",
	TimeOfDay.NOON: "Noon",
	TimeOfDay.AFTERNOON: "Afternoon",
	TimeOfDay.EVENING: "Evening",
	TimeOfDay.DUSK: "Dusk",
	TimeOfDay.NIGHT: "Night"
}

# ============================================================================
# STATE VARIABLES
# ============================================================================
var total_game_time_in_hours: float = 0.0 # Общее игровое время в ЧАСАХ (0.0 - бесконечность)

var current_day: int = 1 # Текущий игровой день (1, 2, 3...)
var is_day: bool = true # Игровая логика: True = с 6:00 до 18:00, False = с 18:00 до 6:00

var current_hour_game_logic: int = 0 # Текущий час (0-23) для игровой логики и enum TimeOfDay
var current_time_of_day: TimeOfDay = TimeOfDay.MORNING # Текущий период дня
var previous_time_of_day: TimeOfDay # Добавлена для отслеживания изменений в логах

var original_sky_resource: Sky = null # Сохраняем оригинальный Sky ресурс для восстановления

# ============================================================================
# DAY/NIGHT VISUAL SETTINGS - МАКСИМАЛЬНО ТЕМНАЯ НОЧЬ И ЯРКИЙ ДЕНЬ
# ============================================================================
# Light Energy для DirectionalLight3D
var day_light_energy: float = 1.0 # Яркое солнце днем
var night_light_energy: float = 0.001 # Почти полное отсутствие солнца ночью

# Ambient Light для WorldEnvironment (цвет общего окружающего света)
var day_ambient_color: Color = Color(0.7, 0.8, 1.0, 1.0) # Светлый синий днем
var night_ambient_color: Color = Color(0.01, 0.01, 0.05, 1.0) # Почти черный с легким оттенком ночью

# Sky Energy для SkyMaterial (общая яркость неба и ground_energy_multiplier)
var day_sky_energy: float = 1.0 # Полная энергия Sky днем
var night_sky_energy: float = 0.001 # Почти ноль света от Sky ночью

# Цвета для ProceduralSkyMaterial во время дня и ночи
var day_sky_top_color: Color = Color(0.2, 0.4, 0.8) # Ярко-голубое небо
var day_sky_horizon_color: Color = Color(0.6, 0.8, 1.0) # Светлый горизонт
var day_ground_color: Color = Color(0.3, 0.25, 0.2) # Цвет земли днем
var day_sun_disk_color: Color = Color(1.0, 0.9, 0.8) # Цвет солнца днем

var night_sky_top_color: Color = Color(0.01, 0.01, 0.05) # Почти черное небо
var night_sky_horizon_color: Color = Color(0.01, 0.01, 0.05) # Почти черный горизонт
var night_ground_color: Color = Color(0.01, 0.01, 0.03) # Почти черная земля ночью
var night_sun_disk_color: Color = Color(0.0, 0.0, 0.0) # Солнца ночью нет (можно сделать луну)

# ============================================================================
# INITIALIZATION
# ============================================================================
func _ready():
	set_process(true)
	
	previous_time_of_day = current_time_of_day # Инициализируем
	
	# --- НОВОЕ: Переносим логику поиска узлов в отдельную функцию,
	#            которая будет вызвана отложено. Это гарантирует, что основная сцена
	#            и ее узлы будут загружены, когда мы их ищем.
	call_deferred("setup_scene_nodes")
	
	# --- Инициализация времени и состояния игры (может оставаться здесь) ---
	total_game_time_in_hours = 6.0 # Всегда начинаем с 6:00 утра
	current_day = 1 # Всегда начинаем с Дня 1 для пользователя
	is_day = true
	current_hour_game_logic = 6
	current_time_of_day = TimeOfDay.MORNING
	previous_time_of_day = TimeOfDay.MORNING
	

# ============================================================================
# SETUP SCENE NODES (Delayed for Autoloads)
# ============================================================================
func setup_scene_nodes():
	"""
	Эта функция вызывается отложено (`call_deferred`), когда основная сцена
	и ее дочерние узлы уже гарантированно добавлены в дерево.
	"""
	# Получаем корневой узел дерева сцены
	var root_node = get_tree().get_root()
	
	# Пытаемся найти узел 'GAME' как прямой дочерний элемент корневого узла.
	# Если ваша основная сцена загружается с другим именем корневого узла,
	# измените "GAME" на это имя.
	var game_node = root_node.get_node_or_null("Last Man Breathing/GAME")

	if not is_instance_valid(game_node):
		# Возможно, здесь стоит добавить some_error_handling() или disable_day_night_system()
		return

	# Теперь, когда узел 'GAME' найден, ищем SunLight и WorldEnvironment относительно него.
	directional_light = game_node.get_node_or_null("SunLight")
	world_environment_node = game_node.get_node_or_null("WorldEnvironment")

	# --- ПРОВЕРКА И ИНИЦИАЛИЗАЦИЯ DIRECTIONAL LIGHT И WORLD ENVIRONMENT ---
	if not is_instance_valid(directional_light):
		print("❌ DirectionalLight3D НЕ НАЙДЕН по пути 'GAME/SunLight'! Освещение не будет работать корректно.")
	else:
		print("✅ DirectionalLight3D найден по пути GAME/SunLight.")
		
	if not is_instance_valid(world_environment_node):
		print("❌ WorldEnvironment НЕ НАЙДЕН по пути 'GAME/WorldEnvironment'! Окружение не будет обновляться.")
	elif world_environment_node.environment:
		# Убедимся, что Environment ресурс существует
		if world_environment_node.environment == null:
			world_environment_node.environment = Environment.new()

		# Убедимся, что Sky ресурс существует. Если нет, создаем ProceduralSkyMaterial.
		if world_environment_node.environment.sky == null:
			var new_sky = Sky.new()
			var new_sky_material = ProceduralSkyMaterial.new()
			new_sky.sky_material = new_sky_material
			world_environment_node.environment.sky = new_sky
			original_sky_resource = new_sky.duplicate() # Сохраняем созданный
		elif world_environment_node.environment.sky.sky_material == null:
			var new_sky_material = ProceduralSkyMaterial.new()
			world_environment_node.environment.sky.sky_material = new_sky_material
			original_sky_resource = world_environment_node.environment.sky.duplicate() # Сохраняем с новым материалом
		else:
			original_sky_resource = world_environment_node.environment.sky.duplicate() # Дублируем
			
		world_environment_node.environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	else:
		print("❌ WorldEnvironment узел найден, но ресурс Environment или Sky в нем отсутствует! Окружение не будет обновляться.")
	
	# Делаем первое полное обновление визуала только после того, как все узлы найдены и готовы
	update_environment_visuals(get_current_hour_float())
	#print_time_diagnostics()


# ============================================================================
# MAIN CYCLE LOGIC
# ============================================================================
func _process(delta: float):
	var total_cycle_duration_real_seconds = day_duration + night_duration
	var game_hours_per_real_second = 24.0 / total_cycle_duration_real_seconds
	
	total_game_time_in_hours += delta * game_hours_per_real_second
	
	var game_hour_float = fmod(total_game_time_in_hours, 24.0)
	var game_minute = int(game_hour_float * 60.0) # считаем минуты

	if game_minute != last_game_minute:
		last_game_minute = game_minute
		_on_game_minute_changed(game_hour_float)
		
func _on_game_minute_changed(game_hour_float: float):
	var new_current_hour_game_logic = int(game_hour_float)
	var new_current_day = int(floor(total_game_time_in_hours / 24.0)) + 1
	
	# Обновление дня
	if new_current_day > current_day:
		current_day = new_current_day
	
	# Смена дня/ночи
	var was_day_before = is_day
	is_day = new_current_hour_game_logic >= 6 and new_current_hour_game_logic < 18
	
	if was_day_before and not is_day:
		night_started.emit(current_day)
		if current_day == 3:
			critical_night_approaching.emit()
	elif not was_day_before and is_day:
		day_started.emit(current_day)
	
	# Обновляем период и визуал
	update_time_of_day(game_hour_float)
	update_environment_visuals(game_hour_float)
	
	# Сигнал UI
	time_changed.emit(get_formatted_time(), is_day, current_day, get_current_time_description_ru(), game_hour_float)


# ============================================================================
# ВИЗУАЛЬНЫЕ ПЕРЕХОДЫ И ВРЕМЯ ДНЯ (для UI/enum)
# ============================================================================
func update_time_of_day(game_hour_float: float):
	"""
	Определяет текущий период дня (для UI и логики enum)
	и логирует изменение периода.
	"""
	previous_time_of_day = current_time_of_day # Сохраняем текущее состояние перед обновлением
	
	var current_hour_for_timeofday_enum = int(game_hour_float) # Используем целую часть часа для enum

	match current_hour_for_timeofday_enum:
		22, 23: # 22:00 - 23:59
			current_time_of_day = TimeOfDay.NIGHT
		0, 1, 2, 3: # 00:00 - 03:59
			current_time_of_day = TimeOfDay.MIDNIGHT
		4, 5: # 04:00 - 05:59
			current_time_of_day = TimeOfDay.DAWN
		6, 7, 8, 9: # 06:00 - 09:59
			current_time_of_day = TimeOfDay.MORNING
		10, 11, 12, 13: # 10:00 - 13:59
			current_time_of_day = TimeOfDay.NOON
		14, 15, 16, 17: # 14:00 - 17:59
			current_time_of_day = TimeOfDay.AFTERNOON
		18, 19: # 18:00 - 19:59
			current_time_of_day = TimeOfDay.EVENING
		20, 21: # 20:00 - 21:59
			current_time_of_day = TimeOfDay.DUSK
		_: # На случай, если час выйдет за пределы (ошибка)
			current_time_of_day = TimeOfDay.NIGHT # Дефолтное значение

	# Логируем, если период дня изменился (РУССКИЙ)
	if current_time_of_day != previous_time_of_day:
		print("⏰ Период дня изменился на: %s (Время: %s)" % [time_descriptions_ru[current_time_of_day], get_formatted_time()])

# ============================================================================
# VISUAL ENVIRONMENT UPDATES (НОВАЯ, БОЛЕЕ ПЛАВНАЯ ЛОГИКА ИНТЕРПОЛЯЦИИ)
# ============================================================================
func update_environment_visuals(game_hour_float: float):
	"""
	Обеспечивает плавные визуальные переходы для освещения DirectionalLight3D
	и настроек WorldEnvironment (включая SkyMaterial) на основе одной непрерывной кривой.
	game_hour_float: Текущий час (0.0-23.999...)
	"""
	# Добавляем проверку, что узлы инициализированы
	if not is_instance_valid(world_environment_node) or not is_instance_valid(directional_light) or not world_environment_node.environment:
		# Если узлы еще не найдены (например, setup_scene_nodes еще не отработал)
		# или если Environment не назначен, просто выходим, чтобы избежать ошибок.
		return 

	var env = world_environment_node.environment

	# Определяем "ключевые часы" для интерполяции.
	const PEAK_NIGHT_HOUR_1 = 0.0
	const LIGHT_START_HOUR = 2.0
	const DAWN_PEAK_HOUR = 6.0
	const MORNING_PEAK_HOUR = 10.0
	const PEAK_DAY_HOUR_1 = 12.0
	const PEAK_DAY_HOUR_2 = 16.0
	const SUNSET_PEAK_HOUR = 18.0
	const DUSK_END_HOUR = 22.0
	const PEAK_NIGHT_HOUR_2 = 24.0

	# --- 1. Прогресс яркости дня/ночи (от 0.0 = полная ночь до 1.0 = полный день) ---
	var day_night_progress: float = 0.0

	if game_hour_float >= LIGHT_START_HOUR and game_hour_float < MORNING_PEAK_HOUR:
		# Рассвет: от почти нуля до почти полной дневной яркости
		day_night_progress = inverse_lerp(LIGHT_START_HOUR, MORNING_PEAK_HOUR, game_hour_float)
	elif game_hour_float >= MORNING_PEAK_HOUR and game_hour_float < SUNSET_PEAK_HOUR:
		# Полный день: всегда 1.0
		day_night_progress = 1.0
	elif game_hour_float >= SUNSET_PEAK_HOUR and game_hour_float < DUSK_END_HOUR:
		# Закат: от полной дневной яркости до почти нуля
		day_night_progress = inverse_lerp(SUNSET_PEAK_HOUR, DUSK_END_HOUR, game_hour_float)
		day_night_progress = 1.0 - day_night_progress # Инвертируем, чтобы шел от 1 до 0
	else:
		# Полная ночь: 0.0
		day_night_progress = 0.0
	
	day_night_progress = smoothstep(0.0, 1.0, day_night_progress)

	# --- 2. Интерполяция параметров освещения на основе day_night_progress ---
	var current_light_energy = lerp(night_light_energy, day_light_energy, day_night_progress)
	var current_ambient_color = night_ambient_color.lerp(day_ambient_color, day_night_progress)
	var current_sky_energy = lerp(night_sky_energy, day_sky_energy, day_night_progress)
	
	var current_sky_top_color = night_sky_top_color.lerp(day_sky_top_color, day_night_progress)
	var current_sky_horizon_color = night_sky_horizon_color.lerp(day_sky_horizon_color, day_night_progress)
	var current_ground_bottom_color = night_ground_color.lerp(day_ground_color, day_night_progress)
	var current_ground_horizon_color = night_ground_color.lerp(day_ground_color, day_night_progress)
	var current_ground_energy = lerp(night_sky_energy, day_sky_energy, day_night_progress)

	# --- 3. Применение дополнительного затемнения для "Критической Ночи" (День 3) ---
	if current_day == 3 and not is_day: # Активируем только когда игровая логика - ночь 3
		var critical_night_factor = 0.0
		if game_hour_float >= SUNSET_PEAK_HOUR and game_hour_float <= PEAK_NIGHT_HOUR_2:
			critical_night_factor = inverse_lerp(SUNSET_PEAK_HOUR, PEAK_NIGHT_HOUR_2, game_hour_float)
		elif game_hour_float >= PEAK_NIGHT_HOUR_1 and game_hour_float < DAWN_PEAK_HOUR:
			critical_night_factor = inverse_lerp(PEAK_NIGHT_HOUR_1, DAWN_PEAK_HOUR, game_hour_float)
			critical_night_factor = 1.0 - critical_night_factor
		
		critical_night_factor = smoothstep(0.0, 1.0, critical_night_factor)
		
		current_light_energy *= lerp(1.0, 0.2, critical_night_factor)
		current_sky_energy *= lerp(1.0, 0.1, critical_night_factor)
		current_ambient_color = current_ambient_color.lerp(Color.BLACK, lerp(0.0, 0.7, critical_night_factor))
		
		current_sky_top_color = current_sky_top_color.lerp(Color.BLACK, lerp(0.0, 0.7, critical_night_factor))
		current_sky_horizon_color = current_sky_horizon_color.lerp(Color.BLACK, lerp(0.0, 0.7, critical_night_factor))
		current_ground_bottom_color = current_ground_bottom_color.lerp(Color.BLACK, lerp(0.0, 0.7, critical_night_factor))
		current_ground_horizon_color = current_ground_horizon_color.lerp(Color.BLACK, lerp(0.0, 0.7, critical_night_factor))
		

	# --- 4. Применение к DirectionalLight3D ---
	directional_light.light_energy = current_light_energy
	
	var rotation_x_angle: float
	if game_hour_float >= DAWN_PEAK_HOUR and game_hour_float <= SUNSET_PEAK_HOUR:
		rotation_x_angle = lerp(90.0, -90.0, inverse_lerp(DAWN_PEAK_HOUR, SUNSET_PEAK_HOUR, game_hour_float))
	else:
		if game_hour_float > SUNSET_PEAK_HOUR:
			rotation_x_angle = lerp(-90.0, 180.0, inverse_lerp(SUNSET_PEAK_HOUR, PEAK_NIGHT_HOUR_2, game_hour_float))
		else:
			rotation_x_angle = lerp(180.0, 90.0, inverse_lerp(PEAK_NIGHT_HOUR_1, DAWN_PEAK_HOUR, game_hour_float))
	
	directional_light.rotation_degrees.x = rotation_x_angle

	# --- 5. Применение к WORLDENVIRONMENT ---
	if env:
		if env.sky == null:
			env.sky = original_sky_resource.duplicate()
		if env.sky.sky_material == null:
			env.sky.sky_material = ProceduralSkyMaterial.new()
		
		if env.sky.sky_material is ProceduralSkyMaterial:
			var sky_mat = env.sky.sky_material as ProceduralSkyMaterial
			
			sky_mat.sky_top_color = current_sky_top_color
			sky_mat.sky_horizon_color = current_sky_horizon_color
			sky_mat.ground_bottom_color = current_ground_bottom_color
			sky_mat.ground_horizon_color = current_ground_horizon_color
			sky_mat.ground_energy_multiplier = current_ground_energy

		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.ambient_light_color = current_ambient_color
		env.ambient_light_energy = current_sky_energy
	
# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

func get_current_hour_float() -> float:
	return fmod(total_game_time_in_hours, 24.0)

func get_current_hour_int() -> int:
	return int(get_current_hour_float())

func get_current_time_description_ru() -> String:
	return time_descriptions_ru[current_time_of_day]

func get_current_time_description_en() -> String:
	return time_descriptions_en[current_time_of_day]

func get_formatted_time() -> String:
	var hours_24 = int(get_current_hour_float())
	var minutes = int(fmod(get_current_hour_float() * 60.0, 60.0))

	var display_hour: int = hours_24
	var period: String = "AM"

	if display_hour >= 12:
		period = "PM"
	if display_hour > 12:
		display_hour -= 12
	if display_hour == 0:
		display_hour = 12
	
	return "%02d:%02d %s" % [display_hour, minutes, period]

func get_formatted_hour_only() -> String:
	var hours_24 = int(get_current_hour_float())
	var display_hour: int = hours_24
	var period: String = "AM"

	if display_hour >= 12:
		period = "PM"
	if display_hour > 12:
		display_hour -= 12
	if display_hour == 0:
		display_hour = 12
	
	return "%d %s" % [display_hour, period]

func get_current_day_number_string() -> String:
	return "Day %d" % current_day

func get_current_period_name() -> String:
	return "День " + str(current_day) if is_day else "Ночь " + str(current_day)

func get_time_remaining_in_current_game_phase() -> float:
	var hours_in_current_cycle_for_visuals = fmod(total_game_time_in_hours, 24.0)
	var total_cycle_duration_real_seconds = day_duration + night_duration
	var real_seconds_per_game_hour = total_cycle_duration_real_seconds / 24.0

	if is_day:
		var hours_until_night = 18.0 - hours_in_current_cycle_for_visuals
		return hours_until_night * real_seconds_per_game_hour
	else:
		var hours_until_next_morning_six_am: float
		if hours_in_current_cycle_for_visuals >= 18.0:
			hours_until_next_morning_six_am = 24.0 - hours_in_current_cycle_for_visuals + 6.0
		else:
			hours_until_next_morning_six_am = 6.0 - hours_in_current_cycle_for_visuals
		return hours_until_next_morning_six_am * real_seconds_per_game_hour


func get_time_remaining_formatted() -> String:
	var remaining = get_time_remaining_in_current_game_phase()
	var minutes = int(remaining / 60)
	var seconds = int(fmod(remaining, 60))
	return "%02d:%02d" % [minutes, seconds]

func is_night_time() -> bool:
	return not is_day

func get_current_day() -> int:
	return current_day

func is_critical_night() -> bool:
	return current_day == 3 and not is_day

# ============================================================================
# SAVE/LOAD SUPPORT (Поддержка сохранения/загрузки состояния)
# ============================================================================
func get_save_data() -> Dictionary:
	return {
		"total_game_time_in_hours": total_game_time_in_hours,
		"current_day": current_day,
		"is_day": is_day
	}

func load_save_data(data: Dictionary):
	total_game_time_in_hours = data.get("total_game_time_in_hours", 6.0)
	current_day = data.get("current_day", 1)
	is_day = data.get("is_day", true)
	
	current_hour_game_logic = int(fmod(total_game_time_in_hours, 24.0))
	update_time_of_day(fmod(total_game_time_in_hours, 24.0))
	update_environment_visuals(fmod(total_game_time_in_hours, 24.0))

# ============================================================================
# GODOT UTILITY HELPER (В Godot уже есть, но для ясности)
# ============================================================================
func inverse_lerp(a: float, b: float, value: float) -> float:
	if a == b:
		return 0.0
	return clamp((value - a) / (b - a), 0.0, 1.0)

func smoothstep(edge0: float, edge1: float, x: float) -> float:
	x = clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0)
	return x * x * (3 - 2 * x)
	
func get_debug_time_info() -> String:
	var current_game_hour_for_display = fmod(total_game_time_in_hours, 24.0)
	return "День %d | Реальное время: %.2f часов | Отображение: %s | Логика: %s" % [
		current_day,
		total_game_time_in_hours,
		get_formatted_time(),
		"ДЕНЬ" if is_day else "НОЧЬ"
	]
