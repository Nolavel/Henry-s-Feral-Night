extends SceneTree

## #80 publisher frames, one idea each, from the real main scene: bunker and the
## tower, the road with its clutter, the weather turn, boarding a breach, the lit
## stove, and Henry seated with Kenny. Frames go to user://shots/first_exit/.
## Run: xvfb-run godot --path . --rendering-driver vulkan --script res://tools/runtime/capture_first_exit_frames.gd

const SCENE: String = "res://experimental_location/scenes/Graciosa_Island_Terrain.tscn"
const OUT_DIR: String = "user://shots/first_exit"
## From docs/world/first_exit_resolved.json.
const BUNKER := Vector2(1427.0, -952.0)
const TOWER := Vector2(1142.6, -713.9)
const BUS := Vector2(1354.6, -832.9)

var _player: Player
var _view: SubViewport
var _camera: Camera3D
var _zone: Node3D
var _time: float = 0.0
var _next_at: float = 4.0
var _step: int = 0


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var scene: Node = (load(SCENE) as PackedScene).instantiate()
	root.add_child(scene)
	_player = scene.find_child("Player", true, false) as Player
	_zone = scene.find_child("ShelterZone", true, false) as Node3D
	_view = SubViewport.new()
	_view.size = Vector2i(1280, 720)
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_view)
	_camera = Camera3D.new()
	_camera.fov = 58.0
	_view.add_child(_camera)


func _process(delta: float) -> bool:
	_time += delta
	if _time < _next_at:
		return false
	for node: Node in root.find_children("*", "Label3D", true, false):
		(node as Label3D).visible = false
	match _step:
		0:  # 1: the bunker at his back, the water tower ahead
			var from: Vector3 = _on_ground(BUNKER.lerp(TOWER, 0.03))
			_put_player(from, _on_ground(TOWER))
			_frame(from - _dir(from, _on_ground(TOWER)) * 3.5 + Vector3(0.0, 2.0, 0.0), _on_ground(TOWER) + Vector3(0.0, 8.0, 0.0))
			_wait(2.0)
		1:
			_shot("01_exile_bunker_and_tower")
			var road: Vector3 = _on_ground(BUS + Vector2(8.0, -6.0))  # 2: the road, the drifted bus across it
			_put_player(road, _on_ground(BUS))
			_frame(road - _dir(road, _on_ground(BUS)) * 4.0 + Vector3(1.5, 2.2, 0.0), _on_ground(BUS) + Vector3(0.0, 1.0, 0.0))
			_wait(2.0)
		2:
			_shot("02_route_clutter")
			var beat: WeatherBeat = root.find_child("WeatherBeat", true, false) as WeatherBeat
			if beat != null:
				beat.fire()  # 3: the authored turn, forced here for the frame only
			_wait(8.0)
		3:
			_shot("03_weather_turn")
			var breach: ShelterBreach = null
			for node: Node in _zone.find_children("*", "", true, false):
				if node is ShelterBreach:
					breach = node
					break
			var inside: Vector3 = breach.global_position - breach.get_facing() * 1.0
			inside.y = _zone.global_position.y - 1.2
			_put_player(inside, breach.global_position)
			var bag: InventoryComponent = InventoryComponent.find_in(_player)
			bag.try_add(load("res://data/items/boards.tres") as ItemResource)
			_player.play_action_animation(&"fix")  # 4: boarding the breach
			breach.board_up()
			_frame(inside - breach.get_facing() * 2.2 + Vector3(1.0, 1.6, 0.0), breach.global_position)
			_wait(1.2)
		4:
			_shot("04_boarding_a_breach")
			var stove := _zone.find_child("Stove", true, false) as HeatSource
			stove.ignite()  # 5: the lit stove in the dark room
			## In the stove's own frame: in front of the door (+X) and to its side, inside the room.
			_frame(stove.to_global(Vector3(2.0, 1.0, 1.0)), stove.to_global(Vector3(0.2, 0.35, 0.0)))
			_wait(2.0)
		5:
			_shot("05_lit_stove")
			var crate := _zone.find_child("RestCrate", true, false) as Node3D
			_player.global_position = crate.global_position + Vector3(0.0, 0.9, 0.0)
			(_player.get_node(^"RestComponent") as RestComponent).sit(crate.find_child("Rest") as Node3D)
			var basis: Basis = crate.global_transform.basis  # 6: seated by the fire, Kenny beside him
			_frame(crate.global_position - basis.z * 2.2 + basis.x * 0.5 + Vector3(0.0, 1.5, 0.0), crate.global_position + Vector3(0.0, 0.5, 0.0))
			_wait(3.0)
		6:
			_shot("06_seated_with_kenny")
			quit()
	return false


func _wait(seconds: float) -> void:
	_next_at = _time + seconds
	_step += 1


func _shot(name: String) -> void:
	_view.get_texture().get_image().save_png("%s/%s.png" % [OUT_DIR, name])
	print("[first_exit] ", name)


func _frame(eye: Vector3, target: Vector3) -> void:
	_camera.global_position = eye
	_camera.look_at(target, Vector3.UP)


func _put_player(at: Vector3, facing: Vector3) -> void:
	_player.global_position = at + Vector3(0.0, 1.0, 0.0)
	_player.velocity = Vector3.ZERO
	var flat: Vector3 = facing - at
	_player.rotation.y = atan2(-flat.x, -flat.z)


func _dir(from: Vector3, to: Vector3) -> Vector3:
	var flat: Vector3 = to - from
	flat.y = 0.0
	return flat.normalized()


func _on_ground(xz: Vector2) -> Vector3:
	var space := root.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(Vector3(xz.x, 400.0, xz.y), Vector3(xz.x, -50.0, xz.y))
	var hit: Dictionary = space.intersect_ray(query)
	return hit.get("position", Vector3(xz.x, 0.0, xz.y))
