extends Node
class_name DayNightManager

signal day_started(day_number: int)
signal night_started(night_number: int)
signal time_changed(formatted_time: String, is_day: bool, day_number: int, period_description: String)
signal critical_night_approaching
signal time_update(current_hour: float)

@export var perfomance_visible_display: bool = true
@export var settings: DayNightSettings
@export var directional_light: DirectionalLight3D
@export var world_environment_node: WorldEnvironment
@export var time_accelerator: TimeAccelerator

var total_game_time_hours: float = 6.0
var current_day: int = 1
var is_day: bool = true
var last_game_minute: int = -1

var sky_resource: Sky
var sky_material: ProceduralSkyMaterial

@export_group("Debug-Visual Component")
@export var time_label: Label
@export var day_label: Label
@export var day_and_night_duration_label: Label
@export var current_day_label: Label

# C# калькулятор
@onready var calculator: Node = preload("res://scripts/systems/world/DayNightCalculator.cs").new()

func _ready():
	setup_default_settings()
	initialize_sky()
	add_child(calculator)

	$DebugTime.visible = perfomance_visible_display
	set_process(true)
	update_environment_visuals(get_current_hour_float())


func setup_default_settings():
	if settings == null:
		settings = DayNightSettings.new()

func initialize_sky():
	if not world_environment_node or not world_environment_node.environment:
		print("WorldEnvironment не найден!")
		return

	var env = world_environment_node.environment

	if env.sky != null and env.sky.sky_material is ProceduralSkyMaterial:
		sky_resource = env.sky
		sky_material = env.sky.sky_material as ProceduralSkyMaterial
	else:
		sky_resource = Sky.new()
		sky_material = ProceduralSkyMaterial.new()
		sky_resource.sky_material = sky_material
		env.sky = sky_resource

func _process(delta: float) -> void:
	var old_total_hours := total_game_time_hours

	# 1. Базовая скорость времени (24 игровых часа за полный цикл)
	var total_cycle_duration := settings.day_duration + settings.night_duration
	var base_game_hours_per_second := 24.0 / total_cycle_duration
	var effective_speed := base_game_hours_per_second

	# 2. Учитываем ускорение, если активен TimeAccelerator
	if time_accelerator and time_accelerator.is_accelerating:
		effective_speed *= time_accelerator.acceleration_factor

	# 3. Обновляем общее игровое время
	total_game_time_hours += delta * effective_speed

	# 4. Вычисляем текущий игровой час и минуту
	var game_hour_float := fmod(total_game_time_hours, 24.0)
	var game_minute := int(game_hour_float * 60.0)

	# 5. Если минута изменилась — вызываем событие
	if game_minute != last_game_minute:
		last_game_minute = game_minute
		on_game_minute_changed(game_hour_float)


func on_game_minute_changed(game_hour_float: float):
	var new_hour = int(game_hour_float)
	var new_day = int(floor(total_game_time_hours / 24.0)) + 1

	if new_day > current_day:
		current_day = new_day

	var was_day = is_day
	is_day = calculator.IsDay(game_hour_float)

	if was_day and not is_day:
		night_started.emit(current_day)
		if current_day == settings.critical_night_day:
			critical_night_approaching.emit()
	elif not was_day and is_day:
		day_started.emit(current_day)

	update_environment_visuals(game_hour_float)
	emit_time_signals(game_hour_float)
	update_time_display()
	time_update.emit(game_hour_float)

func update_environment_visuals(game_hour_float: float):
	if not directional_light or not world_environment_node or not world_environment_node.environment:
		return

	var day_night_progress = calculator.CalculateDayNightProgress(game_hour_float)
	directional_light.light_energy = calculator.InterpolateLightEnergy(settings.night_light_energy, settings.day_light_energy, day_night_progress)
	directional_light.rotation_degrees.x = calculator.CalculateSunRotation(game_hour_float)

	var env = world_environment_node.environment

	if sky_material:
		sky_material.sky_top_color = calculator.InterpolateSkyColor(settings.night_sky_top_color, settings.day_sky_top_color, day_night_progress)
		sky_material.sky_horizon_color = calculator.InterpolateSkyColor(settings.night_sky_horizon_color, settings.day_sky_horizon_color, day_night_progress)
		sky_material.ground_bottom_color = calculator.InterpolateSkyColor(settings.night_ground_color, settings.day_ground_color, day_night_progress)
		sky_material.ground_horizon_color = calculator.InterpolateSkyColor(settings.night_ground_color, settings.day_ground_color, day_night_progress)
		sky_material.ground_energy_multiplier = calculator.InterpolateLightEnergy(settings.night_sky_energy, settings.day_sky_energy, day_night_progress)

	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_color = calculator.InterpolateSkyColor(settings.night_ambient_color, settings.day_ambient_color, day_night_progress)
	env.ambient_light_energy = calculator.InterpolateLightEnergy(settings.night_sky_energy, settings.day_sky_energy, day_night_progress)

	if current_day == settings.critical_night_day and not is_day:
		apply_critical_night_effect(game_hour_float, day_night_progress)

func apply_critical_night_effect(game_hour_float: float, base_progress: float):
	var critical_factor = calculator.CalculateCriticalNightFactor(game_hour_float, current_day, settings.critical_night_day)

	directional_light.light_energy *= lerp(1.0, 0.2, critical_factor)

	var env = world_environment_node.environment
	env.ambient_light_energy *= lerp(1.0, 0.1, critical_factor)
	env.ambient_light_color = env.ambient_light_color.lerp(Color.BLACK, critical_factor * settings.critical_night_darkness_factor)

func emit_time_signals(game_hour_float: float):
	var formatted_time = calculator.FormatTime(game_hour_float)
	var time_of_day = calculator.CalculateTimeOfDay(game_hour_float)
	var period_description = calculator.GetTimeDescriptionRu(time_of_day)

	time_changed.emit(formatted_time, is_day, current_day, period_description)

func update_time_display():
	if time_label and day_label:
		time_label.text = calculator.FormatTime(get_current_hour_float())
		var time_of_day = calculator.CalculateTimeOfDay(get_current_hour_float())
		day_label.text = calculator.GetTimeDescriptionEn(time_of_day)
		day_and_night_duration_label.text = "%d sec Day + %d sec Night" % [settings.day_duration, settings.night_duration]
	if current_day_label:
		current_day_label.text = "Day: %d" % current_day

func get_current_hour_float() -> float:
	return fmod(total_game_time_hours, 24.0)

func get_current_day() -> int:
	return current_day

func is_night_time() -> bool:
	return not is_day

func is_critical_night() -> bool:
	return current_day == settings.critical_night_day and not is_day

func get_save_data() -> Dictionary:
	return {
		"total_game_time_hours": total_game_time_hours,
		"current_day": current_day,
		"is_day": is_day
	}

func load_save_data(data: Dictionary):
	total_game_time_hours = data.get("total_game_time_hours", 6.0)
	current_day = data.get("current_day", 1)
	is_day = data.get("is_day", true)

	update_environment_visuals(get_current_hour_float())
	update_time_display()
