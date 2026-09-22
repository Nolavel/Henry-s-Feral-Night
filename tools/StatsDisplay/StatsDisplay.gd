extends Control

@export_range(0.1, 2.0, 0.05) var update_interval: float = 0.25

var _panel: PanelContainer
var _label: Label
var _elapsed: float = 0.0
var _frames: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.offset_left = -154.0
	_panel.offset_top = 10.0
	_panel.offset_right = -10.0
	_panel.offset_bottom = 62.0
	add_child(_panel)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.025, 0.025, 0.03, 0.78)
	panel_style.border_width_left = 1
	panel_style.border_width_top = 1
	panel_style.border_width_right = 1
	panel_style.border_width_bottom = 1
	panel_style.border_color = Color(1.0, 1.0, 1.0, 0.10)
	panel_style.corner_radius_top_left = 4
	panel_style.corner_radius_top_right = 4
	panel_style.corner_radius_bottom_left = 4
	panel_style.corner_radius_bottom_right = 4
	panel_style.content_margin_left = 10.0
	panel_style.content_margin_top = 6.0
	panel_style.content_margin_right = 10.0
	panel_style.content_margin_bottom = 6.0
	_panel.add_theme_stylebox_override("panel", panel_style)

	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 13)
	_label.add_theme_color_override("font_color", Color(0.90, 0.92, 0.94, 0.96))
	_label.text = "FPS  --\nFRAME  -- ms"
	_panel.add_child(_label)


func _process(delta: float) -> void:
	_elapsed += delta
	_frames += 1

	if _elapsed < update_interval:
		return

	var fps: float = float(_frames) / maxf(_elapsed, 0.0001)
	var frame_ms: float = (_elapsed / maxf(float(_frames), 1.0)) * 1000.0
	var process_ms: float = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var physics_ms: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0

	_label.text = "FPS  %3d\nFRAME %5.2f ms" % [int(round(fps)), frame_ms]
	_label.tooltip_text = "Process %.2f ms  |  Physics %.2f ms" % [process_ms, physics_ms]

	_elapsed = 0.0
	_frames = 0
