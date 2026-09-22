extends SceneTree

## Captures Freeman's Sky from Henry's eye line at four controlled times.
## The island scene is untouched; all tuning exists only in this harness.

const ISLAND_SCENE: String = "res://experimental_location/scenes/Graciosa_Island_Terrain.tscn"
const SKY_SHADER: String = "res://shaders/environment/freemans_sky_quarter.gdshader"
const TERRAIN_CAPTURE_SHADER: String = "res://shaders/environment/terrain3d_stylized_capture.gdshader"
const SHADOW_MATERIAL: String = "res://scenes/environment/visual_fx/StylizedShadowMaterial.tres"
const OUTPUT_DIR: String = "res://artifacts/freemans_sky"
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
	},
	{
		"name": "2030_blue_hour",
		"hour": 20.5,
		"altitude": -6.0,
		"azimuth": -142.5,
		"light_color": Color(0.44, 0.53, 0.72),
		"light_energy": 0.22,
		"sun_intensity": 18.0,
		"ambient_energy": 0.16,
	},
]

var _scene_root: Node3D
var _terrain: Node
var _camera: Camera3D
var _sun: DirectionalLight3D
var _environment: Environment
var _sky_material: ShaderMaterial
var _player: Node3D
var _frame: int = 0
var _configured: bool = false
var _shot_index: int = -1
var _settle_frames: int = 0


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
	_sky_material.set_shader_parameter("view_samples", 20)
	_sky_material.set_shader_parameter("sun_samples", 6)

	_sun.visible = true
	_sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 1800.0

	var camera_position: Vector3 = _player.global_position + Vector3(0.0, 1.62, 0.0)
	var forward: Vector3 = -_player.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.001:
		forward = Vector3.FORWARD
	forward = forward.normalized()

	_camera.global_position = camera_position
	_camera.fov = 68.0
	_camera.look_at(camera_position + forward * 14.0 + Vector3.UP * 11.0, Vector3.UP)
	_camera.current = true

	_hide_player_visuals(_player)
	_hide_capture_ui(_scene_root)
	_configured = true


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

	print(
		"Freeman sky shot %s hour=%.2f altitude=%.2f azimuth=%.2f"
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

	var path: String = "%s/freemans_sky_%s.png" % [
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
