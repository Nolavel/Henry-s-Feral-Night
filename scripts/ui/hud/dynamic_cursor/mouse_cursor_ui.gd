class_name MouseCursorUI
extends Control

## ADT's centre ring, brightening over interactables, carrying this project's
## movement dot, stamina-coloured sprint arcs and jump arc around it.

@export var player: CharacterBody3D
@export var cursor_radius: float = 8.0
@export var cursor_thickness: float = 2.0
## Brush Enso replaces only the centre ring. Sprint/jump stamina arcs keep
## their existing geometry and behaviour.
@export var cursor_enso_scale: float = 1.10
## Nothing under the ring.
@export var cursor_color_idle: Color = Color(0.62, 0.64, 0.66, 0.75)
## An interactable under the ring.
@export var cursor_color_target: Color = Color(1.0, 1.0, 1.0, 0.95)
## Not instant: a highlight that snaps in reads as a flicker.
@export var cursor_color_speed: float = 10.0
## Ray length from the camera, metres.
@export var target_ray_length: float = 12.0

@export_group("Movement and stamina")
@export var movement_controller: MovementController
@export var stamina_manager: StaminaManager
@export var movement_dot_color: Color = Color.GRAY
@export var movement_dot_bright_color: Color = Color.WHITE
@export var sprint_arc_thickness: float = 4.0
@export var sprint_arc_color: Color = Color(0.8, 0.9, 1.0, 1.0)
@export var sprint_animation_speed: float = 2.0
## Below this speed Henry counts as standing still, m/s.
@export var stationary_speed: float = 0.05

const RING_SEGMENTS: int = 32
const JUMP_ARC_COLOR: Color = Color(0.4, 0.8, 1.0)
const CURSOR_ENSO_PATH := "res://assets/ui/hud/dynamic_cursor/enso_cursor_ring.svg"

var is_over_target: bool = false
var _color: Color = Color.WHITE
var _stamina_ratio: float = 1.0
var _sprint_progress: float = 0.0
var _was_sprinting: bool = false
var _dot_alpha: float = 0.0
var _arcs_alpha: float = 0.0
var _arc_angle: float = 0.0
var _jump_charging: bool = false
var _jump_time: float = 0.0
var _jump_alpha: float = 0.0
var _jump_progress: float = 0.0
var _jump_tween: Tween
var _arcs_tween: Tween
var _cursor_enso_texture: Texture2D


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_color = cursor_color_idle
	_cursor_enso_texture = load(CURSOR_ENSO_PATH) as Texture2D
	if _cursor_enso_texture == null:
		push_warning("[MouseCursorUI] Enso cursor texture failed to load")
	if player == null:
		player = get_parent() as CharacterBody3D
	if player != null and movement_controller == null:
		movement_controller = player.get_node_or_null(^"MovementController") as MovementController
	if movement_controller != null and stamina_manager == null:
		stamina_manager = movement_controller.get_node_or_null(^"StaminaManager") as StaminaManager
	if stamina_manager != null:
		stamina_manager.stamina_changed.connect(_on_stamina_changed)
		stamina_manager.jump_performed.connect(_on_jump_performed)


func _process(delta: float) -> void:
	visible = not _is_paused()
	if not visible:
		return
	is_over_target = _ray_hits_target()
	var wanted: Color = cursor_color_target if is_over_target else cursor_color_idle
	_color = _color.lerp(wanted, clampf(cursor_color_speed * delta, 0.0, 1.0))
	_update_movement(delta)
	queue_redraw()


func _draw() -> void:
	var center: Vector2 = get_viewport_rect().size * 0.5
	_draw_cursor_enso(center, _color)
	var inner: Color = _color
	inner.a *= 0.3
	draw_circle(center, cursor_radius * 0.3, inner)
	if _dot_alpha > 0.01:
		var dot: Color = movement_dot_color.lerp(movement_dot_bright_color, _dot_alpha)
		dot.a *= _dot_alpha
		draw_circle(center + Vector2(0.0, cursor_radius + 8.5), 1.5, dot)
	if _arcs_alpha > 0.01:
		_draw_sprint_arcs(center)
	if _jump_alpha > 0.01:
		_draw_jump_arc(center)


func _update_movement(delta: float) -> void:
	if player == null or movement_controller == null:
		return
	var planar_speed: float = Vector2(player.velocity.x, player.velocity.z).length()
	var moving: bool = planar_speed > stationary_speed
	var sprinting: bool = movement_controller.is_currently_sprinting(player.velocity)
	_sprint_progress = clampf(movement_controller.get_sprint_blend(), 0.0, 1.0)
	if stamina_manager != null:
		_stamina_ratio = stamina_manager.get_stamina_ratio()
	_dot_alpha = lerpf(_dot_alpha, 1.0 if moving else 0.0, clampf(8.0 * delta, 0.0, 1.0))
	if sprinting != _was_sprinting:
		_fade_arcs(sprinting)
	_was_sprinting = sprinting
	if not (_arcs_tween and _arcs_tween.is_running()):
		var target: float = _sprint_progress * _stamina_ratio
		_arcs_alpha = lerpf(_arcs_alpha, target, clampf(6.0 * delta, 0.0, 1.0))
	if sprinting:
		_arc_angle = wrapf(_arc_angle + sprint_animation_speed * delta * (0.5 + _sprint_progress * 0.5), 0.0, TAU)
	else:
		_arc_angle = lerp_angle(_arc_angle, 0.0, clampf(4.0 * delta, 0.0, 1.0))
	## Player reports a held jump on the floor; the arc charges under the ring.
	var charging: bool = bool(player.get(&"cam_jump_hold_active"))
	if charging and not _jump_charging:
		_jump_alpha = 0.6
	elif not charging and _jump_charging and player.is_on_floor():
		_jump_alpha = 0.0
	_jump_charging = charging
	_jump_time = _jump_time + delta if charging else 0.0


func _fade_arcs(starting: bool) -> void:
	if _arcs_tween:
		_arcs_tween.kill()
	_arcs_tween = create_tween()
	if starting:
		_arcs_tween.tween_property(self, ^"_arcs_alpha", 1.0, 0.2)
	else:
		_arcs_tween.tween_property(self, ^"_arcs_alpha", 0.0, 0.4)


## Stamina colour: pale blue when full, through yellow and orange to red.
func _stamina_color(base: Color) -> Color:
	var r: float = _stamina_ratio
	if r > 0.5:
		return base.lerp(Color(1.0, 1.0, 0.0), (1.0 - r) * 2.0)
	if r > 0.25:
		return Color(1.0, 1.0, 0.0).lerp(Color(1.0, 0.5, 0.0), (0.5 - r) * 4.0)
	return Color(1.0, 0.5, 0.0).lerp(Color(1.0, 0.0, 0.0), (0.25 - r) * 4.0)


## Four quarter arcs that shrink with stamina and spin while sprinting.
func _draw_sprint_arcs(center: Vector2) -> void:
	var color: Color = _stamina_color(sprint_arc_color)
	color.a *= _stamina_ratio * _arcs_alpha
	var length: float = PI * 0.5 * _sprint_progress * _stamina_ratio
	for i: int in range(4):
		var start: float = float(i) * PI * 0.5 + _arc_angle
		draw_arc(center, cursor_radius + 4.0, start, start + length, 12, color, sprint_arc_thickness, true)


## Charging: a pulsing arc under the ring. Released: it closes to a circle.
func _draw_jump_arc(center: Vector2) -> void:
	var color: Color = _stamina_color(JUMP_ARC_COLOR)
	color.a = _jump_alpha
	var radius: float = cursor_radius + 12.0
	if _jump_charging:
		var length: float = PI * 0.2 + sin(_jump_time * 20.0) * 0.1 + PI * 0.3 * _jump_progress
		draw_arc(center, radius, PI * 0.5 - length * 0.5, PI * 0.5 + length * 0.5, 16, color, 2.0, true)
		return
	var half: float = PI * clampf(_jump_progress, 0.0, 1.0)
	if half >= PI:
		_draw_ring(center, radius, color, 2.0)
	elif half > 0.0:
		draw_arc(center, radius, PI * 1.5 - half, PI * 1.5 + half, 24, color, 2.0, true)


func _draw_cursor_enso(center: Vector2, color: Color) -> void:
	# The texture is authored with the brush opening at six o'clock. Tinting
	# preserves the old idle/target highlight behaviour without touching stamina.
	var diameter := cursor_radius * 2.0 * cursor_enso_scale
	var size := Vector2.ONE * diameter
	var rect := Rect2(center - size * 0.5, size)
	if _cursor_enso_texture != null:
		draw_texture_rect(_cursor_enso_texture, rect, false, color, false)
	else:
		_draw_ring(center, cursor_radius, color, cursor_thickness)


func _draw_ring(center: Vector2, radius: float, color: Color, thickness: float) -> void:
	var points := PackedVector2Array()
	for i: int in range(RING_SEGMENTS + 1):
		var angle: float = TAU * float(i) / float(RING_SEGMENTS)
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	draw_polyline(points, color, thickness, true)


func _on_stamina_changed(current: float, maximum: float) -> void:
	_stamina_ratio = current / maxf(maximum, 0.001)


func _on_jump_performed() -> void:
	if _jump_tween:
		_jump_tween.kill()
	_jump_tween = create_tween().set_parallel(true)
	_jump_tween.tween_property(self, ^"_jump_progress", 1.0, 0.15)
	_jump_tween.tween_property(self, ^"_jump_progress", 0.0, 0.25).set_delay(0.15)
	_jump_tween.tween_property(self, ^"_jump_alpha", 0.0, 0.4).from(0.8)


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
