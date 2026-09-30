extends Node
class_name ColorGradeController

## Owns Hoarbound's final Environment adjustment without replacing the Environment.
## Time of day selects one outdoor LUT; shelter temporarily overrides it. Weather
## only adjusts the selected outdoor profile when the weather state itself changes.

signal profile_changed(profile_id: StringName)

const DAY_PROFILE_ID: StringName = &"HFN_ColdAsh_Day"
const DUSK_PROFILE_ID: StringName = &"HFN_ColdAsh_Dusk"
const NIGHT_PROFILE_ID: StringName = &"HFN_ColdAsh_Night"
const SHELTER_PROFILE_ID: StringName = &"HFN_ColdAsh_Shelter"

const DAY_START_HOUR: float = 7.0
const DUSK_START_HOUR: float = 17.0
const NIGHT_START_HOUR: float = 21.0
const DAWN_START_HOUR: float = 5.0

@export var world_environment: WorldEnvironment
@export var day_profile: ColorGradeProfile
@export var dusk_profile: ColorGradeProfile
@export var night_profile: ColorGradeProfile
@export var shelter_profile: ColorGradeProfile
@export var default_profile_id: StringName = DAY_PROFILE_ID
@export_range(0.0, 1.0, 0.01) var shelter_ambient_energy_cap: float = 0.20

var _current_profile: ColorGradeProfile
var _outdoor_profile_id: StringName = DAY_PROFILE_ID
var _inside_shelter: bool = false
var _weather_brightness: float = 1.0
var _weather_contrast: float = 1.0
var _weather_saturation: float = 1.0
var _outdoor_ambient_energy: float = 1.0
var _last_shelter_ambient_energy: float = -1.0

func _process(_delta: float) -> void:
	if not _inside_shelter or not is_instance_valid(world_environment) or world_environment.environment == null:
		return
	var environment: Environment = world_environment.environment
	var current: float = environment.ambient_light_energy
	## DayNightManager may update ambient while Henry is inside. If the value no
	## longer equals our last cap, remember it as the new outdoor baseline.
	if _last_shelter_ambient_energy < 0.0 or not is_equal_approx(current, _last_shelter_ambient_energy):
		_outdoor_ambient_energy = current
	var target: float = minf(_outdoor_ambient_energy, shelter_ambient_energy_cap)
	environment.ambient_light_energy = target
	_last_shelter_ambient_energy = target


func _ready() -> void:
	_outdoor_profile_id = default_profile_id if default_profile_id != SHELTER_PROFILE_ID else DAY_PROFILE_ID
	if not set_profile(default_profile_id):
		push_warning("ColorGradeController: default profile '%s' is unavailable; using day." % default_profile_id)
		_outdoor_profile_id = DAY_PROFILE_ID
		use_outdoor_profile()

func initialize_for_interior(is_inside: bool) -> void:
	if _inside_shelter == is_inside and _current_profile != null:
		return
	if is_instance_valid(world_environment) and world_environment.environment != null:
		var environment: Environment = world_environment.environment
		if is_inside:
			_outdoor_ambient_energy = environment.ambient_light_energy
			_last_shelter_ambient_energy = -1.0
		else:
			environment.ambient_light_energy = _outdoor_ambient_energy
			_last_shelter_ambient_energy = -1.0
	_inside_shelter = is_inside
	if is_inside:
		use_shelter_profile()
		_process(0.0)
	else:
		use_outdoor_profile()

func update_for_time(game_hour: float) -> void:
	var target: StringName = _profile_id_for_hour(game_hour)
	if target == _outdoor_profile_id:
		return
	_outdoor_profile_id = target
	if not _inside_shelter:
		use_outdoor_profile()

func set_weather_profile(profile: WeatherProfile) -> void:
	var brightness: float = 1.0
	var contrast: float = 1.0
	var saturation: float = 1.0
	if profile != null:
		match profile.id:
			&"calm":
				brightness = 1.03
			&"snowfall":
				brightness = 0.98
				contrast = 0.98
				saturation = 0.94
			&"windy":
				brightness = 0.99
				saturation = 0.96
			&"blizzard":
				brightness = 0.92
				contrast = 0.94
				saturation = 0.86
			_:
				pass
	var changed: bool = (
		not is_equal_approx(_weather_brightness, brightness)
		or not is_equal_approx(_weather_contrast, contrast)
		or not is_equal_approx(_weather_saturation, saturation)
	)
	_weather_brightness = brightness
	_weather_contrast = contrast
	_weather_saturation = saturation
	if changed and not _inside_shelter:
		use_outdoor_profile()

func use_outdoor_profile() -> bool:
	return _apply_profile(_resolve_profile(_outdoor_profile_id), true)

func use_shelter_profile() -> bool:
	return _apply_profile(shelter_profile, false)

func set_profile(profile_id: StringName) -> bool:
	if profile_id == SHELTER_PROFILE_ID:
		_inside_shelter = true
		return use_shelter_profile()
	var profile: ColorGradeProfile = _resolve_profile(profile_id)
	if profile == null:
		push_warning("ColorGradeController: unknown profile '%s'." % profile_id)
		return false
	_inside_shelter = false
	_outdoor_profile_id = profile_id
	return _apply_profile(profile, true)

func get_current_profile_id() -> StringName:
	return _current_profile.profile_id if _current_profile != null else &""

func _profile_id_for_hour(game_hour: float) -> StringName:
	var hour: float = fmod(game_hour + 24.0, 24.0)
	if hour >= DAY_START_HOUR and hour < DUSK_START_HOUR:
		return DAY_PROFILE_ID
	if (hour >= DAWN_START_HOUR and hour < DAY_START_HOUR) or (hour >= DUSK_START_HOUR and hour < NIGHT_START_HOUR):
		return DUSK_PROFILE_ID
	return NIGHT_PROFILE_ID

func _resolve_profile(profile_id: StringName) -> ColorGradeProfile:
	match profile_id:
		DAY_PROFILE_ID:
			return day_profile
		DUSK_PROFILE_ID:
			return dusk_profile
		NIGHT_PROFILE_ID:
			return night_profile
		SHELTER_PROFILE_ID:
			return shelter_profile
		_:
			return null

func _apply_profile(profile: ColorGradeProfile, weather_affects: bool) -> bool:
	if not is_instance_valid(world_environment) or world_environment.environment == null:
		push_warning("ColorGradeController: WorldEnvironment is not ready.")
		return false
	if profile == null or profile.lut == null:
		push_warning("ColorGradeController: requested profile or LUT is missing.")
		return false
	var environment: Environment = world_environment.environment
	environment.adjustment_enabled = true
	environment.adjustment_color_correction = profile.lut
	var weather_brightness: float = _weather_brightness if weather_affects else 1.0
	var weather_contrast: float = _weather_contrast if weather_affects else 1.0
	var weather_saturation: float = _weather_saturation if weather_affects else 1.0
	environment.adjustment_brightness = profile.brightness * weather_brightness
	environment.adjustment_contrast = profile.contrast * weather_contrast
	environment.adjustment_saturation = profile.saturation * weather_saturation
	var changed: bool = _current_profile != profile
	_current_profile = profile
	if changed:
		profile_changed.emit(profile.profile_id)
	return true
