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

# === ЭКСПОРТ ПАРАМЕТРЫ - СОН ===
@export_group("Sleep")
## Percent of the energy track returned per hour slept. Eight hours is a night.
@export var energy_restored_per_hour: float = 12.5
## Metabolism while asleep, as a fraction of the waking rate.
@export_range(0.0, 1.0) var sleep_metabolism_factor: float = 0.65
## Hydration loss while asleep, as a fraction of the waking rate.
@export_range(0.0, 1.0) var sleep_thirst_factor: float = 0.5
## Worst rest quality an empty stomach can drag a night down to.
@export_range(0.0, 1.0) var minimum_rest_quality: float = 0.25

@export_group("Carry")
## Extra hourly energy cost with a full pack; nothing below half full.
@export var carry_fatigue_factor: float = 0.6
## The pack whose weight tires Henry. Found under the player when unset.
@export var carry_inventory: InventoryComponent

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

func _on_time_changed(_formatted_time: String, _is_day: bool, _day_number: int, _period_description: String):
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
		

## Applies the hourly drain of every vital; `fraction` bills part of an hour.
func process_hourly_consumption(fraction: float = 1.0):
	# Голод
	var hourly_calorie_loss = base_metabolism_rate
	hourly_calorie_loss = apply_hunger_modifiers(hourly_calorie_loss) # TODO: Будущие модификаторы
	current_calories = max(0.0, current_calories - hourly_calorie_loss * fraction)
	
	# Жажда  
	var hourly_thirst_loss = base_thirst_rate
	hourly_thirst_loss = apply_thirst_modifiers(hourly_thirst_loss) # TODO: Жара, активность
	current_hydration = max(0.0, current_hydration - hourly_thirst_loss * fraction)
	
	# Энергия
	var hourly_energy_loss = base_energy_rate
	hourly_energy_loss = apply_energy_modifiers(hourly_energy_loss) # TODO: Влияние голода
	current_energy = max(0.0, current_energy - hourly_energy_loss * fraction)

## Emits UI update signals for every vital.
func update_ui_signals():
	hunger_level_changed.emit(calculate_hunger_progress())
	thirst_level_changed.emit(calculate_thirst_progress())
	energy_level_changed.emit(calculate_energy_progress())

## Checks every vital against its critical threshold.
func check_critical_states():
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

## Fires UI alerts when a vital changes.
func calculate_hunger_progress() -> float:
	return clamp(current_calories / max_calories, 0.0, 1.0)

func calculate_thirst_progress() -> float:
	return clamp(current_hydration / max_hydration, 0.0, 1.0)

func calculate_energy_progress() -> float:
	return clamp(current_energy / max_energy, 0.0, 1.0)

# === МЕТОДЫ ВОСПОЛНЕНИЯ ===
## Adds calories and updates the UI.
func add_calories(amount: float):
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

## Adds hydration and updates the UI.
func add_hydration(amount: float):
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

## Adds energy and updates the UI.
func add_energy(amount: float):
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

## Restores energy over a night and charges the night's own metabolism.
## Sleep is not a free reset: a starving or parched body rests badly.
## Bills hours spent awake while the clock jumps (waiting by the stove), fractions included.
func pass_awake_hours(hours: float) -> void:
	var whole: int = floori(maxf(hours, 0.0))
	for i: int in range(whole):
		process_hourly_consumption()
	var part: float = maxf(hours, 0.0) - float(whole)
	if part > 0.0:
		process_hourly_consumption(part)
	update_ui_signals()
	check_critical_states()


func rest_sleep(hours: float) -> void:
	if hours <= 0.0:
		return

	## The clock jumps past _on_time_changed, so sleep bills its own hours.
	var slept_metabolism: float = base_metabolism_rate * sleep_metabolism_factor
	current_calories = max(0.0, current_calories - slept_metabolism * hours)
	current_hydration = max(0.0, current_hydration - base_thirst_rate * sleep_thirst_factor * hours)

	add_energy(hours * energy_restored_per_hour * get_rest_quality())
	update_ui_signals()
	check_critical_states()


## How well the body rests, from the worse of hunger and thirst. Full quality
## above half on both tracks, never below the floor.
func get_rest_quality() -> float:
	var worst: float = min(calculate_hunger_progress(), calculate_thirst_progress())
	return clamp(worst * 2.0, minimum_rest_quality, 1.0)

# === МОДИФИКАТОРЫ (ЗАГЛУШКИ ДЛЯ БУДУЩЕГО ФУНКЦИОНАЛА) ===
## Applies modifiers to calorie drain.
func apply_hunger_modifiers(base_rate: float) -> float:
	# TODO: Влияние температуры, активности, болезней
	return base_rate

## Applies modifiers to hydration drain.
func apply_thirst_modifiers(base_rate: float) -> float:
	# TODO: Влияние жары, физической активности, потоотделения
	return base_rate

## A pack past half its limit tires Henry faster, up to carry_fatigue_factor
## extra at the limit. Hunger and illness are still to come.
func apply_energy_modifiers(base_rate: float) -> float:
	var load: float = _carry_load_fraction()
	var over_half: float = clamp((load - 0.5) * 2.0, 0.0, 1.0)
	return base_rate * (1.0 + over_half * carry_fatigue_factor)


func _carry_load_fraction() -> float:
	## Only Henry's own pack: search from the player, never from the scene root.
	if carry_inventory == null and get_parent() != null and get_parent().is_in_group(&"player"):
		carry_inventory = InventoryComponent.find_in(get_parent())
	if carry_inventory == null:
		return 0.0
	return carry_inventory.get_load_fraction()

# === ВСПОМОГАТЕЛЬНЫЕ МЕТОДЫ (СОВМЕСТИМОСТЬ) ===
func is_currently_satiated_from_meal() -> bool:
	return has_recently_eaten

func is_currently_hydrated_from_drink() -> bool:
	return has_recently_drunk

func is_currently_rested_from_sleep() -> bool:
	return has_recently_rested


## Key this system owns in a save file, stated explicitly so renaming the
## script never orphans an existing save.
func get_save_key() -> StringName:
	return &"bio"


func get_save_data() -> Dictionary:
	return {
		"calories": current_calories,
		"hydration": current_hydration,
		"energy": current_energy,
	}


## Restores the three tracks and re-derives the critical flags from them, so
## a loaded starving Henry is starving again rather than silently fine.
func load_save_data(data: Dictionary) -> void:
	current_calories = clamp(float(data.get("calories", current_calories)), 0.0, max_calories)
	current_hydration = clamp(float(data.get("hydration", current_hydration)), 0.0, max_hydration)
	current_energy = clamp(float(data.get("energy", current_energy)), 0.0, max_energy)
	previous_calories = current_calories
	previous_hydration = current_hydration
	previous_energy = current_energy
	update_ui_signals()
	check_critical_states()
