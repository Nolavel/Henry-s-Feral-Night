extends Control

@export_range(0.1, 2.0, 0.05) var update_interval: float = 0.25

var _panel: PanelContainer
var _label: Label
var _elapsed: float = 0.0
var _frames: int = 0
var _last_wall_usec: int = 0
var _show_panel: bool = true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_last_wall_usec = Time.get_ticks_usec()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.offset_left = -154.0
	_panel.offset_top = 10.0
	_panel.offset_right = -10.0
	_panel.offset_bottom = 116.0
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
	_label.text = "FPS      --\nFRAME    -- ms\nPROCESS  -- ms\nPHYSICS  -- ms\nSESSION  00:00:00"
	_panel.add_child(_label)


func on_world_ready(context: WorldContext) -> void:
	if context == null or context.world == null:
		return
	_show_panel = bool(context.world.get("enable_runtime_debug_panel"))

	visible = _show_panel
	set_process(_show_panel)


func _process(_delta: float) -> void:
	var now_usec: int = Time.get_ticks_usec()
	if _last_wall_usec <= 0:
		_last_wall_usec = now_usec
	var wall_delta_s: float = maxf(float(now_usec - _last_wall_usec) / 1000000.0, 0.0)
	_last_wall_usec = now_usec

	_elapsed += wall_delta_s
	_frames += 1

	if _elapsed >= update_interval:
		_update_visible_snapshot()


func _update_visible_snapshot() -> void:
	var fps: float = float(_frames) / maxf(_elapsed, 0.0001)
	var frame_ms: float = (_elapsed / maxf(float(_frames), 1.0)) * 1000.0
	var process_ms: float = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var physics_ms: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var snapshot := (
		"FPS      %3d\n"
		+ "FRAME   %5.2f ms\n"
		+ "PROCESS %5.2f ms\n"
		+ "PHYSICS %5.2f ms\n"
		+ "SESSION %s"
	) % [int(round(fps)), frame_ms, process_ms, physics_ms, _format_session_uptime()]

	if _show_panel:
		_label.text = snapshot
	_elapsed = 0.0
	_frames = 0


func _format_session_uptime() -> String:
	var total_seconds: int = int(Time.get_ticks_msec() / 1000)
	var hours: int = floori(float(total_seconds) / 3600.0)
	var minutes: int = floori(float(total_seconds % 3600) / 60.0)
	var seconds: int = total_seconds % 60
	return "%02d:%02d:%02d" % [hours, minutes, seconds]
