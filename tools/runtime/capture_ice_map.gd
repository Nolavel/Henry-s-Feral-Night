extends SceneTree

## Renders the bay top-down: ice thickness shading, the two routes across it,
## and where a sprinting crossing actually breaks through. This is the tool for
## answering whether the shortcut is worth the risk.

const PROFILE: String = "res://resources/ice/bay_ice.tres"
const OUT_PATH: String = "user://shots/ice_map.png"
const MARGIN: float = 70.0
const WARMUP_FRAMES: int = 4
## World extent drawn, in metres, centred on the origin.
const EXTENT_M: float = 260.0

var _canvas: Control
var _field: IceField
var _frames: int = 0
var _size: Vector2 = Vector2(1920, 1080)
var _break_point: Vector2 = Vector2.INF
var _thinnest_point: Vector2 = Vector2.INF
var _thinnest: float = 1.0
var _seconds_to_break: float = -1.0
var _shore_route: PackedVector2Array = PackedVector2Array()
var _bay_route: PackedVector2Array = PackedVector2Array()


func _initialize() -> void:
	_field = IceField.new()
	_field.profile = load(PROFILE) as IceProfile
	_field.shore_polygon = _island()
	root.add_child(_field)
	_build_routes()
	_simulate_crossing()
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.draw.connect(_draw_map)
	root.add_child(_canvas)


func _process(_delta: float) -> bool:
	_frames += 1
	if _canvas != null:
		_canvas.queue_redraw()
	if _frames < WARMUP_FRAMES:
		return false
	var image: Image = root.get_texture().get_image()
	if image == null:
		push_error("ice map: no image")
		quit(1)
		return true
	var absolute: String = ProjectSettings.globalize_path(OUT_PATH)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	image.save_png(absolute)
	print("ice map: %s" % absolute)
	return true


## A bay bitten out of the island's east side, so a shortcut exists at all.
func _island() -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(-90.0, -80.0), Vector2(60.0, -95.0), Vector2(85.0, -30.0),
		Vector2(5.0, -12.0), Vector2(0.0, 30.0), Vector2(80.0, 42.0),
		Vector2(70.0, 95.0), Vector2(-85.0, 85.0),
	])


## The two ways from the north headland to the south one.
func _build_routes() -> void:
	var start := Vector2(78.0, -34.0)
	var goal := Vector2(74.0, 46.0)
	_bay_route = PackedVector2Array([start, Vector2(96.0, 6.0), goal])
	_shore_route = PackedVector2Array([
		start, Vector2(20.0, -18.0), Vector2(-4.0, 6.0), Vector2(6.0, 34.0), goal
	])


## Walks the bay route at a sprint and records where the ice gives way.
func _simulate_crossing() -> void:
	var broke: Array[Vector2] = []
	_field.tile_broke.connect(
		func(_tile: Vector2i, where: Vector3) -> void:
			broke.append(Vector2(where.x, where.z))
	)
	_field.set_gait(IceField.Gait.SPRINT)

	var walked: float = 0.0
	var total: float = _route_length(_bay_route)
	## MovementController.sprint_speed; a slower guess made sprinting look safe.
	var speed: float = 8.0
	var elapsed: float = 0.0
	while walked < total and broke.is_empty():
		walked += speed * 0.1
		elapsed += 0.1
		var point: Vector2 = _point_along(_bay_route, walked)
		_field.step(Vector3(point.x, 0.0, point.y), 0.1)
		var base: float = _field.get_base_thickness(
			_field.world_to_tile(Vector3(point.x, 0.0, point.y))
		)
		if base < _thinnest:
			_thinnest = base
			_thinnest_point = point
	if not broke.is_empty():
		_break_point = broke[0]
		_seconds_to_break = elapsed


func _draw_map() -> void:
	var font: Font = ThemeDB.fallback_font
	_size = root.get_visible_rect().size
	_canvas.size = _size
	_canvas.draw_rect(Rect2(Vector2.ZERO, _size), Color(0.05, 0.06, 0.09))

	var step: float = _field.profile.tile_size_m
	var half: float = EXTENT_M * 0.5
	var x: float = -half
	while x < half:
		var z: float = -half
		while z < half:
			var centre := Vector2(x + step * 0.5, z + step * 0.5)
			_draw_cell(centre, step)
			z += step
		x += step

	_draw_polygon_outline(_island(), Color(0.55, 0.62, 0.72, 0.85))
	_draw_route(_shore_route, Color(0.45, 0.85, 0.65), 4.0)
	_draw_route(_bay_route, Color(0.95, 0.55, 0.35), 4.0)

	if _break_point != Vector2.INF:
		var screen: Vector2 = _to_screen(_break_point)
		_canvas.draw_circle(screen, 13.0, Color(0.95, 0.25, 0.25, 0.85))
		_canvas.draw_string(
			font, screen + Vector2(20, 6),
			"breaks through after %.0f s" % _seconds_to_break, HORIZONTAL_ALIGNMENT_LEFT,
			-1, 20, Color(0.98, 0.6, 0.55)
		)
	elif _thinnest_point != Vector2.INF:
		var screen: Vector2 = _to_screen(_thinnest_point)
		_canvas.draw_circle(screen, 11.0, Color(0.95, 0.75, 0.30, 0.85))
		_canvas.draw_string(
			font, screen + Vector2(18, 6),
			"thinnest point on the route: %.2f" % _thinnest, HORIZONTAL_ALIGNMENT_LEFT,
			-1, 20, Color(0.98, 0.82, 0.5)
		)

	_draw_legend(font)


## Shades one cell by the thickness of the ice there; land is left dark.
func _draw_cell(centre: Vector2, step: float) -> void:
	if _field.distance_to_shore(centre) <= 0.0:
		var land: Vector2 = _to_screen(centre - Vector2(step, step) * 0.5)
		_canvas.draw_rect(
			Rect2(land, Vector2(step, step) * _scale()), Color(0.12, 0.13, 0.15), true
		)
		return
	var thickness: float = _field.get_base_thickness(
		_field.world_to_tile(Vector3(centre.x, 0.0, centre.y))
	)
	var tint: Color = Color(0.32, 0.55, 0.78).lerp(Color(0.86, 0.36, 0.34), 1.0 - thickness)
	tint.a = 0.30 + 0.45 * (1.0 - thickness)
	var top_left: Vector2 = _to_screen(centre - Vector2(step, step) * 0.5)
	_canvas.draw_rect(Rect2(top_left, Vector2(step, step) * _scale()), tint, true)


func _draw_polygon_outline(points: PackedVector2Array, colour: Color) -> void:
	var count: int = points.size()
	for i: int in range(count):
		_canvas.draw_line(
			_to_screen(points[i]), _to_screen(points[(i + 1) % count]), colour, 3.0, true
		)


func _draw_route(points: PackedVector2Array, colour: Color, width: float) -> void:
	var screen: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in points:
		screen.append(_to_screen(point))
	if screen.size() > 1:
		_canvas.draw_polyline(screen, colour, width, true)


func _draw_legend(font: Font) -> void:
	var shore_m: float = _route_length(_shore_route)
	var bay_m: float = _route_length(_bay_route)
	var saved: float = shore_m - bay_m
	_canvas.draw_string(
		font, Vector2(MARGIN, 52), "The bay crossing, sprinted", HORIZONTAL_ALIGNMENT_LEFT,
		-1, 24, Color(1, 1, 1, 0.92)
	)
	_canvas.draw_string(
		font, Vector2(MARGIN, 86),
		"green: around the shore  %.0f m        orange: across the ice  %.0f m        saves %.0f m (%.0f%%)"
		% [shore_m, bay_m, saved, 100.0 * saved / maxf(1.0, shore_m)],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color(1, 1, 1, 0.6)
	)
	var verdict: String = ""
	if _break_point != Vector2.INF:
		verdict = "a sprinted crossing breaks through: the shortcut is a real gamble"
	else:
		verdict = (
			"a sprinted crossing survives (thinnest ice on the route %.2f): "
			% _thinnest
			+ "this shortcut is free, so the mechanic never fires here"
		)
	_canvas.draw_string(
		font, Vector2(MARGIN, 116), verdict, HORIZONTAL_ALIGNMENT_LEFT, -1, 19,
		Color(0.95, 0.72, 0.45) if _break_point == Vector2.INF else Color(0.6, 0.9, 0.7)
	)
	_canvas.draw_string(
		font, Vector2(MARGIN, _size.y - 34),
		"cell tint: blue solid ice, red thin ice        thickness falls off from %.0f m to %.0f m offshore"
		% [_field.profile.solid_until_m, _field.profile.thinnest_from_m],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1, 0.5)
	)


func _scale() -> float:
	return minf(_size.x - MARGIN * 2.0, _size.y - MARGIN * 2.0) / EXTENT_M


func _to_screen(world: Vector2) -> Vector2:
	return _size * 0.5 + world * _scale()


func _route_length(points: PackedVector2Array) -> float:
	var total: float = 0.0
	for i: int in range(points.size() - 1):
		total += points[i].distance_to(points[i + 1])
	return total


## Position a given distance along a polyline.
func _point_along(points: PackedVector2Array, distance: float) -> Vector2:
	var travelled: float = 0.0
	for i: int in range(points.size() - 1):
		var segment: float = points[i].distance_to(points[i + 1])
		if travelled + segment >= distance:
			var t: float = (distance - travelled) / maxf(0.001, segment)
			return points[i].lerp(points[i + 1], t)
		travelled += segment
	return points[points.size() - 1]
