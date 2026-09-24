extends SceneTree

## Issue #57 demo in the real main scene at night: Henry lights a road flare
## (L path), stands in the dark shelter, walks outside in wind, drops it.
## Frames go to user://shots/flare/, rendered through a capture SubViewport.
## Run: xvfb-run godot --path . --rendering-driver vulkan --script res://tools/runtime/capture_held_flare_ingame.gd

const SCENE: String = "res://experimental_location/scenes/Graciosa_Island_Terrain.tscn"
const OUT_DIR: String = "user://shots/flare"
const WARMUP: float = 3.0
const NIGHT_HOUR: float = 22.5

var _player: Player
var _light: HeldLightComponent
var _zone: Node3D
var _view: SubViewport
var _camera: Camera3D
var _time: float = 0.0
var _phase_time: float = 0.0
var _phase: int = 0
var _shots: Array = []
## "front" or "side"; side shows smoke drifting across the frame.
var _framing: String = "front"


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var scene: Node = (load(SCENE) as PackedScene).instantiate()
	root.add_child(scene)
	_player = scene.find_child("Player", true, false) as Player
	_light = _player.get_node(^"HeldLightComponent") as HeldLightComponent
	_zone = scene.find_child("ShelterZone", true, false) as Node3D
	_view = SubViewport.new()
	_view.size = Vector2i(1280, 720)
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_view)
	_camera = Camera3D.new()
	_camera.fov = 55.0
	_view.add_child(_camera)


func _process(delta: float) -> bool:
	_time += delta
	_phase_time += delta
	if _time < WARMUP:
		return false
	_hide_labels()
	_frame_camera()
	match _phase:
		0:
			_set_night_and_wind()
			_teleport(_zone.global_position)
			var inventory: InventoryComponent = InventoryComponent.find_in(_player)
			inventory.try_add(load("res://data/items/road_flare.tres") as ItemResource)
			inventory.try_add(load("res://data/items/road_flare.tres") as ItemResource)
			print("[flare] lit=", _light.light())
			_next([[1.5, "01_shelter_standing"], [3.0, "02_shelter_standing_late"]], "front")
		1:
			if _shots.is_empty():
				var outside: Vector3 = _zone.global_position + (_zone.global_transform.basis.z * 7.0)
				_teleport(outside)
				_player.move_to_position(outside + _zone.global_transform.basis.x * 8.0)
				_next([[1.2, "03_walking_a"], [2.4, "04_walking_b"]], "front")
		2:
			if _shots.is_empty():
				_player.stop_moving()
				_next([[1.5, "05_wind_smoke_side"], [2.5, "06_wind_smoke_side_b"]], "side")
		3:
			if _shots.is_empty():
				_light.drop()
				_player.move_to_position(_player.global_position - _player.global_transform.basis.z * 3.0)
				_next([[2.0, "07_dropped_on_snow"]], "drop")
		4:
			if _shots.is_empty():
				print("[flare] done")
				quit()
	_take_due_shots()
	return false


func _set_night_and_wind() -> void:
	for node: Node in root.find_children("*", "", true, false):
		if node is DayNightManager:
			var clock := node as DayNightManager
			clock.total_game_time_hours = NIGHT_HOUR
			clock.call(&"_force_update_visuals")
		elif node is WeatherController:
			(node as WeatherController).set_weather(&"windy", true)


func _next(shots: Array, framing: String) -> void:
	_shots = shots
	_framing = framing
	_phase += 1
	_phase_time = 0.0
	print("[flare] phase %d at %.1fs" % [_phase, _time])


func _take_due_shots() -> void:
	while not _shots.is_empty() and _phase_time >= float(_shots[0][0]):
		var name: String = _shots.pop_front()[1]
		_view.get_texture().get_image().save_png("%s/%s.png" % [OUT_DIR, name])
		print("[flare] shot %s holding=%s" % [name, _light.is_holding()])


func _teleport(spot: Vector3) -> void:
	var ground: Vector3 = spot
	ground.y = _zone.global_position.y - 1.2
	_player.global_position = ground + Vector3(0.0, 0.3, 0.0)
	_player.velocity = Vector3.ZERO


## Front: three-quarter from Henry's visual front (+Z). Side: square to his
## right so drifting smoke crosses the frame. Drop: looks down at the flare.
func _frame_camera() -> void:
	var basis: Basis = _player.global_transform.basis
	var chest: Vector3 = _player.global_position + Vector3(0.0, 1.1, 0.0)
	match _framing:
		"side":
			_camera.global_position = chest + basis.x * 3.2 + Vector3(0.0, 0.3, 0.0)
		"drop":
			_camera.global_position = chest + basis.z * 3.0 + Vector3(0.0, 1.4, 0.0)
		_:
			_camera.global_position = chest + basis.z * 2.4 + basis.x * 0.9 + Vector3(0.0, 0.3, 0.0)
	_camera.look_at(chest - Vector3(0.0, 0.3 if _framing != "drop" else 0.9, 0.0), Vector3.UP)


func _hide_labels() -> void:
	for node: Node in root.find_children("*", "Label3D", true, false):
		(node as Label3D).visible = false
