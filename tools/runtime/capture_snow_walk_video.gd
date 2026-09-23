extends SceneTree

## 20-second visual regression for Claude's snow presentation + bone-driven
## footprints. Loads the configured main scene and drives Henry through the
## real input path; no synthetic foot stamps are injected.

const OUT_DIR := "res://artifacts/snow_walk_video"
const FRAME_DIR := OUT_DIR + "/frames"
const VIDEO_FPS := 15
const DURATION_S := 20.0
const TOTAL_FRAMES := int(VIDEO_FPS * DURATION_S)
const WALK_START_S := 1.5
const WALK_END_S := 15.5
const VIEWPORT_SIZE := Vector2i(960, 540)

const WEATHER_SCRIPT: GDScript = preload("res://scripts/systems/world/WeatherController.gd")
const FOOTPRINT_SCRIPT: GDScript = preload("res://scripts/systems/world/snow/footprint_system.gd")
const SNOWFALL_SCRIPT: GDScript = preload("res://scripts/systems/world/weather/snowfall_vfx.gd")
const SNOW_PROP_SHADER: Shader = preload("res://shaders/environment/snow/snow_prop.gdshader")

var _scene: Node
var _player: CharacterBody3D
var _camera: Camera3D
var _weather: WeatherController
var _footprints: FootprintSystem
var _snowfall: SnowfallVFX
var _start_position := Vector3.ZERO
var _end_position := Vector3.ZERO


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = VIEWPORT_SIZE
	var main_scene_path: String = String(ProjectSettings.get_setting("application/run/main_scene", ""))
	var packed := load(main_scene_path) as PackedScene
	if packed == null:
		push_error("SnowWalkVideo: cannot load main scene %s" % main_scene_path)
		quit(2)
		return

	_scene = packed.instantiate()
	root.add_child(_scene)
	await _wait_process_frames(30)

	if _scene.has_method("initialize"):
		_scene.call("initialize")
	await _wait_process_frames(6)

	_player = _scene.get_node_or_null("Player") as CharacterBody3D
	if _player == null:
		push_error("SnowWalkVideo: Player not found")
		quit(3)
		return

	var context := _scene.call("get_context") as WorldContext
	if context == null:
		push_error("SnowWalkVideo: WorldContext missing")
		quit(4)
		return

	_weather = context.get_system(WEATHER_SCRIPT) as WeatherController
	_footprints = context.get_system(FOOTPRINT_SCRIPT) as FootprintSystem
	_snowfall = context.get_system(SNOWFALL_SCRIPT) as SnowfallVFX
	if _weather == null or _footprints == null:
		push_error("SnowWalkVideo: weather or footprint system missing")
		quit(5)
		return

	_hide_capture_noise()
	_apply_claude_snow_to_floor()
	_disable_existing_cameras(_scene)
	_create_capture_camera()

	_player.global_position = Vector3(20.0, 1.0, 28.0)
	_player.global_rotation = Vector3.ZERO
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()
	_start_position = _player.global_position

	_weather.scheduler_enabled = false
	_weather.set_weather(&"snowfall", true)
	if _snowfall != null:
		_snowfall.follow_target = _player
		_snowfall.foreground_target = _camera
		_snowfall.sync_from_weather()

	_prepare_output_dir()
	_release_motion_input()
	await _wait_physics_seconds(0.75)

	var physics_tps: int = Engine.physics_ticks_per_second
	var physics_steps_per_frame: int = maxi(1, int(round(float(physics_tps) / float(VIDEO_FPS))))
	print(
		"[HFN_SNOW_VIDEO] recording %d frames @ %d fps; physics=%d Hz (%d steps/frame)"
		% [TOTAL_FRAMES, VIDEO_FPS, physics_tps, physics_steps_per_frame]
	)

	for frame_index: int in range(TOTAL_FRAMES):
		var video_time: float = float(frame_index) / float(VIDEO_FPS)
		var walking: bool = video_time >= WALK_START_S and video_time < WALK_END_S
		if walking:
			Input.action_press("move_forward", 1.0)
		else:
			Input.action_release("move_forward")

		for _step: int in range(physics_steps_per_frame):
			await physics_frame

		_update_camera(video_time)
		await process_frame
		await RenderingServer.frame_post_draw
		_save_frame(frame_index)

	_release_motion_input()
	_end_position = _player.global_position
	var visible_prints: int = _footprints.get_visible_count()
	_write_report(main_scene_path, visible_prints)

	print(
		"[HFN_SNOW_VIDEO] complete prints=%d start=%s end=%s snow_cover=%.2f"
		% [visible_prints, str(_start_position), str(_end_position), _weather.get_snow_cover()]
	)
	if visible_prints < 4:
		push_error("SnowWalkVideo: expected real bone-driven footprints, got %d" % visible_prints)
		quit(6)
		return
	quit(0)


func _apply_claude_snow_to_floor() -> void:
	var floor := _scene.get_node_or_null("MeshPlane") as MeshInstance3D
	if floor == null:
		push_error("SnowWalkVideo: TestScene floor missing")
		return
	var material := ShaderMaterial.new()
	material.shader = SNOW_PROP_SHADER
	material.set_shader_parameter("base_color", Color(0.16, 0.18, 0.21, 1.0))
	material.set_shader_parameter("base_roughness", 0.96)
	material.set_shader_parameter("snow_color", Color(0.91, 0.94, 0.98, 1.0))
	material.set_shader_parameter("snow_roughness", 0.86)
	material.set_shader_parameter("snow_softness", 0.16)
	floor.material_override = material


func _create_capture_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "SnowWalkCaptureCamera"
	_camera.fov = 58.0
	_camera.current = true
	_scene.add_child(_camera)
	_camera.global_position = _player_position_or(Vector3(20.0, 1.0, 28.0)) + Vector3(0.0, 5.2, 7.8)
	_camera.look_at(_player_position_or(Vector3(20.0, 1.0, 28.0)) + Vector3(0.0, 0.8, -2.2), Vector3.UP)


func _update_camera(video_time: float) -> void:
	var player_pos: Vector3 = _player.global_position
	if video_time < WALK_END_S:
		var follow_position := player_pos + Vector3(0.0, 5.2, 7.8)
		_camera.global_position = _camera.global_position.lerp(follow_position, 0.32)
		_camera.look_at(player_pos + Vector3(0.0, 0.75, -2.2), Vector3.UP)
		return

	var reveal_t: float = clampf((video_time - WALK_END_S) / maxf(0.1, DURATION_S - WALK_END_S), 0.0, 1.0)
	var overview_position := player_pos + Vector3(0.0, 9.5, 12.5)
	_camera.global_position = _camera.global_position.lerp(overview_position, 0.06 + reveal_t * 0.08)
	var trail_mid := _start_position.lerp(player_pos, 0.58)
	trail_mid.y = 0.15
	_camera.look_at(trail_mid, Vector3.UP)


func _player_position_or(fallback: Vector3) -> Vector3:
	return _player.global_position if _player != null else fallback


func _save_frame(frame_index: int) -> void:
	var image: Image = root.get_texture().get_image()
	if image == null or image.is_empty():
		push_error("SnowWalkVideo: empty viewport frame %d" % frame_index)
		return
	var path := "%s/frame_%04d.jpg" % [FRAME_DIR, frame_index]
	var error := image.save_jpg(ProjectSettings.globalize_path(path), 0.88)
	if error != OK:
		push_error("SnowWalkVideo: save_jpg failed for frame %d (%d)" % [frame_index, error])


func _prepare_output_dir() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FRAME_DIR))


func _hide_capture_noise() -> void:
	var stats := _scene.get_node_or_null("StatsDisplay") as CanvasItem
	if stats != null:
		stats.visible = false
	var hud := _player.get_node_or_null("HUD") as CanvasItem if _player != null else null
	if hud != null:
		hud.visible = false
	var in_game_ui := _player.get_node_or_null("InGameUI") as CanvasItem if _player != null else null
	if in_game_ui != null:
		in_game_ui.visible = false
	var world_ui := _scene.get_node_or_null("WorldUI") as CanvasLayer
	if world_ui != null:
		world_ui.visible = false


func _disable_existing_cameras(node: Node) -> void:
	if node is Camera3D:
		(node as Camera3D).current = false
	for child: Node in node.get_children():
		_disable_existing_cameras(child)


func _release_motion_input() -> void:
	Input.action_release("move_forward")
	Input.action_release("move_backward")
	Input.action_release("move_left")
	Input.action_release("move_right")
	Input.action_release("sprint")


func _wait_process_frames(count: int) -> void:
	for _index: int in range(count):
		await process_frame


func _wait_physics_seconds(seconds: float) -> void:
	var ticks: int = int(ceil(seconds * float(Engine.physics_ticks_per_second)))
	for _index: int in range(ticks):
		await physics_frame


func _write_report(main_scene_path: String, visible_prints: int) -> void:
	var report := {
		"main_scene": main_scene_path,
		"duration_s": DURATION_S,
		"fps": VIDEO_FPS,
		"frames": TOTAL_FRAMES,
		"weather": "snowfall",
		"snow_cover": _weather.get_snow_cover(),
		"snowfall_density": _weather.get_snowfall_density(),
		"visible_footprints": visible_prints,
		"start_position": [_start_position.x, _start_position.y, _start_position.z],
		"end_position": [_end_position.x, _end_position.y, _end_position.z],
	}
	var file := FileAccess.open("%s/report.json" % OUT_DIR, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
