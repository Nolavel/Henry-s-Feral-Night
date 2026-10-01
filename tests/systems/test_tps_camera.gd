extends SceneTree

## Boom length by space, walls, a real shoulder offset, crouch, a low ceiling and
## a thin pole, and no automatic turn while the mouse moves.
## Run: godot --headless --script tests/systems/test_tps_camera.gd

const SETTLE_FRAMES: int = 240

var _failures: int = 0
var _frame: int = 0
var _camera: TpsCamera
var _player: CharacterBody3D
var _capsule: CollisionShape3D
var _walls: Node3D
## At each settle boundary: check the stage that settled, then enter the next.
var _boundaries: Array = []
var _aimed_yaw: float = 0.0
var _mouse_busy: bool = false
var _crouch_reference_y: float = 0.0


## Stages step on physics frames, where the world settles.
func _physics_process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		_build()
		_enter_open_field()
		_boundaries = [
			[_check_open_field, _enter_corridor], [_check_corridor, _enter_doorway_under_roof],
			[_check_doorway, _enter_wall_behind], [_check_wall_behind, _enter_open_field],
			[_record_standing, _enter_crouch],
			[_check_crouch, _enter_low_ceiling], [_check_low_ceiling, _enter_thin_pole],
			[_check_thin_pole, _enter_mouse_busy], [_check_mouse_busy, _enter_mouse_rest],
			[_check_mouse_rest, _finish],
		]
	elif _frame % SETTLE_FRAMES == 0 and not _boundaries.is_empty():
		var boundary: Array = _boundaries.pop_front()
		(boundary[0] as Callable).call()
		(boundary[1] as Callable).call()
	if _mouse_busy:
		_mouse(1.0 if _frame % 2 == 0 else -1.0)
	return false


func _build() -> void:
	_player = CharacterBody3D.new()
	_capsule = CollisionShape3D.new()
	_capsule.shape = CapsuleShape3D.new()
	_capsule.position.y = 1.0
	_player.add_child(_capsule)
	root.add_child(_player)
	_camera = TpsCamera.new()
	_camera.player = _player
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


func _eye() -> Vector3:
	return _player.global_position + Vector3.UP * _capsule.shape.height * 0.9 * TpsCamera.EYE_RATIO


func _enter_open_field() -> void:
	_clear_walls()


func _check_open_field() -> void:
	_check(_camera.get_openness() > 0.95, "open field reads as closed: %.2f" % _camera.get_openness())
	_check(absf(_camera.get_boom_length() - _camera.far_distance) < 0.1,
		"open field boom %.2f, want %.2f" % [_camera.get_boom_length(), _camera.far_distance])
	## Over the right shoulder as a real offset, so collision sees it; no lens shift.
	_check(_camera.global_position.x > 0.6, "camera is not over the right shoulder: x=%.2f" % _camera.global_position.x)
	_check(is_zero_approx(_camera.h_offset), "a lens shift moves the camera unchecked: %.2f" % _camera.h_offset)


## Walls along Z either side of Henry, 1.5 m apart.
func _enter_corridor() -> void:
	_clear_walls()
	var half: float = 1.5 * 0.5 + 0.1
	_add_box(Vector3(-half, 1.5, 0.0), Vector3(0.2, 3.0, 20.0))
	_add_box(Vector3(half, 1.5, 0.0), Vector3(0.2, 3.0, 20.0))


func _check_corridor() -> void:
	var boom: float = _camera.get_boom_length()
	_check(boom < 2.0, "corridor boom %.2f is not pulled in" % boom)
	_check(boom > _camera.near_distance - 0.01, "corridor boom %.2f under the near limit" % boom)
	## The shoulder must not carry the camera into the side wall at x=0.75.
	_check(_camera.global_position.x < 0.75 - 0.15, "camera pushed into the side wall: x=%.2f" % _camera.global_position.x)


## A 1 m doorway in a wall across X, with a low lintel roof over Henry.
func _enter_doorway_under_roof() -> void:
	_clear_walls()
	_add_box(Vector3(-3.0, 1.5, 0.0), Vector3(5.0, 3.0, 0.2))
	_add_box(Vector3(3.0, 1.5, 0.0), Vector3(5.0, 3.0, 0.2))
	_add_box(Vector3(0.0, 2.6, 0.0), Vector3(1.2, 0.2, 2.0))


func _check_doorway() -> void:
	var boom: float = _camera.get_boom_length()
	_check(boom < 1.2, "doorway boom %.2f is not near the close limit" % boom)
	_check(absf(_camera.global_position.x) < 0.35, "the shoulder did not shrink in the doorway: x=%.2f" % _camera.global_position.x)


## A wall 1 m behind Henry, between him and the camera.
func _enter_wall_behind() -> void:
	_clear_walls()
	_add_box(Vector3(0.0, 1.5, 1.2), Vector3(6.0, 3.0, 0.2))


func _check_wall_behind() -> void:
	var z: float = _camera.global_position.z
	_check(z < 1.1, "camera sits in or behind the wall at z=%.2f" % z)


## Crouching as Player does it: the capsule shortens and keeps its feet down.
func _record_standing() -> void:
	_crouch_reference_y = _camera.global_position.y


func _enter_crouch() -> void:
	(_capsule.shape as CapsuleShape3D).height = 1.3
	_capsule.position.y = 0.65


func _check_crouch() -> void:
	var drop: float = _crouch_reference_y - _camera.global_position.y
	_check(drop > 0.3, "crouching lowered the camera by only %.2f m" % drop)


## A slab 1.5 m up over the crouched Henry: the camera stays under it.
func _enter_low_ceiling() -> void:
	_add_box(Vector3(0.0, 1.6, 0.0), Vector3(6.0, 0.2, 8.0))


func _check_low_ceiling() -> void:
	_check(_camera.global_position.y < 1.5, "camera sits in or over the slab: y=%.2f" % _camera.global_position.y)
	var query := PhysicsRayQueryParameters3D.create(_eye(), _camera.global_position)
	query.exclude = [_player.get_rid()]
	_check(root.get_world_3d().direct_space_state.intersect_ray(query).is_empty(),
		"the slab stands between the camera and Henry")
	_check(_camera.global_position.distance_to(_eye()) > 0.6, "the camera collapsed under the slab")


## Standing again, a thin pole halfway between Henry and the camera.
func _enter_thin_pole() -> void:
	_clear_walls()
	(_capsule.shape as CapsuleShape3D).height = 2.0
	_capsule.position.y = 1.0
	var pole := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 0.08
	cylinder.height = 3.0
	shape.shape = cylinder
	pole.add_child(shape)
	pole.position = Vector3(_camera.global_position.x, 1.5, 1.5)
	_walls.add_child(pole)


func _check_thin_pole() -> void:
	var distance: float = _camera.global_position.distance_to(_eye())
	_check(distance > 2.0, "a thin pole pulled the boom in to %.2f m" % distance)


## Back to a wall with the view aimed into it while the mouse keeps moving.
func _enter_mouse_busy() -> void:
	_clear_walls()
	_add_box(Vector3(0.0, 1.5, 0.75), Vector3(6.0, 3.0, 0.3))
	_camera.set_look(0.0, -10.0)
	_aimed_yaw = 0.0
	_mouse_busy = true


func _check_mouse_busy() -> void:
	var drift: float = absf(rad_to_deg(angle_difference(_aimed_yaw, _camera.get_yaw())))
	_check(drift < 1.0, "the camera turned by itself %.1f deg while the mouse moved" % drift)
	_aimed_yaw = _camera.get_yaw()


func _enter_mouse_rest() -> void:
	_mouse_busy = false


func _check_mouse_rest() -> void:
	var turned: float = absf(rad_to_deg(angle_difference(_aimed_yaw, _camera.get_yaw())))
	var distance: float = _camera.global_position.distance_to(_eye())
	_check(turned > 5.0 or distance > 0.55, "after the mouse rested the camera found no room: %.2f m" % distance)


## Jiggles the mouse by a pixel each way, so its net turn is zero.
func _mouse(dx: float) -> void:
	var event := InputEventMouseMotion.new()
	event.relative = Vector2(dx, 0.0)
	event.screen_relative = Vector2(dx, 0.0)
	Input.parse_input_event(event)


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
