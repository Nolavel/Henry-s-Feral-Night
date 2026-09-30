class_name DevDioramaMap
extends Control

## Debug-only oblique world map rendered from the live World3D.
## It never owns gameplay state and removes itself from release builds.

enum Mode { FOLLOW, FREE, RECENTERING }

const GROUP: StringName = &"dev_diorama_map"
const PANEL_SIZE: Vector2 = Vector2(500.0, 320.0)
const PANEL_OFFSET: Vector2 = Vector2(20.0, 20.0)
const RENDER_SIZE: Vector2i = Vector2i(640, 360)
const DEFAULT_HEIGHT_M: float = 30.0
const MIN_HEIGHT_M: float = 18.0
const MAX_HEIGHT_M: float = 60.0
const CAMERA_FOV_DEG: float = 36.0
const CAMERA_YAW_DEG: float = 12.0
const CAMERA_PITCH_DEG: float = 64.0
const FOLLOW_RESPONSE: float = 9.0
const RECENTER_SECONDS: float = 0.35

var _context: WorldContext
var _player: Node3D
var _terrain: IslandTerrain
var _mode: Mode = Mode.FOLLOW
var _focus: Vector3 = Vector3.ZERO
var _recenter_start: Vector3 = Vector3.ZERO
var _recenter_elapsed: float = 0.0
var _height_m: float = DEFAULT_HEIGHT_M
var _dragging: bool = false
var _disabled_for_release: bool = false

var _panel: PanelContainer
var _map_area: Control
var _map_container: SubViewportContainer
var _viewport: SubViewport
var _camera: Camera3D
var _marker: Label
var _mode_label: Label
var _height_label: Label
var _follow_button: Button
var _free_button: Button
var _center_button: Button


func _ready() -> void:
	if not OS.is_debug_build():
		_disabled_for_release = true
		visible = false
		queue_free()
		return
	add_to_group(GROUP)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	get_viewport().size_changed.connect(_resize_to_viewport)
	_resize_to_viewport()
	set_process(true)


func on_world_ready(context: WorldContext) -> void:
	if _disabled_for_release or context == null:
		return
	_context = context
	_player = context.player
	_terrain = context.world.find_child("IslandTerrain", true, false) as IslandTerrain if context.world != null else null
	if _player == null:
		visible = false
		return
	_focus = _player.global_position
	visible = true
	_update_camera()
	_update_marker()


func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player) or _camera == null:
		return
	match _mode:
		Mode.FOLLOW:
			var weight: float = 1.0 - exp(-FOLLOW_RESPONSE * maxf(delta, 0.0))
			_focus = _focus.lerp(_player.global_position, weight)
		Mode.RECENTERING:
			_recenter_elapsed += maxf(delta, 0.0)
			var t: float = clampf(_recenter_elapsed / RECENTER_SECONDS, 0.0, 1.0)
			var eased: float = t * t * (3.0 - 2.0 * t)
			_focus = _recenter_start.lerp(_player.global_position, eased)
			if t >= 1.0:
				_mode = Mode.FOLLOW
				_focus = _player.global_position
				_sync_controls()
		Mode.FREE:
			pass
	_update_camera()
	_update_marker()


func get_mode() -> Mode:
	return _mode


func get_height_m() -> float:
	return _height_m


func get_focus_world() -> Vector3:
	return _focus


func set_free_focus(world_position: Vector3) -> void:
	if _player == null:
		return
	_focus = world_position
	_snap_focus_to_ground()
	_mode = Mode.FREE
	_sync_controls()
	_update_camera()


func recenter() -> void:
	if _player == null:
		return
	_recenter_start = _focus
	_recenter_elapsed = 0.0
	_mode = Mode.RECENTERING
	_sync_controls()


func get_map_image() -> Image:
	if _viewport == null or _viewport.get_texture() == null:
		return null
	return _viewport.get_texture().get_image()


func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.name = "DioramaPanel"
	_panel.position = PANEL_OFFSET
	_panel.custom_minimum_size = PANEL_SIZE
	_panel.size = PANEL_SIZE
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_theme_stylebox_override("panel", _panel_style())
	add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 7)
	margin.add_theme_constant_override("margin_bottom", 8)
	_panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	margin.add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	column.add_child(header)

	var title := Label.new()
	title.text = "DEV DIORAMA"
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", Color(0.95, 0.92, 0.84))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	_mode_label = Label.new()
	_mode_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mode_label.add_theme_font_size_override("font_size", 11)
	_mode_label.add_theme_color_override("font_color", Color(0.63, 0.68, 0.72))
	header.add_child(_mode_label)

	_follow_button = _button("FOLLOW")
	_follow_button.pressed.connect(_set_follow)
	header.add_child(_follow_button)
	_free_button = _button("FREE")
	_free_button.pressed.connect(_set_free)
	header.add_child(_free_button)
	_center_button = _button("CENTER")
	_center_button.pressed.connect(recenter)
	header.add_child(_center_button)

	_height_label = Label.new()
	_height_label.custom_minimum_size.x = 42.0
	_height_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_height_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_height_label.add_theme_font_size_override("font_size", 11)
	_height_label.add_theme_color_override("font_color", Color(0.78, 0.81, 0.84))
	header.add_child(_height_label)

	_map_area = Control.new()
	_map_area.name = "MapArea"
	_map_area.custom_minimum_size = Vector2(0.0, 272.0)
	_map_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_map_area)

	_map_container = SubViewportContainer.new()
	_map_container.name = "ViewportContainer"
	_map_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_map_container.stretch = true
	_map_container.mouse_filter = Control.MOUSE_FILTER_STOP
	_map_container.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_map_container.gui_input.connect(_on_map_gui_input)
	_map_area.add_child(_map_container)

	_viewport = SubViewport.new()
	_viewport.name = "MapViewport"
	_viewport.size = RENDER_SIZE
	_viewport.own_world_3d = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_map_container.add_child(_viewport)

	_camera = Camera3D.new()
	_camera.name = "DioramaCamera"
	_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	_camera.fov = CAMERA_FOV_DEG
	_camera.near = 0.15
	_camera.far = 1200.0
	_viewport.add_child(_camera)
	_camera.make_current()

	_marker = Label.new()
	_marker.name = "HenryMarker"
	_marker.text = "●"
	_marker.custom_minimum_size = Vector2(18.0, 18.0)
	_marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_marker.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marker.add_theme_font_size_override("font_size", 18)
	_marker.add_theme_color_override("font_color", Color(1.0, 0.76, 0.24))
	_marker.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.025, 0.95))
	_marker.add_theme_constant_override("outline_size", 4)
	_map_area.add_child(_marker)

	var hint := Label.new()
	hint.text = "drag · wheel"
	hint.position = Vector2(8.0, 7.0)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color(0.86, 0.88, 0.90, 0.62))
	_map_area.add_child(hint)
	_sync_controls()


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.03, 0.035, 0.90)
	style.border_color = Color(0.52, 0.57, 0.61, 0.48)
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	return style


func _button(text_value: String) -> Button:
	var button := Button.new()
	button.text = text_value
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(52.0, 22.0)
	button.add_theme_font_size_override("font_size", 10)
	return button


func _set_follow() -> void:
	if _player == null:
		return
	_mode = Mode.FOLLOW
	_sync_controls()


func _set_free() -> void:
	if _player == null:
		return
	_mode = Mode.FREE
	_sync_controls()


func _on_map_gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null:
		if button.button_index == MOUSE_BUTTON_LEFT:
			_dragging = button.pressed
			if button.pressed and _mode != Mode.FREE:
				_mode = Mode.FREE
				_sync_controls()
			_map_container.accept_event()
			return
		if button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_set_height(_height_m * 0.88)
			_map_container.accept_event()
			return
		if button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_set_height(_height_m * 1.14)
			_map_container.accept_event()
			return

	var motion := event as InputEventMouseMotion
	if motion != null and _dragging:
		_pan(motion.relative)
		_map_container.accept_event()


func _pan(screen_delta: Vector2) -> void:
	if _camera == null or screen_delta.is_zero_approx():
		return
	_mode = Mode.FREE
	var right: Vector3 = _camera.global_basis.x
	right.y = 0.0
	right = right.normalized()
	var forward: Vector3 = -_camera.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var meters_per_pixel: float = _meters_per_pixel()
	_focus -= right * screen_delta.x * meters_per_pixel
	_focus += forward * screen_delta.y * meters_per_pixel
	_snap_focus_to_ground()
	_sync_controls()


func _meters_per_pixel() -> float:
	var display_height: float = maxf(_map_area.size.y if _map_area != null else 272.0, 1.0)
	var visible_m: float = 2.0 * _height_m * tan(deg_to_rad(CAMERA_FOV_DEG) * 0.5) * 1.7
	return visible_m / display_height


func _set_height(value: float) -> void:
	_height_m = clampf(value, MIN_HEIGHT_M, MAX_HEIGHT_M)
	_sync_controls()
	_update_camera()


func _snap_focus_to_ground() -> void:
	if _terrain == null:
		return
	_focus.y = maxf(_terrain.get_height(_focus.x, _focus.z), 0.0) + 1.0


func _update_camera() -> void:
	if _camera == null:
		return
	var target: Vector3 = _focus
	var horizontal: float = _height_m / tan(deg_to_rad(CAMERA_PITCH_DEG))
	var offset := Vector3(0.0, _height_m, horizontal)
	offset = Basis(Vector3.UP, deg_to_rad(CAMERA_YAW_DEG)) * offset
	_camera.global_position = target + offset
	_camera.look_at(target, Vector3.UP)


func _update_marker() -> void:
	if _marker == null or _camera == null or _player == null or _map_area == null:
		return
	var world_point: Vector3 = _player.global_position + Vector3.UP * 1.2
	if _camera.is_position_behind(world_point) or _map_area.size.x <= 1.0 or _map_area.size.y <= 1.0:
		_marker.visible = false
		return
	var point: Vector2 = _camera.unproject_position(world_point)
	var scale_to_panel := Vector2(
		_map_area.size.x / float(RENDER_SIZE.x),
		_map_area.size.y / float(RENDER_SIZE.y)
	)
	_marker.position = point * scale_to_panel - Vector2(9.0, 9.0)
	_marker.visible = (
		_marker.position.x > -18.0
		and _marker.position.y > -18.0
		and _marker.position.x < _map_area.size.x
		and _marker.position.y < _map_area.size.y
	)


func _sync_controls() -> void:
	if _mode_label == null:
		return
	_mode_label.text = Mode.keys()[_mode]
	_height_label.text = "%dm" % int(round(_height_m))
	_follow_button.disabled = _mode == Mode.FOLLOW
	_free_button.disabled = _mode == Mode.FREE


func _resize_to_viewport() -> void:
	size = get_viewport_rect().size
