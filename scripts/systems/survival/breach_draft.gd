class_name BreachDraft
extends Node3D

## Weather-driven snow uses the actual door gaps or the remaining window opening.
const DRAFT_SHADER: Shader = preload("res://shaders/environment/weather/breach_draft.gdshader")
const FULL_WIND_MPS: float = 12.0
const MIN_EXPOSURE: float = 0.001
static var _weather: WeatherController
var breach: ShelterBreach
var _streams: Array[GPUParticles3D] = []
var _check_left: float = 0.0


func _ready() -> void:
	if breach == null:
		breach = get_parent() as ShelterBreach
	for index: int in range(4 if breach != null and breach.closure != null else 1):
		_streams.append(_make_stream(index))


static func set_weather(weather: WeatherController) -> void:
	_weather = weather


func get_strength() -> float:
	var weather: WeatherController = _find_weather()
	if breach == null or weather == null or breach.is_boarded():
		return 0.0
	var exposure: float = breach.get_exposure_against(weather.get_wind_direction())
	if breach.severity > 0.0:
		exposure /= breach.severity
	return clampf(exposure * weather.get_wind_speed_mps() / FULL_WIND_MPS * weather.get_snowfall_density(), 0.0, 1.0)


func is_blowing() -> bool:
	for stream: GPUParticles3D in _streams:
		if stream.emitting:
			return true
	return false


func get_emission_regions() -> Array[AABB]:
	if breach.closure != null:
		return breach.closure.get_draft_regions()
	return [AABB(Vector3(-breach.opening_width_m * 0.5, -breach.opening_height_m * 0.5, -0.075), Vector3(breach.opening_width_m, breach.opening_height_m, 0.01))]


func _process(delta: float) -> void:
	_check_left -= delta
	if _check_left > 0.0:
		return
	_check_left = 0.05 if breach.closure != null and breach.closure.is_swinging() else 0.2
	var regions: Array[AABB] = get_emission_regions()
	while _streams.size() < regions.size():
		_streams.append(_make_stream(_streams.size()))
	var strength: float = get_strength()
	for index: int in range(_streams.size()):
		var stream: GPUParticles3D = _streams[index]
		stream.emitting = index < regions.size() and strength > MIN_EXPOSURE
		if not stream.emitting:
			continue
		var region: AABB = regions[index]
		stream.position = region.get_center()
		var material := stream.process_material as ShaderMaterial
		material.set_shader_parameter("emission_box_extents", region.size * 0.5)
		if breach.closure != null:
			breach.closure.apply_snow_barrier(material)
		stream.amount_ratio = clampf(strength, 0.02, 1.0)
		var closed: bool = breach.closure != null and not breach.closure.is_open() and not breach.closure.is_swinging()
		material.set_shader_parameter("speed_min", 0.35 if closed else 1.6)
		material.set_shader_parameter("speed_max", 0.7 if closed else 3.2)


func _make_stream(index: int) -> GPUParticles3D:
	var snow := GPUParticles3D.new()
	snow.name = "Snow%d" % index
	snow.amount = 40 if breach.closure != null else 160
	snow.lifetime = 1.2
	snow.emitting = false
	snow.local_coords = false
	snow.collision_base_size = 0.002
	snow.visibility_aabb = AABB(Vector3(-3.0, -2.0, -3.0), Vector3(6.0, 4.0, 6.0))
	var material := ShaderMaterial.new()
	material.shader = DRAFT_SHADER
	snow.process_material = material
	var flake := QuadMesh.new()
	flake.size = Vector2(0.012, 0.012)
	var look := StandardMaterial3D.new()
	look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	look.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	look.vertex_color_use_as_albedo = true
	look.albedo_color = Color.WHITE
	flake.material = look
	snow.draw_pass_1 = flake
	add_child(snow)
	return snow


func _find_weather() -> WeatherController:
	if is_instance_valid(_weather) and not _weather.profiles.is_empty():
		return _weather
	if is_inside_tree():
		for node: Node in get_tree().root.find_children("*", "", true, false):
			if node is WeatherController and not (node as WeatherController).profiles.is_empty():
				_weather = node as WeatherController
				return _weather
	return null
