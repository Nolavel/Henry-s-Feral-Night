extends Node3D
class_name ExperimentalSnowfallVFX

## Test-only local snowfall volume. WeatherController owns wind direction,
## gusts and snowfall density. This node only turns those live values into VFX.
##
## Two layers are intentional:
## - WorldSnow: many small flakes around Henry.
## - ForegroundSnow: a very small number of larger flakes close to the camera.

const SNOW_SHADER: Shader = preload(
	"res://experimental/weather_snow/wind_driven_snow.gdshader"
)

@export var weather_controller: WeatherController
@export var follow_target: Node3D
@export var foreground_target: Node3D

@export_group("World snow")
@export_range(256, 6000, 64) var max_particles: int = 3840
@export_range(1.0, 12.0, 0.25) var emitter_height: float = 6.0
@export_range(0.0, 12.0, 0.25) var max_upwind_offset: float = 9.0

@export_group("Foreground snow")
@export_range(8, 128, 8) var foreground_particles_max: int = 32
@export_range(0.0, 1.0, 0.01) var foreground_density_scale: float = 0.08
@export_range(0.5, 5.0, 0.1) var foreground_distance: float = 2.4
@export_range(0.0, 3.0, 0.1) var foreground_height: float = 1.0

var particles: GPUParticles3D
var foreground_particles: GPUParticles3D

var _process_material: ShaderMaterial
var _foreground_material: ShaderMaterial
var _visual_wind_velocity: Vector3 = Vector3.ZERO
var _last_direction: Vector3 = Vector3.FORWARD


func _ready() -> void:
	_build_particles()
	_bind_weather()


func _process(_delta: float) -> void:
	if is_instance_valid(follow_target):
		global_position = follow_target.global_position + Vector3.UP * emitter_height

	if foreground_particles != null and is_instance_valid(foreground_target):
		var camera_forward: Vector3 = -foreground_target.global_transform.basis.z.normalized()
		foreground_particles.global_position = (
			foreground_target.global_position
			+ camera_forward * foreground_distance
			+ Vector3.UP * foreground_height
			- _last_direction * minf(_visual_wind_velocity.length() * 0.25, 1.5)
		)


func _build_particles() -> void:
	_process_material = _make_process_material(
		Vector3(24.0, 1.8, 18.0),
		0.55,
		1.00
	)
	particles = _make_particle_layer(
		"WorldSnow",
		max_particles,
		6.5,
		0.012,
		_build_snowflake_mesh(0.010, 0.0016, 0.0042, 0.00115),
		_process_material
	)
	particles.visibility_aabb = AABB(
		Vector3(-48.0, -26.0, -48.0),
		Vector3(96.0, 52.0, 96.0)
	)
	add_child(particles)

	_foreground_material = _make_process_material(
		Vector3(4.2, 2.0, 2.8),
		0.66,
		1.10
	)
	foreground_particles = _make_particle_layer(
		"ForegroundSnow",
		foreground_particles_max,
		3.4,
		0.026,
		_build_snowflake_mesh(0.022, 0.0030, 0.0085, 0.0022),
		_foreground_material
	)
	foreground_particles.randomness = 0.42
	foreground_particles.visibility_aabb = AABB(
		Vector3(-10.0, -8.0, -10.0),
		Vector3(20.0, 16.0, 20.0)
	)
	add_child(foreground_particles)


func _make_process_material(
	emit_size: Vector3,
	size_min: float,
	size_max: float
) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SNOW_SHADER
	material.set_shader_parameter("box_emit_size", emit_size)
	material.set_shader_parameter("size_min", size_min)
	material.set_shader_parameter("size_max", size_max)
	return material


func _make_particle_layer(
	layer_name: String,
	amount: int,
	lifetime: float,
	collision_size: float,
	mesh: Mesh,
	material: ShaderMaterial
) -> GPUParticles3D:
	var layer := GPUParticles3D.new()
	layer.name = layer_name
	layer.amount = amount
	layer.amount_ratio = 0.0
	layer.lifetime = lifetime
	layer.randomness = 0.22
	layer.preprocess = 2.0
	layer.local_coords = false
	layer.fixed_fps = 60
	layer.interpolate = true
	layer.collision_base_size = collision_size
	layer.process_material = material
	layer.draw_pass_1 = mesh
	return layer


func _build_snowflake_mesh(
	arm_length: float,
	arm_width: float,
	branch_length: float,
	branch_width: float
) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()

	for arm_index: int in range(6):
		var angle: float = deg_to_rad(float(arm_index) * 60.0)
		var direction := Vector2(cos(angle), sin(angle))
		_append_strip(
			vertices,
			indices,
			Vector2.ZERO,
			direction * arm_length,
			arm_width
		)

		var branch_root: Vector2 = direction * arm_length * 0.56
		for side: float in [-1.0, 1.0]:
			var branch_direction: Vector2 = direction.rotated(deg_to_rad(42.0 * side))
			_append_strip(
				vertices,
				indices,
				branch_root,
				branch_root + branch_direction * branch_length,
				branch_width
			)

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color(0.94, 0.97, 1.0, 0.94)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, material)
	return mesh


func _append_strip(
	vertices: PackedVector3Array,
	indices: PackedInt32Array,
	from: Vector2,
	to: Vector2,
	width: float
) -> void:
	var direction: Vector2 = (to - from).normalized()
	var normal := Vector2(-direction.y, direction.x) * width * 0.5
	var base: int = vertices.size()
	vertices.append(Vector3(from.x + normal.x, from.y + normal.y, 0.0))
	vertices.append(Vector3(from.x - normal.x, from.y - normal.y, 0.0))
	vertices.append(Vector3(to.x - normal.x, to.y - normal.y, 0.0))
	vertices.append(Vector3(to.x + normal.x, to.y + normal.y, 0.0))
	indices.append_array(PackedInt32Array([
		base, base + 1, base + 2,
		base, base + 2, base + 3,
	]))


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
	if particles != null:
		particles.restart()
	if foreground_particles != null:
		foreground_particles.restart()


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

	var direction: Vector3 = weather_controller.get_wind_direction().normalized()
	var density: float = clampf(snowfall_density, 0.0, 1.0)
	var speed: float = maxf(wind_speed_mps, 0.0)

	var visual_speed: float = minf(
		speed * 0.26 + sqrt(speed) * 0.20,
		7.2
	)
	_last_direction = direction
	_visual_wind_velocity = direction * visual_speed

	for material: ShaderMaterial in [_process_material, _foreground_material]:
		material.set_shader_parameter("wind_velocity", _visual_wind_velocity)
		material.set_shader_parameter(
			"turbulence_strength",
			lerpf(0.10, 1.20, clampf(speed / 28.0, 0.0, 1.0))
		)

	var upwind_offset: float = minf(visual_speed * 1.25, max_upwind_offset)
	particles.position = -direction * upwind_offset
	particles.amount_ratio = density
	particles.emitting = density > 0.005

	var foreground_ratio: float = clampf(
		density * foreground_density_scale,
		0.0,
		1.0
	)
	foreground_particles.amount_ratio = foreground_ratio
	foreground_particles.emitting = foreground_ratio > 0.005


func set_collision_debug(enabled: bool) -> void:
	for material: ShaderMaterial in [_process_material, _foreground_material]:
		if material != null:
			material.set_shader_parameter("collision_debug", enabled)


func get_visual_wind_velocity() -> Vector3:
	return _visual_wind_velocity
