extends Node3D
class_name ExperimentalSnowfallVFX

## Test-only local snowfall volume. WeatherController owns all weather motion;
## this node only translates its current conditions into particle parameters.

const SNOW_SHADER: Shader = preload(
	"res://experimental/weather_snow/wind_driven_snow.gdshader"
)

@export var weather_controller: WeatherController
@export var follow_target: Node3D
@export_range(0.0, 1.5, 0.05) var wind_response: float = 0.55
@export_range(256, 5000, 64) var max_particles: int = 2304

var particles: GPUParticles3D
var _process_material: ShaderMaterial


func _ready() -> void:
	_build_particles()
	_bind_weather()


func _process(_delta: float) -> void:
	if is_instance_valid(follow_target):
		var target_position: Vector3 = follow_target.global_position
		global_position.x = target_position.x
		global_position.z = target_position.z


func _build_particles() -> void:
	particles = GPUParticles3D.new()
	particles.name = "SnowParticles"
	particles.amount = max_particles
	particles.amount_ratio = 0.0
	particles.lifetime = 6.0
	particles.randomness = 0.28
	particles.preprocess = 1.5
	particles.local_coords = false
	particles.fixed_fps = 30
	particles.interpolate = true
	particles.visibility_aabb = AABB(
		Vector3(-40.0, -24.0, -40.0),
		Vector3(80.0, 48.0, 80.0)
	)

	_process_material = ShaderMaterial.new()
	_process_material.shader = SNOW_SHADER
	particles.process_material = _process_material

	var flake_material := StandardMaterial3D.new()
	flake_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flake_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flake_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	flake_material.vertex_color_use_as_albedo = true
	flake_material.albedo_color = Color(0.94, 0.97, 1.0, 0.92)

	var flake := QuadMesh.new()
	flake.size = Vector2(0.055, 0.055)
	flake.material = flake_material
	particles.draw_pass_1 = flake

	add_child(particles)


func _bind_weather() -> void:
	if not is_instance_valid(weather_controller):
		return
	if not weather_controller.conditions_updated.is_connected(_on_conditions_updated):
		weather_controller.conditions_updated.connect(_on_conditions_updated)
	if not weather_controller.weather_changed.is_connected(_on_weather_changed):
		weather_controller.weather_changed.connect(_on_weather_changed)
	sync_from_weather()


func sync_from_weather() -> void:
	if not is_instance_valid(weather_controller) or _process_material == null:
		return
	_apply_conditions(
		weather_controller.get_wind_speed_mps(),
		weather_controller.get_snowfall_density()
	)


func restart_particles() -> void:
	if particles == null:
		return
	particles.restart()


func _on_weather_changed(_profile: WeatherProfile) -> void:
	sync_from_weather()


func _on_conditions_updated(
	_ambient_offset_c: float,
	wind_speed_mps: float,
	snowfall_density: float
) -> void:
	_apply_conditions(wind_speed_mps, snowfall_density)


func _apply_conditions(wind_speed_mps: float, snowfall_density: float) -> void:
	if _process_material == null or particles == null:
		return
	var direction: Vector3 = weather_controller.get_wind_direction()
	var density: float = clampf(snowfall_density, 0.0, 1.0)
	var speed: float = maxf(wind_speed_mps, 0.0)

	# Tiny snow crystals quickly inherit air motion, but not at a literal 1:1
	# visual scale. WeatherController remains the sole authority for direction.
	_process_material.set_shader_parameter(
		"wind_velocity",
		direction * speed * wind_response
	)
	_process_material.set_shader_parameter(
		"turbulence_strength",
		lerpf(0.12, 1.35, clampf(speed / 28.0, 0.0, 1.0))
	)

	particles.amount_ratio = density
	particles.emitting = density > 0.005
