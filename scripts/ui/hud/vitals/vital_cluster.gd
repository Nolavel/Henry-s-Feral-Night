class_name VitalCluster
extends Control

## Four pentagons in an X, tips to the centre: warmth top-left, water top-right,
## food bottom-right, sleep bottom-left. A drain draws a cell in, a refill grows it.

const THERMAL_SCRIPT: GDScript = preload("res://scripts/systems/survival/thermal_manager.gd")
const ICON_THIRST: Texture2D = preload("res://assets/textures/ui/game/biomonitor/thirst_icon.png")
const ICON_HUNGER: Texture2D = preload("res://assets/textures/ui/game/biomonitor/hunger_icon.png")
const ICON_SLEEP: Texture2D = preload("res://assets/textures/ui/game/biomonitor/sleep.png")
const ICON_WARMTH: Texture2D = preload("res://assets/textures/ui/game/biomonitor/temperature_icon.png")

@export var bio_monitor: BioMonitorManager
@export var thermal_manager: ThermalManager

@export_group("Shape")
@export var cell_width: float = 58.0
@export var cell_height: float = 64.0
## Depth of the pointed end, from tip to where the sides start.
@export var cell_tip: float = 29.0
## Gap between each tip and the centre.
@export var centre_gap: float = 22.0
@export var outline_width: float = 2.0
@export var icon_size: float = 26.0

@export_group("Motion")
## A change smaller than this is not a pulse, so steady drift stays quiet.
@export_range(0.0, 0.2, 0.005) var pulse_threshold: float = 0.01
## A drain draws the cell this far toward the centre.
@export var drain_push_px: float = 6.0
@export var drain_duration: float = 0.35
@export var refill_scale: float = 0.15
@export var refill_duration: float = 2.0
## A critical cell sits this far in and breathes.
@export var critical_push_px: float = 3.0
## Whole-cell opacity at rest, and while it drains, refills or is critical.
@export_range(0.0, 1.0, 0.05) var idle_alpha: float = 0.45
@export_range(0.0, 1.0, 0.05) var active_alpha: float = 1.0

@export_group("Colours")
@export var base_color: Color = Color("#2A2E33CC")
@export var outline_color: Color = Color("#C9CED2")
## Neutral level fill; only a low level turns it rust.
@export var fill_high: Color = Color("#C9CED2")
@export var fill_mid: Color = Color("#9BA3AA")
@export var fill_low: Color = Color("#B8452F")
@export var drain_flash: Color = Color("#A34A3A")
@export var refill_flash: Color = Color("#A8C47A")
@export var warmth_normal: Color = Color("#D8DADB")
@export var warmth_cold: Color = Color("#7FB6D9")
@export var warmth_critical: Color = Color("#BFF1F5")

var cells: Dictionary = {}
var _time: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	cells[&"warmth"] = VitalCell.new(&"warmth", Vector2(-1.0, -1.0), ICON_WARMTH)
	cells[&"thirst"] = VitalCell.new(&"thirst", Vector2(1.0, -1.0), ICON_THIRST)
	cells[&"hunger"] = VitalCell.new(&"hunger", Vector2(1.0, 1.0), ICON_HUNGER)
	cells[&"sleep"] = VitalCell.new(&"sleep", Vector2(-1.0, 1.0), ICON_SLEEP)
	_bind_bio_monitor()
	_bind_thermal()


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


## The composition root builds the thermal model; the cluster finds it here.
func on_world_ready(context: WorldContext) -> void:
	if thermal_manager == null:
		thermal_manager = context.get_system(THERMAL_SCRIPT) as ThermalManager
		_bind_thermal()


## Feeds one vital 0..1; pulses when it moved enough.
func set_vital(id: StringName, value: float) -> void:
	var cell: VitalCell = cells.get(id)
	if cell == null:
		return
	match cell.set_level(value, pulse_threshold):
		VitalCell.Pulse.DRAIN:
			_play_drain(cell)
		VitalCell.Pulse.REFILL:
			_play_refill(cell)


func get_cell(id: StringName) -> VitalCell:
	return cells.get(id)


func _bind_bio_monitor() -> void:
	if bio_monitor == null:
		var player: Node = owner.get_parent() if owner != null else null
		if player != null:
			bio_monitor = player.get_node_or_null(^"BioMonitorManager") as BioMonitorManager
	if bio_monitor == null:
		return
	bio_monitor.hunger_level_changed.connect(func(v: float) -> void: set_vital(&"hunger", v))
	bio_monitor.thirst_level_changed.connect(func(v: float) -> void: set_vital(&"thirst", v))
	bio_monitor.energy_level_changed.connect(func(v: float) -> void: set_vital(&"sleep", v))
	_seed(&"hunger", bio_monitor.current_calories / maxf(bio_monitor.max_calories, 0.001))
	_seed(&"thirst", bio_monitor.current_hydration / maxf(bio_monitor.max_hydration, 0.001))
	_seed(&"sleep", bio_monitor.current_energy / maxf(bio_monitor.max_energy, 0.001))


func _bind_thermal() -> void:
	if thermal_manager == null or thermal_manager.body_temperature_changed.is_connected(_on_body_temperature):
		return
	thermal_manager.body_temperature_changed.connect(_on_body_temperature)
	_seed(&"warmth", thermal_manager.get_body_temperature_normalised())


func _on_body_temperature(_celsius: float, normalised: float) -> void:
	set_vital(&"warmth", normalised)


## Sets a level without a pulse, for the first reading.
func _seed(id: StringName, value: float) -> void:
	var cell: VitalCell = cells.get(id)
	if cell != null:
		cell.set_level(value, INF)


func _play_drain(cell: VitalCell) -> void:
	_restart(cell)
	cell.pulse = VitalCell.Pulse.DRAIN
	cell.tween.tween_property(cell, ^"push", drain_push_px, drain_duration * 0.35) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	cell.tween.parallel().tween_property(cell, ^"flash", 1.0, drain_duration * 0.35)
	cell.tween.tween_property(cell, ^"push", 0.0, drain_duration * 0.65) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	cell.tween.parallel().tween_property(cell, ^"flash", 0.0, drain_duration * 1.5)


func _play_refill(cell: VitalCell) -> void:
	_restart(cell)
	cell.pulse = VitalCell.Pulse.REFILL
	cell.tween.tween_property(cell, ^"grow", refill_scale, refill_duration * 0.2) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	cell.tween.parallel().tween_property(cell, ^"flash", 1.0, refill_duration * 0.2)
	cell.tween.tween_interval(refill_duration * 0.5)
	cell.tween.tween_property(cell, ^"grow", 0.0, refill_duration * 0.3) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	cell.tween.parallel().tween_property(cell, ^"flash", 0.0, refill_duration * 0.3)


func _restart(cell: VitalCell) -> void:
	if cell.tween != null and cell.tween.is_valid():
		cell.tween.kill()
	cell.tween = create_tween()


func _draw() -> void:
	var centre: Vector2 = size * 0.5
	var shape: PackedVector2Array = VitalCell.pentagon(cell_width, cell_height, cell_tip)
	for cell: VitalCell in cells.values():
		_draw_cell(cell, centre, shape)


func _draw_cell(cell: VitalCell, centre: Vector2, shape: PackedVector2Array) -> void:
	var breathe: float = 0.0
	var active: float = maxf(cell.flash, cell.grow / maxf(refill_scale, 0.001))
	if cell.critical:
		breathe = critical_push_px
		active = maxf(active, 0.6 + 0.4 * (0.5 + 0.5 * sin(_time * 3.0)))
	var alpha: float = lerpf(idle_alpha, active_alpha, clampf(active, 0.0, 1.0))
	var out: Vector2 = cell.direction
	var angle: float = Vector2.UP.angle_to(out)
	var anchor: Vector2 = centre + out * maxf(centre_gap - cell.push - breathe, 0.0)
	var xform := Transform2D(angle, Vector2.ONE * (1.0 + cell.grow), 0.0, anchor)
	var outline: PackedVector2Array = xform * shape
	draw_colored_polygon(outline, _faded(base_color, alpha))
	var fill: PackedVector2Array = _fill_polygon(shape, cell.level)
	if fill.size() >= 3:
		draw_colored_polygon(xform * fill, _faded(_fill_color(cell), alpha))
	var edge: Color = outline_color
	if cell.flash > 0.0:
		var flash: Color = drain_flash if cell.pulse == VitalCell.Pulse.DRAIN else refill_flash
		edge = edge.lerp(flash, cell.flash)
	var closed := outline.duplicate()
	closed.append(outline[0])
	draw_polyline(closed, _faded(edge, alpha), outline_width * (1.0 + cell.flash * 0.6), true)
	if cell.icon != null:
		var middle: Vector2 = xform * Vector2(0.0, -(cell_height + cell_tip) * 0.5)
		var icon_px: float = icon_size * (1.0 + cell.grow)
		var rect := Rect2(middle - Vector2.ONE * icon_px * 0.5, Vector2.ONE * icon_px)
		draw_texture_rect(cell.icon, rect, false, Color(1.0, 1.0, 1.0, 0.9 * alpha))


## The part of the pentagon filled to `level`, measured from its outer base in.
func _fill_polygon(shape: PackedVector2Array, level: float) -> PackedVector2Array:
	if level <= 0.001:
		return PackedVector2Array()
	var depth: float = cell_height * level
	var band := PackedVector2Array([
		Vector2(-cell_width, -cell_height - 1.0),
		Vector2(cell_width, -cell_height - 1.0),
		Vector2(cell_width, -cell_height + depth),
		Vector2(-cell_width, -cell_height + depth),
	])
	var clipped: Array[PackedVector2Array] = Geometry2D.intersect_polygons(shape, band)
	return clipped[0] if not clipped.is_empty() else PackedVector2Array()


func _fill_color(cell: VitalCell) -> Color:
	var colour: Color
	if cell.id == &"warmth":
		if cell.level > 0.5:
			colour = warmth_cold.lerp(warmth_normal, (cell.level - 0.5) * 2.0)
		else:
			colour = warmth_critical.lerp(warmth_cold, cell.level * 2.0)
	elif cell.level > 0.5:
		colour = fill_mid.lerp(fill_high, (cell.level - 0.5) * 2.0)
	elif cell.level > 0.25:
		colour = fill_low.lerp(fill_mid, (cell.level - 0.25) * 4.0)
	else:
		colour = fill_low
	colour.a = 0.55
	return colour


static func _faded(colour: Color, alpha: float) -> Color:
	return Color(colour.r, colour.g, colour.b, colour.a * alpha)
