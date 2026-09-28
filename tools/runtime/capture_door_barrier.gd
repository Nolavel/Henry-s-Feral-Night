extends SceneTree

## Native stress capture uses the production snow shaders against the actual shelter door.
class DirectedWeather:
	extends WeatherController
	var direction: Vector3

	func get_wind_direction() -> Vector3:
		return direction

	func get_wind_speed_mps() -> float:
		return 17.0

	func get_snowfall_density() -> float:
		return 1.0

const OUT: String = "res://.godot/codex-checks/door-barrier"
var _camera: Camera3D
var _door: HingedDoor
var _probe: GPUParticles3D


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.size = Vector2i(1280, 720)
	var scene := (load("res://scenes/world/first_exit/first_exit_blockout.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	_door = scene.get_node(^"ShelterHouse/House/HouseDoor") as HingedDoor
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.015, 0.02, 0.03)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.7
	root.add_child(environment)
	_camera = Camera3D.new()
	root.add_child(_camera)
	_camera.global_position = _door.to_global(Vector3(0.45, -0.15, -1.1))
	_camera.look_at(_door.to_global(Vector3(0.65, -0.15, 0.0)))
	_camera.fov = 70.0
	_camera.make_current()
	var weather := DirectedWeather.new()
	weather.profiles = WeatherController.load_profiles_from("res://resources/weather")
	weather.starting_profile_id = &"blizzard"
	weather.scheduler_enabled = false
	weather.direction = -_door.breach.get_facing()
	root.add_child(weather)
	weather.set_process(false)
	BreachDraft.set_weather(weather)
	await create_timer(3.0).timeout
	await _shot("01_actual_closed_gap")
	_probe = GPUParticles3D.new()
	_probe.amount = 512
	_probe.lifetime = 0.7
	_probe.local_coords = false
	_probe.visibility_aabb = AABB(Vector3(-3, -3, -3), Vector3(6, 6, 6))
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/environment/weather/wind_driven_snow.gdshader") as Shader
	material.set_shader_parameter("box_emit_size", Vector3(0.08, 0.25, 0.02))
	material.set_shader_parameter("wind_velocity", _door.global_basis * Vector3(0, 0, -3))
	material.set_shader_parameter("fall_speed_min", 0.1)
	material.set_shader_parameter("fall_speed_max", 0.1)
	material.set_shader_parameter("turbulence_strength", 0.0)
	_probe.process_material = material
	var flake := QuadMesh.new()
	flake.size = Vector2(0.012, 0.012)
	var look := StandardMaterial3D.new()
	look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	look.vertex_color_use_as_albedo = true
	look.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	flake.material = look
	_probe.draw_pass_1 = flake
	root.add_child(_probe)
	_probe.global_position = _door.to_global(Vector3(0.70, -0.15, 0.25))
	_door.apply_snow_barrier(material)
	await create_timer(2.0).timeout
	await _shot("02_exterior_gap_stress")
	_probe.global_position = _door.to_global(Vector3(0.25, -0.15, 0.25))
	await create_timer(2.0).timeout
	await _shot("03_exterior_leaf_blocked")
	var blockers: Array[Node] = scene.find_children("*", "GPUParticlesCollision3D", true, false)
	for blocker: Node in blockers:
		blocker.set(&"cull_mask", 0)
	material.set_shader_parameter("snow_door_enabled", false)
	await create_timer(2.0).timeout
	await _shot("04_without_barrier_control")
	for blocker: Node in blockers:
		blocker.set(&"cull_mask", 0xFFFFF)
	_door.apply_snow_barrier(material)
	_door.door_hinge.rotation.y = deg_to_rad(45.0)
	_door._sync_breach_exposure()
	_door.apply_snow_barrier(material)
	await create_timer(2.0).timeout
	await _shot("05_leaf_at_45_degrees")
	print("door barrier captures: ", ProjectSettings.globalize_path(OUT))
	quit()


func _shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + "/" + label + ".png")
