
# Vital_Signs_UI.gd
extends Control

## Looked up through the world context, never by node path.
const THERMAL_SCRIPT: GDScript = preload("res://scripts/systems/survival/thermal_manager.gd")

@export var vital_signs_enabled: bool = true

# === ЭКСПОРТ ГРУПП ДЛЯ ВСЕХ ПОКАЗАТЕЛЕЙ ===
@export_group("Thirst")
@export var thirst_warning_sign: TextureRect
@export var thirst_upper: TextureRect
@export var thirst_icon: TextureRect
@export var thirst_lower: TextureRect

@export_group("Hunger")
@export var hunger_warning_sign: TextureRect
@export var hunger_upper: TextureRect # Основной индикатор (прозрачность по голоду)
@export var hunger_icon: TextureRect # Динамический индикатор (мигающий)
@export var hunger_lower: TextureRect

@export_group("Sleep")
@export var sleep_warning_sign: TextureRect
@export var sleep_upper: TextureRect
@export var sleep_icon: TextureRect
@export var sleep_lower: TextureRect

@export_group("Temperature")
@export var temperature_device_equip: bool = true
@export var temperature_warning_sign: TextureRect
@export var temperature_upper: TextureRect
@export var temperature_icon: TextureRect
@export var temperature_lower: TextureRect

@export_group("Radiation")
@export var radiation_device_equip: bool = true
@export var radiation_warning_sign: TextureRect
@export var radiation_upper: TextureRect
@export var radiation_icon: TextureRect
@export var radiation_lower: TextureRect

@export_group("Important References")
@export var player: CharacterBody3D
@export var bio_monitor: BioMonitorManager # Ссылка на BioMonitor
## Supplies body temperature and hypothermia stage; without it the
## thermometer stays idle instead of showing a false reading.
@export var thermal_manager: ThermalManager

# === ПЕРЕМЕННЫЕ ДЛЯ ОТСЛЕЖИВАНИЯ КРИТИЧЕСКИХ СОСТОЯНИЙ ===
var is_critically_hungry_in_hud: bool = false
var is_critically_thirsty_in_hud: bool = false
var is_critically_tired_in_hud: bool = false
var is_freezing_in_hud: bool = false

var hunger_tween: Tween = null # ИСПРАВЛЕНИЕ: Инициализация
var thirst_tween: Tween = null # ИСПРАВЛЕНИЕ: Инициализация
var energy_tween: Tween = null # ИСПРАВЛЕНИЕ: Инициализация
var temperature_tween: Tween = null
var _last_body_temp_c: float = 0.0

# === КОНСТАНТЫ ДЛЯ ПРОЗРАЧНОСТИ ===
const ICON_MIN_ALPHA: float = 0.25 # Минимальная прозрачность (все хорошо)
const ICON_MAX_ALPHA: float = 0.9  # Максимальная прозрачность (критично)
const ALERT_DURATION: float = 3.5  # Длительность показа Upper/Lower в секундах

## Degrees of change needed before the HUD flashes an up or down alert.
const TEMPERATURE_ALERT_DELTA_C: float = 0.35

func _ready() -> void:
	if not vital_signs_enabled:
		visible = false
		return
		
		# Логика видимости для Temperature и Radiation 
	for temperature_device in [temperature_warning_sign, temperature_upper, temperature_icon, temperature_lower]:
		if temperature_device:
			temperature_device.visible = temperature_device_equip
		
	for radiation_device in [radiation_warning_sign, radiation_upper, radiation_icon, radiation_lower]:
		if radiation_device:
			radiation_device.visible = radiation_device_equip
	
	# Скрываем все warnings, uppers и lowers по умолчанию
	hide_all_temporary_elements()
	
	# Логика видимости для Temperature и Radiation 
	setup_device_visibility()
	
	# Подписка на сигналы BioMonitorManager
	setup_bio_monitor_connections()
	
	# Подписка на сигналы ThermalManager
	setup_thermal_connections()
	
	# Инициализация начального состояния
	call_deferred("initialize_ui_state")

## Sets visibility of the Temperature and Radiation devices.
func setup_device_visibility():
	# Показываем только иконки в зависимости от equip (остальное скрыто через modulate)
	if temperature_icon:
		temperature_icon.visible = temperature_device_equip
		
	if radiation_icon:
		radiation_icon.visible = radiation_device_equip

## Hides every warning, upper and lower by default via modulate.
func hide_all_temporary_elements():
	# Скрываем все warning signs
	if hunger_warning_sign:
		hunger_warning_sign.modulate = Color(1.0, 1.0, 1.0, 0.0)
	if thirst_warning_sign:
		thirst_warning_sign.modulate = Color(1.0, 1.0, 1.0, 0.0)
	if sleep_warning_sign:
		sleep_warning_sign.modulate = Color(1.0, 1.0, 1.0, 0.0)
	if temperature_warning_sign:
		temperature_warning_sign.modulate = Color(1.0, 1.0, 1.0, 0.0)
	if radiation_warning_sign:
		radiation_warning_sign.modulate = Color(1.0, 1.0, 1.0, 0.0)
	
	# Скрываем все uppers 
	if hunger_upper:
		hunger_upper.modulate = Color(1.0, 1.0, 1.0, 0.0)
	if thirst_upper:
		thirst_upper.modulate = Color(1.0, 1.0, 1.0, 0.0)
	if sleep_upper:
		sleep_upper.modulate = Color(1.0, 1.0, 1.0, 0.0)
	if temperature_upper:
		temperature_upper.modulate = Color(1.0, 1.0, 1.0, 0.0)
	if radiation_upper:
		radiation_upper.modulate = Color(1.0, 1.0, 1.0, 0.0)
	
	# Скрываем все lowers 
	if hunger_lower:
		hunger_lower.modulate = Color(1.0, 1.0, 1.0, 0.0)
	if thirst_lower:
		thirst_lower.modulate = Color(1.0, 1.0, 1.0, 0.0)
	if sleep_lower:
		sleep_lower.modulate = Color(1.0, 1.0, 1.0, 0.0)
	if temperature_lower:
		temperature_lower.modulate = Color(1.0, 1.0, 1.0, 0.0)
	if radiation_lower:
		radiation_lower.modulate = Color(1.0, 1.0, 1.0, 0.0)

## Subscribes to BioMonitorManager signals.
func setup_bio_monitor_connections():
	if bio_monitor:
		# === ГОЛОД ===
		bio_monitor.hunger_level_changed.connect(_on_hunger_level_changed)
		bio_monitor.critical_hunger_reached.connect(_on_critical_hunger_reached)
		bio_monitor.not_critical_hunger.connect(_on_not_critical_hunger)
		
		# === ЖАЖДА ===
		bio_monitor.thirst_level_changed.connect(_on_thirst_level_changed)
		bio_monitor.critical_dehydration_reached.connect(_on_critical_dehydration_reached)
		bio_monitor.dehydration_recovered.connect(_on_dehydration_recovered)
		
		# === ЭНЕРГИЯ ===
		bio_monitor.energy_level_changed.connect(_on_energy_level_changed)
		bio_monitor.critical_exhaustion_reached.connect(_on_critical_exhaustion_reached)
		bio_monitor.exhaustion_recovered.connect(_on_exhaustion_recovered)
	else:
		print("ОШИБКА: BioMonitorManager не назначен в Vital_Signs_UI!")

## Lifecycle hook world.gd offers to the player subtree. The thermal model is
## created by the composition root, so the thermometer finds it here.
func on_world_ready(context: WorldContext) -> void:
	if thermal_manager != null:
		return
	thermal_manager = context.get_system(THERMAL_SCRIPT) as ThermalManager
	if thermal_manager == null:
		push_warning("Vital_Signs_UI: the world built no ThermalManager, thermometer stays idle")
		return
	setup_thermal_connections()


## Subscribes the thermometer to the thermal model.
func setup_thermal_connections() -> void:
	if not thermal_manager:
		return
	if not thermal_manager.body_temperature_changed.is_connected(_on_body_temperature_changed):
		thermal_manager.body_temperature_changed.connect(_on_body_temperature_changed)
	if not thermal_manager.stage_changed.is_connected(_on_thermal_stage_changed):
		thermal_manager.stage_changed.connect(_on_thermal_stage_changed)
	initialize_thermal_state()


## Seeds the thermometer from the live model. Kept out of initialize_ui_state,
## which returns early when no BioMonitorManager is assigned.
func initialize_thermal_state() -> void:
	if not thermal_manager:
		return
	_last_body_temp_c = thermal_manager.get_body_temperature_c()
	_apply_temperature_icon(thermal_manager.get_body_temperature_normalised())
	is_freezing_in_hud = thermal_manager.get_stage() >= ThermalManager.Stage.HYPOTHERMIC
	if temperature_warning_sign:
		temperature_warning_sign.modulate = Color(1.0, 1.0, 1.0, 1.0 if is_freezing_in_hud else 0.0)
	if temperature_lower:
		temperature_lower.modulate = Color(1.0, 1.0, 1.0, 0.0)
	if temperature_upper:
		temperature_upper.modulate = Color(1.0, 1.0, 1.0, 0.0)


## Sets the initial UI state.
func initialize_ui_state():
	if not bio_monitor:
		return
	
	# Получаем начальные прогрессы и устанавливаем прозрачность иконок
	var hunger_progress = bio_monitor.calculate_hunger_progress()
	var thirst_progress = bio_monitor.calculate_thirst_progress()
	var energy_progress = bio_monitor.calculate_energy_progress()
	
	_on_hunger_level_changed(hunger_progress)
	_on_thirst_level_changed(thirst_progress)
	_on_energy_level_changed(energy_progress)
	
	# Устанавливаем начальные критические состояния
	is_critically_hungry_in_hud = bio_monitor.is_currently_critically_hungry
	is_critically_thirsty_in_hud = bio_monitor.is_currently_critically_thirsty
	is_critically_tired_in_hud = bio_monitor.is_currently_critically_tired
	
	# Инициализация warning signs
	update_warning_signs()

# === ОБРАБОТЧИКИ ИЗМЕНЕНИЯ УРОВНЕЙ ===
## Updates hunger icon alpha (0 starving, 1 fed).
func _on_hunger_level_changed(progress: float):
	if hunger_icon:
		var alpha_value = lerp(ICON_MAX_ALPHA, ICON_MIN_ALPHA, progress)
		hunger_icon.modulate = Color(1.0, 1.0, 1.0, alpha_value)

## Updates thirst icon alpha (0 dehydrated, 1 hydrated).
func _on_thirst_level_changed(progress: float):
	if thirst_icon:
		var alpha_value = lerp(ICON_MAX_ALPHA, ICON_MIN_ALPHA, progress)
		thirst_icon.modulate = Color(1.0, 1.0, 1.0, alpha_value)

## Updates energy icon alpha (0 exhausted, 1 rested).
func _on_energy_level_changed(progress: float):
	if sleep_icon:
		var alpha_value = lerp(ICON_MAX_ALPHA, ICON_MIN_ALPHA, progress)
		sleep_icon.modulate = Color(1.0, 1.0, 1.0, alpha_value)

## Drives the thermometer icon and flashes an up or down alert on real change.
func _on_body_temperature_changed(celsius: float, normalised: float) -> void:
	_apply_temperature_icon(normalised)
	if not is_zero_approx(_last_body_temp_c):
		var delta: float = celsius - _last_body_temp_c
		if absf(delta) >= TEMPERATURE_ALERT_DELTA_C:
			_last_body_temp_c = celsius
			if delta < 0.0:
				trigger_temperature_lower_alert()
			else:
				trigger_temperature_upper_alert()
			return
	else:
		_last_body_temp_c = celsius


## Mirrors the hypothermia stage onto the warning sign and the lower indicator.
func _on_thermal_stage_changed(stage: ThermalManager.Stage) -> void:
	var freezing: bool = stage >= ThermalManager.Stage.HYPOTHERMIC
	if freezing == is_freezing_in_hud:
		return
	is_freezing_in_hud = freezing
	update_warning_signs()
	if not temperature_lower:
		return
	if freezing:
		if temperature_tween and is_instance_valid(temperature_tween) and temperature_tween.is_running():
			temperature_tween.kill()
		temperature_lower.modulate = Color(1.0, 0.0, 0.0, 1.0)
	else:
		temperature_lower.modulate = Color(1.0, 1.0, 1.0, 0.0)


## Colder bodies show a more opaque icon, matching the other vital signs.
func _apply_temperature_icon(normalised: float) -> void:
	if not temperature_icon:
		return
	var alpha_value: float = lerpf(ICON_MAX_ALPHA, ICON_MIN_ALPHA, clampf(normalised, 0.0, 1.0))
	temperature_icon.modulate = Color(1.0, 1.0, 1.0, alpha_value)


## Flashes the falling-temperature indicator, unless already freezing.
func trigger_temperature_lower_alert() -> void:
	if not temperature_lower or is_freezing_in_hud:
		return
	show_temporary_indicator(temperature_lower, "temperature_tween")


## Flashes the rising-temperature indicator when the player warms up.
func trigger_temperature_upper_alert() -> void:
	if not temperature_upper:
		return
	show_temporary_indicator(temperature_upper, "temperature_tween")


# === ОБРАБОТЧИКИ КРИТИЧЕСКИХ СОСТОЯНИЙ ===
## Handles entering critical hunger.
func _on_critical_hunger_reached():
	is_critically_hungry_in_hud = true
	update_warning_signs()
	# В критическом состоянии показываем постоянно lower индикатор
	if hunger_lower:
		hunger_lower.modulate = Color(1.0, 0.0, 0.0, 1.0) # Красный цвет для критического состояния

## Handles leaving critical hunger.
func _on_not_critical_hunger():
	is_critically_hungry_in_hud = false
	update_warning_signs()
	# Скрываем lower индикатор при выходе из критического состояния
	if hunger_lower:
		hunger_lower.modulate = Color(1.0, 1.0, 1.0, 0.0)

## Handles entering critical thirst.
func _on_critical_dehydration_reached():
	is_critically_thirsty_in_hud = true
	update_warning_signs()
	# В критическом состоянии показываем постоянно lower индикатор
	if thirst_lower:
		thirst_lower.modulate = Color(1.0, 0.0, 0.0, 1.0) # Красный цвет для критического состояния

## Handles recovery from critical thirst.
func _on_dehydration_recovered():
	is_critically_thirsty_in_hud = false
	update_warning_signs()
	# Скрываем lower индикатор при выходе из критического состояния
	if thirst_lower:
		thirst_lower.modulate = Color(1.0, 1.0, 1.0, 0.0)

## Handles entering critical fatigue.
func _on_critical_exhaustion_reached():
	is_critically_tired_in_hud = true
	update_warning_signs()
	# В критическом состоянии показываем постоянно lower индикатор
	if sleep_lower:
		sleep_lower.modulate = Color(1.0, 0.0, 0.0, 1.0)
	## В критическом состоянии показываем постоянно lower индикатор
	#if energy_tween and is_instance_valid(energy_tween) and energy_tween.is_running():
		#energy_tween.kill()

## Handles recovery from critical fatigue.
func _on_exhaustion_recovered():
	is_critically_tired_in_hud = false
	update_warning_signs()
	# Скрываем lower индикатор при выходе из критического состояния
	if energy_tween and is_instance_valid(energy_tween) and energy_tween.is_running():
		energy_tween.kill()

# === МЕТОДЫ ДЛЯ УПРАВЛЕНИЯ WARNING SIGNS ===
## Updates every warning sign via modulate.
func update_warning_signs():
	if hunger_warning_sign:
		hunger_warning_sign.modulate = Color(1.0, 1.0, 1.0, 1.0 if is_critically_hungry_in_hud else 0.0)
		
	if thirst_warning_sign:
		thirst_warning_sign.modulate = Color(1.0, 1.0, 1.0, 1.0 if is_critically_thirsty_in_hud else 0.0)
		
	if sleep_warning_sign:
		sleep_warning_sign.modulate = Color(1.0, 1.0, 1.0, 1.0 if is_critically_tired_in_hud else 0.0)
		
	if temperature_warning_sign:
		temperature_warning_sign.modulate = Color(1.0, 1.0, 1.0, 1.0 if is_freezing_in_hud else 0.0)


## Shows the hunger lower indicator for 3.5 s.
func trigger_hourly_hunger_alert():
	if not hunger_lower or is_critically_hungry_in_hud:
		return # Не показываем если в критическом состоянии
	
	await get_tree().create_timer(1.0).timeout
	show_temporary_indicator(hunger_lower, "hunger_tween")

## Shows the thirst lower indicator for 3.5 s.
func trigger_hourly_thirst_alert():
	if not thirst_lower or is_critically_thirsty_in_hud:
		return # Не показываем если в критическом состоянии
	

	show_temporary_indicator(thirst_lower, "thirst_tween")

## Shows the energy lower indicator for 3.5 s.
func trigger_hourly_energy_alert():
	if not sleep_lower or is_critically_tired_in_hud:
		return # Не показываем если в критическом состоянии
	
	await get_tree().create_timer(2.0).timeout
	show_temporary_indicator(sleep_lower, "energy_tween")

## Shows the hunger upper indicator for 3.5 s on refill.
func trigger_hunger_upper_alert():
	if not hunger_upper:
		return

	show_temporary_indicator(hunger_upper, "hunger_tween")

## Shows the thirst upper indicator for 3.5 s on refill.
func trigger_thirst_upper_alert():
	if not thirst_upper:
		return
	

	show_temporary_indicator(thirst_upper, "thirst_tween")

## Shows the energy upper indicator for 3.5 s on refill.
func trigger_energy_upper_alert():
	if not sleep_upper:
		return
	

	show_temporary_indicator(sleep_upper, "energy_tween")

## Shows a temporary indicator; takes the tween variable name as a string.
func show_temporary_indicator(indicator: TextureRect, var_name: String):
	if not indicator:
		return

	var current_tween: Tween = null

	# Получаем ссылку на внешнюю переменную-твин
	if var_name == "hunger_tween":
		current_tween = hunger_tween
	elif var_name == "thirst_tween":
		current_tween = thirst_tween
	elif var_name == "energy_tween":
		current_tween = energy_tween
	elif var_name == "temperature_tween":
		current_tween = temperature_tween
	else:
		push_warning("Неизвестное имя переменной для Tween: " + var_name)
		return

	# Отменяем предыдущий твин, если он работает
	if current_tween and is_instance_valid(current_tween) and current_tween.is_running():
		current_tween.kill()

	# Создаем новый твин
	current_tween = create_tween()

	# Присваиваем новый твин обратно внешней переменной (КРИТИЧЕСКИ ВАЖНО!)
	if var_name == "hunger_tween":
		hunger_tween = current_tween
	elif var_name == "thirst_tween":
		thirst_tween = current_tween
	elif var_name == "energy_tween":
		energy_tween = current_tween
	elif var_name == "temperature_tween":
		temperature_tween = current_tween
	
	# Показываем индикатор с обычным белым цветом (не красным)
	indicator.modulate = Color(1.0, 1.0, 1.0, 1.0)
	
	# Ждем ALERT_DURATION секунд
	current_tween.tween_interval(ALERT_DURATION)
	
	# Скрываем индикатор через modulate
	current_tween.tween_property(indicator, "modulate", Color(1.0, 1.0, 1.0, 0.0), 0.3)
