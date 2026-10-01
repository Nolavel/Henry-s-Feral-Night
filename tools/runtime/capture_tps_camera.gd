extends SceneTree

## Stills of the TPS camera in TestScene at the poses where #170 measured trouble,
## identical for any camera build so before/after frames compare one to one.
## Run: xvfb-run godot --path . --rendering-driver vulkan --windowed --resolution 960x540 --fixed-fps 60 --script res://tools/runtime/capture_tps_camera.gd -- <label>

const SCENE: String = "res://tests/scenes/TestScene.tscn"
const OUT_ROOT: String = "user://shots/tps_camera"
## Long enough for a rested mouse to pass the 0.9 s auto-look cooldown and turn.
const SETTLE_FRAMES: int = 150
## Name, Henry origin, yaw (degrees), pitch, crouch, keep the mouse moving.
const STILLS: Array = [
	["open", Vector3(8.0, 1.0, 6.0), 0.0, -10.0, false, true],
	["door_side", Vector3(3.0, 1.0, 14.0), 0.0, -10.0, false, true],
	["door_side_rested", Vector3(3.0, 1.0, 14.0), 0.0, -10.0, false, false],
	["door_exit", Vector3(5.1, 1.0, 14.0), -90.0, -10.0, false, true],
	["corner_aiming", Vector3(-2.3, 1.0, 16.3), 0.0, -10.0, false, true],
	["corner_rested", Vector3(-2.3, 1.0, 16.3), 0.0, -10.0, false, false],
	["crouch_slab", Vector3(14.0, 1.0, 9.0), 180.0, -10.0, true, true],
	["pole", Vector3(20.0, 1.0, 0.0), 0.0, -10.0, false, true],
]


## Runs last in each frame, after every _process.
class FrameProbe extends Node:
	signal frame_done

	func _init() -> void:
		process_priority = 4096

	func _process(_delta: float) -> void:
		frame_done.emit()


var _label: String = "run"
var _scene: Node
var _player: CharacterBody3D
var _cam: Camera3D
var _probe: FrameProbe
var _frame: int = 0


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		_label = args[0]
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	_scene = (load(SCENE) as PackedScene).instantiate()
	root.add_child(_scene)
	_player = _scene.find_child("Player", true, false) as CharacterBody3D
	_cam = _scene.find_child("PlayerCamera", true, false) as Camera3D
	_add_prop(Vector3(14.0, 1.6, 9.0), BoxMesh.new(), Vector3(3.0, 0.2, 4.0))
	## On the camera-to-head line of both camera builds at the "pole" pose.
	_add_prop(Vector3(20.42, 1.5, 1.5), CylinderMesh.new(), Vector3(0.16, 3.0, 0.16))
	_probe = FrameProbe.new()
	root.add_child(_probe)
	_run.call_deferred()


func _run() -> void:
	await _frames(60)
	var dir: String = ProjectSettings.globalize_path(OUT_ROOT.path_join(_label))
	DirAccess.make_dir_recursive_absolute(dir)
	for still: Array in STILLS:
		await _place(still)
		for i: int in range(SETTLE_FRAMES):
			if still[5]:
				_mouse(1.0 if i % 2 == 0 else -1.0)
			await _frames(1)
		var image: Image = root.get_texture().get_image()
		image.save_png(dir.path_join("%s.png" % still[0]))
		var eye: Vector3 = _eye()
		print("[capture] %s camera %.2f m from the eyes" % [still[0], _cam.global_position.distance_to(eye)])
		Input.action_release(&"crouch")
	quit(0)


func _place(still: Array) -> void:
	Input.action_release(&"crouch")
	_player.velocity = Vector3.ZERO
	_player.rotation.y = deg_to_rad(still[2])
	if still[4]:
		## Crouch in the open first; a standing capsule does not fit under the slab.
		_player.global_position = still[1] + Vector3(0.0, 0.0, -4.0)
		Input.action_press(&"crouch")
		await _frames(15)
	_player.global_position = still[1]
	_player.velocity = Vector3.ZERO
	_cam.call(&"set_look", deg_to_rad(still[2]), still[3])
	if _cam.has_method(&"snap_to_target"):
		_cam.call(&"snap_to_target")
	else:
		_cam.set("_has_position", false)
		_cam.set("_collision_distance", -1.0)


## A visible static prop: mesh sized `size`, with a matching collider.
func _add_prop(at: Vector3, mesh: PrimitiveMesh, size: Vector3) -> Node3D:
	var visual := MeshInstance3D.new()
	var shape := CollisionShape3D.new()
	if mesh is BoxMesh:
		(mesh as BoxMesh).size = size
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
	else:
		var cylinder_mesh := mesh as CylinderMesh
		cylinder_mesh.top_radius = size.x * 0.5
		cylinder_mesh.bottom_radius = size.x * 0.5
		cylinder_mesh.height = size.y
		var cylinder := CylinderShape3D.new()
		cylinder.radius = size.x * 0.5
		cylinder.height = size.y
		shape.shape = cylinder
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.35, 0.22, 0.12)
	mesh.material = material
	visual.mesh = mesh
	var body := StaticBody3D.new()
	body.add_child(shape)
	visual.add_child(body)
	visual.position = at
	_scene.add_child(visual)
	return visual


func _mouse(dx: float) -> void:
	var event := InputEventMouseMotion.new()
	event.relative = Vector2(dx, 0.0)
	event.screen_relative = Vector2(dx, 0.0)
	Input.parse_input_event(event)


func _frames(count: int) -> void:
	for i: int in range(count):
		await _probe.frame_done
		_frame += 1


## The camera's eye point; ADT's 0.69 m over the capsule centre on builds without it.
func _eye() -> Vector3:
	if _cam.has_method(&"get_eye_position"):
		return _cam.call(&"get_eye_position")
	return _player.global_position + Vector3.UP * 0.69
