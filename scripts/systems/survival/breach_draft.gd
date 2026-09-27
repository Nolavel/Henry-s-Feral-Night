class_name BreachDraft
extends Node3D

## Snow blowing in through an open ShelterBreach (the parent), as dense as the
## hole is exposed to the current wind: the player reads which side to board
## first by looking, not by a meter. Gone once the breach is boarded.

## Wind speed (m/s) at which an exposed hole shows its full stream.
const FULL_WIND_MPS: float = 12.0
## Exposure below this shows nothing: a lee-side hole stays quiet.
const MIN_EXPOSURE: float = 0.02

static var _weather: WeatherController

var breach: ShelterBreach
var _snow: GPUParticles3D
var _check_left: float = 0.0


func _ready() -> void:
	if breach == null:
		breach = get_parent() as ShelterBreach
	_snow = GPUParticles3D.new()
	_snow.name = "Snow"
	_snow.amount = 160
	_snow.lifetime = 1.6
	_snow.emitting = false
	_snow.local_coords = false
	_snow.visibility_aabb = AABB(Vector3(-3.0, -2.0, -3.0), Vector3(6.0, 4.0, 6.0))
	_snow.position = Vector3(0.0, 0.0, -0.35)  # just outside; the breach faces -Z
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(0.35, 0.45, 0.05)
	process.direction = Vector3(0.0, -0.15, 1.0)  # inward (+Z), sinking a little
	process.spread = 14.0
	process.initial_velocity_min = 1.6
	process.initial_velocity_max = 3.2
	process.gravity = Vector3(0.0, -1.2, 0.0)
	process.scale_min = 0.6
	process.scale_max = 1.2
	process.particle_flag_align_y = false
	_snow.process_material = process
	var flake := QuadMesh.new()
	flake.size = Vector2(0.025, 0.025)
	var look := StandardMaterial3D.new()
	look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	look.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	look.albedo_color = Color(0.95, 0.97, 1.0, 0.8)
	look.disable_fog = true
	flake.material = look
	_snow.draw_pass_1 = flake
	add_child(_snow)


## The wind the draft reads; tests set it, the game finds the populated controller.
static func set_weather(weather: WeatherController) -> void:
	_weather = weather


## Current stream strength 0..1: exposure against the wind times wind speed.
func get_strength() -> float:
	var weather: WeatherController = _find_weather()
	if breach == null or weather == null or breach.is_boarded():
		return 0.0
	var exposure: float = breach.get_exposure_against(weather.get_wind_direction())
	if breach.severity > 0.0:
		exposure /= breach.severity  # direction only; severity scales amount below
	var speed: float = clampf(weather.get_wind_speed_mps() / FULL_WIND_MPS, 0.0, 1.0)
	return clampf(exposure * speed * (0.5 + breach.severity), 0.0, 1.0)


func is_blowing() -> bool:
	return _snow != null and _snow.emitting


func _process(delta: float) -> void:
	_check_left -= delta
	if _check_left > 0.0:
		return
	_check_left = 0.5
	var strength: float = get_strength()
	var blowing: bool = strength > MIN_EXPOSURE
	if _snow.emitting != blowing:
		_snow.emitting = blowing
	if blowing:
		_snow.amount_ratio = snappedf(clampf(strength, 0.1, 1.0), 0.05)


func _find_weather() -> WeatherController:
	if is_instance_valid(_weather) and not _weather.profiles.is_empty():
		return _weather
	if not is_inside_tree():
		return null
	for node: Node in get_tree().root.find_children("*", "", true, false):
		var candidate := node as WeatherController
		if candidate != null and not candidate.profiles.is_empty():
			_weather = candidate
			return candidate
	return null
