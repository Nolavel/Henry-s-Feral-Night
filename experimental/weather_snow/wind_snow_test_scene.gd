extends Node3D

const WEATHER_CONTROLLER_SCRIPT: GDScript = preload(
	"res://scripts/systems/world/WeatherController.gd"
)
const SNOW_VFX_SCRIPT: GDScript = preload(
	"res://experimental/weather_snow/snowfall_vfx.gd"
)

var weather_controller: WeatherController
var snow_vfx: ExperimentalSnowfallVFX
var status_label: Label


func _ready() -> void:
	_build_environment()
	_build_weather()
	_build_snow()
	set_weather_profile(&"snowfall")


func _process(_delta: float) -> void:
	_update_status()


func set_weather_profile(id: StringName) -> void:
	if weather_controller == null:
		return
	weather_controller.set_weather(id, true)
	if snow_vfx != null:
		snow_vfx.sync_from_weather()
		snow_vfx.restart_particles()
	_update_status()


func _build_weather() -> void:
	weather_controller = WEATHER_CONTROLLER_SCRIPT.new() as WeatherController
	weather_controller.name = "WeatherController"
	weather_controller.scheduler_enabled = false
	weather_controller.starting_profile_id = &"calm"

	var loaded_profiles: Array[WeatherProfile] = []
	for path: String in [
		"res://resources/weather/calm.tres",
		"res://resources/weather/snowfall.tres",
		"res://resources/weather/windy.tres",
		"res://resources/weather/blizzard.tres",
	]:
		var profile := load(path) as WeatherProfile
		if profile != null:
			loaded_profiles.append(profile)
	weather_controller.profiles = loaded_profiles
	add_child(weather_controller)


func _build_snow() -> void:
	snow_vfx = SNOW_VFX_SCRIPT.new() as ExperimentalSnowfallVFX
	snow_vfx.name = "LocalSnowVFX"
	snow_vfx.weather_controller = weather_controller
	snow_vfx.position = Vector3(0.0, 9.0, 0.0)
	add_child(snow_vfx)


func _build_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.055, 0.065, 0.085)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.42, 0.48, 0.58)
	environment.ambient_light_energy = 0.55
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.42, 0.48, 0.56)
	environment.fog_light_energy = 0.35
	environment.fog_density = 0.008

	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38.0, -42.0, 0.0)
	sun.light_color = Color(0.78, 0.86, 1.0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	add_child(sun)

	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color(0.72, 0.76, 0.80)
	ground_material.roughness = 0.95

	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(34.0, 34.0)
	ground_mesh.material = ground_material
	var ground := MeshInstance3D.new()
	ground.mesh = ground_mesh
	add_child(ground)

	_make_marker(Vector3(-5.0, 1.5, -4.0), Vector3(0.7, 3.0, 0.7), Color(0.22, 0.25, 0.30))
	_make_marker(Vector3(0.0, 2.3, -8.0), Vector3(1.0, 4.6, 1.0), Color(0.17, 0.20, 0.25))
	_make_marker(Vector3(5.0, 1.0, -2.0), Vector3(0.8, 2.0, 0.8), Color(0.25, 0.27, 0.31))

	var camera := Camera3D.new()
	camera.name = "Camera3D"
	camera.current = true
	camera.fov = 62.0
	camera.position = Vector3(0.0, 4.2, 13.5)
	add_child(camera)
	camera.look_at(Vector3(0.0, 4.0, -1.5), Vector3.UP)

	var canvas := CanvasLayer.new()
	add_child(canvas)
	status_label = Label.new()
	status_label.position = Vector2(24.0, 22.0)
	status_label.add_theme_font_size_override("font_size", 22)
	status_label.add_theme_color_override("font_color", Color(0.94, 0.97, 1.0))
	canvas.add_child(status_label)


func _make_marker(position_3d: Vector3, size: Vector3, color: Color) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var marker := MeshInstance3D.new()
	marker.position = position_3d
	marker.mesh = mesh
	add_child(marker)


func _update_status() -> void:
	if status_label == null or weather_controller == null:
		return
	var profile := weather_controller.get_current_profile()
	var id: String = String(profile.id) if profile != null else "none"
	var wind: Vector3 = weather_controller.get_wind_direction()
	status_label.text = (
		"%s   snow %.2f   wind %.1f m/s   dir (%.2f, %.2f)"
		% [
			id,
			weather_controller.get_snowfall_density(),
			weather_controller.get_wind_speed_mps(),
			wind.x,
			wind.z,
		]
	)
