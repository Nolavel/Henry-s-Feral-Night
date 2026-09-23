extends SceneTree

## Production snowfall regression on the authored island around Henry.
## Captures the exact SnowfallVFX world-system script that world.gd instantiates.

const ISLAND_SCENE: String = "res://experimental_location/scenes/Graciosa_Island_Terrain.tscn"
const SNOW_SCRIPT: GDScript = preload(
	"res://scripts/systems/world/weather/snowfall_vfx.gd"
)
const TERRAIN_CAPTURE_SHADER: String = "res://shaders/environment/terrain3d_stylized_capture.gdshader"
const SHADOW_MATERIAL: String = "res://scenes/environment/visual_fx/StylizedShadowMaterial.tres"
const OUTPUT_DIR: String = "user://shots/production_snow"

const INITIAL_WARMUP_FRAMES: int = 90
const STATE_SETTLE_FRAMES: int = 100
const SHOTS: Array[Dictionary] = [
	{"name": "01_snowfall", "weather": &"snowfall"},
	{"name": "02_windy", "weather": &"windy"},
	{"name": "03_blizzard", "weather": &"blizzard"},
]

var _scene_root: Node3D
var _terrain: Node
var _player: Node3D
var _camera: Camera3D
var _weather: WeatherController
var _snow: SnowfallVFX
var _heightfield: SnowHeightFieldService

var _anchor: Vector3 = Vector3(1420.0, 3.0, -943.0)
var _configured: bool = false
var _frame: int = 0
var _shot_index: int = -1
var _settle: int = 0
var _sample_count: int = 0
var _sample_delta_sum: float = 0.0
var _sample_delta_max: float = 0.0


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	var packed := load(ISLAND_SCENE) as PackedScene
	if packed == null:
		push_error("Production snow capture: island scene failed to load.")
		quit(1)
		return

	_scene_root = packed.instantiate() as Node3D
	if _scene_root == null:
		push_error("Production snow capture: island root is not Node3D.")
		quit(1)
		return

	_scene_root.set_script(null)

	var spawner := _scene_root.get_node_or_null("FirstSpawner") as Marker3D
	if spawner != null:
		_anchor = spawner.position

	_terrain = _scene_root.get_node_or_null("NavigationRegion3D/Terrain3D")
	_player = _scene_root.get_node_or_null("Player") as Node3D
	if _terrain == null or _player == null:
		push_error("Production snow capture: Terrain3D or Player is missing.")
		quit(1)
		return

	_player.process_mode = Node.PROCESS_MODE_DISABLED
	_disable_existing_cameras(_scene_root)
	_hide_capture_ui(_scene_root)

	if not _install_capture_terrain_shader():
		quit(1)
		return

	root.add_child(_scene_root)


func _process(delta: float) -> bool:
	_frame += 1

	if _settle > 0 and _settle < 80:
		_sample_count += 1
		_sample_delta_sum += delta
		_sample_delta_max = maxf(_sample_delta_max, delta)

	if not _configured:
		if _frame < INITIAL_WARMUP_FRAMES:
			return false
		_configure()
		return false

	if _settle > 0:
		_settle -= 1
		if _settle == 0:
			_capture_shot(SHOTS[_shot_index])
		return false

	_shot_index += 1
	if _shot_index >= SHOTS.size():
		quit(0)
		return true

	var shot: Dictionary = SHOTS[_shot_index]
	_weather.set_weather(shot["weather"] as StringName, true)
	_snow.sync_from_weather()
	_snow.restart_particles()
	_sample_count = 0
	_sample_delta_sum = 0.0
	_sample_delta_max = 0.0
	_settle = STATE_SETTLE_FRAMES
	return false


func _configure() -> void:
	var ground_anchor := _position_above_terrain(Vector2(_anchor.x, _anchor.z), 0.0)
	_player.global_position = ground_anchor + Vector3.UP
	_player.rotation_degrees.y = 18.0

	_camera = Camera3D.new()
	_camera.name = "SnowCaptureCamera"
	_camera.fov = 61.0
	_scene_root.add_child(_camera)

	var forward := Vector3(-0.38, 0.0, -1.0).normalized()
	_camera.global_position = ground_anchor - forward * 7.0 + Vector3.UP * 2.65
	_camera.look_at(ground_anchor + Vector3.UP * 1.55, Vector3.UP)
	_camera.current = true

	_weather = WeatherController.new()
	_weather.name = "SnowCaptureWeather"
	_weather.scheduler_enabled = false
	_weather.starting_profile_id = &"snowfall"
	_weather.profiles = WeatherController.load_profiles_from("res://resources/weather")
	_scene_root.add_child(_weather)
	_weather.initialize()

	_snow = SNOW_SCRIPT.new() as SnowfallVFX
	if _snow == null:
		push_error("Production snow capture: SnowfallVFX system failed to instantiate.")
		quit(1)
		return
	_scene_root.add_child(_snow)

	var context := WorldContext.new()
	context.player = _player
	context.camera = _camera
	context.stream_container = _scene_root
	context.world = _scene_root
	var systems: Array[Node] = []
	systems.append(_weather)
	context.systems = systems
	_snow.on_world_ready(context)
	_snow.sync_from_weather()

	_heightfield = _snow.get_node_or_null("HeightFieldService") as SnowHeightFieldService
	if _heightfield == null:
		push_error("Production snow capture: HeightFieldService missing.")
		quit(1)
		return

	print(
		"Production snow HeightField size=%s resolution=256 snap=8m particles=3072+32 anchor=%s"
		% [str(_heightfield.size), str(ground_anchor)]
	)
	_configured = true


func _capture_shot(shot: Dictionary) -> void:
	var image := root.get_texture().get_image()
	if image == null:
		push_error("Production snow capture: viewport image is null.")
		quit(1)
		return

	var avg_ms: float = (
		(_sample_delta_sum / float(_sample_count)) * 1000.0
		if _sample_count > 0
		else 0.0
	)
	var approx_fps: float = 1000.0 / avg_ms if avg_ms > 0.0 else 0.0
	print(
		"Production snow shot=%s density=%.2f weather_wind=%.2f visual_wind=%s avg_frame_ms=%.2f approx_fps=%.1f max_frame_ms=%.2f"
		% [
			String(shot["name"]),
			_weather.get_snowfall_density(),
			_weather.get_wind_speed_mps(),
			str(_snow.get_visual_wind_velocity()),
			avg_ms,
			approx_fps,
			_sample_delta_max * 1000.0,
		]
	)

	var path := "%s/production_snow_%s.png" % [OUTPUT_DIR, String(shot["name"])]
	var absolute := ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var error := image.save_png(absolute)
	if error != OK:
		push_error("Production snow capture: save_png failed: %s" % error)
		quit(1)
		return
	print("Production snow capture saved: %s" % absolute)


func _position_above_terrain(xz: Vector2, above: float) -> Vector3:
	var ground: float = _anchor.y
	var data: Object = _terrain.get("data")
	if data != null and data.has_method("get_height"):
		var value: Variant = data.call("get_height", Vector3(xz.x, 0.0, xz.y))
		if value is float and not is_nan(float(value)):
			ground = float(value)
	return Vector3(xz.x, ground + above, xz.y)


func _install_capture_terrain_shader() -> bool:
	var terrain_material: Object = _terrain.get("material")
	if terrain_material == null:
		push_error("Production snow capture: Terrain3D material missing.")
		return false

	var custom_shader := load(TERRAIN_CAPTURE_SHADER) as Shader
	if custom_shader == null:
		push_error("Production snow capture: terrain capture shader failed to load.")
		return false

	terrain_material.set("shader_override", custom_shader)
	terrain_material.set("shader_override_enabled", true)

	var source_material := load(SHADOW_MATERIAL) as ShaderMaterial
	if source_material != null and terrain_material.has_method("set_shader_param"):
		var noise_texture: Variant = source_material.get_shader_parameter("noise_texture")
		terrain_material.call("set_shader_param", &"noise_texture", noise_texture)
	return true


func _disable_existing_cameras(node: Node) -> void:
	if node is Camera3D:
		(node as Camera3D).current = false
		(node as Camera3D).process_mode = Node.PROCESS_MODE_DISABLED
	for child: Node in node.get_children():
		_disable_existing_cameras(child)


func _hide_capture_ui(node: Node) -> void:
	if node is CanvasItem:
		(node as CanvasItem).visible = false
	if node is CanvasLayer:
		(node as CanvasLayer).visible = false
	if node is Label3D:
		(node as Label3D).visible = false
	for child: Node in node.get_children():
		_hide_capture_ui(child)
