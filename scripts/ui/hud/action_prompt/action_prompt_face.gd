class_name ActionPromptFace
extends Control

## Text/key face for the centered interaction prompt.
## No card, raster grid or center fill: the key/action sits directly in the
## clear space between the morph brackets.

const KEY_RECT := Rect2(44.0, 45.0, 58.0, 58.0)
const KEY_BASE := Color(0.94, 0.84, 0.65, 1.0)
const KEY_CONFIRM := Color(1.0, 0.76, 0.24, 1.0)
const KEY_BORDER_BASE := Color(0.77, 0.56, 0.27, 1.0)
const KEY_BORDER_CONFIRM := Color(1.0, 0.82, 0.36, 1.0)

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


func set_prompt(_header: String, key: String, action: String, detail: String) -> void:
	if _key == key and _action == action and _detail == detail:
		return
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
	_key_style.bg_color = KEY_BASE
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

	_key_style.bg_color = KEY_BASE.lerp(KEY_CONFIRM, _confirm)
	_key_style.border_color = KEY_BORDER_BASE.lerp(KEY_BORDER_CONFIRM, _confirm)

	var key_rect := KEY_RECT
	# The only hard-edged geometry is the physical key itself. No enclosing card.
	draw_rect(Rect2(key_rect.position + Vector2(0.0, 4.0), key_rect.size),
		Color(0.16, 0.10, 0.055, 0.78), true)
	draw_style_box(_key_style, key_rect)
	draw_line(
		key_rect.position + Vector2(8.0, 7.0),
		key_rect.position + Vector2(key_rect.size.x - 8.0, 7.0),
		Color(1.0, 0.96, 0.86, lerpf(0.65, 0.92, _confirm)),
		2.0
	)

	var key_size := 32
	var key_width := _key_font.get_string_size(
		_key, HORIZONTAL_ALIGNMENT_LEFT, -1, key_size
	).x
	var key_pos := Vector2(
		key_rect.position.x + (key_rect.size.x - key_width) * 0.5,
		key_rect.position.y + 40.0
	)
	draw_string(
		_key_font, key_pos, _key, HORIZONTAL_ALIGNMENT_LEFT, -1, key_size,
		Color(0.08, 0.055, 0.035, 1.0)
	)

	var text_x := 124.0
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
