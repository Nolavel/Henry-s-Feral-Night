extends Node3D

@onready var world: Node3D = $World

var _player: CharacterBody3D
var _camera: Camera3D
var _door: InteractiveArea
var _interact: InteractComponent
var _miss_point := Vector3.ZERO
var _door_point := Vector3.ZERO
var _elapsed := 0.0
var _pressed := false


func _ready() -> void:
	get_tree().current_scene = self
	call_deferred("_stage")


func _stage() -> void:
	for _i in range(5):
		await get_tree().process_frame
	_player = world.get_node_or_null(^"Player") as CharacterBody3D
	_camera = world.get_node_or_null(^"PlayerCamera") as Camera3D
	_door = world.get_node_or_null(^"FirstExitBlockout/ShelterHouse/House/HouseDoor") as InteractiveArea
	if _player == null or _camera == null or _door == null:
		push_error("focus video: staging nodes missing")
		get_tree().quit(1)
		return
	_interact = _player.get_node_or_null(^"InteractComponent") as InteractComponent

	var outward := _door.global_transform.basis.z
	outward.y = 0.0
	outward = outward.normalized()
	var right := _door.global_transform.basis.x
	right.y = 0.0
	right = right.normalized()
	_player.global_position = _door.global_position + outward * 0.72
	_player.global_position.y = _door.global_position.y - 2.0
	_player.velocity = Vector3.ZERO
	_camera.process_mode = Node.PROCESS_MODE_DISABLED
	_camera.global_position = _player.global_position + outward * 3.0 + right * 1.0 + Vector3.UP * 2.05
	_door_point = _door.global_position + Vector3.UP * 0.10
	_miss_point = _door_point + right * 1.65
	_camera.look_at(_miss_point, Vector3.UP)

	var debug := world.get_node_or_null(^"Perfomance&Debugging")
	if debug is Node3D:
		(debug as Node3D).visible = false
	var stats := world.get_node_or_null(^"StatsDisplay")
	if stats is CanvasItem:
		(stats as CanvasItem).visible = false


func _process(delta: float) -> void:
	if _camera == null:
		return
	_elapsed += delta
	var target := _miss_point
	if _elapsed >= 1.4 and _elapsed < 4.0:
		var t := clampf((_elapsed - 1.4) / 0.55, 0.0, 1.0)
		target = _miss_point.lerp(_door_point, t)
	elif _elapsed >= 4.0 and _elapsed < 4.65:
		var t2 := clampf((_elapsed - 4.0) / 0.35, 0.0, 1.0)
		target = _door_point.lerp(_miss_point, t2)
	elif _elapsed >= 4.65:
		var t3 := clampf((_elapsed - 4.65) / 0.35, 0.0, 1.0)
		target = _miss_point.lerp(_door_point, t3)
	_camera.look_at(target, Vector3.UP)

	if not _pressed and _elapsed >= 3.15 and _interact != null:
		_pressed = true
		_interact.try_interact()

	if _elapsed >= 6.0:
		get_tree().quit(0)
