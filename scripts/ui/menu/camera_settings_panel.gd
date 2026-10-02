class_name CameraSettingsPanel
extends Control

## Camera options are staged locally. Back discards them; Accept persists and
## applies them, then closes this frame.
signal closed(saved: bool)

const STORE: GDScript = preload("res://scripts/settings/camera_user_settings.gd")
const CAMERA_GROUP: StringName = &"tps_camera_user_settings"

const FRAME_SIZE := Vector2(560.0, 310.0)
const ACCENT := Color(0.93, 0.72, 0.18, 1.0)
const ACCENT_HOVER := Color(1.0, 0.80, 0.24, 1.0)
const ACCENT_PRESSED := Color(0.82, 0.61, 0.12, 1.0)
const DISABLED := Color(0.22, 0.23, 0.25, 0.94)
const BACKGROUND := Color(0.055, 0.06, 0.07, 0.97)

var _saved_sensitivity: float = STORE.DEFAULT_MOUSE_SENSITIVITY
var _saved_invert_y: bool = STORE.DEFAULT_INVERT_Y

var _sensitivity_slider: HSlider
var _sensitivity_value: Label
var _invert_y: CheckBox
var _accept_button: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	visible = false


func open() -> void:
	var values: Dictionary = STORE.load_camera()
	_saved_sensitivity = float(values["mouse_sensitivity_multiplier"])
	_saved_invert_y = bool(values["invert_y"])
	_sensitivity_slider.set_value_no_signal(_saved_sensitivity * 100.0)
	_invert_y.set_pressed_no_signal(_saved_invert_y)
	_refresh_value_label()
	_refresh_dirty_state()
	visible = true
	_sensitivity_slider.grab_focus()


func is_open() -> bool:
	return visible


func back() -> void:
	if not visible:
		return
	visible = false
	closed.emit(false)


func _accept() -> void:
	if _accept_button.disabled:
		return

	var sensitivity: float = _sensitivity_slider.value / 100.0
	var invert_y: bool = _invert_y.button_pressed
	var error: Error = STORE.save_camera(sensitivity, invert_y)
	if error != OK:
		push_warning("CameraSettingsPanel: settings save failed (error %d)" % error)
		return

	_saved_sensitivity = sensitivity
	_saved_invert_y = invert_y
	if is_inside_tree():
		get_tree().call_group(CAMERA_GROUP, &"reload_user_settings")
	_refresh_dirty_state()
	visible = false
	closed.emit(true)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause"):
		back()
		get_viewport().set_input_as_handled()


func _build() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.0, 0.0, 0.68)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)

	var frame := PanelContainer.new()
	frame.anchor_left = 0.5
	frame.anchor_top = 0.5
	frame.anchor_right = 0.5
	frame.anchor_bottom = 0.5
	frame.offset_left = -FRAME_SIZE.x * 0.5
	frame.offset_top = -FRAME_SIZE.y * 0.5
	frame.offset_right = FRAME_SIZE.x * 0.5
	frame.offset_bottom = FRAME_SIZE.y * 0.5
	frame.add_theme_stylebox_override("panel", _frame_style())
	add_child(frame)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_bottom", 24)
	frame.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	margin.add_child(column)

	var title := Label.new()
	title.text = tr("SETTINGS_TITLE")
	title.add_theme_font_size_override("font_size", 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	var sensitivity_row := HBoxContainer.new()
	sensitivity_row.add_theme_constant_override("separation", 14)
	column.add_child(sensitivity_row)

	var sensitivity_label := Label.new()
	sensitivity_label.text = tr("SETTINGS_MOUSE_SENSITIVITY")
	sensitivity_label.custom_minimum_size.x = 190.0
	sensitivity_row.add_child(sensitivity_label)

	_sensitivity_slider = HSlider.new()
	_sensitivity_slider.min_value = STORE.MIN_MOUSE_SENSITIVITY * 100.0
	_sensitivity_slider.max_value = STORE.MAX_MOUSE_SENSITIVITY * 100.0
	_sensitivity_slider.step = 5.0
	_sensitivity_slider.value = STORE.DEFAULT_MOUSE_SENSITIVITY * 100.0
	_sensitivity_slider.custom_minimum_size = Vector2(250.0, 34.0)
	_sensitivity_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sensitivity_slider.value_changed.connect(_on_value_changed)
	sensitivity_row.add_child(_sensitivity_slider)

	_sensitivity_value = Label.new()
	_sensitivity_value.custom_minimum_size.x = 62.0
	_sensitivity_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sensitivity_row.add_child(_sensitivity_value)

	_invert_y = CheckBox.new()
	_invert_y.text = tr("SETTINGS_INVERT_Y")
	_invert_y.toggled.connect(_on_invert_toggled)
	column.add_child(_invert_y)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 12)
	column.add_child(buttons)

	var back_button := Button.new()
	back_button.text = tr("SETTINGS_BACK")
	back_button.custom_minimum_size = Vector2(150.0, 42.0)
	back_button.pressed.connect(back)
	buttons.add_child(back_button)

	_accept_button = Button.new()
	_accept_button.text = tr("SETTINGS_ACCEPT")
	_accept_button.custom_minimum_size = Vector2(150.0, 42.0)
	_accept_button.add_theme_stylebox_override("disabled", _button_style(DISABLED))
	_accept_button.add_theme_stylebox_override("normal", _button_style(ACCENT))
	_accept_button.add_theme_stylebox_override("hover", _button_style(ACCENT_HOVER))
	_accept_button.add_theme_stylebox_override("pressed", _button_style(ACCENT_PRESSED))
	_accept_button.add_theme_color_override("font_color", Color(0.08, 0.07, 0.04))
	_accept_button.add_theme_color_override("font_hover_color", Color(0.05, 0.045, 0.025))
	_accept_button.add_theme_color_override("font_pressed_color", Color(0.05, 0.045, 0.025))
	_accept_button.add_theme_color_override("font_disabled_color", Color(0.58, 0.59, 0.61))
	_accept_button.pressed.connect(_accept)
	buttons.add_child(_accept_button)

	_refresh_value_label()
	_refresh_dirty_state()


func _on_value_changed(_value: float) -> void:
	_refresh_value_label()
	_refresh_dirty_state()


func _on_invert_toggled(_pressed: bool) -> void:
	_refresh_dirty_state()


func _refresh_value_label() -> void:
	if _sensitivity_value != null and _sensitivity_slider != null:
		_sensitivity_value.text = "%d%%" % int(round(_sensitivity_slider.value))


func _refresh_dirty_state() -> void:
	if _accept_button == null or _sensitivity_slider == null or _invert_y == null:
		return
	var staged_sensitivity: float = _sensitivity_slider.value / 100.0
	var dirty: bool = (
		not is_equal_approx(staged_sensitivity, _saved_sensitivity)
		or _invert_y.button_pressed != _saved_invert_y
	)
	_accept_button.disabled = not dirty


func _frame_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = BACKGROUND
	style.border_color = Color(0.48, 0.49, 0.51, 0.82)
	style.set_border_width_all(1)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	return style


func _button_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	return style
