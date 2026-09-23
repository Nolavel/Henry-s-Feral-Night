extends Node3D
class_name ExperimentalSnowfallVFX

## Test-only local snowfall volume. WeatherController owns wind direction,
## gusts and snowfall density. This node only turns those live values into VFX.

const SNOW_SHADER: Shader = preload(
	"res://experimental/weather_snow/wind_driven_snow.gdshader"
)

@export var weather_controller: WeatherController
@export var follow_target: Node3D
@export_range(256, 6000, 64) var max_particles: int = 3200
@export_range(0.0, 12.0, 0.25) var max_upwind_offset: float = 9.0

var particles: GPUParticles3D
var _process_material: ShaderMaterial
var _visual_wind_velocity: Vector3 = Vector3.ZERO


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
	particles.lifetime = 6.5
	particles.randomness = 0.22
	particles.preprocess = 2.0
	particles.local_coords = false
	particles.fixed_fps = 60
	particles.interpolate = true
	particles.collision_base_size = 0.04
	particles.visibility_aabb = AABB(
		Vector3(-48.0, -26.0, -48.0),
		Vector3(96.0, 52.0, 96.0)
	)

	_process_material = ShaderMaterial.new()
	_process_material.shader = SNOW_SHADER
	particles.process_material = _process_material
	particles.draw_pass_1 = _build_snowflake_mesh()

	add_child(particles)


func _build_snowflake_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()

	# One visible six-arm crystal. It is geometry, not a square texture card.
	# The dimensions are intentionally stylised for the test; production can
	# scale them down after motion/collision is approved.
	for arm_index: int in range(6):
		var angle: float = deg_to_rad(float(arm_index) * 60.0)
		var direction := Vector2(cos(angle), sin(angle))
		_append_strip(vertices, indices, Vector2.ZERO, direction * 0.060, 0.0055)

		var branch_root: Vector2 = direction * 0.034
		for side: float in [-1.0, 1.0]:
			var branch_direction: Vector2 = direction.rotated(deg_to_rad(42.0 * side))
			_append_strip(
				vertices,
				indices,
				branch_root,
				branch_root + branch_direction * 0.022,
				0.0040
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
	material.albedo_color = Color(0.94, 0.97, 1.0, 0.96)
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

	# Weather uses real m/s. VFX uses a compressed visual velocity so a blizzard
	# still crosses the player volume instead of evacuating it in one frame.
	var visual_speed: float = minf(
		speed * 0.26 + sqrt(speed) * 0.20,
		7.2
	)
	_visual_wind_velocity = direction * visual_speed
	_process_material.set_shader_parameter("wind_velocity", _visual_wind_velocity)
	_process_material.set_shader_parameter(
		"turbulence_strength",
		lerpf(0.10, 1.20, clampf(speed / 28.0, 0.0, 1.0))
	)

	# Spawn upstream so strong weather carries flakes through the local volume.
	var upwind_offset: float = minf(visual_speed * 1.25, max_upwind_offset)
	particles.position = -direction * upwind_offset
	particles.amount_ratio = density
	particles.emitting = density > 0.005


func get_visual_wind_velocity() -> Vector3:
	return _visual_wind_velocity
