class_name HealthStrip
extends Control

## Compact health treatment inspired by the approved segmented reference.
## The layers are intentionally separate in draw-space:
## body -> delayed damage trail -> live fill -> frame/dividers -> cross/effects.
## This keeps the HUD resolution-independent and avoids baking a raster bar.

@export var health: PlayerHealthSystem

@export_group("Geometry")
@export var health_mark_slot: float = 22.0
@export var outer_chamfer: float = 3.0
@export var frame_width: float = 1.6
@export var inner_inset: float = 2.5
@export_range(2, 8, 1) var segment_count: int = 5

@export_group("Motion")
## Damage is immediate; the pale residual catches up afterward.
@export var trail_delay: float = 0.08
@export var trail_duration: float = 0.62
## Healing eases into the new amount and carries a brief leading-edge glint.
@export var heal_duration: float = 0.62
@export var damage_flash_duration: float = 0.24
@export var heal_glint_duration: float = 0.72

@export_group("Colours")
@export var body_color: Color = Color("#12171BDD")
@export var body_inner_color: Color = Color("#20262BCC")
@export var frame_color: Color = Color("#343B40F2")
@export var frame_highlight: Color = Color("#7C858A8C")
@export var divider_color: Color = Color("#0A0D0FCC")
@export var divider_highlight: Color = Color("#70777B66")
@export var fill_left: Color = Color("#C52B25F5")
@export var fill_right: Color = Color("#7B2727E8")
@export var trail_color: Color = Color("#E0A09A99")
@export var damage_edge_color: Color = Color("#F05A4EFF")
@export var heal_edge_color: Color = Color("#F0C06DFF")
@export var cross_color: Color = Color("#D33A31FF")
@export var cross_shadow: Color = Color("#080B0DDD")
@export var cross_highlight: Color = Color("#FF796B80")

var ratio: float = 1.0
var trail: float = 1.0
var damage_flash: float = 0.0
var heal_glint: float = 0.0
var _tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if health == null and owner != null and owner.get_parent() != null:
		health = owner.get_parent().get_node_or_null(^"PlayerHealthSystem") as PlayerHealthSystem
	if health != null:
		health.health_changed.connect(set_health)
		set_health(health.current_health, health.max_health, false)
	queue_redraw()


## Moves the bar to current/max. Spending snaps the live fill down, leaving a
## delayed residual; healing eases upward with a warm moving edge highlight.
func set_health(current: float, maximum: float, animate: bool = true) -> void:
	var next: float = clampf(current / maxf(maximum, 0.001), 0.0, 1.0)
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if not animate or not is_inside_tree():
		ratio = next
		trail = next
		damage_flash = 0.0
		heal_glint = 0.0
		queue_redraw()
		return
	_tween = create_tween()
	if next < ratio:
		ratio = next
		damage_flash = 1.0
		queue_redraw()
		_tween.tween_property(self, ^"damage_flash", 0.0, damage_flash_duration) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_tween.parallel().tween_interval(trail_delay)
		_tween.tween_property(self, ^"trail", next, trail_duration) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	else:
		trail = next
		heal_glint = 1.0
		_tween.tween_property(self, ^"ratio", next, heal_duration) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_tween.parallel().tween_property(self, ^"heal_glint", 0.0, heal_glint_duration) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var bar := _bar_rect()
	if bar.size.x <= 1.0 or bar.size.y <= 1.0:
		return
	_draw_cross()
	_draw_body(bar)
	_draw_trail(bar)
	_draw_fill(bar)
	_draw_frame(bar)
	_draw_feedback(bar)


func _bar_rect() -> Rect2:
	return Rect2(Vector2(health_mark_slot, 0.0), Vector2(maxf(size.x - health_mark_slot, 0.0), size.y))


func _inner_rect(bar: Rect2) -> Rect2:
	return Rect2(
		bar.position + Vector2.ONE * inner_inset,
		Vector2(maxf(bar.size.x - inner_inset * 2.0, 0.0), maxf(bar.size.y - inner_inset * 2.0, 0.0))
	)


func _draw_body(bar: Rect2) -> void:
	draw_colored_polygon(_chamfered_rect(bar, outer_chamfer), body_color)
	var inner := _inner_rect(bar)
	if inner.size.x > 0.0 and inner.size.y > 0.0:
		draw_rect(inner, body_inner_color, true)


func _draw_trail(bar: Rect2) -> void:
	if trail <= ratio + 0.001:
		return
	var inner := _inner_rect(bar)
	var x0: float = inner.position.x + inner.size.x * ratio
	var x1: float = inner.position.x + inner.size.x * trail
	if x1 > x0:
		draw_rect(Rect2(Vector2(x0, inner.position.y), Vector2(x1 - x0, inner.size.y)), trail_color, true)


func _draw_fill(bar: Rect2) -> void:
	var inner := _inner_rect(bar)
	var filled_w: float = inner.size.x * clampf(ratio, 0.0, 1.0)
	if filled_w <= 0.25:
		return
	var strips: int = 12
	for i in range(strips):
		var t0: float = float(i) / float(strips)
		var t1: float = float(i + 1) / float(strips)
		var sx0: float = inner.position.x + filled_w * t0
		var sx1: float = inner.position.x + filled_w * t1 + 0.5
		var colour: Color = fill_left.lerp(fill_right, t0 * 0.78)
		draw_rect(Rect2(Vector2(sx0, inner.position.y), Vector2(maxf(sx1 - sx0, 0.0), inner.size.y)), colour, true)
	# Thin specular top edge keeps the fill readable without turning neon.
	var top_glint := Color(1.0, 0.43, 0.37, 0.28)
	draw_line(
		Vector2(inner.position.x + 1.0, inner.position.y + 0.8),
		Vector2(inner.position.x + maxf(filled_w - 1.0, 1.0), inner.position.y + 0.8),
		top_glint,
		1.0,
		true
	)


func _draw_frame(bar: Rect2) -> void:
	var outline := _chamfered_rect(bar, outer_chamfer)
	var closed := outline.duplicate()
	closed.append(outline[0])
	draw_polyline(closed, frame_color, frame_width, true)
	var inner := _inner_rect(bar)
	var inner_line := Rect2(inner.position - Vector2.ONE * 0.8, inner.size + Vector2.ONE * 1.6)
	draw_rect(inner_line, frame_highlight, false, 0.8)
	# Five restrained cells, like the reference, but only the frame is segmented.
	for i in range(1, segment_count):
		var x: float = inner.position.x + inner.size.x * (float(i) / float(segment_count))
		draw_line(Vector2(x, bar.position.y + 1.0), Vector2(x, bar.position.y + bar.size.y - 1.0), divider_color, 2.2, true)
		draw_line(Vector2(x + 1.0, bar.position.y + 2.0), Vector2(x + 1.0, bar.position.y + bar.size.y - 2.0), divider_highlight, 0.7, true)


func _draw_cross() -> void:
	var centre := Vector2(health_mark_slot * 0.43, size.y * 0.5)
	var arm: float = minf(size.y * 0.74, 13.0)
	var thickness: float = maxf(arm * 0.34, 3.0)
	var shadow_offset := Vector2(1.0, 1.0)
	_draw_cross_rects(centre + shadow_offset, arm, thickness, cross_shadow)
	_draw_cross_rects(centre, arm, thickness, cross_color)
	# Tiny top-left highlight gives the cross the same material hierarchy as frame.
	draw_line(centre + Vector2(-arm * 0.25, -arm * 0.5), centre + Vector2(arm * 0.25, -arm * 0.5), cross_highlight, 0.8, true)


func _draw_cross_rects(centre: Vector2, arm: float, thickness: float, colour: Color) -> void:
	draw_rect(Rect2(centre - Vector2(thickness * 0.5, arm * 0.5), Vector2(thickness, arm)), colour, true)
	draw_rect(Rect2(centre - Vector2(arm * 0.5, thickness * 0.5), Vector2(arm, thickness)), colour, true)


func _draw_feedback(bar: Rect2) -> void:
	var inner := _inner_rect(bar)
	if damage_flash > 0.001:
		var x: float = inner.position.x + inner.size.x * ratio
		var c: Color = damage_edge_color
		c.a *= damage_flash
		draw_line(Vector2(x, inner.position.y - 1.0), Vector2(x, inner.end.y + 1.0), c, 2.0 + damage_flash * 1.5, true)
	if heal_glint > 0.001:
		var hx: float = inner.position.x + inner.size.x * ratio
		var width: float = 8.0 + 12.0 * heal_glint
		var c2: Color = heal_edge_color
		c2.a *= heal_glint * 0.75
		draw_rect(Rect2(Vector2(hx - width, inner.position.y), Vector2(width, inner.size.y)), c2, true)


func _chamfered_rect(rect: Rect2, chamfer: float) -> PackedVector2Array:
	var c: float = minf(chamfer, minf(rect.size.x, rect.size.y) * 0.45)
	return PackedVector2Array([
		rect.position + Vector2(c, 0.0),
		Vector2(rect.end.x - c, rect.position.y),
		rect.position + Vector2(rect.size.x, c),
		Vector2(rect.end.x, rect.end.y - c),
		rect.end - Vector2(c, 0.0),
		Vector2(rect.position.x + c, rect.end.y),
		rect.position + Vector2(0.0, rect.size.y - c),
		rect.position + Vector2(0.0, c),
	])
