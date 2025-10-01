# BioMonitorManager.gd
extends Node3D

class_name BioMonitorManager

# === СИГНАЛЫ ===
# Голод (существующие)
signal hunger_level_changed(progress: float) # 0.0 (голоден) до 1.0 (сыт)
signal critical_hunger_reached # Игрок полностью голоден
signal not_critical_hunger # Игрок поел после критического голода

# Жажда
signal thirst_level_changed(progress: float) # 0.0 (обезвожен) до 1.0 (гидратирован)
signal critical_dehydration_reached # Критическое обезвоживание
signal dehydration_recovered # Восстановление после критического обезвоживания

# Энергия/Сон
signal energy_level_changed(progress: float) # 0.0 (истощен) до 1.0 (бодр)
signal critical_exhaustion_reached # Критическая усталость
signal exhaustion_recovered # Восстановление после критической усталости

# === ЭКСПОРТ ПАРАМЕТРЫ - НАЧАЛЬНЫЕ ЗНАЧЕНИЯ ===
@export_group("Initial Values")
@export var initial_hunger_percent: float = 100.0
@export var initial_thirst_percent: float = 100.0
@export var initial_energy_percent: float = 100.0

# === ЭКСПОРТ ПАРАМЕТРЫ - МАКСИМАЛЬНЫЕ ЗНАЧЕНИЯ ===
@export_group("Maximum Values")
@export var max_calories: float = 2500.0
@export var max_hydration: float = 100.0 # Условные единицы гидратации
@export var max_energy: float = 100.0 # Условные единицы энергии

# === ЭКСПОРТ ПАРАМЕТРЫ - РАСХОДЫ В ЧАС ===
@export_group("Hourly Consumption")
@export var base_metabolism_rate: float = 100.0 # Базовый расход калорий в час (BMR)
@export var base_thirst_rate: float = 5.0 # Базовый расход гидратации в час (5% от макс.)
@export var base_energy_rate: float = 7.0 # Базовый расход энергии в час (7% от макс.)

# === ЭКСПОРТ ПАРАМЕТРЫ - КРИТИЧЕСКИЕ ПОРОГИ ===
@export_group("Critical Thresholds")
@export var critical_hunger_threshold: float = 0.0 # Процент калорий для критического голода (0.0 = 0 калорий)
@export var critical_thirst_threshold: float = 10.0 # 20% от максимальной гидратации
@export var critical_energy_threshold: float = 10.0 # 20% от максимальной энергии

# === ТЕКУЩИЕ ЗНАЧЕНИЯ ===
var current_calories: float
var current_hydration: float
var current_energy: float

# === ПРЕДЫДУЩИЕ ЗНАЧЕНИЯ (для отслеживания изменений) ===
var previous_calories: float
var previous_hydration: float
var previous_energy: float

# === СОСТОЯНИЯ ===
var last_game_hour: int = -1
var is_currently_critically_hungry: bool = false
var is_currently_critically_thirsty: bool = false
var is_currently_critically_tired: bool = false
var has_recently_eaten: bool = false
var has_recently_drunk: bool = false
var has_recently_rested: bool = false

# === ССЫЛКИ ===
@export var dn_manager: DayNightManager
@export var bio_monitor_ui: Control

func _ready():
	# Инициализация начальных значений
	current_calories = (initial_hunger_percent / 100.0) * max_calories
	current_hydration = (initial_thirst_percent / 100.0) * max_hydration
	current_energy = (initial_energy_percent / 100.0) * max_energy
	
	# Сохраняем начальные значения как предыдущие
	previous_calories = current_calories
	previous_hydration = current_hydration
	previous_energy = current_energy
	
	if dn_manager:
		dn_manager.time_changed.connect(_on_time_changed)
	else:
		print("ОШИБКА: DayNightManager не назначен в BioMonitorManager!")
		
	if not bio_monitor_ui:
		print("ОШИБКА: PlayerHUD_Control не назначен в BioMonitorManager! Динамические оповещения не будут работать.")

	# Инициализация начального прогресса и состояний
	call_deferred("emit_initial_progress")


func emit_initial_progress():
	hunger_level_changed.emit(calculate_hunger_progress())
	thirst_level_changed.emit(calculate_thirst_progress())
	energy_level_changed.emit(calculate_energy_progress())
	
	# Установим начальные критические состояния
	is_currently_critically_hungry = (current_calories <= max_calories * (critical_hunger_threshold / 100.0))
	is_currently_critically_thirsty = (current_hydration <= max_hydration * (critical_thirst_threshold / 100.0))
	is_currently_critically_tired = (current_energy <= max_energy * (critical_energy_threshold / 100.0))

func _on_time_changed(formatted_time: String, is_day: bool, day_number: int, period_description: String):
	var current_game_hour = int(dn_manager.get_current_hour_float()) 

	if current_game_hour != last_game_hour:
		last_game_hour = current_game_hour
		
		# Сбрасываем флаги недавнего восполнения
		if has_recently_eaten:
			has_recently_eaten = false
		if has_recently_drunk:
			has_recently_drunk = false
		if has_recently_rested:
			has_recently_rested = false
		
		# Сохраняем предыдущие значения ПЕРЕД расходом
		previous_calories = current_calories
		previous_hydration = current_hydration
		previous_energy = current_energy
		
		# === РАСХОД ПОКАЗАТЕЛЕЙ ===
		process_hourly_consumption()
		
		# === ОБНОВЛЕНИЕ UI ===
		update_ui_signals()
		
		# === ПРОВЕРКА КРИТИЧЕСКИХ СОСТОЯНИЙ ===
		check_critical_states()
		
		# === UI МЕТОДЫ (если назначен) ===
		if bio_monitor_ui:
			# Upper/Lower алерты только если НЕ в критических состояниях
			trigger_ui_alerts()

func process_hourly_consumption():
	"""Обрабатывает почасовой расход всех показателей"""
	# Голод
	var hourly_calorie_loss = base_metabolism_rate
	hourly_calorie_loss = apply_hunger_modifiers(hourly_calorie_loss) # TODO: Будущие модификаторы
	current_calories = max(0.0, current_calories - hourly_calorie_loss)
	
	# Жажда  
	var hourly_thirst_loss = base_thirst_rate
	hourly_thirst_loss = apply_thirst_modifiers(hourly_thirst_loss) # TODO: Жара, активность
	current_hydration = max(0.0, current_hydration - hourly_thirst_loss)
	
	# Энергия
	var hourly_energy_loss = base_energy_rate
	hourly_energy_loss = apply_energy_modifiers(hourly_energy_loss) # TODO: Влияние голода
	current_energy = max(0.0, current_energy - hourly_energy_loss)

func update_ui_signals():
	"""Отправляет сигналы обновления UI для всех показателей"""
	hunger_level_changed.emit(calculate_hunger_progress())
	thirst_level_changed.emit(calculate_thirst_progress())
	energy_level_changed.emit(calculate_energy_progress())

func check_critical_states():
	"""Проверяет критические состояния всех показателей"""
	# === ГОЛОД ===
	var new_critical_hunger = (current_calories <= max_calories * (critical_hunger_threshold / 100.0))
	if new_critical_hunger and not is_currently_critically_hungry:
		is_currently_critically_hungry = true
		critical_hunger_reached.emit()
		print("Игрок полностью голоден!")
	elif not new_critical_hunger and is_currently_critically_hungry:
		is_currently_critically_hungry = false
		not_critical_hunger.emit()
		print("Игрок поел, больше не в критическом голоде.")
	
	# === ЖАЖДА ===
	var new_critical_thirst = (current_hydration <= max_hydration * (critical_thirst_threshold / 100.0))
	if new_critical_thirst and not is_currently_critically_thirsty:
		is_currently_critically_thirsty = true
		critical_dehydration_reached.emit()
		print("Игрок критически обезвожен!")
	elif not new_critical_thirst and is_currently_critically_thirsty:
		is_currently_critically_thirsty = false
		dehydration_recovered.emit()
		print("Игрок восстановил гидратацию.")
	
	# === ЭНЕРГИЯ ===
	var new_critical_energy = (current_energy <= max_energy * (critical_energy_threshold / 100.0))
	if new_critical_energy and not is_currently_critically_tired:
		is_currently_critically_tired = true
		critical_exhaustion_reached.emit()
		print("Игрок критически устал! Энергия: ", current_energy, "/", max_energy)
	elif not new_critical_energy and is_currently_critically_tired:
		is_currently_critically_tired = false
		exhaustion_recovered.emit()
		print("Игрок восстановил энергию.")

func trigger_ui_alerts():
	"""Запускает UI алерты при изменении показателей"""
	# Голод - только если не в критическом состоянии и значение уменьшилось
	if not is_currently_critically_hungry and current_calories < previous_calories:
		bio_monitor_ui.trigger_hourly_hunger_alert()
	
	# Жажда - только если не в критическом состоянии и значение уменьшилось
	if not is_currently_critically_thirsty and current_hydration < previous_hydration:
		bio_monitor_ui.trigger_hourly_thirst_alert()
	
	# Энергия - только если не в критическом состоянии и значение уменьшилось
	if not is_currently_critically_tired and current_energy < previous_energy:
		bio_monitor_ui.trigger_hourly_energy_alert()

# === РАСЧЕТ ПРОГРЕССА ===
func calculate_hunger_progress() -> float:
	return clamp(current_calories / max_calories, 0.0, 1.0)

func calculate_thirst_progress() -> float:
	return clamp(current_hydration / max_hydration, 0.0, 1.0)

func calculate_energy_progress() -> float:
	return clamp(current_energy / max_energy, 0.0, 1.0)

# === МЕТОДЫ ВОСПОЛНЕНИЯ ===
func add_calories(amount: float):
	"""Добавляет калории и обновляет UI."""
	var old_critical_state = is_currently_critically_hungry
	
	current_calories = clamp(current_calories + amount, 0.0, max_calories)
	hunger_level_changed.emit(calculate_hunger_progress())
	has_recently_eaten = true
	
	# Проверяем изменение критического состояния
	var new_critical_state = (current_calories <= max_calories * (critical_hunger_threshold / 100.0))
	if old_critical_state and not new_critical_state:
		is_currently_critically_hungry = false
		not_critical_hunger.emit()
		print("Игрок поел, больше не в критическом голоде.")
	
	# Показываем Upper alert при восполнении
	if bio_monitor_ui:
		bio_monitor_ui.trigger_hunger_upper_alert()

func add_hydration(amount: float):
	"""Добавляет гидратацию и обновляет UI."""
	var old_critical_state = is_currently_critically_thirsty
	
	current_hydration = clamp(current_hydration + amount, 0.0, max_hydration)
	thirst_level_changed.emit(calculate_thirst_progress())
	has_recently_drunk = true
	
	# Проверяем изменение критического состояния
	var new_critical_state = (current_hydration <= max_hydration * (critical_thirst_threshold / 100.0))
	if old_critical_state and not new_critical_state:
		is_currently_critically_thirsty = false
		dehydration_recovered.emit()
		print("Игрок восстановил гидратацию.")
	
	# Показываем Upper alert при восполнении
	if bio_monitor_ui:
		bio_monitor_ui.trigger_thirst_upper_alert()

func add_energy(amount: float):
	"""Добавляет энергию и обновляет UI."""
	var old_critical_state = is_currently_critically_tired
	
	current_energy = clamp(current_energy + amount, 0.0, max_energy)
	energy_level_changed.emit(calculate_energy_progress())
	has_recently_rested = true
	
	# Проверяем изменение критического состояния
	var new_critical_state = (current_energy <= max_energy * (critical_energy_threshold / 100.0))
	if old_critical_state and not new_critical_state:
		is_currently_critically_tired = false
		exhaustion_recovered.emit()
		print("Игрок восстановил энергию.")
	
	# Показываем Upper alert при восполнении
	if bio_monitor_ui:
		bio_monitor_ui.trigger_energy_upper_alert()

func rest_sleep(hours: float):
	"""Восстанавливает энергию через сон."""
	# TODO: Реализовать восстановление через сон
	# Примерная логика: add_energy(hours * 12.5) # ~100% за 8 часов
	pass

# === МОДИФИКАТОРЫ (ЗАГЛУШКИ ДЛЯ БУДУЩЕГО ФУНКЦИОНАЛА) ===
func apply_hunger_modifiers(base_rate: float) -> float:
	"""Применяет модификаторы к расходу калорий"""
	# TODO: Влияние температуры, активности, болезней
	return base_rate

func apply_thirst_modifiers(base_rate: float) -> float:
	"""Применяет модификаторы к расходу гидратации"""
	# TODO: Влияние жары, физической активности, потоотделения
	return base_rate

func apply_energy_modifiers(base_rate: float) -> float:
	"""Применяет модификаторы к расходу энергии"""
	# TODO: Влияние голода, болезней, стресса
	return base_rate

# === ВСПОМОГАТЕЛЬНЫЕ МЕТОДЫ (СОВМЕСТИМОСТЬ) ===
func is_currently_satiated_from_meal() -> bool:
	return has_recently_eaten

func is_currently_hydrated_from_drink() -> bool:
	return has_recently_drunk

func is_currently_rested_from_sleep() -> bool:
	return has_recently_rested
