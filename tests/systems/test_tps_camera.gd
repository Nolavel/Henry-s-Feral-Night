extends SceneTree

## The camera boom shortens in tight spaces and lengthens in the open, and a
## wall between camera and Henry pulls the camera in front of it.
## Run: godot --headless --script tests/systems/test_tps_camera.gd

const SETTLE_FRAMES: int = 240

var _failures: int = 0
var _frame: int = 0
var _stage: int = 0
var _camera: TpsCamera
var _player: CharacterBody3D
var _walls: Node3D


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		_build()
		_enter_open_field()
	elif _frame == SETTLE_FRAMES:
		_check_open_field()
		_enter_corridor(1.5)
	elif _frame == SETTLE_FRAMES * 2:
		_check_corridor()
		_enter_doorway_under_roof()
	elif _frame == SETTLE_FRAMES * 3:
		_check_doorway()
		_enter_wall_behind()
	elif _frame == SETTLE_FRAMES * 4:
		_check_wall_behind()
		_finish()
	return false


func _build() -> void:
	_player = CharacterBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = CapsuleShape3D.new()
	shape.position.y = 1.0
	_player.add_child(shape)
	root.add_child(_player)
	_camera = TpsCamera.new()
	_camera.player = _player
	_camera.origin_above_feet = 0.0
	root.add_child(_camera)
	_camera.set_look(0.0, -10.0)
	_walls = Node3D.new()
	root.add_child(_walls)


func _clear_walls() -> void:
	for child: Node in _walls.get_children():
		child.free()


func _add_box(center: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = center
	_walls.add_child(body)


func _enter_open_field() -> void:
	_clear_walls()


func _check_open_field() -> void:
	_check(_camera.get_openness() > 0.95, "open field reads as closed: %.2f" % _camera.get_openness())
	_check(absf(_camera.get_boom_length() - _camera.far_distance) < 0.1,
		"open field boom %.2f, want %.2f" % [_camera.get_boom_length(), _camera.far_distance])
	## Over the right shoulder, as in ADT: part moved, part lens shift.
	_check(_camera.global_position.x > 0.2, "camera is not over the right shoulder: x=%.2f" % _camera.global_position.x)
	_check(_camera.h_offset > 0.3, "no shoulder lens shift: %.2f" % _camera.h_offset)


## Walls along Z either side of Henry, width apart.
func _enter_corridor(width: float) -> void:
	_clear_walls()
	var half: float = width * 0.5 + 0.1
	_add_box(Vector3(-half, 1.5, 0.0), Vector3(0.2, 3.0, 20.0))
	_add_box(Vector3(half, 1.5, 0.0), Vector3(0.2, 3.0, 20.0))


func _check_corridor() -> void:
	var boom: float = _camera.get_boom_length()
	_check(boom < 2.0, "corridor boom %.2f is not pulled in" % boom)
	_check(boom > _camera.near_distance - 0.01, "corridor boom %.2f under the near limit" % boom)


## A 1 m doorway in a wall across X, with a low lintel roof over Henry.
func _enter_doorway_under_roof() -> void:
	_clear_walls()
	_add_box(Vector3(-3.0, 1.5, 0.0), Vector3(5.0, 3.0, 0.2))
	_add_box(Vector3(3.0, 1.5, 0.0), Vector3(5.0, 3.0, 0.2))
	_add_box(Vector3(0.0, 2.6, 0.0), Vector3(1.2, 0.2, 2.0))


func _check_doorway() -> void:
	var boom: float = _camera.get_boom_length()
	_check(boom < 1.5, "doorway boom %.2f is not near the close limit" % boom)


## A wall 1 m behind Henry, between him and the camera.
func _enter_wall_behind() -> void:
	_clear_walls()
	_add_box(Vector3(0.0, 1.5, 1.2), Vector3(6.0, 3.0, 0.2))


func _check_wall_behind() -> void:
	var z: float = _camera.global_position.z
	_check(z < 1.1, "camera sits in or behind the wall at z=%.2f" % z)


func _finish() -> void:
	if _failures > 0:
		push_error("tps camera: %d check(s) failed" % _failures)
		quit(1)
		return
	print("tps camera: all checks passed")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("tps camera: %s" % message)
