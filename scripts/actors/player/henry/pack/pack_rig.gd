class_name PackRig
extends Node3D

## Henry's backpack on his back: a tray with four outer flaps over an inner
## attachment field. The top flap alone opens for a quick stow; all four open for the Hub.

signal openness_changed(state: Openness)

enum Openness { CLOSED, TOP_ONLY, FULL }

## Hinge angles when open, in degrees; flaps swing out (-Z) first.
const TOP_OPEN_DEG: float = 150.0
const BOTTOM_OPEN_DEG: float = -120.0
const SIDE_OPEN_DEG: float = 150.0
## Share of the outer face each band covers, top to bottom.
const TOP_SHARE: float = 0.27
const BOTTOM_SHARE: float = 0.2
const FLAP_THICKNESS: float = 0.02

@export var size: Vector3 = Vector3(0.34, 0.44, 0.2)
@export var color: Color = Color(0.36, 0.33, 0.28)
@export var field_color: Color = Color(0.55, 0.5, 0.4)
## Seconds for the full book opening; the top-only opening takes half.
@export var open_time: float = 0.6
@export_flags_3d_render var render_layers: int = 1

var _state: Openness = Openness.CLOSED
var _top: Node3D
var _bottom: Node3D
var _left: Node3D
var _right: Node3D
var _field: Node3D
var _tween: Tween


func _init() -> void:
	name = "Backpack"


func _ready() -> void:
	if _top == null:
		build()


## Builds the tray, the field and the four hinged flaps. Idempotent.
func build() -> void:
	if _top != null:
		return
	var material: StandardMaterial3D = _material(color)
	var outer_z: float = -size.z * 0.5
	var tray_depth: float = size.z - FLAP_THICKNESS
	_box("Tray", Vector3(size.x, size.y, tray_depth), Vector3(0.0, 0.0, FLAP_THICKNESS * 0.5), material, self)
	_field = _build_field(outer_z + FLAP_THICKNESS + 0.002)
	var top_h: float = size.y * TOP_SHARE
	var bottom_h: float = size.y * BOTTOM_SHARE
	var mid_h: float = size.y - top_h - bottom_h
	var mid_y: float = size.y * 0.5 - top_h - mid_h * 0.5
	var flap_z: float = outer_z + FLAP_THICKNESS * 0.5
	_top = _hinge("TopFlap", Vector3(0.0, size.y * 0.5, flap_z))
	_box("Panel", Vector3(size.x, top_h, FLAP_THICKNESS), Vector3(0.0, -top_h * 0.5, 0.0), material, _top)
	_bottom = _hinge("BottomFlap", Vector3(0.0, -size.y * 0.5, flap_z))
	_box("Panel", Vector3(size.x, bottom_h, FLAP_THICKNESS), Vector3(0.0, bottom_h * 0.5, 0.0), material, _bottom)
	var half_w: float = size.x * 0.5
	_left = _hinge("LeftFlap", Vector3(-half_w, mid_y, flap_z))
	_box("Panel", Vector3(half_w, mid_h, FLAP_THICKNESS), Vector3(half_w * 0.5, 0.0, 0.0), material, _left)
	_right = _hinge("RightFlap", Vector3(half_w, mid_y, flap_z))
	_box("Panel", Vector3(half_w, mid_h, FLAP_THICKNESS), Vector3(-half_w * 0.5, 0.0, 0.0), material, _right)


func get_openness() -> Openness:
	return _state


func is_open() -> bool:
	return _state != Openness.CLOSED


## The bottom flap's hinge, for things strapped to the outside (Kenny).
func get_bottom_flap() -> Node3D:
	build()
	return _bottom


## The inner attachment field, where slot visuals live.
func get_field() -> Node3D:
	build()
	return _field


## Opens or closes the flaps; instant skips the tween (tests, loading).
func set_openness(state: Openness, instant: bool = false) -> void:
	build()
	_state = state
	var full: bool = state == Openness.FULL
	var top_open: bool = state != Openness.CLOSED
	var targets: Dictionary = {
		_top: Vector3(deg_to_rad(TOP_OPEN_DEG) if top_open else 0.0, 0.0, 0.0),
		_bottom: Vector3(deg_to_rad(BOTTOM_OPEN_DEG) if full else 0.0, 0.0, 0.0),
		_left: Vector3(0.0, deg_to_rad(SIDE_OPEN_DEG) if full else 0.0, 0.0),
		_right: Vector3(0.0, -deg_to_rad(SIDE_OPEN_DEG) if full else 0.0, 0.0),
	}
	if _tween != null:
		_tween.kill()
	if instant or not is_inside_tree():
		for flap: Node3D in targets:
			flap.rotation = targets[flap]
	else:
		var time: float = open_time if full or _left.rotation.y > 0.01 else open_time * 0.5
		_tween = create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		for flap: Node3D in targets:
			## The top leads; sides and bottom follow so the pack reads as unfolding.
			var delay: float = 0.0 if flap == _top else time * 0.25
			_tween.tween_property(flap, ^"rotation", targets[flap], time * 0.75).set_delay(delay)
	openness_changed.emit(state)


## Open amount of one flap, 0 closed to 1 fully open. Names: top, bottom, left, right.
func get_flap_open(flap_name: StringName) -> float:
	build()
	match flap_name:
		&"top":
			return _top.rotation.x / deg_to_rad(TOP_OPEN_DEG)
		&"bottom":
			return _bottom.rotation.x / deg_to_rad(BOTTOM_OPEN_DEG)
		&"left":
			return _left.rotation.y / deg_to_rad(SIDE_OPEN_DEG)
		&"right":
			return -_right.rotation.y / deg_to_rad(SIDE_OPEN_DEG)
	return 0.0


## A lighter board behind the flaps with a grid of strap loops.
func _build_field(z: float) -> Node3D:
	var field := Node3D.new()
	field.name = "Field"
	add_child(field)
	var inset: Vector2 = Vector2(size.x - 0.03, size.y - 0.03)
	_box("Board", Vector3(inset.x, inset.y, 0.004), Vector3(0.0, 0.0, z), _material(field_color), field)
	var loop_material: StandardMaterial3D = _material(color.darkened(0.3))
	for row: int in range(4):
		for column: int in range(3):
			var at := Vector3((column - 1) * inset.x * 0.3, (1.5 - row) * inset.y * 0.22, z - 0.004)
			_box("Loop", Vector3(0.05, 0.012, 0.006), at, loop_material, field)
	return field


func _hinge(hinge_name: String, at: Vector3) -> Node3D:
	var hinge := Node3D.new()
	hinge.name = hinge_name
	hinge.position = at
	add_child(hinge)
	return hinge


func _box(box_name: String, box_size: Vector3, at: Vector3, material: Material, parent: Node3D) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = box_size
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = box_name
	instance.mesh = mesh
	instance.position = at
	instance.layers = render_layers
	parent.add_child(instance)
	return instance


func _material(albedo: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = albedo
	material.roughness = 0.9
	return material
