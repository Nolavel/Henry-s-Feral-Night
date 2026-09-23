extends SceneTree

## Real-island snow validation around Henry.
## Tests two things in one CI pass:
## 1) small world flakes + rare large foreground flakes;
## 2) GPUParticlesCollisionHeightField3D following the camera over Terrain3D.

const ISLAND_SCENE: String = "res://experimental_location/scenes/Graciosa_Island_Terrain.tscn"
const SNOW_VFX_SCRIPT: GDScript = preload(
	"res://experimental/weather_snow/snowfall_vfx.gd"
)
const TERRAIN_CAPTURE_SHADER: String = "res://shaders/environment/terrain3d_stylized_capture.gdshader"
const SHADOW_MATERIAL: String = "res://scenes/environment/visual_fx/StylizedShadowMaterial.tres"
const OUTPUT_DIR: String = "user://shots/island_snow_heightfield"

const INITIAL_WARMUP_FRAMES: int = 90
const STATE_SETTLE_FRAMES: int = 120

const SHOTS: Array[Dictionary] = [
	{"name": "01_snowfall", "weather": &"snowfall", "collision_debug": false},
	{"name": "02_windy", "weather": &"windy", "collision_debug": false},
	{"name": "03_blizzard", "weather": &"blizzard", "collision_debug": false},
	{"name": "04_heightfield_probe", "weather": &"snowfall", "collision_debug": true},
]

var _scene_root: Node3D
var _terrain: Node
var _player: Node3D
var _camera: Camera3D
var _heightfield: GPUParticlesCollisionHeightField3D
var _weather: WeatherController
var _snow: ExperimentalSnowfallVFX

var _anchor: Vector3 = Vector3(1420.0, 3.0, -943.0)
var _configured: bool = false
var _frame: int = 0
var _shot_index: int = -1
var _settle: int = 0


func _initialize() -> void:
	root.size = Vector2i(1280, 720)

	var packed := load(ISLAND_SCENE) as PackedScene
	if packed == null:
		push_error("Island snow capture: island scene failed to load.")
		quit(1)
		return

	_scene_root = packed.instantiate() as Node3D
	if _scene_root == null:
		push_error("Island snow capture: island root is not Node3D.")
		quit(1)
		return

	# Keep this capture isolated from the production composition-root lifecycle.
	_scene_root.set_script(null)

	var spawner := _scene_root.get_node_or_null("FirstSpawner") as Marker3D
	if spawner != null:
		# Before tree-entry global_position is not resolved; the island root is
		# identity, so the authored local marker position is the correct anchor.
		_anchor = spawner.position

	_terrain = _scene_root.get_node_or_null("NavigationRegion3D/Terrain3D")
	_player = _scene_root.get_node_or_null("Player") as Node3D
	if _terrain == null or _player == null:
		push_error("Island snow capture: Terrain3D or Player is missing.")
		quit(1)
		return

	_player.process_mode = Node.PROCESS_MODE_DISABLED
	_disable_existing_cameras(_scene_root)
	_hide_capture_ui(_scene_root)

	if not _install_capture_terrain_shader():
		quit(1)
		return

	root.add_child(_scene_root)


func _process(_delta: float) -> bool:
	_frame += 1

	if not _configured:
		if _frame < INITIAL_WARMUP_FRAMES:
			return false
		_configure_island_test()
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
	_snow.set_collision_debug(bool(shot["collision_debug"]))
	_snow.foreground_particles.visible = not bool(shot["collision_debug"])
	_snow.sync_from_weather()
	_snow.restart_particles()
	_settle = STATE_SETTLE_FRAMES
	return false


func _configure_island_test() -> void:
	var ground_anchor := _position_above_terrain(Vector2(_anchor.x, _anchor.z), 0.0)

	_player.global_position = ground_anchor + Vector3.UP * 1.0
	_player.rotation_degrees.y = 18.0

	_camera = Camera3D.new()
	_camera.name = "SnowCaptureCamera"
	_camera.fov = 61.0
	_scene_root.add_child(_camera)

	var forward := Vector3(-0.38, 0.0, -1.0).normalized()
	_camera.global_position = (
		ground_anchor
		- forward * 7.0
		+ Vector3.UP * 2.65
	)
	_camera.look_at(ground_anchor + Vector3.UP * 1.55, Vector3.UP)
	_camera.current = true

	_heightfield = GPUParticlesCollisionHeightField3D.new()
	_heightfield.name = "HenrySnowHeightField"
	_heightfield.size = Vector3(56.0, 28.0, 56.0)
	_heightfield.resolution = GPUParticlesCollisionHeightField3D.RESOLUTION_512
	_heightfield.update_mode = GPUParticlesCollisionHeightField3D.UPDATE_MODE_WHEN_MOVED
	_heightfield.follow_camera_enabled = true
	_scene_root.add_child(_heightfield)
	_heightfield.global_position = _camera.global_position

	_weather = WeatherController.new()
	_weather.name = "SnowCaptureWeather"
	_weather.scheduler_enabled = false
	_weather.starting_profile_id = &"snowfall"
	_weather.profiles = WeatherController.load_profiles_from("res://resources/weather")
	_scene_root.add_child(_weather)
	_weather.initialize()

	_snow = SNOW_VFX_SCRIPT.new() as ExperimentalSnowfallVFX
	_snow.name = "HenryLocalSnow"
	_snow.weather_controller = _weather
	_snow.follow_target = _player
	_snow.foreground_target = _camera
	_scene_root.add_child(_snow)
	_snow.sync_from_weather()

	# Moving the current camera after the collider is in-tree forces the first
	# heightfield refresh in UPDATE_MODE_WHEN_MOVED + follow-camera mode.
	_camera.global_position += Vector3(0.02, 0.0, 0.0)
	_camera.global_position -= Vector3(0.02, 0.0, 0.0)

	print(
		"Island snow HeightField size=%s resolution=512 follow_camera=true anchor=%s"
		% [str(_heightfield.size), str(ground_anchor)]
	)
	_configured = true


func _capture_shot(shot: Dictionary) -> void:
	var image := root.get_texture().get_image()
	if image == null:
		push_error("Island snow capture: viewport image is null.")
		quit(1)
		return

	print(
		"Island snow shot=%s density=%.2f weather_wind=%.2f visual_wind=%s collision_debug=%s"
		% [
			String(shot["name"]),
			_weather.get_snowfall_density(),
			_weather.get_wind_speed_mps(),
			str(_snow.get_visual_wind_velocity()),
			str(bool(shot["collision_debug"])),
		]
	)

	var path := "%s/island_snow_%s.png" % [OUTPUT_DIR, String(shot["name"])]
	var absolute := ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var error := image.save_png(absolute)
	if error != OK:
		push_error("Island snow capture: save_png failed: %s" % error)
		quit(1)
		return
	print("Island snow capture saved: %s" % absolute)


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
		push_error("Island snow capture: Terrain3D material missing.")
		return false

	var custom_shader := load(TERRAIN_CAPTURE_SHADER) as Shader
	if custom_shader == null:
		push_error("Island snow capture: terrain capture shader failed to load.")
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
