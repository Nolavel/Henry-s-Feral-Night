class_name WindStreak
extends Node3D

## A cartoon wind streak along local +X: a line draws itself, curls into one
## closed self-crossing loop, runs on straight and fades from the tail.

signal finished

const SAMPLES: int = 240

@export var length: float = 6.0
## Loop size: spread of the curvature bump along the path, metres.
@export var loop_spread: float = 0.45
## Where the loop sits along the path, 0..1.
@export_range(0.1, 0.9) var loop_at: float = 0.45
## Loop plane tilt around +X, degrees; 0 curls straight up.
@export var loop_tilt_deg: float = 0.0
@export var width: float = 0.035
## Visible trail as a share of the path.
@export_range(0.1, 1.0) var tail: float = 0.55
@export var duration: float = 1.6
@export var color: Color = Color(1.0, 1.0, 1.0, 0.85)
@export var autoplay: bool = true
@export var repeat: bool = false
@export var repeat_delay: float = 2.0


var _points: PackedVector3Array = PackedVector3Array()
var _mesh: ImmediateMesh
var _material: StandardMaterial3D
var _head: float = 0.0
var _playing: bool = false
var _wait: float = 0.0


func _ready() -> void:
	_mesh = ImmediateMesh.new()
	var instance := MeshInstance3D.new()
	instance.mesh = _mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.vertex_color_use_as_albedo = true
	_material.disable_fog = true
	rebuild_path()
	if autoplay:
		play()


## Recomputes the path: heading turns by exactly TAU under a gaussian curvature bump.
func rebuild_path() -> void:
	_points.resize(SAMPLES)
	var ds: float = length / float(SAMPLES - 1)
	var centre: float = length * loop_at
	var bumps: PackedFloat32Array = PackedFloat32Array()
	bumps.resize(SAMPLES)
	var total: float = 0.0
	for i: int in range(SAMPLES):
		var d: float = (i * ds - centre) / loop_spread
		bumps[i] = exp(-0.5 * d * d)
		total += bumps[i] * ds
	var tilt: Basis = Basis(Vector3.RIGHT, deg_to_rad(loop_tilt_deg))
	var heading: float = 0.0
	var at: Vector2 = Vector2.ZERO
	for i: int in range(SAMPLES):
		_points[i] = tilt * Vector3(at.x, at.y, 0.0)
		heading += bumps[i] * TAU / total * ds
		at += Vector2(cos(heading), sin(heading)) * ds


func play() -> void:
	_head = 0.0
	_playing = true
	visible = true


## Head position along the path; runs past 1 so the tail can leave.
func set_head(head: float) -> void:
	_head = head
	_draw()


func _process(delta: float) -> void:
	if not _playing:
		if repeat:
			_wait -= delta
			if _wait <= 0.0:
				play()
		return
	_head += delta / duration * (1.0 + tail)
	if _head >= 1.0 + tail:
		_playing = false
		_wait = repeat_delay
		_mesh.clear_surfaces()
		finished.emit()
		return
	_draw()


func _draw() -> void:
	_mesh.clear_surfaces()
	var last: int = SAMPLES - 1
	var head_i: int = clampi(int(_head * last), 0, last)
	var tail_i: int = clampi(int((_head - tail) * last), 0, last)
	if head_i - tail_i < 2:
		return
	var view: Vector3 = Vector3.BACK
	var camera: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _material)
	for i: int in range(tail_i, head_i + 1):
		var p: Vector3 = _points[i]
		var along: Vector3 = (_points[mini(i + 1, last)] - _points[maxi(i - 1, 0)]).normalized()
		if camera != null:
			view = to_local(camera.global_position) - p
		var side: Vector3 = along.cross(view).normalized() * width * 0.5
		var f: float = float(i - tail_i) / float(head_i - tail_i)  # 0 at tail, 1 at head
		var c: Color = color
		c.a *= f
		_mesh.surface_set_color(c)
		_mesh.surface_add_vertex(p - side * (0.3 + 0.7 * f))
		_mesh.surface_add_vertex(p + side * (0.3 + 0.7 * f))
	_mesh.surface_end()
