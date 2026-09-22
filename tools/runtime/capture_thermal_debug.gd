extends SceneTree

## Simulates one worsening night twice, exposed and with a shelter reached
## partway, and charts both to a PNG so the model can be tuned without Godot.

const PROFILE_DIR: String = "res://resources/weather"
const OUT_PATH: String = "user://shots/thermal_debug.png"
const MARGIN: int = 72
const WARMUP_FRAMES: int = 4
const STEP_HOURS: float = 0.1
const TOTAL_HOURS: float = 12.0
## Hour of the run at which the sheltered pass reaches a lit shelter.
const SHELTER_AT_HOUR: float = 5.0
## Narrative order: the night gets worse, it does not shuffle at random.
const PROFILE_ORDER: Array[StringName] = [&"calm", &"snowfall", &"windy", &"blizzard"]

var _exposed: Array[Dictionary] = []
var _sheltered: Array[Dictionary] = []
var _canvas: Control
var _frames: int = 0
var _size: Vector2 = Vector2(1920, 1080)


func _initialize() -> void:
	var profiles: Array[WeatherProfile] = _load_profiles()
	if profiles.is_empty():
		push_error("thermal debug: no weather profiles found")
		quit(1)
		return
	_exposed = _run_simulation(profiles, false)
	_sheltered = _run_simulation(profiles, true)
	_build_canvas()


func _process(_delta: float) -> bool:
	_frames += 1
	if _canvas != null:
		_canvas.queue_redraw()
	if _frames < WARMUP_FRAMES:
		return false
	var image: Image = root.get_texture().get_image()
	if image == null:
		push_error("thermal debug: viewport returned no image")
		quit(1)
		return true
	var absolute: String = ProjectSettings.globalize_path(OUT_PATH)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	image.save_png(absolute)
	print("thermal debug: %s" % absolute)
	return true


func _load_profiles() -> Array[WeatherProfile]:
	var profiles: Array[WeatherProfile] = []
	var dir := DirAccess.open(PROFILE_DIR)
	if dir == null:
		return profiles
	var names: Array[String] = []
	for file_name: String in dir.get_files():
		var clean: String = file_name.trim_suffix(".remap")
		if clean.ends_with(".tres"):
			names.append(clean)
	for clean: String in names:
		var profile := load("%s/%s" % [PROFILE_DIR, clean]) as WeatherProfile
		if profile != null:
			profiles.append(profile)
	profiles.sort_custom(_by_narrative_order)
	return profiles


## Orders profiles so the charted night escalates instead of shuffling.
func _by_narrative_order(a: WeatherProfile, b: WeatherProfile) -> bool:
	return PROFILE_ORDER.find(a.id) < PROFILE_ORDER.find(b.id)


## Walks the night, switching weather every few hours and recording the body.
func _run_simulation(profiles: Array[WeatherProfile], with_shelter: bool) -> Array[Dictionary]:
	var weather := WeatherController.new()
	weather.profiles = profiles
	weather.scheduler_enabled = false
	root.add_child(weather)
	weather.initialize()

	var manager := ThermalManager.new()
	manager.ambient_min_c = -18.0
	manager.ambient_max_c = -18.0
	manager.weather_controller = weather
	root.add_child(manager)
	manager.initialize()

	var zone := ThermalZone.new()
	zone.is_interior = true
	zone.wind_exposure = 0.0
	zone.temperature_offset_c = 6.0
	zone.max_heated_offset_c = 16.0
	zone.heating_rate_c_per_hour = 9.0
	root.add_child(zone)
	zone.add_heat_source()

	var fire := HeatSource.new()
	fire.peak_offset_c = 18.0
	fire.radius_m = 5.0
	fire.starts_burning = false
	root.add_child(fire)
	fire.initialize()

	var samples: Array[Dictionary] = []
	var segment: float = TOTAL_HOURS / float(profiles.size())
	var clock: float = 18.0
	var elapsed: float = 0.0
	var sheltered: bool = false
	manager.reset_clock()
	manager._on_time_update(clock)

	while elapsed < TOTAL_HOURS:
		var index: int = mini(profiles.size() - 1, int(elapsed / segment))
		weather.set_weather(profiles[index].id, true)
		if with_shelter and not sheltered and elapsed >= SHELTER_AT_HOUR:
			sheltered = true
			manager._zones.append(zone)
			fire.ignite()
		clock = fmod(clock + STEP_HOURS, 24.0)
		manager._on_time_update(clock)
		elapsed += STEP_HOURS
		samples.append({
			"hours": elapsed,
			"body": manager.get_body_temperature_c(),
			"felt": manager.get_felt_temperature_c(),
			"stage": manager.get_stage(),
			"profile": String(profiles[index].id),
		})

	for node: Node in [manager, weather, zone, fire]:
		if node.get_parent() != null:
			node.get_parent().remove_child(node)
		node.free()
	return samples


func _build_canvas() -> void:
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.size = _size
	_canvas.draw.connect(_draw_chart)
	root.add_child(_canvas)


## Draws the body-temperature curve with a band per weather profile.
func _draw_chart() -> void:
	var font: Font = ThemeDB.fallback_font
	_size = root.get_visible_rect().size
	_canvas.size = _size
	_canvas.draw_rect(Rect2(Vector2.ZERO, _size), Color(0.06, 0.07, 0.10))
	if _exposed.is_empty():
		return

	var plot := Rect2(MARGIN, MARGIN, _size.x - MARGIN * 2, _size.y - MARGIN * 2)
	var min_c: float = 26.0
	var max_c: float = 37.5

	var last_profile: String = ""
	var band_start: float = 0.0
	for i: int in range(_exposed.size()):
		var sample: Dictionary = _exposed[i]
		if sample["profile"] != last_profile:
			if last_profile != "":
				_draw_band(plot, band_start, sample["hours"], last_profile, font)
			last_profile = sample["profile"]
			band_start = sample["hours"]
	_draw_band(plot, band_start, TOTAL_HOURS, last_profile, font)

	for line: float in [36.0, 35.0, 33.0, 31.0, 28.0]:
		var y: float = plot.position.y + plot.size.y * (1.0 - (line - min_c) / (max_c - min_c))
		_canvas.draw_line(
			Vector2(plot.position.x, y), Vector2(plot.end.x, y), Color(1, 1, 1, 0.12), 1.0
		)
		_canvas.draw_string(
			font, Vector2(8, y + 5), "%.0f C" % line, HORIZONTAL_ALIGNMENT_LEFT, -1, 16,
			Color(1, 1, 1, 0.45)
		)

	_draw_curve(plot, _exposed, min_c, max_c, Color(0.95, 0.42, 0.38))
	_draw_curve(plot, _sheltered, min_c, max_c, Color(0.45, 0.85, 0.65))

	var shelter_x: float = plot.position.x + plot.size.x * (SHELTER_AT_HOUR / TOTAL_HOURS)
	_canvas.draw_line(
		Vector2(shelter_x, plot.position.y), Vector2(shelter_x, plot.end.y),
		Color(0.45, 0.85, 0.65, 0.45), 2.0
	)
	_canvas.draw_string(
		font, Vector2(shelter_x + 8, plot.end.y - 14), "reaches lit shelter",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(0.45, 0.85, 0.65, 0.9)
	)

	_canvas.draw_string(
		font, Vector2(MARGIN, 76), "red: exposed all night    green: shelters at hour 5",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1, 0.55)
	)

	var final: Dictionary = _sheltered[_sheltered.size() - 1]
	var final_exposed: Dictionary = _exposed[_exposed.size() - 1]
	_canvas.draw_string(
		font, Vector2(MARGIN, 44),
		"Body temperature across one night at -18 C ambient", HORIZONTAL_ALIGNMENT_LEFT, -1, 22,
		Color(1, 1, 1, 0.9)
	)
	_canvas.draw_string(
		font, Vector2(MARGIN, _size.y - 22),
		"exposed ends at %.2f C (stage %d)    sheltered ends at %.2f C (stage %d, felt %.1f C)"
		% [final_exposed["body"], final_exposed["stage"], final["body"], final["stage"], final["felt"]],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1, 0.65)
	)


## Plots one run's body-temperature curve in the given colour.
func _draw_curve(
	plot: Rect2, samples: Array[Dictionary], min_c: float, max_c: float, colour: Color
) -> void:
	var points: PackedVector2Array = PackedVector2Array()
	for sample: Dictionary in samples:
		var x: float = plot.position.x + plot.size.x * (sample["hours"] / TOTAL_HOURS)
		var t: float = clampf((sample["body"] - min_c) / (max_c - min_c), 0.0, 1.0)
		points.append(Vector2(x, plot.position.y + plot.size.y * (1.0 - t)))
	if points.size() > 1:
		_canvas.draw_polyline(points, colour, 3.0, true)


## Shades the time range one weather profile covered and labels it.
func _draw_band(plot: Rect2, from_h: float, to_h: float, label: String, font: Font) -> void:
	var x0: float = plot.position.x + plot.size.x * (from_h / TOTAL_HOURS)
	var x1: float = plot.position.x + plot.size.x * (to_h / TOTAL_HOURS)
	var tint: Color = Color(0.30, 0.45, 0.65, 0.16)
	if label == "blizzard":
		tint = Color(0.85, 0.30, 0.30, 0.20)
	elif label == "snowfall":
		tint = Color(0.60, 0.65, 0.80, 0.16)
	elif label == "calm":
		tint = Color(0.35, 0.70, 0.45, 0.14)
	_canvas.draw_rect(Rect2(x0, plot.position.y, x1 - x0, plot.size.y), tint)
	if x1 - x0 < 90.0:
		return
	_canvas.draw_string(
		font, Vector2(x0 + 10, plot.position.y + 26), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 20,
		Color(1, 1, 1, 0.8)
	)
