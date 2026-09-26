class_name ActionPromptFace
extends Control

## The readable face of HFN's world-space interaction banner. The ink below it
## is the same ADT blot shader used by the controls panel; this layer only draws
## the frame, key cap and factual action text.

const FRAME_RECT := Rect2(26.0, 22.0, 332.0, 116.0)
const KEY_RECT := Rect2(44.0, 45.0, 62.0, 62.0)
const DIVIDER_X := 127.0

var _header: String = "INTERACT"
var _key: String = "F"
var _action: String = "Interact"
var _detail: String = ""
var _press: float = 0.0

var _font: Font
var _key_font: Font
var _frame_style: StyleBoxFlat
var _key_style: StyleBoxFlat


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_styles()
	queue_redraw()


func set_prompt(header: String, key: String, action: String, detail: String) -> void:
	if _header == header and _key == key and _action == action and _detail == detail:
		return
	_header = header
	_key = key
	_action = action
	_detail = detail
	queue_redraw()


func set_press_amount(value: float) -> void:
	var next := clampf(value, 0.0, 1.0)
	if is_equal_approx(next, _press):
		return
	_press = next
	queue_redraw()


func _build_styles() -> void:
	_frame_style = StyleBoxFlat.new()
	_frame_style.bg_color = Color(0.035, 0.029, 0.022, 0.93)
	_frame_style.border_color = Color(0.72, 0.54, 0.26, 0.88)
	_frame_style.set_border_width_all(2)
	_frame_style.set_corner_radius_all(9)

	_key_style = StyleBoxFlat.new()
	_key_style.bg_color = Color(0.94, 0.84, 0.65, 1.0)
	_key_style.border_color = Color(0.77, 0.56, 0.27, 1.0)
	_key_style.set_border_width_all(3)
	_key_style.set_corner_radius_all(10)


func _draw() -> void:
	if _font == null:
		_font = get_theme_default_font()
	if _key_font == null:
		var system_font := SystemFont.new()
		system_font.font_names = ["Consolas", "Courier New", "DejaVu Sans Mono", "monospace"]
		_key_font = system_font
	if _font == null or _key_font == null:
		return

	# Small offset reads as a physical press without scaling the whole banner.
	var press_offset := Vector2(0.0, _press * 3.0)
	var frame := Rect2(FRAME_RECT.position + press_offset * 0.25, FRAME_RECT.size)
	var key_rect := Rect2(KEY_RECT.position + press_offset, KEY_RECT.size)

	# A narrow shadow keeps the frame legible against snow without making it a
	# giant black card.
	draw_rect(Rect2(frame.position + Vector2(3.0, 5.0), frame.size),
		Color(0.0, 0.0, 0.0, 0.34), true)
	draw_style_box(_frame_style, frame)

	# Gold divider and inner edge are carried from the ADT visual language.
	draw_line(Vector2(DIVIDER_X, 38.0) + press_offset * 0.25,
		Vector2(DIVIDER_X, 122.0) + press_offset * 0.25,
		Color(0.72, 0.54, 0.26, 0.62), 2.0)

	# Key cap: cream face, dark lower shadow, bright top edge.
	draw_rect(Rect2(key_rect.position + Vector2(0.0, 5.0), key_rect.size),
		Color(0.20, 0.14, 0.08, 0.90), true)
	draw_style_box(_key_style, key_rect)
	draw_line(key_rect.position + Vector2(9.0, 8.0),
		key_rect.position + Vector2(key_rect.size.x - 9.0, 8.0),
		Color(1.0, 0.96, 0.86, 0.72), 2.0)

	var key_size := 34
	var key_width := _key_font.get_string_size(_key, HORIZONTAL_ALIGNMENT_LEFT, -1, key_size).x
	var key_pos := Vector2(
		key_rect.position.x + (key_rect.size.x - key_width) * 0.5,
		key_rect.position.y + 43.0
	)
	draw_string(_key_font, key_pos, _key, HORIZONTAL_ALIGNMENT_LEFT, -1, key_size,
		Color(0.08, 0.055, 0.035, 1.0))

	var text_x := 148.0
	var y_shift := press_offset.y * 0.25
	draw_string(_font, Vector2(text_x, 50.0 + y_shift), _header.to_upper(),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.79, 0.61, 0.31, 0.95))
	draw_string(_font, Vector2(text_x, 82.0 + y_shift), _action,
		HORIZONTAL_ALIGNMENT_LEFT, 192.0, 24, Color(0.96, 0.93, 0.86, 1.0))
	if not _detail.is_empty():
		draw_string(_font, Vector2(text_x, 108.0 + y_shift), _detail,
			HORIZONTAL_ALIGNMENT_LEFT, 192.0, 13, Color(0.72, 0.72, 0.70, 0.95))
