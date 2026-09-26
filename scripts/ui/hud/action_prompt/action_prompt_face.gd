class_name ActionPromptFace
extends Control

## Text/key face for the world-space interaction prompt.
## There is deliberately NO card/frame here. The only backing is the same
## multi-blob ADT ink shader used by KeyHintsPanel.

const KEY_RECT := Rect2(44.0, 45.0, 58.0, 58.0)
const KEY_SURFACE := Color(0.075, 0.038, 0.012, 0.98)
const KEY_BORDER_BASE := Color(0.88, 0.34, 0.055, 0.92)
const KEY_BORDER_CONFIRM := Color(1.0, 0.76, 0.18, 1.0)
const MATRIX_BASE := Color(1.0, 0.30, 0.035, 0.72)
const MATRIX_CONFIRM := Color(1.0, 0.76, 0.16, 1.0)
const MATRIX_GLOW_BASE := Color(1.0, 0.18, 0.02, 0.11)
const MATRIX_GLOW_CONFIRM := Color(1.0, 0.68, 0.12, 0.24)
const MATRIX_COLS := 7
const MATRIX_ROWS := 7
const MATRIX_CELL := Vector2(4.0, 4.0)
const MATRIX_GAP := Vector2(2.0, 2.0)

var _header: String = "INTERACT"
var _key: String = "F"
var _action: String = "Interact"
var _detail: String = ""
var _confirm: float = 0.0

var _font: Font
var _key_font: Font
var _key_style: StyleBoxFlat


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_style()
	queue_redraw()


func set_prompt(header: String, key: String, action: String, detail: String) -> void:
	if _header == header and _key == key and _action == action and _detail == detail:
		return
	_header = header
	_key = key
	_action = action
	_detail = detail
	queue_redraw()


func set_confirm_amount(value: float) -> void:
	var next := clampf(value, 0.0, 1.0)
	if is_equal_approx(next, _confirm):
		return
	_confirm = next
	queue_redraw()


func get_confirm_amount() -> float:
	return _confirm


func _build_style() -> void:
	_key_style = StyleBoxFlat.new()
	_key_style.bg_color = KEY_SURFACE
	_key_style.border_color = KEY_BORDER_BASE
	_key_style.set_border_width_all(2)
	_key_style.set_corner_radius_all(8)


func _draw() -> void:
	if _font == null:
		var ui_font := SystemFont.new()
		ui_font.font_names = ["DejaVu Sans", "Arial", "Liberation Sans", "sans-serif"]
		_font = ui_font
	if _key_font == null:
		var system_font := SystemFont.new()
		system_font.font_names = ["Consolas", "Courier New", "DejaVu Sans Mono", "monospace"]
		_key_font = system_font
	if _font == null or _key_font == null:
		return

	_key_style.bg_color = KEY_SURFACE
	_key_style.border_color = KEY_BORDER_BASE.lerp(KEY_BORDER_CONFIRM, _confirm)

	var key_rect := KEY_RECT
	# Physical key shadow only; the face itself is an amber dot-matrix display.
	draw_rect(
		Rect2(key_rect.position + Vector2(0.0, 4.0), key_rect.size),
		Color(0.12, 0.055, 0.012, 0.82),
		true
	)
	draw_style_box(_key_style, key_rect)
	_draw_key_matrix(key_rect)

	var key_size := 32
	var key_width := _key_font.get_string_size(
		_key, HORIZONTAL_ALIGNMENT_LEFT, -1, key_size
	).x
	var key_pos := Vector2(
		key_rect.position.x + (key_rect.size.x - key_width) * 0.5,
		key_rect.position.y + 40.0
	)
	# The glyph sits above the matrix instead of being built from the cells.
	# A tiny dark offset separates it from hot cells without introducing a card.
	draw_string(
		_key_font, key_pos + Vector2(1.0, 1.5), _key,
		HORIZONTAL_ALIGNMENT_LEFT, -1, key_size,
		Color(0.055, 0.022, 0.006, 0.90)
	)
	draw_string(
		_key_font, key_pos, _key, HORIZONTAL_ALIGNMENT_LEFT, -1, key_size,
		Color(1.0, 0.91, 0.64, 1.0)
	)

	var text_x := 124.0
	draw_string(
		_font, Vector2(text_x, 51.0), _header.to_upper(),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
		Color(0.86, 0.67, 0.34, 1.0)
	)
	draw_string(
		_font, Vector2(text_x, 80.0), _action,
		HORIZONTAL_ALIGNMENT_LEFT, 202.0, 25,
		Color(0.98, 0.96, 0.91, 1.0)
	)
	if not _detail.is_empty():
		draw_string(
			_font, Vector2(text_x, 105.0), _detail,
			HORIZONTAL_ALIGNMENT_LEFT, 202.0, 14,
			Color(0.82, 0.82, 0.80, 1.0)
		)


## Amber square matrix inspired by instrument/terminal displays. The cells are
## intentionally regular: the physical key remains readable at world scale and
## the press acknowledgement comes from the matrix warming toward yellow.
func _draw_key_matrix(key_rect: Rect2) -> void:
	var grid_size := Vector2(
		MATRIX_COLS * MATRIX_CELL.x + (MATRIX_COLS - 1) * MATRIX_GAP.x,
		MATRIX_ROWS * MATRIX_CELL.y + (MATRIX_ROWS - 1) * MATRIX_GAP.y
	)
	var origin := key_rect.position + (key_rect.size - grid_size) * 0.5
	var cell_color := MATRIX_BASE.lerp(MATRIX_CONFIRM, _confirm)
	var glow_color := MATRIX_GLOW_BASE.lerp(MATRIX_GLOW_CONFIRM, _confirm)

	for row in range(MATRIX_ROWS):
		for col in range(MATRIX_COLS):
			var cell_pos := origin + Vector2(
				col * (MATRIX_CELL.x + MATRIX_GAP.x),
				row * (MATRIX_CELL.y + MATRIX_GAP.y)
			)
			# Soft one-pixel halo gives the grid the photographed amber-display
			# character without blurring the actual square cell.
			draw_rect(
				Rect2(cell_pos - Vector2.ONE, MATRIX_CELL + Vector2.ONE * 2.0),
				glow_color,
				true
			)
			draw_rect(Rect2(cell_pos, MATRIX_CELL), cell_color, true)
