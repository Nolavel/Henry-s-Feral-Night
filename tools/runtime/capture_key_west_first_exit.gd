extends SceneTree

const MAIN_SCENE: String = "res://scenes/world/key_west/key_west.tscn"
const OUT_DIR: String = "res://docs/runtime_previews/key_west_first_exit"
const BUNKER := Vector2(-3452.88, 2273.84)
const SHELTER := Vector2(-3551.61, 1567.72)
const FIRST_CAPTURE_FRAME: int = 210
const BETWEEN_SHOTS: int = 120
var _scene: Node3D
var _player: Player
var _camera: TpsCamera
var _terrain: IslandTerrain
var _weather: WeatherController
var _frame: int = 0
var _shot: int = 0
var _next: int = FIRST_CAPTURE_FRAME

func _initialize() -> void:
	OS.set_environment("HFN_WORLD", "key_west_test")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_scene = (load(MAIN_SCENE) as PackedScene).instantiate() as Node3D
	root.add_child(_scene)

func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 20:
		_bind()
	if _frame < _next or _player == null:
		return false
	if _shot == 0:
		if not _validate_start():
			quit(1)
			return true
		_capture("01_whitehead_bunker_blizzard")
		_place_between()
	elif _shot == 1:
		_capture("02_coast_to_fort_street")
		_place_shelter_approach()
	else:
		_capture("03_fort_street_shelter")
		_write_report()
		print("key west first exit capture: complete")
		quit()
		return true
	_shot += 1
	_next = _frame + BETWEEN_SHOTS
	return false

func _bind() -> void:
	_player = get_first_node_in_group(&"player") as Player
	_camera = _scene.get_node_or_null(^"PlayerCamera") as TpsCamera
	_terrain = _scene.get_node_or_null(^"IslandTerrain") as IslandTerrain
	for node: Node in _scene.get_children():
		if node is WeatherController:
			_weather = node as WeatherController
			break
	var splash := _scene.get_node_or_null(^"StartupTitleCard")
	if splash != null:
		splash.queue_free()
	if _player != null:
		_player.set_physics_process(false)

func _validate_start() -> bool:
	if _weather == null or _weather.get_current_profile() == null:
		push_error("key west first exit capture: weather did not initialize")
		return false
	if _weather.get_current_profile().id != &"blizzard":
		push_error("key west first exit capture: first visible weather is not blizzard")
		return false
	if _weather.get_snowfall_density() < 0.9 or _weather.get_wind_speed_mps() < 17.0:
		push_error("key west first exit capture: storm values are not live")
		return false
	if _player.global_position.distance_to(Vector3(BUNKER.x, _player.global_position.y, BUNKER.y)) > 15.0:
		push_error("key west first exit capture: player did not spawn at Whitehead bunker")
		return false
	return true

func _place_between() -> void:
	_place_player(BUNKER.lerp(SHELTER, 0.63), SHELTER)

func _place_shelter_approach() -> void:
	var outward := (BUNKER - SHELTER).normalized()
	_place_player(SHELTER + outward * 26.0, SHELTER)

func _place_player(p: Vector2, look: Vector2) -> void:
	var y: float = maxf(_terrain.get_height(p.x, p.y), 0.0) + 1.0
	_player.global_position = Vector3(p.x, y, p.y)
	var direction := (look - p).normalized()
	var yaw: float = atan2(direction.x, direction.y) + PI
	_player.global_rotation.y = yaw
	if _camera != null:
		_camera.set_look(yaw, _camera.start_pitch_deg)
	var streaming := _find_streaming()
	if streaming != null:
		streaming.scan(_player.global_position)

func _find_streaming() -> StreamingSystem:
	for node: Node in _scene.get_children():
		if node is StreamingSystem:
			return node as StreamingSystem
	return null

func _capture(name: String) -> void:
	root.get_texture().get_image().save_png("%s/%s.png" % [OUT_DIR, name])
	print("[key-west-first-exit] ", name, " player=", _player.global_position)

func _write_report() -> void:
	var streaming := _find_streaming()
	var report := {
		"profile": "key_west_test",
		"spawn": [BUNKER.x, BUNKER.y],
		"shelter": [SHELTER.x, SHELTER.y],
		"route_distance_m": BUNKER.distance_to(SHELTER),
		"weather": String(_weather.get_current_profile().id),
		"snowfall_density": _weather.get_snowfall_density(),
		"wind_speed_mps": _weather.get_wind_speed_mps(),
		"wind_direction": [_weather.get_wind_direction().x, _weather.get_wind_direction().y, _weather.get_wind_direction().z],
		"stream_chunks": streaming.get_chunk_count() if streaming != null else 0,
	}
	var file := FileAccess.open("%s/report.json" % OUT_DIR, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
