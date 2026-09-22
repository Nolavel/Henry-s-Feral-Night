extends Node
class_name DayNightManager

signal day_started(day_number: int)
signal night_started(night_number: int)
signal time_changed(formatted_time: String, is_day: bool, day_number: int, period_description: String)
signal critical_night_approaching
signal time_update(current_hour: float)

enum TimeOfDay {
	MIDNIGHT,
	DAWN,
	MORNING,
	NOON,
	AFTERNOON,
	EVENING,
	DUSK,
	NIGHT,
}

const OVERCAST_SHADER: Shader = preload("res://scripts/systems/world/shaders/simple_overcast.gdshader")

const PERIOD_RU: Array[String] = [
	"Полночь",
	"Рассвет",
	"Утро",
	"Полдень",
	"День",
	"Вечер",
	"Сумерки",
	"Ночь",
]

const PERIOD_EN: Array[String] = [
	"Midnight",
	"Dawn",
	"Morning",
	"Noon",
	"Afternoon",
	"Evening",
	"Dusk",
	"Night",
]

const SUNRISE_HOUR: float = 6.0
const SUNSET_HOUR: float = 18.0
const LIGHT_START_HOUR: float = 2.0
const MORNING_PEAK_HOUR: float = 10.0
const DUSK_END_HOUR: float = 22.0

@export var perfomance_visible_display: bool = true
@export var settings: DayNightSettings
@export var directional_light: DirectionalLight3D
@export var world_environment_node: WorldEnvironment
@export var time_accelerator: TimeAccelerator

@export_group("Debug-Visual Component")
@export var time_label: Label
@export var day_label: Label
@export var day_and_night_duration_label: Label
@export var current_day_label: Label

var total_game_time_hours: float = 6.0
var current_day: int = 1
var is_day: bool = true
var last_game_minute: int = -1

var sky_resource: Sky
var sky_material: ShaderMaterial
var _noise_texture: NoiseTexture2D


func _ready() -> void:
	_setup_default_settings()
	_initialize_sky()

	if has_node("DebugTime"):
		$DebugTime.visible = perfomance_visible_display

	set_process(true)
	call_deferred("_force_update_visuals")


func _process(delta: float) -> void:
	var total_cycle_duration: float = maxf(settings.day_duration + settings.night_duration, 0.001)
	var game_hours_per_second: float = 24.0 / total_cycle_duration

	if is_instance_valid(time_accelerator) and time_accelerator.is_accelerating:
		game_hours_per_second *= time_accelerator.acceleration_factor

	total_game_time_hours += delta * game_hours_per_second

	var game_hour: float = get_current_hour_float()
	var game_minute: int = int(game_hour * 60.0)

	if game_minute != last_game_minute:
		last_game_minute = game_minute
		_on_game_minute_changed(game_hour)


func _setup_default_settings() -> void:
	if settings == null:
		settings = DayNightSettings.new()


func _initialize_sky() -> void:
	if not is_instance_valid(world_environment_node):
		push_warning("DayNightManager: WorldEnvironment is not assigned.")
		return

	if world_environment_node.environment == null:
		world_environment_node.environment = Environment.new()

	var environment: Environment = world_environment_node.environment
	environment.background_mode = Environment.BG_SKY
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY

	sky_resource = Sky.new()
	sky_material = ShaderMaterial.new()
	sky_material.shader = OVERCAST_SHADER
	sky_resource.sky_material = sky_material
	environment.sky = sky_resource

	_build_cloud_noise()
	_apply_static_sky_parameters()

	if is_instance_valid(directional_light):
		directional_light.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY


func _build_cloud_noise() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = settings.cloud_noise_seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = settings.cloud_noise_frequency
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = settings.cloud_noise_octaves
	noise.fractal_lacunarity = 2.0
	noise.fractal_gain = 0.52

	_noise_texture = NoiseTexture2D.new()
	_noise_texture.width = settings.cloud_noise_size
	_noise_texture.height = settings.cloud_noise_size
	_noise_texture.seamless = true
	_noise_texture.normalize = true
	_noise_texture.noise = noise

	sky_material.set_shader_parameter("noise_texture", _noise_texture)


func _apply_static_sky_parameters() -> void:
	if sky_material == null:
		return

	sky_material.set_shader_parameter("use_directional_light", true)
	sky_material.set_shader_parameter("cloud_density", settings.cloud_density)
	sky_material.set_shader_parameter("cloud_depth", settings.cloud_depth)
	sky_material.set_shader_parameter("cloud_sag", settings.cloud_sag)
	sky_material.set_shader_parameter("noise_tiling", settings.cloud_tiling)
	sky_material.set_shader_parameter("wind_speed", settings.cloud_wind_speed)
	sky_material.set_shader_parameter("directional_energy_scale", settings.cloud_light_energy_scale)
	sky_material.set_shader_parameter("ground_curve", settings.ground_curve)


func _force_update_visuals() -> void:
	var hour: float = get_current_hour_float()
	is_day = _is_day(hour)
	_update_environment_visuals(hour)
	_emit_time_signals(hour)
	_update_time_display()


func _on_game_minute_changed(game_hour: float) -> void:
	var new_day: int = int(floor(total_game_time_hours / 24.0)) + 1
	if new_day > current_day:
		current_day = new_day

	var was_day: bool = is_day
	is_day = _is_day(game_hour)

	if was_day and not is_day:
		night_started.emit(current_day)
		if current_day == settings.critical_night_day:
			critical_night_approaching.emit()
	elif not was_day and is_day:
		day_started.emit(current_day)

	_update_environment_visuals(game_hour)
	_emit_time_signals(game_hour)
	_update_time_display()
	time_update.emit(game_hour)


func _update_environment_visuals(game_hour: float) -> void:
	if not is_instance_valid(directional_light):
		return
	if not is_instance_valid(world_environment_node) or world_environment_node.environment == null:
		return
	if sky_material == null:
		_initialize_sky()
		if sky_material == null:
			return

	var day_progress: float = _calculate_day_progress(game_hour)
	var altitude: float = _calculate_light_altitude(game_hour)
	var azimuth: float = _calculate_light_azimuth(game_hour)
	var light_color: Color = _calculate_light_color(game_hour)
	var light_energy: float = _calculate_light_energy(game_hour)
	var critical_factor: float = _calculate_critical_night_factor(game_hour)

	directional_light.rotation_degrees = Vector3(-altitude, azimuth, 0.0)
	directional_light.light_color = light_color
	directional_light.light_energy = light_energy * lerpf(1.0, 0.22, critical_factor)

	var environment: Environment = world_environment_node.environment
	var ambient_color: Color = settings.night_ambient_color.lerp(
		settings.day_ambient_color,
		day_progress
	)
	var ambient_energy: float = lerpf(
		settings.night_sky_energy,
		settings.day_sky_energy,
		day_progress
	)

	if critical_factor > 0.0:
		ambient_color = ambient_color.lerp(
			Color.BLACK,
			critical_factor * settings.critical_night_darkness_factor
		)
		ambient_energy *= lerpf(1.0, 0.12, critical_factor)

	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_color = ambient_color
	environment.ambient_light_energy = ambient_energy

	var cloud_color: Color = _calculate_cloud_color(game_hour)
	var ground_color: Color = settings.night_ground_color.lerp(
		settings.day_ground_color,
		day_progress
	)
	var exposure: float = lerpf(
		settings.night_overcast_exposure,
		settings.day_overcast_exposure,
		day_progress
	)

	if critical_factor > 0.0:
		cloud_color = cloud_color.lerp(Color(0.01, 0.012, 0.018), critical_factor * 0.75)
		ground_color = ground_color.lerp(Color.BLACK, critical_factor * 0.6)
		exposure *= lerpf(1.0, 0.35, critical_factor)

	sky_material.set_shader_parameter("cloud_color", cloud_color)
	sky_material.set_shader_parameter("ground_bottom_color", ground_color)
	sky_material.set_shader_parameter("exposure", exposure)


func _calculate_day_progress(game_hour: float) -> float:
	var progress: float = 0.0

	if game_hour >= LIGHT_START_HOUR and game_hour < MORNING_PEAK_HOUR:
		progress = inverse_lerp(LIGHT_START_HOUR, MORNING_PEAK_HOUR, game_hour)
	elif game_hour >= MORNING_PEAK_HOUR and game_hour < SUNSET_HOUR:
		progress = 1.0
	elif game_hour >= SUNSET_HOUR and game_hour < DUSK_END_HOUR:
		progress = 1.0 - inverse_lerp(SUNSET_HOUR, DUSK_END_HOUR, game_hour)

	return smoothstep(0.0, 1.0, clampf(progress, 0.0, 1.0))


func _calculate_light_azimuth(game_hour: float) -> float:
	return wrapf((game_hour / 24.0) * 360.0 - 90.0, -180.0, 180.0)


func _calculate_light_altitude(game_hour: float) -> float:
	if _is_day(game_hour):
		var day_progress: float = inverse_lerp(SUNRISE_HOUR, SUNSET_HOUR, game_hour)
		var arc: float = 1.0 - pow((day_progress - 0.5) * 2.0, 2.0)
		return lerpf(-10.0, settings.sun_max_altitude, clampf(arc, 0.0, 1.0))

	var night_progress: float
	if game_hour > SUNSET_HOUR:
		night_progress = inverse_lerp(SUNSET_HOUR, 24.0, game_hour)
	else:
		night_progress = inverse_lerp(0.0, SUNRISE_HOUR, game_hour) + 0.25

	var moon_arc: float = 1.0 - pow((night_progress - 0.5) * 2.0, 2.0)
	return lerpf(-30.0, settings.moon_max_altitude, clampf(moon_arc, 0.0, 1.0))


func _calculate_light_color(game_hour: float) -> Color:
	if game_hour >= 5.0 and game_hour < 7.0:
		var dawn_t: float = smoothstep(0.0, 1.0, inverse_lerp(5.0, 7.0, game_hour))
		return settings.sun_color_sunrise.lerp(settings.sun_color_noon, dawn_t)

	if game_hour >= 7.0 and game_hour < 17.0:
		return settings.sun_color_noon

	if game_hour >= 17.0 and game_hour < 19.0:
		var dusk_t: float = smoothstep(0.0, 1.0, inverse_lerp(17.0, 19.0, game_hour))
		return settings.sun_color_noon.lerp(settings.sun_color_sunset, dusk_t)

	return settings.moon_color


func _calculate_light_energy(game_hour: float) -> float:
	if not _is_day(game_hour):
		return settings.night_light_energy

	var day_progress: float = inverse_lerp(SUNRISE_HOUR, SUNSET_HOUR, game_hour)
	var arc: float = 1.0 - pow((day_progress - 0.5) * 2.0, 2.0)
	return lerpf(
		settings.night_light_energy,
		settings.day_light_energy,
		smoothstep(0.0, 1.0, clampf(arc, 0.0, 1.0))
	)


func _calculate_cloud_color(game_hour: float) -> Color:
	if game_hour >= 4.0 and game_hour < 7.0:
		var t: float = smoothstep(0.0, 1.0, inverse_lerp(4.0, 7.0, game_hour))
		return settings.dawn_cloud_color.lerp(settings.day_cloud_color, t)

	if game_hour >= 7.0 and game_hour < 17.0:
		return settings.day_cloud_color

	if game_hour >= 17.0 and game_hour < 21.0:
		var t: float = smoothstep(0.0, 1.0, inverse_lerp(17.0, 21.0, game_hour))
		return settings.dusk_cloud_color.lerp(settings.night_cloud_color, t)

	return settings.night_cloud_color


func _calculate_critical_night_factor(game_hour: float) -> float:
	if current_day != settings.critical_night_day or _is_day(game_hour):
		return 0.0

	var factor: float
	if game_hour >= SUNSET_HOUR:
		factor = inverse_lerp(SUNSET_HOUR, 24.0, game_hour)
	else:
		factor = 1.0 - inverse_lerp(0.0, SUNRISE_HOUR, game_hour)

	return smoothstep(0.0, 1.0, clampf(factor, 0.0, 1.0))


func _is_day(game_hour: float) -> bool:
	return game_hour >= SUNRISE_HOUR and game_hour < SUNSET_HOUR


func _calculate_time_of_day(game_hour: float) -> TimeOfDay:
	var hour: int = int(game_hour)

	if hour < 4:
		return TimeOfDay.MIDNIGHT
	if hour < 6:
		return TimeOfDay.DAWN
	if hour < 10:
		return TimeOfDay.MORNING
	if hour < 14:
		return TimeOfDay.NOON
	if hour < 18:
		return TimeOfDay.AFTERNOON
	if hour < 20:
		return TimeOfDay.EVENING
	if hour < 22:
		return TimeOfDay.DUSK
	return TimeOfDay.NIGHT


func _format_time(game_hour: float) -> String:
	var hours_24: int = int(game_hour)
	var minutes: int = int(fmod(game_hour * 60.0, 60.0))
	var display_hour: int = hours_24
	var period: String = "AM"

	if display_hour >= 12:
		period = "PM"
	if display_hour > 12:
		display_hour -= 12
	if display_hour == 0:
		display_hour = 12

	return "%02d:%02d %s" % [display_hour, minutes, period]


func _emit_time_signals(game_hour: float) -> void:
	var period: TimeOfDay = _calculate_time_of_day(game_hour)
	time_changed.emit(
		_format_time(game_hour),
		is_day,
		current_day,
		PERIOD_RU[int(period)]
	)


func _update_time_display() -> void:
	var game_hour: float = get_current_hour_float()
	var period: TimeOfDay = _calculate_time_of_day(game_hour)

	if is_instance_valid(time_label):
		time_label.text = _format_time(game_hour)

	if is_instance_valid(day_label):
		day_label.text = PERIOD_EN[int(period)]

	if is_instance_valid(day_and_night_duration_label):
		day_and_night_duration_label.text = "%d sec Day + %d sec Night" % [
			int(settings.day_duration),
			int(settings.night_duration),
		]

	if is_instance_valid(current_day_label):
		current_day_label.text = "Day: %d" % current_day


func get_current_hour_float() -> float:
	return fmod(total_game_time_hours, 24.0)


func get_current_day() -> int:
	return current_day


func is_night_time() -> bool:
	return not is_day


func is_critical_night() -> bool:
	return current_day == settings.critical_night_day and not is_day


func force_update_lighting() -> void:
	_update_environment_visuals(get_current_hour_float())


func get_save_data() -> Dictionary:
	return {
		"total_game_time_hours": total_game_time_hours,
		"current_day": current_day,
		"is_day": is_day,
	}


func load_save_data(data: Dictionary) -> void:
	total_game_time_hours = float(data.get("total_game_time_hours", 6.0))
	current_day = int(data.get("current_day", 1))
	is_day = bool(data.get("is_day", true))
	call_deferred("_force_update_visuals")
