class_name WeatherController
extends Node

## Global weather state machine. Weather is one value for the whole island, so
## it lives here as scalars, not as a volume that follows the player.

## Emitted when a new profile starts blending in.
signal weather_changed(profile: WeatherProfile)
## Emitted every tick with the blended values the rest of the game reads.
signal conditions_updated(ambient_offset_c: float, wind_speed_mps: float, snowfall_density: float)

## Directory the default profiles are loaded from when none are assigned.
const DEFAULT_PROFILE_DIR: String = "res://resources/weather"

@export_group("Profiles")
## Weather profiles the scheduler may pick from, as .tres resources.
@export var profiles: Array[WeatherProfile] = []
## Profile forced at startup; empty picks one by weight.
@export var starting_profile_id: StringName = &""

@export_group("Wiring")
## Drives the in-game clock used for durations and gusts.
@export var day_night_manager: DayNightManager
## Freezes the scheduler so a scene can pin one profile for testing.
@export var scheduler_enabled: bool = true

@export_group("Wind")
## Seed for the gust noise, so a session is reproducible.
@export var gust_seed: int = 7321

var _current: WeatherProfile
var _previous: WeatherProfile
var _blend: float = 1.0
var _blend_speed: float = 1.0
var _remaining_h: float = 0.0
var _elapsed_s: float = 0.0
var _gust_noise: FastNoiseLite
var _hours: GameHourTracker = GameHourTracker.new()

var _ambient_offset_c: float = 0.0
var _wind_speed_mps: float = 0.0
var _snowfall_density: float = 0.0
var _visibility_m: float = 0.0
var _wetness_rate: float = 0.0


func _ready() -> void:
	initialize()


## Builds the gust noise, wires the clock and activates the first profile.
## Public so headless tests can drive it without waiting for a frame.
func initialize() -> void:
	if _gust_noise != null:
		return
	_gust_noise = FastNoiseLite.new()
	_gust_noise.seed = gust_seed
	_gust_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	if day_night_manager != null:
		day_night_manager.time_update.connect(_on_time_update)
	else:
		push_warning("WeatherController: no DayNightManager, scheduler will not advance")
	if profiles.is_empty():
		push_warning("WeatherController: no profiles assigned, weather stays neutral")
		return
	var initial: WeatherProfile = _find_profile(starting_profile_id)
	if initial == null:
		initial = _pick_weighted()
	_activate(initial, true)


func _process(delta: float) -> void:
	if _current == null:
		return
	_elapsed_s += delta
	if _blend < 1.0:
		_blend = minf(1.0, _blend + delta * _blend_speed)
	_sample_conditions()
	conditions_updated.emit(_ambient_offset_c, _wind_speed_mps, _snowfall_density)


## Resolves the day/night clock from the scene when the world comes up, so the
## scheduler runs without anyone wiring an export by hand.
func on_world_ready(context: WorldContext) -> void:
	if day_night_manager == null:
		day_night_manager = _find_day_night_manager(context)
	if day_night_manager != null and not day_night_manager.time_update.is_connected(_on_time_update):
		day_night_manager.time_update.connect(_on_time_update)
	if profiles.is_empty():
		profiles = load_profiles_from(DEFAULT_PROFILE_DIR)
	initialize()


## Loads every WeatherProfile in a directory, sorted for a stable order.
static func load_profiles_from(directory: String) -> Array[WeatherProfile]:
	var profiles: Array[WeatherProfile] = []
	var dir := DirAccess.open(directory)
	if dir == null:
		return profiles
	var names: Array[String] = []
	for file_name: String in dir.get_files():
		var clean: String = file_name.trim_suffix(".remap")
		if clean.ends_with(".tres"):
			names.append(clean)
	names.sort()
	for clean: String in names:
		var profile := load("%s/%s" % [directory, clean]) as WeatherProfile
		if profile != null:
			profiles.append(profile)
	return profiles


## Walks the scene for a DayNightManager, since it is authored in the level
## rather than created by the composition root.
func _find_day_night_manager(context: WorldContext) -> DayNightManager:
	var roots: Array[Node] = [context.player]
	if is_inside_tree():
		roots.append(get_tree().current_scene)
	for root_node: Node in roots:
		if root_node == null:
			continue
		var found := _search_for_day_night(root_node)
		if found != null:
			return found
	return null


func _search_for_day_night(node: Node) -> DayNightManager:
	var typed := node as DayNightManager
	if typed != null:
		return typed
	for child: Node in node.get_children():
		var found := _search_for_day_night(child)
		if found != null:
			return found
	return null


## Key this system owns in a save file, stated explicitly so renaming the
## script never orphans an existing save.
func get_save_key() -> StringName:
	return &"weather"


## State the save system persists for this system.
func get_save_data() -> Dictionary:
	return {
		"profile_id": String(_current.id) if _current != null else "",
		"remaining_h": _remaining_h,
	}


## Restores the active profile, snapping rather than blending into it.
func load_save_data(data: Dictionary) -> void:
	var id := StringName(String(data.get("profile_id", "")))
	var profile: WeatherProfile = _find_profile(id)
	if profile != null:
		_activate(profile, true)
	_remaining_h = float(data.get("remaining_h", _remaining_h))
	_hours.reset()


## Forces a profile by id, blending in over its own blend time.
func set_weather(id: StringName, instant: bool = false) -> void:
	var profile: WeatherProfile = _find_profile(id)
	if profile == null:
		push_warning("WeatherController: unknown profile '%s'" % id)
		return
	_activate(profile, instant)


func get_current_profile() -> WeatherProfile:
	return _current


## Blended ambient offset in degrees Celsius, before wind chill.
func get_ambient_offset_c() -> float:
	return _ambient_offset_c


## Blended wind speed including the current gust, in metres per second.
func get_wind_speed_mps() -> float:
	return _wind_speed_mps


## Blended snowfall density, 0.0 clear to 1.0 whiteout.
func get_snowfall_density() -> float:
	return _snowfall_density


## Blended visibility clamp in metres; 0.0 means the weather does not clamp it.
func get_visibility_m() -> float:
	return _visibility_m


## Blended clothing soak rate in wetness units per in-game hour.
func get_wetness_rate_per_hour() -> float:
	return _wetness_rate


## Mixes the outgoing and incoming profiles and applies the gust on top.
func _sample_conditions() -> void:
	var from: WeatherProfile = _previous if _previous != null else _current
	_ambient_offset_c = lerpf(from.ambient_offset_c, _current.ambient_offset_c, _blend)
	_snowfall_density = lerpf(from.snowfall_density, _current.snowfall_density, _blend)
	_visibility_m = lerpf(from.visibility_m, _current.visibility_m, _blend)
	_wetness_rate = lerpf(from.wetness_rate_per_hour, _current.wetness_rate_per_hour, _blend)

	var base_wind: float = lerpf(from.wind_speed_mps, _current.wind_speed_mps, _blend)
	var gust_range: float = lerpf(from.gust_speed_mps, _current.gust_speed_mps, _blend)
	var period: float = maxf(0.1, lerpf(from.gust_period_s, _current.gust_period_s, _blend))
	var gust: float = (_gust_noise.get_noise_1d(_elapsed_s / period) + 1.0) * 0.5
	_wind_speed_mps = base_wind + gust_range * gust


## Counts down the active profile's duration and rolls the next one.
func _on_time_update(current_hour: float) -> void:
	var hours: float = _hours.consume(current_hour)
	if _current == null or not scheduler_enabled or hours <= 0.0:
		return
	_remaining_h -= hours
	if _remaining_h > 0.0:
		return
	var next: WeatherProfile = _pick_weighted()
	if next == _current and profiles.size() > 1:
		next = _pick_weighted()
	_activate(next, false)


## Swaps in a profile, either instantly or blended over its blend time.
func _activate(profile: WeatherProfile, instant: bool) -> void:
	if profile == null:
		return
	_previous = _current
	_current = profile
	_blend = 1.0 if instant or _previous == null else 0.0
	_blend_speed = 1.0 / maxf(0.01, profile.blend_time_s)
	_remaining_h = randf_range(profile.min_duration_h, profile.max_duration_h)
	_sample_conditions()
	weather_changed.emit(profile)


func _find_profile(id: StringName) -> WeatherProfile:
	if id == &"":
		return null
	for profile: WeatherProfile in profiles:
		if profile != null and profile.id == id:
			return profile
	return null


func _pick_weighted() -> WeatherProfile:
	var total: float = 0.0
	for profile: WeatherProfile in profiles:
		if profile != null:
			total += maxf(0.0, profile.weight)
	if total <= 0.0:
		return profiles[0]
	var roll: float = randf() * total
	for profile: WeatherProfile in profiles:
		if profile == null:
			continue
		roll -= maxf(0.0, profile.weight)
		if roll <= 0.0:
			return profile
	return profiles[profiles.size() - 1]
