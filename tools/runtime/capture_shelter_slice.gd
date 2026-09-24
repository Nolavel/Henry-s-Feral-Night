extends SceneTree

## Issue #56 demo in the real main scene: Henry carries the shelter firewood,
## feeds the stove, opens the cabinet and boards a window, through the normal
## approach path. Frames go to user://shots/slice/.
## Run: xvfb-run godot --path . --rendering-driver vulkan --script res://tools/runtime/capture_shelter_slice.gd

const SCENE: String = "res://experimental_location/scenes/Graciosa_Island_Terrain.tscn"
const OUT_DIR: String = "user://shots/slice"
const WARMUP: float = 3.0
## A phase that waits longer than this is reported and the capture quits.
const PHASE_TIMEOUT: float = 20.0

var _player: Player
var _interact: InteractComponent
var _inventory: InventoryComponent
var _camera: Camera3D
## Renders the shared 3D world through the capture camera only: no game
## camera, no HUD.
var _view: SubViewport
var _fill: OmniLight3D
var _zone: Node3D
var _firewood: InteractiveArea
var _feed: HeatSourceFeed
var _cabinet: Cabinet
var _board: BreachBoardUp
var _time: float = 0.0
var _phase_time: float = 0.0
var _phase: int = 0
var _shots: Array = []  # [phase-relative time, name] still due in this phase
var _log: PackedStringArray = []


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var scene: Node = (load(SCENE) as PackedScene).instantiate()
	root.add_child(scene)
	_player = scene.find_child("Player", true, false) as Player
	_interact = _player.find_child("InteractComponent", true, false) as InteractComponent
	_inventory = InventoryComponent.find_in(_player)
	_firewood = scene.find_child("FirewoodShelter", true, false) as InteractiveArea
	var shelter: Node = _firewood.get_parent() if _firewood != null else scene
	_zone = scene.find_child("ShelterZone", true, false) as Node3D
	_feed = _zone.find_child("Feed", true, false) as HeatSourceFeed
	_cabinet = _zone.find_child("Open", true, false) as Cabinet
	_board = _zone.find_child("BackWindow1", true, false).find_child("BoardUp", true, false) as BreachBoardUp
	_view = SubViewport.new()
	_view.size = Vector2i(1280, 720)
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_view)
	_view.world_3d = root.get_viewport().world_3d
	_camera = Camera3D.new()
	_camera.fov = 55.0
	_view.add_child(_camera)
	## Capture-only fill light so the dark shelter interior reads in frames.
	_fill = OmniLight3D.new()
	_fill.light_energy = 1.4
	_fill.omni_range = 7.0
	scene.add_child(_fill)
	_say("nodes: firewood=%s feed=%s cabinet=%s board=%s shelter=%s" % [_firewood != null, _feed != null,
		_cabinet != null, _board != null, shelter.name])


func _process(delta: float) -> bool:
	_time += delta
	_phase_time += delta
	if _time < WARMUP:
		return false
	_quiet_game_view()
	_frame_camera()
	if _phase_time > PHASE_TIMEOUT:
		_say("phase %d timed out; henry at %s" % [_phase, _player.global_position])
		_write_log()
		quit(1)
		return false
	match _phase:
		0:
			_teleport_near(_firewood, 3.2)
			_interact.call(&"_begin_approach", _firewood)
			_next([[0.7, "01_firewood_approach"]])
		1:
			if _inventory.has_item(&"firewood"):
				_next([[0.35, "02_firewood_pickup"], [1.6, "03_firewood_held"]])
		2:
			if _shots.is_empty():
				var away: Vector3 = _player.global_position - _zone.global_position
				away.y = 0.0
				_player.move_to_position(_player.global_position + away.normalized() * 6.0)
				_next([[1.2, "04_carry_walk_a"], [2.4, "05_carry_walk_b"]])
		3:
			if _shots.is_empty():
				_inventory.try_add(load("res://data/items/tinder.tres") as ItemResource)
				_teleport_near(_feed, 2.6)
				_interact.call(&"_begin_approach", _feed)
				_next([[0.6, "06_carry_to_stove"]])
		4:
			if not _inventory.has_item(&"firewood") and _phase_time > 0.8:
				_say("stove fed; carrying=%s" % _player.animation_component.is_carrying())
				_next([[0.6, "07_stove_fed_hands_free"]])
		5:
			if _shots.is_empty():
				_teleport_near(_cabinet, 2.4)
				_interact.call(&"_begin_approach", _cabinet)
				_next([])
		6:
			if _cabinet.is_open():
				_next([[0.15, "08_cabinet_reach"], [0.75, "09_cabinet_swing"], [1.5, "10_cabinet_open"]])
		7:
			if _shots.is_empty():
				_inventory.try_add(load("res://data/items/boards.tres") as ItemResource)
				_teleport_near(_board, 2.4)
				_interact.call(&"_begin_approach", _board)
				_next([])
		8:
			if _board.breach != null and _board.breach.is_boarded():
				_next([[0.6, "11_fix_kneel"], [1.6, "12_fix_work"], [4.0, "13_fix_done_walks"]])
		9:
			if _phase_time > 0.6 and _phase_time < 3.0:
				var planar: float = Vector2(_player.velocity.x, _player.velocity.z).length()
				if planar > 0.05:
					_say("moved during fix at %.2fs: %.2f m/s" % [_phase_time, planar])
			if _phase_time > 3.2 and _phase_time < 3.3:
				_player.move_to_position(_zone.global_position)
			if _shots.is_empty():
				_say("done")
				_write_log()
				quit()
	_take_due_shots()
	return false


## Prompt labels spawn and fade in at runtime; the frames hide them.
func _quiet_game_view() -> void:
	for node: Node in root.find_children("*", "", true, false):
		if node is Label3D:
			(node as Label3D).visible = false


func _next(shots: Array) -> void:
	_shots = shots
	_phase += 1
	_phase_time = 0.0
	_say("phase %d at %.1fs" % [_phase, _time])


func _take_due_shots() -> void:
	while not _shots.is_empty() and _phase_time >= float(_shots[0][0]):
		var name: String = _shots.pop_front()[1]
		var image: Image = _view.get_texture().get_image()
		image.save_png("%s/%s.png" % [OUT_DIR, name])
		_say("shot %s action=%s locked=%s carry=%s" % [name, _player.animation_component._current_action,
			_player.animation_component.is_action_locking(), _player.animation_component.is_carrying()])


## Puts Henry a few metres from a target, on the shelter-centre side.
func _teleport_near(target: Node3D, distance: float) -> void:
	var from: Vector3 = _zone.global_position - target.global_position
	from.y = 0.0
	if from.length() < 0.5:
		from = Vector3(1.0, 0.0, 0.0)
	var spot: Vector3 = target.global_position + from.normalized() * distance
	spot.y = target.global_position.y + 0.3
	_player.global_position = spot
	_player.velocity = Vector3.ZERO


## Outdoors a three-quarter view from Henry's front right; inside the shelter
## the camera stands in the room and looks at him, so walls never block it.
func _frame_camera() -> void:
	var basis: Basis = _player.global_transform.basis
	var chest: Vector3 = _player.global_position + Vector3(0.0, 1.0, 0.0)
	if _phase >= 5:
		var from_henry: Vector3 = _zone.global_position - _player.global_position
		from_henry.y = 0.0
		from_henry = from_henry.normalized() if from_henry.length() > 0.3 else -basis.z
		_camera.global_position = chest + from_henry * 2.2 + basis.x * 0.6 + Vector3(0.0, 0.7, 0.0)
	else:
		_camera.global_position = chest - basis.z * 2.3 + basis.x * 1.3 + Vector3(0.0, 0.6, 0.0)
	_camera.look_at(chest, Vector3.UP)
	_fill.global_position = _camera.global_position + Vector3(0.0, 0.5, 0.0)


func _say(text: String) -> void:
	print("[slice] ", text)
	_log.append(text)


func _write_log() -> void:
	var file := FileAccess.open("%s/log.txt" % OUT_DIR, FileAccess.WRITE)
	file.store_string("\n".join(_log))
