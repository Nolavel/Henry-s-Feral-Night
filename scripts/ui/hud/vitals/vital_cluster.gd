class_name VitalCluster
extends Control

## The original biomonitor image indicators, restored as one horizontal row.
## Behaviour still comes from VitalCell/BioMonitor/ThermalManager; only the
## presentation goes back to the four production PNGs.
const THERMAL_SCRIPT: GDScript = preload("res://scripts/systems/survival/thermal_manager.gd")
const THIRST_TEXTURE: Texture2D = preload("res://assets/textures/ui/game/biomonitor/thirst_icon.png")
const HUNGER_TEXTURE: Texture2D = preload("res://assets/textures/ui/game/biomonitor/hunger_icon.png")
const SLEEP_TEXTURE: Texture2D = preload("res://assets/textures/ui/game/biomonitor/sleep.png")
const WARMTH_TEXTURE: Texture2D = preload("res://assets/textures/ui/game/biomonitor/temperature_icon.png")

const ROW_HUNGER: int = 0
const ROW_THIRST: int = 1
const ROW_SLEEP: int = 2
const ROW_WARMTH: int = 3
const DISPLAY_ORDER: Array[StringName] = [&"thirst", &"hunger", &"sleep", &"warmth"]
## Warmth can move both ways; keep its small trend cue.
const TREND_IDS: Array[StringName] = [&"warmth"]

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
@export var icon_size: float = 54.0
@export var icon_gap: float = 18.0
## Legacy fields kept serialized for compatibility with older scene overrides.
## The restored horizontal biomonitor does not draw the centre silhouette.
## Height of the quiet figure standing between the top cells, above the health bar.
@export var silhouette_height: float = 44.0
## Distance from the centre down to the figure's feet, the health bar's top.
@export var silhouette_floor: float = 15.0

@export_group("Motion")
## A change smaller than this is not a pulse, so steady drift stays quiet.
@export_range(0.0, 0.2, 0.005) var pulse_threshold: float = 0.01
## Morphs play once when 50% or 10% is crossed; they never idle-loop.
@export_range(0.25, 0.4, 0.01) var morph_duration: float = 0.35
## A drain draws the cell this far toward the centre.
@export var drain_push_px: float = 6.0
@export var drain_duration: float = 0.35
@export var refill_scale: float = 0.15
@export var refill_duration: float = 2.0
## A critical cell rests this far inward without continuous animation.
@export var critical_push_px: float = 3.0
## Whole-cell opacity at rest, and while it drains, refills or is critical.
@export_range(0.0, 1.0, 0.05) var idle_alpha: float = 0.45
@export_range(0.0, 1.0, 0.05) var active_alpha: float = 1.0

@export_group("Trend")
## Seconds over which a value must move to show a trend mark.
@export var trend_window: float = 1.5
## Smallest move within the window that counts as a trend.
@export var trend_epsilon: float = 0.002
@export var trend_size: float = 7.0

@export_group("Colours")
## Solid backing of every cell; the level shows through the glyph, not a fill.
@export var base_color: Color = Color("#2A2E3399")
@export var silhouette_color: Color = Color("#15181B8C")
@export var normal_color: Color = Color("#F1F2EC")
@export var warning_color: Color = Color("#D2A943")
@export var critical_color: Color = Color("#C34E42")
@export var drain_flash: Color = Color("#A34A3A")
@export var refill_flash: Color = Color("#A8C47A")
## Water fill of the figure while clothes are wet.
@export var wet_color: Color = Color("#5B8DB8B3")

var cells: Dictionary = {}
## Latest value per id (vital ids plus &"wetness"), its value at the window start and its trend -1/0/+1.
var _values: Dictionary = {}
var _window_start: Dictionary = {}
var _trends: Dictionary = {}
var _window_left: float = 0.0
var _wetness: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	cells[&"warmth"] = VitalCell.new(&"warmth", Vector2(-1.0, -1.0), ROW_WARMTH)
	cells[&"thirst"] = VitalCell.new(&"thirst", Vector2(1.0, -1.0), ROW_THIRST)
	cells[&"hunger"] = VitalCell.new(&"hunger", Vector2(1.0, 1.0), ROW_HUNGER)
	cells[&"sleep"] = VitalCell.new(&"sleep", Vector2(-1.0, 1.0), ROW_SLEEP)
	_bind_bio_monitor()
	_bind_thermal()


func _process(delta: float) -> void:
	_window_left -= delta
	if _window_left <= 0.0:
		_window_left = trend_window
		for id: StringName in _values:
			var moved: float = float(_values[id]) - float(_window_start.get(id, _values[id]))
			_trends[id] = 0 if absf(moved) < trend_epsilon else int(signf(moved))
			_window_start[id] = _values[id]
	queue_redraw()


## Rising, falling or steady (+1, -1, 0) over the last window. Ids: the vitals and wetness.
func get_trend(id: StringName) -> int:
	return int(_trends.get(id, 0))


## Clothing wetness 0..1: fills the figure from the feet and gets its own trend mark.
func set_wetness(value: float) -> void:
	_wetness = clampf(value, 0.0, 1.0)
	_track(&"wetness", _wetness)


func _track(id: StringName, value: float) -> void:
	if not _window_start.has(id):
		_window_start[id] = value
	_values[id] = value


## The composition root builds the thermal model; the cluster finds it here.
func on_world_ready(context: WorldContext) -> void:
	if thermal_manager == null:
		thermal_manager = context.get_system(THERMAL_SCRIPT) as ThermalManager
		_bind_thermal()


## Feeds one vital 0..1; pulses on movement and morphs only across thresholds.
func set_vital(id: StringName, value: float) -> void:
	var cell: VitalCell = cells.get(id)
	if cell == null:
		return
	_track(id, value)
	var previous_severity: int = cell.severity
	var pulse: int = cell.set_level(value, pulse_threshold)
	if cell.severity != previous_severity:
		_play_morph(cell)
	match pulse:
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
	thermal_manager.wetness_changed.connect(set_wetness)
	_seed(&"warmth", thermal_manager.get_body_temperature_normalised())
	set_wetness(thermal_manager.get_wetness())


func _on_body_temperature(_celsius: float, normalised: float) -> void:
	set_vital(&"warmth", normalised)


## Sets a level and matching baked frame without playing an initial animation.
func _seed(id: StringName, value: float) -> void:
	var cell: VitalCell = cells.get(id)
	_track(id, value)
	if cell != null:
		cell.set_level(value, INF)
		cell.morph_frame = cell.target_morph_frame()


func _play_drain(cell: VitalCell) -> void:
	_restart_motion(cell)
	cell.pulse = VitalCell.Pulse.DRAIN
	cell.tween.tween_property(cell, ^"push", drain_push_px, drain_duration * 0.35) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	cell.tween.parallel().tween_property(cell, ^"flash", 1.0, drain_duration * 0.35)
	cell.tween.tween_property(cell, ^"push", 0.0, drain_duration * 0.65) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	cell.tween.parallel().tween_property(cell, ^"flash", 0.0, drain_duration * 1.5)


func _play_refill(cell: VitalCell) -> void:
	_restart_motion(cell)
	cell.pulse = VitalCell.Pulse.REFILL
	cell.tween.tween_property(cell, ^"grow", refill_scale, refill_duration * 0.2) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	cell.tween.parallel().tween_property(cell, ^"flash", 1.0, refill_duration * 0.2)
	cell.tween.tween_interval(refill_duration * 0.5)
	cell.tween.tween_property(cell, ^"grow", 0.0, refill_duration * 0.3) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	cell.tween.parallel().tween_property(cell, ^"flash", 0.0, refill_duration * 0.3)


func _play_morph(cell: VitalCell) -> void:
	if cell.morph_tween != null and cell.morph_tween.is_valid():
		cell.morph_tween.kill()
	cell.morph_tween = create_tween()
	cell.morph_tween.tween_property(cell, ^"morph_frame", cell.target_morph_frame(), morph_duration) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _restart_motion(cell: VitalCell) -> void:
	if cell.tween != null and cell.tween.is_valid():
		cell.tween.kill()
	cell.tween = create_tween()


func _draw() -> void:
	var count: int = DISPLAY_ORDER.size()
	var total_width: float = icon_size * float(count) + icon_gap * float(maxi(count - 1, 0))
	var start_x: float = (size.x - total_width) * 0.5
	var centre_y: float = size.y * 0.5
	for index in range(count):
		var id: StringName = DISPLAY_ORDER[index]
		var cell: VitalCell = cells.get(id)
		if cell == null:
			continue
		var centre := Vector2(start_x + icon_size * 0.5 + float(index) * (icon_size + icon_gap), centre_y)
		_draw_biomonitor_icon(cell, centre)


func _draw_biomonitor_icon(cell: VitalCell, centre: Vector2) -> void:
	var texture: Texture2D = _texture_for(cell.id)
	if texture == null:
		return
	var source_size := Vector2(float(texture.get_width()), float(texture.get_height()))
	if source_size.x <= 0.0 or source_size.y <= 0.0:
		return
	var fit: float = icon_size / maxf(source_size.x, source_size.y)
	var draw_size: Vector2 = source_size * fit * (1.0 + cell.grow)
	var alpha: float = lerpf(0.25, 0.90, 1.0 - cell.level)
	if cell.severity == VitalCell.Severity.WARNING:
		alpha = maxf(alpha, 0.72)
	elif cell.critical:
		alpha = maxf(alpha, 0.95)
	alpha = clampf(alpha + cell.flash * 0.10, 0.0, 1.0)
	var tint := Color(1.0, 1.0, 1.0, alpha)
	var rect := Rect2(centre - draw_size * 0.5 + Vector2(0.0, cell.push), draw_size)
	draw_texture_rect(texture, rect, false, tint)
	if TREND_IDS.has(cell.id):
		_draw_trend(get_trend(cell.id), centre + Vector2(icon_size * 0.62, 0.0), get_trend(cell.id) > 0)


func _texture_for(id: StringName) -> Texture2D:
	match id:
		&"thirst":
			return THIRST_TEXTURE
		&"hunger":
			return HUNGER_TEXTURE
		&"sleep":
			return SLEEP_TEXTURE
		&"warmth":
			return WARMTH_TEXTURE
		_:
			return null


func _draw_cell(cell: VitalCell, centre: Vector2, shape: PackedVector2Array) -> void:
	var critical_inset: float = critical_push_px if cell.critical else 0.0
	var active: float = maxf(cell.flash, cell.grow / maxf(refill_scale, 0.001))
	if cell.severity == VitalCell.Severity.WARNING:
		active = maxf(active, 0.65)
	elif cell.critical:
		active = maxf(active, 1.0)
	var alpha: float = lerpf(idle_alpha, active_alpha, clampf(active, 0.0, 1.0))
	var out: Vector2 = cell.direction
	var angle: float = Vector2.UP.angle_to(out)
	var anchor: Vector2 = centre + out * maxf(centre_gap - cell.push - critical_inset, 0.0)
	var xform := Transform2D(angle, Vector2.ONE * (1.0 + cell.grow), 0.0, anchor)
	var outline: PackedVector2Array = xform * shape
	draw_colored_polygon(outline, base_color)
	var edge: Color = _state_color(cell)
	if cell.flash > 0.0:
		var flash: Color = drain_flash if cell.pulse == VitalCell.Pulse.DRAIN else refill_flash
		edge = edge.lerp(flash, cell.flash)
	var closed := outline.duplicate()
	closed.append(outline[0])
	draw_polyline(closed, _faded(edge, alpha), outline_width * (1.0 + cell.flash * 0.6), true)
	_draw_icon(cell, xform, alpha)
	if TREND_IDS.has(cell.id):
		var outer: Vector2 = xform * Vector2(0.0, -(cell_height + cell_tip) * 0.5) + out.normalized() * (cell_width * 0.5 + trend_size)
		_draw_trend(get_trend(cell.id), outer, get_trend(cell.id) > 0)


func _draw_icon(cell: VitalCell, xform: Transform2D, alpha: float) -> void:
	var middle: Vector2 = xform * Vector2(0.0, -(cell_height + cell_tip) * 0.5)
	var icon_px: float = icon_size * (1.0 + cell.grow)
	var rect := Rect2(middle - Vector2.ONE * icon_px * 0.5, Vector2.ONE * icon_px)
	var frame: int = clampi(roundi(cell.morph_frame), 0, MORPH_FRAME_COUNT - 1)
	var source := Rect2(
		Vector2(float(frame) * MORPH_CELL_PX, float(cell.icon_row) * MORPH_CELL_PX),
		Vector2.ONE * MORPH_CELL_PX
	)
	var tint: Color = _state_color(cell)
	tint.a = 0.96 * alpha
	draw_texture_rect_region(ICON_ATLAS, rect, source, tint)


## A plain standing figure, feet at `feet`, scaled to silhouette_height.
func _draw_silhouette(feet: Vector2) -> void:
	var k: float = silhouette_height / 52.0
	var body := PackedVector2Array([
		Vector2(-3, -41), Vector2(3, -41), Vector2(11, -38), Vector2(12, -20),
		Vector2(8, -20), Vector2(7, -30), Vector2(7, -18), Vector2(6, 0),
		Vector2(1.5, 0), Vector2(0, -16), Vector2(-1.5, 0), Vector2(-6, 0),
		Vector2(-7, -18), Vector2(-7, -30), Vector2(-8, -20), Vector2(-12, -20),
		Vector2(-11, -38),
	])
	var xform := Transform2D(0.0, Vector2(k * 0.85, k), 0.0, feet)
	var figure: PackedVector2Array = xform * body
	draw_colored_polygon(figure, silhouette_color)
	draw_circle(xform * Vector2(0.0, -46.5), 5.0 * k, silhouette_color)
	if _wetness > 0.01:
		var line: float = feet.y - silhouette_height * _wetness
		var water := PackedVector2Array([Vector2(feet.x - 40.0, line), Vector2(feet.x + 40.0, line),
			Vector2(feet.x + 40.0, feet.y + 1.0), Vector2(feet.x - 40.0, feet.y + 1.0)])
		for wet: PackedVector2Array in Geometry2D.intersect_polygons(figure, water):
			draw_colored_polygon(wet, wet_color)
		var drying: int = get_trend(&"wetness")
		_draw_trend(drying, feet + Vector2(silhouette_height * 0.35, -silhouette_height * 0.5), drying < 0)


## A small arrow: up for rising, down for falling; green when the change helps Henry.
func _draw_trend(trend: int, at: Vector2, good: bool) -> void:
	if trend == 0:
		return
	var up: bool = trend > 0
	var s: float = trend_size
	var tip: Vector2 = at + Vector2(0.0, -s if up else s)
	var points := PackedVector2Array([tip, at + Vector2(-s * 0.8, s * 0.3 if up else -s * 0.3),
		at + Vector2(s * 0.8, s * 0.3 if up else -s * 0.3)])
	draw_colored_polygon(points, refill_flash if good else drain_flash)


func _state_color(cell: VitalCell) -> Color:
	match cell.severity:
		VitalCell.Severity.WARNING:
			return warning_color
		VitalCell.Severity.CRITICAL:
			return critical_color
		_:
			return normal_color


static func _faded(colour: Color, alpha: float) -> Color:
	return Color(colour.r, colour.g, colour.b, colour.a * alpha)
