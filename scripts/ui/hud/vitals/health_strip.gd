class_name HealthStrip
extends Control

## The old red HUD band, smaller, as the health bar: same shader and fade to
## the right, cut to current health. Damage leaves a pale trail that catches up.

const BAND_SHADER: Shader = preload("res://assets/materials/Shaders/BG_indicatorSURV.gdshader")

@export var health: PlayerHealthSystem
## The band colour the HUD used before, and its fade to the right.
@export var fill_color: Color = Color(0.62, 0.16, 0.14, 0.96)
@export var trail_color: Color = Color(0.91, 0.84, 0.78, 0.85)
@export var back_color: Color = Color(0.39, 0.2418, 0.2418, 0.35)
@export var heal_glint: Color = Color(0.88, 0.63, 0.33, 0.96)
@export var health_mark_color: Color = Color("#C34E42")
@export var health_mark_size: float = 9.0
## Reserved width for the compact health cross left of the band.
@export var health_mark_slot: float = 18.0
@export var fade_start: float = 0.35
@export var fade_curve: float = 0.691
## How long the damage trail takes to catch up, seconds.
@export var trail_duration: float = 0.6
@export var heal_duration: float = 0.5

var ratio: float = 1.0
var trail: float = 1.0
var glint: float = 0.0
var _tween: Tween
var _fill_clip: Control
var _trail_clip: Control
var _fill_material: ShaderMaterial


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add_band(self, back_color)
	_trail_clip = _add_clip()
	_add_band(_trail_clip, trail_color)
	_fill_clip = _add_clip()
	_fill_material = _add_band(_fill_clip, fill_color)
	resized.connect(_layout)
	_layout()
	if health == null and owner != null and owner.get_parent() != null:
		health = owner.get_parent().get_node_or_null(^"PlayerHealthSystem") as PlayerHealthSystem
	if health != null:
		health.health_changed.connect(set_health)
		set_health(health.current_health, health.max_health, false)


## Moves the band to current/max; a drop leaves the trail, a rise glints.
func set_health(current: float, maximum: float, animate: bool = true) -> void:
	var next: float = clampf(current / maxf(maximum, 0.001), 0.0, 1.0)
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if not animate or not is_inside_tree():
		ratio = next
		trail = next
		_layout()
		return
	_tween = create_tween()
	if next < ratio:
		ratio = next
		_layout()
		_tween.tween_interval(0.15)
		_tween.tween_property(self, ^"trail", next, trail_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	else:
		trail = next
		_tween.tween_property(self, ^"ratio", next, heal_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_tween.parallel().tween_property(self, ^"glint", 1.0, heal_duration * 0.3)
		_tween.tween_property(self, ^"glint", 0.0, heal_duration)


func _process(_delta: float) -> void:
	_layout()


func _draw() -> void:
	var centre := Vector2(health_mark_slot * 0.5, size.y * 0.5)
	var half: float = health_mark_size * 0.5
	var width: float = 2.2
	draw_line(centre + Vector2(-half, 0.0), centre + Vector2(half, 0.0), health_mark_color, width, true)
	draw_line(centre + Vector2(0.0, -half), centre + Vector2(0.0, half), health_mark_color, width, true)


func _layout() -> void:
	if _fill_clip == null:
		return
	var bar_width: float = maxf(size.x - health_mark_slot, 0.0)
	var bar_size := Vector2(bar_width, size.y)
	_fill_clip.position = Vector2(health_mark_slot, 0.0)
	_trail_clip.position = Vector2(health_mark_slot, 0.0)
	_fill_clip.size = Vector2(bar_width * ratio, size.y)
	_trail_clip.size = Vector2(bar_width * maxf(trail, ratio), size.y)
	for clip: Control in [_fill_clip, _trail_clip]:
		var band := clip.get_child(0) as Control
		band.position = Vector2.ZERO
		band.size = bar_size
	var back := get_child(0) as Control
	back.position = Vector2(health_mark_slot, 0.0)
	back.size = bar_size
	_fill_material.set_shader_parameter(&"base_color", fill_color.lerp(heal_glint, glint * 0.6))


func _add_clip() -> Control:
	var clip := Control.new()
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.position = Vector2(health_mark_slot, 0.0)
	add_child(clip)
	return clip


## One full-width band with the old HUD shader; clips cut it to a length.
func _add_band(parent: Control, colour: Color) -> ShaderMaterial:
	var band := ColorRect.new()
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.set_anchors_preset(Control.PRESET_TOP_LEFT)
	band.position = Vector2(health_mark_slot, 0.0) if parent == self else Vector2.ZERO
	band.size = Vector2(maxf(size.x - health_mark_slot, 0.0), size.y)
	var material := ShaderMaterial.new()
	material.shader = BAND_SHADER
	material.set_shader_parameter(&"base_color", colour)
	material.set_shader_parameter(&"fade_direction", 0)
	material.set_shader_parameter(&"fade_start", fade_start)
	material.set_shader_parameter(&"fade_end", 1.0)
	material.set_shader_parameter(&"fade_curve", fade_curve)
	material.set_shader_parameter(&"corner_radius", 0.0)
	band.material = material
	parent.add_child(band)
	if parent == self:
		resized.connect(_layout)
	return material
