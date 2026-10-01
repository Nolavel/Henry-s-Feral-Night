extends SceneTree

## Narrow doorway as a short traversal: W held 35 degrees off a 1.2 m door carries Henry
## through its centre, the frame closes fast and reopens softly; a corridor is no doorway.
## Run: godot --headless --script tests/systems/test_passage_traversal.gd

const CONTROL_YAW_DEG: float = 35.0

var _failures: int = 0
var _player: Player
var _camera: TpsCamera
var _walls: Node3D
var _base_fov: float = 70.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_walls = Node3D.new()
	root.add_child(_walls)
	_box(Vector3(0.0, -0.5, 0.0), Vector3(40.0, 1.0, 40.0))
	_box(Vector3(-3.1, 1.5, 0.0), Vector3(5.0, 3.0, 0.3))
	_box(Vector3(3.1, 1.5, 0.0), Vector3(5.0, 3.0, 0.3))
	_box(Vector3(0.0, 2.6, 0.0), Vector3(1.2, 0.8, 0.3))
	_player = (load("res://scenes/actors/player/player.tscn") as PackedScene).instantiate() as Player
	root.add_child(_player)
	_player.global_position = Vector3(0.8, 1.0, 2.6)
	_camera = (load("res://scenes/game/systems/camera/tps_camera.tscn") as PackedScene).instantiate() as TpsCamera
	_camera.player = _player
	root.add_child(_camera)
	_camera.set_look(deg_to_rad(CONTROL_YAW_DEG), -10.0)
	for i: int in range(30):
		await physics_frame
	await _through_the_door()
	await _back_out()
	await _corridor_is_not_a_door()
	if _failures > 0:
		push_error("passage traversal: %d check(s) failed" % _failures)
		quit(1)
		return
	print("passage traversal: all checks passed")
	quit(0)


func _through_the_door() -> void:
	_base_fov = _camera.fov
	Input.action_press(&"move_forward")
	var crossed: bool = false
	var compressed: bool = false
	for i: int in range(600):
		await physics_frame
		var at: Vector3 = _player.global_position
		if not crossed and at.z <= 0.0:
			crossed = true
			_check(absf(at.x) < 0.3, "Henry crossed the door plane %.2f m off its centre" % at.x)
			var off_axis: float = absf(rad_to_deg(angle_difference(0.0, _camera.get_view_yaw())))
			var view: float = absf(rad_to_deg(angle_difference(0.0, _camera.global_rotation.y)))
			_check(view <= _camera.passage_yaw_limit_deg + 5.0,
				"mid-door the view looks %.1f deg off the passage (control %.1f)" % [view, off_axis])
			_check(_camera.get_body_fade() < 0.35, "mid-door Henry is faded %.2f" % _camera.get_body_fade())
		## The frame closes fast on the way in and opens back out softly.
		var share: float = (_camera.fov - _base_fov) / _camera.passage_fov_deg
		if not compressed and at.z <= 0.4:
			compressed = true
			_check(share >= 0.8, "0.4 m before the door the frame is only %.2f closed" % share)
		if at.z < -1.15:
			_check(share >= 0.3, "just past the exit the frame already snapped open (%.2f)" % share)
			break
	Input.action_release(&"move_forward")
	_check(crossed and _player.global_position.z < -1.0,
		"W held 35 deg off the door left Henry at z=%.2f, not through" % _player.global_position.z)
	_check(is_equal_approx(_camera.get_yaw(), deg_to_rad(CONTROL_YAW_DEG)),
		"the doorway moved the control yaw to %.1f deg" % rad_to_deg(_camera.get_yaw()))


## Half into the door, S held instead: Henry is carried back out the way he came.
func _back_out() -> void:
	_player.global_position = Vector3(0.8, 1.0, 2.6)
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()
	_camera.set_look(deg_to_rad(CONTROL_YAW_DEG), -10.0)
	_camera.snap_to_target()
	for i: int in range(30):
		await physics_frame
	Input.action_press(&"move_forward")
	for i: int in range(600):
		await physics_frame
		if _player.global_position.z <= -0.3:
			break
	Input.action_release(&"move_forward")
	Input.action_press(&"move_backward")
	var stuck: int = 0
	for i: int in range(600):
		var before: Vector3 = _player.global_position
		await physics_frame
		stuck = stuck + 1 if before.distance_to(_player.global_position) < 0.002 else 0
		if _player.global_position.z > 1.2 or stuck > 30:
			break
	Input.action_release(&"move_backward")
	_check(_player.global_position.z > 1.2,
		"S held in the door left Henry at z=%.2f, not back out" % _player.global_position.z)


## A 1.4 m wide, 8 m long corridor: narrow at both ends, so no traversal starts.
func _corridor_is_not_a_door() -> void:
	for child: Node in _walls.get_children():
		if child.position.y > 0.0:
			child.free()
	_box(Vector3(-0.85, 1.5, 0.0), Vector3(0.3, 3.0, 8.0))
	_box(Vector3(0.85, 1.5, 0.0), Vector3(0.3, 3.0, 8.0))
	_player.global_position = Vector3(0.0, 1.0, 0.0)
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()
	for i: int in range(30):
		await physics_frame
	var passage := _player.get_node(^"PassageTraversalComponent") as PassageTraversalComponent
	_check(not passage.is_active(), "an 8 m corridor was taken for a doorway")


func _box(center: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = center
	_walls.add_child(body)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("passage traversal: %s" % message)
