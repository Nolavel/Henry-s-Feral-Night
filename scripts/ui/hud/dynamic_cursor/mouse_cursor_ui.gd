class_name MouseCursorUI
extends Control

## ADT's dynamic cursor, ring only: a dim ring at screen centre that brightens
## over anything Henry can interact with. Hidden while a menu is open.

@export var player: CharacterBody3D
@export var cursor_radius: float = 8.0
@export var cursor_thickness: float = 2.0
## Nothing under the ring.
@export var cursor_color_idle: Color = Color(0.62, 0.64, 0.66, 0.75)
## An interactable under the ring.
@export var cursor_color_target: Color = Color(1.0, 1.0, 1.0, 0.95)
## Not instant: a highlight that snaps in reads as a flicker.
@export var cursor_color_speed: float = 10.0
## Ray length from the camera, metres.
@export var target_ray_length: float = 12.0

const RING_SEGMENTS: int = 32

var is_over_target: bool = false
var _color: Color = Color.WHITE


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_color = cursor_color_idle
	if player == null:
		player = get_parent() as CharacterBody3D


func _process(delta: float) -> void:
	visible = not _is_paused()
	if not visible:
		return
	is_over_target = _ray_hits_target()
	var wanted: Color = cursor_color_target if is_over_target else cursor_color_idle
	_color = _color.lerp(wanted, clampf(cursor_color_speed * delta, 0.0, 1.0))
	queue_redraw()


func _draw() -> void:
	var center: Vector2 = get_viewport_rect().size * 0.5
	var points := PackedVector2Array()
	for i: int in range(RING_SEGMENTS + 1):
		var angle: float = TAU * float(i) / float(RING_SEGMENTS)
		points.append(center + Vector2(cos(angle), sin(angle)) * cursor_radius)
	draw_polyline(points, _color, cursor_thickness, true)


## One ray from the camera through screen centre, the look direction.
func _ray_hits_target() -> bool:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null or player == null:
		return false
	var center: Vector2 = get_viewport_rect().size * 0.5
	var from: Vector3 = camera.project_ray_origin(center)
	var to: Vector3 = from + camera.project_ray_normal(center) * target_ray_length
	var params := PhysicsRayQueryParameters3D.create(from, to)
	params.collide_with_areas = true
	params.collide_with_bodies = true
	params.exclude = [player.get_rid()]
	var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(params)
	if hit.is_empty():
		return false
	var node := hit.get("collider") as Node
	for i: int in range(4):
		if node == null:
			return false
		if node is InteractiveArea:
			return (node as InteractiveArea).can_interact()
		node = node.get_parent()
	return false


func _is_paused() -> bool:
	var state: Node = get_node_or_null(^"/root/PlayerState")
	return state != null and bool(state.call(&"is_paused"))
