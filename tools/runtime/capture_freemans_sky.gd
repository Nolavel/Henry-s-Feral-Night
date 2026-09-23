extends SceneTree

## Captures Freeman's Sky from Henry's eye line at four controlled times.
## The island scene is untouched; all tuning exists only in this harness.

const ISLAND_SCENE: String = "res://experimental_location/scenes/Graciosa_Island_Terrain.tscn"
const SKY_SHADER: String = "res://shaders/environment/freemans_parallax_clouds.gdshader"
const TERRAIN_CAPTURE_SHADER: String = "res://shaders/environment/terrain3d_stylized_capture.gdshader"
const SHADOW_MATERIAL: String = "res://scenes/environment/visual_fx/StylizedShadowMaterial.tres"
const OUTPUT_DIR: String = "res://artifacts/freemans_clouds"
const INITIAL_WARMUP_FRAMES: int = 90
const SHOT_SETTLE_FRAMES: int = 18

const SHOTS: Array[Dictionary] = [
	{
		"name": "0615_dawn",
		"hour": 6.25,
		"altitude": 3.5,
		"azimuth": 3.75,
		"light_color": Color(1.0, 0.63, 0.46),
		"light_energy": 1.25,
		"sun_intensity": 39.0,
		"ambient_energy": 0.34,
		"cloud_color": Color(0.34, 0.30, 0.31),
	},
	{
		"name": "1200_noon",
		"hour": 12.0,
		"altitude": 56.0,
		"azimuth": 90.0,
		"light_color": Color(0.93, 0.97, 1.0),
		"light_energy": 2.35,
		"sun_intensity": 48.0,
		"ambient_energy": 0.68,
		"cloud_color": Color(0.30, 0.39, 0.48),
	},
	{
		"name": "1745_sunset",
		"hour": 17.75,
		"altitude": 4.0,
		"azimuth": 176.25,
		"light_color": Color(1.0, 0.50, 0.34),
		"light_energy": 1.35,
		"sun_intensity": 45.0,
		"ambient_energy": 0.40,
		"cloud_color": Color(0.30, 0.24, 0.27),
	},
	{
		"name": "1900_twilight",
		"hour": 19.0,
		"altitude": -1.5,
		"azimuth": 195.0,
		"light_color": Color(0.55, 0.61, 0.78),
		"light_energy": 0.42,
		"sun_intensity": 32.0,
		"ambient_energy": 0.22,
		"cloud_color": Color(0.08, 0.10, 0.15),
	},
]

var _scene_root: Node3D
var _terrain: Node
var _camera: Camera3D
var _sun: DirectionalLight3D
var _environment: Environment
var _sky_material: ShaderMaterial
var _player: Node3D
var _anchor: Vector3 = Vector3(1420.0, 3.0, -943.0)
var _frame: int = 0
var _configured: bool = false
var _shot_index: int = -1
var _settle_frames: int = 0
var _black_frames: int = 0


func _initialize() -> void:
	var packed: PackedScene = load(ISLAND_SCENE) as PackedScene
	if packed == null:
		push_error("Freeman sky capture: island scene failed to load.")
		quit(1)
		return

	_scene_root = packed.instantiate() as Node3D
	if _scene_root == null:
		push_error("Freeman sky capture: island root is not Node3D.")
		quit(1)
		return

	var spawner: Marker3D = _scene_root.get_node_or_null("FirstSpawner") as Marker3D
	if spawner != null:
		_anchor = spawner.position

	_terrain = _scene_root.get_node_or_null("NavigationRegion3D/Terrain3D")
	if _terrain == null:
		push_error("Freeman sky capture: Terrain3D node is absent.")
		quit(1)
		return
	if not _install_capture_terrain_shader():
		quit(1)
		return

	root.add_child(_scene_root)


func _process(_delta: float) -> bool:
	_frame += 1

	if not _configured:
		if _frame < 8:
			return false
		_configure_scene()
		return false

	if _frame < INITIAL_WARMUP_FRAMES:
		return false

	if _settle_frames > 0:
		_settle_frames -= 1
		if _settle_frames == 0:
			_capture_current_shot()
		return false

	_shot_index += 1
	if _shot_index >= SHOTS.size():
		if _black_frames == SHOTS.size():
			push_error("Freeman sky capture: every rendered frame is black.")
			quit(2)
		else:
			quit(0)
		return true

	_apply_shot(SHOTS[_shot_index])
	_settle_frames = SHOT_SETTLE_FRAMES
	return false


func _install_capture_terrain_shader() -> bool:
	var terrain_material: Object = _terrain.get("material")
	if terrain_material == null:
		push_error("Freeman sky capture: Terrain3D material missing.")
		return false

	var custom_shader: Shader = load(TERRAIN_CAPTURE_SHADER) as Shader
	if custom_shader == null:
		push_error("Freeman sky capture: capture terrain shader failed to load.")
		return false

	terrain_material.set("shader_override", custom_shader)
	terrain_material.set("shader_override_enabled", true)

	var source_material: ShaderMaterial = load(SHADOW_MATERIAL) as ShaderMaterial
	if source_material != null and terrain_material.has_method("set_shader_param"):
		var noise_texture: Variant = source_material.get_shader_parameter("noise_texture")
		terrain_material.call("set_shader_param", "hfn_shadow_noise", noise_texture)
		terrain_material.call("set_shader_param", "hfn_scale_macro", 0.09)
		terrain_material.call("set_shader_param", "hfn_scale_detail", 0.44)
		terrain_material.call("set_shader_param", "hfn_shadow_floor", 0.005)
		terrain_material.call("set_shader_param", "hfn_shadow_edge_light", 0.06)
		terrain_material.call("set_shader_param", "hfn_shadow_threshold", 0.46)
		terrain_material.call("set_shader_param", "hfn_break_softness", 0.045)
		terrain_material.call("set_shader_param", "hfn_detail_amount", 0.12)

	_terrain.set("show_grid", false)
	_terrain.set("show_region_grid", false)
	_terrain.set("show_checkered", false)
	return true


func _configure_scene() -> void:
	_camera = _scene_root.get_node_or_null("PlayerCamera") as Camera3D
	_player = _scene_root.get_node_or_null("Player") as Node3D
	_sun = _scene_root.get_node_or_null(
		"WorldEnvironmentSystem/Lighting/SunLight"
	) as DirectionalLight3D
	var world_environment: WorldEnvironment = _scene_root.get_node_or_null(
		"WorldEnvironmentSystem/Environment/WorldEnvironment"
	) as WorldEnvironment

	if _camera == null or _player == null or _sun == null or world_environment == null:
		push_error("Freeman sky capture: camera, player, sun, or environment is missing.")
		quit(1)
		return

	var world_environment_system: Node = _scene_root.get_node_or_null("WorldEnvironmentSystem")
	if world_environment_system != null:
		world_environment_system.process_mode = Node.PROCESS_MODE_DISABLED
	_player.process_mode = Node.PROCESS_MODE_DISABLED
	_camera.process_mode = Node.PROCESS_MODE_DISABLED

	_environment = world_environment.environment
	if _environment == null:
		_environment = Environment.new()
		world_environment.environment = _environment

	var sky_shader: Shader = load(SKY_SHADER) as Shader
	if sky_shader == null:
		push_error("Freeman sky capture: sky shader failed to load.")
		quit(1)
		return

	_sky_material = ShaderMaterial.new()
	_sky_material.shader = sky_shader
	var sky: Sky = Sky.new()
	sky.sky_material = _sky_material
	_environment.sky = sky
	_environment.background_mode = Environment.BG_SKY
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_environment.volumetric_fog_enabled = false

	## Cold maritime tuning: denser aerosol glow without losing the blue-hour ozone.
	_sky_material.set_shader_parameter("rayleigh_scale_height", 9000.0)
	_sky_material.set_shader_parameter("rayleigh_multi_scattering", 0.018)
	_sky_material.set_shader_parameter("mie_scale_height", 1600.0)
	_sky_material.set_shader_parameter("mie_scattering", 0.000008)
	_sky_material.set_shader_parameter("mie_albedo", 0.88)
	_sky_material.set_shader_parameter("mie_g_forward", 0.80)
	_sky_material.set_shader_parameter("mie_weight", 0.78)
	_sky_material.set_shader_parameter("mie_multi_scattering", 0.24)
	_sky_material.set_shader_parameter("ground_color", Vector3(0.10, 0.13, 0.16))
	_sky_material.set_shader_parameter("view_samples", 12)
	_sky_material.set_shader_parameter("sun_samples", 4)
	## GitHub's lavapipe path currently falls back to Compatibility, where the
	## sky shader may not receive LIGHT0. Runtime Forward+ leaves this false.
	_sky_material.set_shader_parameter("use_manual_sun_direction", true)

	## Existing HFN Simple Overcast cloud language, now composited over Freeman.
	_build_cloud_noise()
	_sky_material.set_shader_parameter("cloud_density", 4.8)
	_sky_material.set_shader_parameter("cloud_depth", 2.0)
	_sky_material.set_shader_parameter("cloud_sag", 2.0)
	_sky_material.set_shader_parameter("cloud_noise_tiling", Vector2(1.0, 1.0))
	_sky_material.set_shader_parameter("cloud_wind_speed", Vector2(0.24, 0.08))
	_sky_material.set_shader_parameter("cloud_parallax_strength", 0.22)
	_sky_material.set_shader_parameter("cloud_parallax_layer_separation", 0.35)
	_sky_material.set_shader_parameter("cloud_parallax_detail_weight", 0.45)
	_sky_material.set_shader_parameter("cloud_parallax_mid_scale", 1.65)
	_sky_material.set_shader_parameter("cloud_parallax_high_scale", 2.55)
	_sky_material.set_shader_parameter("cloud_shape_contrast", 0.52)
	_sky_material.set_shader_parameter("cloud_shadow_strength", 0.34)
	_sky_material.set_shader_parameter("cloud_coverage", 0.39)
	_sky_material.set_shader_parameter("cloud_opacity", 0.88)

	_sun.visible = true
	_sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 1800.0

	var camera_position: Vector3 = _position_above_terrain(
		Vector2(_anchor.x, _anchor.z),
		1.62
	)
	## Matches the inward-looking direction already used by the island VFX
	## ground preview, but starts at Henry's authored spawn/eye height.
	var forward: Vector3 = Vector3(-64.0, 0.0, -86.0).normalized()

	_camera.global_position = camera_position
	_camera.fov = 68.0
	_camera.look_at(
		camera_position + forward * 40.0 + Vector3.UP * 10.0,
		Vector3.UP
	)
	_camera.current = true

	_hide_player_visuals(_player)
	_hide_capture_ui(_scene_root)
	_configured = true



func _build_cloud_noise() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = 1731
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.008
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 5
	noise.fractal_lacunarity = 2.0
	noise.fractal_gain = 0.52

	var texture := NoiseTexture2D.new()
	texture.width = 256
	texture.height = 256
	texture.seamless = true
	texture.normalize = true
	texture.noise = noise
	_sky_material.set_shader_parameter("cloud_noise_texture", texture)


func _apply_shot(shot: Dictionary) -> void:
	_sun.rotation_degrees = Vector3(
		-float(shot["altitude"]),
		float(shot["azimuth"]),
		0.0
	)
	_sun.light_color = shot["light_color"] as Color
	_sun.light_energy = float(shot["light_energy"])
	_environment.ambient_light_energy = float(shot["ambient_energy"])
	_sky_material.set_shader_parameter("sun_intensity", float(shot["sun_intensity"]))
	_sky_material.set_shader_parameter("cloud_color", shot["cloud_color"] as Color)
	_sky_material.set_shader_parameter("cloud_sun_color", shot["light_color"] as Color)
	_sky_material.set_shader_parameter("cloud_sun_energy", float(shot["light_energy"]) * 5.0)
	_sky_material.set_shader_parameter(
		"manual_sun_direction",
		_sun_direction_from_angles(float(shot["altitude"]), float(shot["azimuth"]))
	)

	print(
		"Freeman + parallax shot %s hour=%.2f altitude=%.2f azimuth=%.2f"
		% [
			String(shot["name"]),
			float(shot["hour"]),
			float(shot["altitude"]),
			float(shot["azimuth"]),
		]
	)


func _capture_current_shot() -> void:
	var shot: Dictionary = SHOTS[_shot_index]
	var image: Image = root.get_texture().get_image()
	if image == null:
		push_error("Freeman sky capture: viewport image is null.")
		quit(1)
		return

	var mean_luma: float = _sample_mean_luma(image)
	if mean_luma < 0.0005:
		_black_frames += 1
	print("Freeman sky frame mean luma: %.6f" % mean_luma)

	var path: String = "%s/freemans_clouds_%s.png" % [
		OUTPUT_DIR,
		String(shot["name"]),
	]
	var absolute: String = ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var error: Error = image.save_png(absolute)
	if error != OK:
		push_error("Freeman sky capture: save_png failed: %s" % error)
		quit(1)
		return
	print("Freeman sky capture saved: %s" % absolute)


func _position_above_terrain(xz: Vector2, above: float) -> Vector3:
	var ground: float = _anchor.y
	var data: Object = _terrain.get("data")
	if data != null and data.has_method("get_height"):
		var value: Variant = data.call("get_height", Vector3(xz.x, 0.0, xz.y))
		if value is float and not is_nan(float(value)):
			ground = float(value)
	return Vector3(xz.x, ground + above, xz.y)


func _sun_direction_from_angles(altitude_deg: float, azimuth_deg: float) -> Vector3:
	var altitude: float = deg_to_rad(altitude_deg)
	var azimuth: float = deg_to_rad(azimuth_deg)
	var cos_altitude: float = cos(altitude)
	return Vector3(
		cos_altitude * sin(azimuth),
		sin(altitude),
		cos_altitude * cos(azimuth)
	).normalized()


func _sample_mean_luma(image: Image) -> float:
	var total: float = 0.0
	var count: int = 0
	for y: int in range(0, image.get_height(), 64):
		for x: int in range(0, image.get_width(), 64):
			var pixel: Color = image.get_pixel(x, y)
			total += pixel.r * 0.2126 + pixel.g * 0.7152 + pixel.b * 0.0722
			count += 1
	return total / float(maxi(count, 1))


func _hide_player_visuals(node: Node) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).visible = false
	if node is Label3D:
		(node as Label3D).visible = false
	for child: Node in node.get_children():
		_hide_player_visuals(child)


func _hide_capture_ui(node: Node) -> void:
	if node is CanvasItem:
		(node as CanvasItem).visible = false
	if node is CanvasLayer:
		(node as CanvasLayer).visible = false
	if node is Label3D:
		(node as Label3D).visible = false
	for child: Node in node.get_children():
		_hide_capture_ui(child)
