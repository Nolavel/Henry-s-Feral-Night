extends Control

# === Геометрия ===
@export_group("geometry")
@export var size_side: float = 120.0           # главный ромб (здоровье)
@export var yellow_size: float = 55.0          # жёлтые ромбы (радиация, температура)
@export var gap_yellow: float = 20.0           # вынос жёлтых от ребра главного
@export var overlap: float = 0.3               # нахлёст правого ромба под главный
@export var gap_left: float = 10.0             # отступ первого левого ромба от левого угла главного
@export var left_size: float = 60.0            # размер левых ромбов (жажда, голод, сон)
@export var gap_between_left: float = 2.0     # промежуток между левыми ромбами

# Правый блок: оранжевый ромб (в нахлёст под главным) и два прямоугольника справа
@export_subgroup("slot_weapon_geometry")
@export var size_right: float = 96.0
@export var bars_dx: float = 4.0
@export var bars_sep: float = 38.0
@export var bar_length: float = 90.0
@export var bar_height: float = 30.0

# === Цвета ===
@export_group("colors")
@export var line_color_main: Color = Color(0.0, 1.0, 1.0, 0.8)
@export var fill_color_main: Color = Color(0.0, 0.5, 0.5, 0.2)
@export var line_color_right: Color = Color(1.0, 0.6, 0.0, 0.9)
@export var fill_color_right: Color = Color(1.0, 0.5, 0.0, 0.2)
@export var line_color_yellow: Color = Color(1.0, 0.85, 0.2, 0.9)
@export var fill_color_yellow: Color = Color(1.0, 0.85, 0.2, 0.15)
@export var line_color_left: Color = Color(1.0, 0.85, 0.2, 0.9)
@export var fill_color_left: Color = Color(1.0, 0.85, 0.2, 0.15)

@export var line_width: float = 2.0

# === Иконки (основные) ===
@export_group("background_slots")
@export var tex_health: Texture2D            # главный ромб (здоровье)
@export var tex_radiation: Texture2D         # верх-лево над главным
@export var tex_temperature: Texture2D       # верх-право над главным
@export var tex_weapon: Texture2D            # правый ромб (weapon)

@export var tex_thirst: Texture2D            # левый ряд 1
@export var tex_hunger: Texture2D            # левый ряд 2
@export var tex_sleep: Texture2D             # левый ряд 3

# === Оверлеи поверх (необязательно) ===
@export_group("overlay")
@export var overlay_health: Texture2D
@export var overlay_radiation: Texture2D
@export var overlay_temperature: Texture2D
@export var overlay_weapon: Texture2D
@export var overlay_thirst: Texture2D
@export var overlay_hunger: Texture2D
@export var overlay_sleep: Texture2D

func _ready() -> void:
	queue_redraw()

func _draw() -> void:
	var center := size * 0.5

	# --- Главный ромб (здоровье) ---
	var main_points := _diamond_points(center, size_side)
	_draw_polygon_outline(main_points, line_color_main, fill_color_main)
	_draw_texture_center(tex_health, center)
	_draw_texture_center(overlay_health, center)

	# --- Жёлтые ромбы НАД главным: верх-лево (радиация) и верх-право (температура) ---
	# верх-лево: ребро (левый -> верхний) = (3, 0)
	var yellow_ul_center := _edge_center_offset(main_points[3], main_points[0], center, gap_yellow, yellow_size)
	_draw_diamond(yellow_ul_center, yellow_size, line_color_yellow, fill_color_yellow)
	_draw_texture_center(tex_radiation, yellow_ul_center)
	_draw_texture_center(overlay_radiation, yellow_ul_center)

	# верх-право: ребро (верхний -> правый) = (0, 1)
	var yellow_ur_center := _edge_center_offset(main_points[0], main_points[1], center, gap_yellow, yellow_size)
	_draw_diamond(yellow_ur_center, yellow_size, line_color_yellow, fill_color_yellow)
	_draw_texture_center(tex_temperature, yellow_ur_center)
	_draw_texture_center(overlay_temperature, yellow_ur_center)

	# --- Правый ромб (weapon) в нахлёст под главным ---
	var half_diag_main := size_side / sqrt(2.0)
	var half_diag_right := size_right / sqrt(2.0)
	var offset_x := (half_diag_main + half_diag_right) - (half_diag_main * overlap)
	var right_center := center + Vector2(offset_x, 0)
	var right_points := _diamond_points(right_center, size_right)
	_draw_polygon_outline(right_points, line_color_right, fill_color_right)
	_draw_texture_center(tex_weapon, right_center)
	_draw_texture_center(overlay_weapon, right_center)

	# --- Два прямоугольника справа от правого угла оранжевого ромба (сохраняем) ---
	var orange_right_corner := right_points[1]

	# верхний: левая сторона параллельна top->right
	var edge_top := (right_points[1] - right_points[0]).normalized()
	var top_anchor := orange_right_corner + Vector2(bars_dx, -bars_sep * 0.5)
	_draw_rect_left_slanted_vertical(top_anchor, bar_length, bar_height, edge_top, line_color_main, fill_color_main)

	# нижний: левая сторона параллельна right->bottom
	var edge_bottom := (right_points[2] - right_points[1]).normalized()
	var bottom_anchor := orange_right_corner + Vector2(bars_dx,  bars_sep * 0.5)
	_draw_rect_left_slanted_vertical(bottom_anchor, bar_length, bar_height, edge_bottom, line_color_main, fill_color_main)

	# --- Левая цепочка: три ромба (жажда, голод, сон) ---
	var left_corner := main_points[3]
	var half_diag_left := left_size / sqrt(2.0)

	var thirst_center := left_corner + Vector2(-(gap_left + half_diag_left), 0)
	_draw_diamond(thirst_center, left_size, line_color_left, fill_color_left)
	_draw_texture_center(tex_thirst, thirst_center)
	_draw_texture_center(overlay_thirst, thirst_center)

	var hunger_center := thirst_center + Vector2(-(half_diag_left * 2.0 + gap_between_left), 0)
	_draw_diamond(hunger_center, left_size, line_color_left, fill_color_left)
	_draw_texture_center(tex_hunger, hunger_center)
	_draw_texture_center(overlay_hunger, hunger_center)

	var sleep_center := hunger_center + Vector2(-(half_diag_left * 2.0 + gap_between_left), 0)
	_draw_diamond(sleep_center, left_size, line_color_left, fill_color_left)
	_draw_texture_center(tex_sleep, sleep_center)
	_draw_texture_center(overlay_sleep, sleep_center)

# === Helpers ===

func _diamond_points(center: Vector2, side: float) -> PackedVector2Array:
	var half_diag := side / sqrt(2.0)
	return PackedVector2Array([
		center + Vector2(0, -half_diag),   # 0: top
		center + Vector2(half_diag, 0),    # 1: right
		center + Vector2(0, half_diag),    # 2: bottom
		center + Vector2(-half_diag, 0)    # 3: left
	])

func _draw_diamond(center: Vector2, side: float, line_col: Color, fill_col: Color) -> void:
	var points := _diamond_points(center, side)
	_draw_polygon_outline(points, line_col, fill_col)

func _draw_polygon_outline(points: PackedVector2Array, line_col: Color, fill_col: Color) -> void:
	if fill_col.a > 0.0:
		draw_polygon(points, PackedColorArray([fill_col]))
	points.append(points[0])
	draw_polyline(points, line_col, line_width, true)

func _draw_texture_center(tex: Texture2D, center: Vector2) -> void:
	if tex == null:
		return
	var tex_size := tex.get_size()
	var pos := center - tex_size * 0.5
	draw_texture(tex, pos)

# Центр внешнего ромба, вынесенного от середины ребра главного наружу
func _edge_center_offset(p1: Vector2, p2: Vector2, center: Vector2, gap: float, side: float) -> Vector2:
	var mid := (p1 + p2) * 0.5
	var edge_dir := (p2 - p1).normalized()
	var normal := Vector2(-edge_dir.y, edge_dir.x)
	# выбирать наружную нормаль
	if (mid + normal * 5.0).distance_to(center) < mid.distance_to(center):
		normal = -normal
	return mid + normal * (gap + side / (2.0 * sqrt(2.0)))

# Прямоугольник: левая сторона параллельна edge_dir, верх/низ горизонтальны, правая строго вертикальна
func _draw_rect_left_slanted_vertical(anchor: Vector2, width: float, height: float, edge_dir: Vector2, line_col: Color, fill_col: Color) -> void:
	var t := edge_dir.normalized()
	var y_top := anchor.y - height * 0.5
	var y_bot := anchor.y + height * 0.5

	var eps := 1e-5
	var left_top: Vector2
	var left_bot: Vector2
	if abs(t.y) > eps:
		var s_top := (y_top - anchor.y) / t.y
		var s_bot := (y_bot - anchor.y) / t.y
		left_top = anchor + t * s_top
		left_bot = anchor + t * s_bot
	else:
		left_top = Vector2(anchor.x, y_top)
		left_bot = Vector2(anchor.x, y_bot)

	var right_top := left_top + Vector2(width, 0)
	var right_bot := left_bot + Vector2(width, 0)

	var poly := PackedVector2Array([left_bot, right_bot, right_top, left_top])
	if fill_col.a > 0.0:
		draw_polygon(poly, PackedColorArray([fill_col]))
	poly.append(left_bot)
	draw_polyline(poly, line_col, line_width, true)
