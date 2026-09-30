extends SceneTree

## Production visual regression for the shared stylized-shadow contract.
## Captures the same Key West views with the global effect disabled/enabled.

const MAIN_SCENE: String = "res://scenes/world/key_west/key_west.tscn"
const OUT_DIR: String = "res://docs/runtime_previews/stylized_shadows"
const BUNKER := Vector2(-3452.88, 2273.84)
const SHELTER := Vector2(-3579.85, 1574.51)
const FIRST_ACTION_FRAME: int = 210
const SETTLE_FRAMES: int = 36
const BETWEEN_SHOTS: int = 90
const SHOTS := [
	{
		"name": "bunker",
		"at": BUNKER,
		"look": BUNKER.lerp(SHELTER, 0.22),
	},
	{
		"name": "city_route",
		"at": BUNKER.lerp(SHELTER, 0.58),
		"look": SHELTER,
	},
	{
		"name": "shelter",
		"at": SHELTER + (BUNKER - SHELTER).normalized() * 26.0,
		"look": SHELTER,
	},
]

var _scene: Node3D
var _player: Player
var _camera: TpsCamera
var _terrain: IslandTerrain
var _frame: int = 0
var _shot_index: int = 0
var _phase: int = 0
var _next_frame: int = FIRST_ACTION_FRAME


func _initialize() -> void:
	OS.set_environment("HFN_WORLD", "key_west_test")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	RenderingServer.global_shader_parameter_set(&"stylized_shadow_strength", 1.0)
	_scene = (load(MAIN_SCENE) as PackedScene).instantiate() as Node3D
	root.add_child(_scene)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 20:
		_bind()
	if _player == null or _terrain == null or _frame < _next_frame:
		return false

	if _shot_index >= SHOTS.size():
		RenderingServer.global_shader_parameter_set(&"stylized_shadow_strength", 1.0)
		_write_report()
		print("[stylized-shadows] production regression capture complete")
		quit()
		return true

	var shot: Dictionary = SHOTS[_shot_index]
	if _phase == 0:
		_place_player(shot["at"] as Vector2, shot["look"] as Vector2)
		RenderingServer.global_shader_parameter_set(&"stylized_shadow_strength", 0.0)
		_phase = 1
		_next_frame = _frame + SETTLE_FRAMES
	elif _phase == 1:
		_capture("%02d_%s_physical" % [_shot_index * 2 + 1, String(shot["name"])])
		RenderingServer.global_shader_parameter_set(&"stylized_shadow_strength", 1.0)
		_phase = 2
		_next_frame = _frame + SETTLE_FRAMES
	else:
		_capture("%02d_%s_stylized" % [_shot_index * 2 + 2, String(shot["name"])])
		_shot_index += 1
		_phase = 0
		_next_frame = _frame + BETWEEN_SHOTS
	return false


func _bind() -> void:
	_player = get_first_node_in_group(&"player") as Player
	_camera = _scene.get_node_or_null(^"PlayerCamera") as TpsCamera
	_terrain = _scene.get_node_or_null(^"IslandTerrain") as IslandTerrain
	var splash := _scene.get_node_or_null(^"StartupTitleCard")
	if splash != null:
		splash.queue_free()
	if _player != null:
		_player.set_physics_process(false)


func _place_player(at: Vector2, look: Vector2) -> void:
	var y: float = maxf(_terrain.get_height(at.x, at.y), 0.0) + 1.0
	_player.global_position = Vector3(at.x, y, at.y)
	var direction := (look - at).normalized()
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
	var image := root.get_texture().get_image()
	if image == null:
		push_error("stylized shadow capture: viewport image is null")
		quit(1)
		return
	var path := "%s/%s.png" % [OUT_DIR, name]
	var error := image.save_png(path)
	if error != OK:
		push_error("stylized shadow capture: save failed %s" % error)
		quit(1)
		return
	print("[stylized-shadows] saved ", path)


func _write_report() -> void:
	var report := {
		"scene": MAIN_SCENE,
		"views": SHOTS.size(),
		"pairs": SHOTS.size(),
		"directional_strength": 1.0,
		"local_light_strength": 0.45,
		"contract": "solid physical core + noise-broken perimeter",
	}
	var file := FileAccess.open("%s/report.json" % OUT_DIR, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
