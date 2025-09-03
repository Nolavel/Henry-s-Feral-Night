extends Control 

# ============================================================================
# EXPORT VARIABLES - Grouped for better organization
# ============================================================================
@export_group("Minimap Settings")
@export var minimap_radius: float = 100.0
@export var compass_offset: float = 25.0
@export var minimap_scale: float = 0.1
@export var min_marker_distance: float = 20.0

@export_group("Player References")
@export var player_node_path: NodePath
@export var player_head_node_path: NodePath 
@export var player_marker_radius: float = 5.0

@export_group("Movement Arrow")
@export var show_movement_arrow: bool = true
@export var movement_threshold: float = 0.01
@export var arrow_head_size: float = 12.0
@export var arrow_head_width: float = 4.0
@export var arrow_distance_from_player: float = 20.0
@export var movement_arrow_color: Color = Color.CYAN

@export_group("Compass")
@export var compass_font_size_min: float = 14.0
@export var compass_font_size_max: float = 22.0
@export var compass_lerp_speed: float = 5.0
@export var compass_activation_angle: float = 30.0

@export_group("Performance Settings")
@export var physics_update_frequency: float = 30.0  # Reduced from 60
@export var compass_update_frequency: float = 15.0  # Reduced from 30

@export_group("Objective & Enemy Settings")
@export var show_objective_pointer: bool = true
@export var objective_arrow_color: Color = Color.BLUE
@export var objective_arrow_size: float = 15.0
@export var show_enemy_indicators: bool = true
@export var enemy_detection_range: float = 100.0
@export var enemy_color_hostile: Color = Color.RED
@export var enemy_triangle_size: float = 6.0

# ============================================================================
# CORE VARIABLES - Optimized structure
# ============================================================================
@onready var minimap_camera := $"../../../MinimapViewport/MinimapCamera"

var player: Node3D = null
var player_head: Node3D = null

# Pre-allocated arrays to avoid garbage collection
var compass_labels: Array = []
var object_markers_data: Array = []
var objective_objects: Array = []
var detected_enemies: Array = []

var player_marker_container: Control = null

# ============================================================================
# CACHED VALUES - Better performance through caching
# ============================================================================
var minimap_center: Vector2
var player_previous_position: Vector3
var movement_direction: Vector2
var is_moving: bool = false

# Compass caching
var compass_target_sizes: Dictionary = {}
var compass_current_sizes: Dictionary = {}
var cached_player_rotation: float = 0.0

# Performance timers - using physics delta
var main_update_timer: float = 0.0
var compass_update_timer: float = 0.0
var main_update_interval: float
var compass_update_interval: float

# Reusable variables to avoid allocations
var _temp_vector3: Vector3
var _temp_vector2: Vector2

# ============================================================================
# INITIALIZATION
# ============================================================================
func _ready():
	# Calculate intervals based on physics frequency
	main_update_interval = 1.0 / physics_update_frequency
	compass_update_interval = 1.0 / compass_update_frequency
	
	# Initialize player references
	_initialize_player_references()
	if not player:
		return
	
	# Cache minimap center once
	minimap_center = Vector2(minimap_radius + compass_offset, minimap_radius + compass_offset)
	
	# Setup UI properties
	_setup_ui_properties()
	
	# Initialize position tracking
	player_previous_position = player.global_transform.origin
	
	# Create UI elements
	_create_all_ui_elements()
	
	# Find game objects
	_find_game_objects()

func _initialize_player_references():
	"""Centralized player reference initialization"""
	if player_node_path:
		player = get_node_or_null(player_node_path)
	if player_head_node_path:
		player_head = get_node_or_null(player_head_node_path)
	
	if not player:
		printerr("Minimap: Player node not found!")
		set_physics_process(false)

func _setup_ui_properties():
	"""Setup UI sizing and positioning"""
	custom_minimum_size = Vector2(
		minimap_radius * 2 + compass_offset * 2, 
		minimap_radius * 2 + compass_offset * 2
	)
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_CENTER

func _create_all_ui_elements():
	"""Create all UI elements in order"""
	create_compass_labels()
	create_player_marker()

func _find_game_objects():
	"""Find and initialize all game objects"""
	find_and_create_object_markers()
	find_objective_objects()
	find_enemy_objects()

# ============================================================================
# PHYSICS PROCESS - Main update loop moved to physics
# ============================================================================
func _physics_process(delta):
	if not player:
		return
	
	# Lightweight movement tracking every physics frame
	_update_player_movement_physics(delta)
	
	# Update player marker position (lightweight)
	_update_player_marker_physics()
	
	# Main updates with controlled frequency
	main_update_timer += delta
	if main_update_timer >= main_update_interval:
		_update_object_markers_physics(main_update_timer)
		main_update_timer = 0.0
	
	# Compass updates with lower frequency
	compass_update_timer += delta
	if compass_update_timer >= compass_update_interval:
		_update_compass_labels_physics(compass_update_timer)
		_update_detected_enemies_physics()
		compass_update_timer = 0.0
	
	# Queue redraw for visual updates
	queue_redraw()

# ============================================================================
# OPTIMIZED PHYSICS UPDATES
# ============================================================================
func _update_player_movement_physics(delta: float):
	"""Physics-based movement tracking - more stable"""
	_temp_vector3 = player.global_transform.origin
	
	if delta > 0.0:
		var velocity_3d = (_temp_vector3 - player_previous_position) / delta
		var speed = velocity_3d.length()
		is_moving = speed > movement_threshold
		
		if is_moving:
			# Cache 2D movement direction
			movement_direction.x = velocity_3d.x
			movement_direction.y = velocity_3d.z
			movement_direction = movement_direction.normalized()
	
	player_previous_position = _temp_vector3

func _update_player_marker_physics():
	"""Physics-based player marker update"""
	if player_marker_container:
		player_marker_container.position = minimap_center
		player_marker_container.visible = true

func _update_object_markers_physics(delta: float):
	"""Optimized object marker updates in physics"""
	if object_markers_data.is_empty():
		return
	
	var camera = minimap_camera
	if not camera:
		return
	
	var marker_constraint_radius = minimap_radius + 18
	var player_pos = player.global_transform.origin
	
	# Cache player rotation once per update
	cached_player_rotation = _get_player_rotation_cached()
	
	# Batch process all markers
	var visible_count = 0
	for item in object_markers_data:
		if not _process_single_marker_physics(item, camera, marker_constraint_radius, player_pos, delta):
			continue
		visible_count += 1
	
	# Optional debug info
	if visible_count > 10:  # Only log when many markers are visible
		print("Minimap: Processing ", visible_count, " visible markers")

func _process_single_marker_physics(item: Dictionary, camera: Camera3D, constraint_radius: float, player_pos: Vector3, delta: float) -> bool:
	"""Process a single marker - returns true if visible"""
	var obj = item.object
	if not is_instance_valid(obj):
		item.container.visible = false
		return false

	var obj_pos = obj.global_transform.origin
	var distance_to_object = player_pos.distance_to(obj_pos)

	# Hide very close objects
	if distance_to_object < 2.0:
		item.container.visible = false
		return false

	# Project position
	var projected_pos = camera.unproject_position(obj_pos)
	var is_behind = camera.is_position_behind(obj_pos)
	
	var final_pos = projected_pos
	
	# Handle off-screen objects
	if is_behind or (projected_pos - minimap_center).length() > constraint_radius:
		final_pos = _calculate_constrained_position(obj_pos, player_pos, projected_pos, is_behind, constraint_radius)
	
	# Update marker position with smooth interpolation
	var target_pos = final_pos - item.container.size * 0.5
	item.container.position = item.container.position.lerp(target_pos, delta * 8.0)
	item.container.visible = true
	
	# Update distance label
	item.distance_label.text = str(int(distance_to_object)) + "m"
	
	return true

func _calculate_constrained_position(obj_pos: Vector3, player_pos: Vector3, projected_pos: Vector2, is_behind: bool, constraint_radius: float) -> Vector2:
	"""Calculate constrained position for off-screen objects"""
	var dir_to_object: Vector2
	
	if is_behind:
		var world_dir = (obj_pos - player_pos).normalized()
		dir_to_object.x = world_dir.x * cos(-cached_player_rotation) - world_dir.z * sin(-cached_player_rotation)
		dir_to_object.y = world_dir.x * sin(-cached_player_rotation) + world_dir.z * cos(-cached_player_rotation)
		dir_to_object = dir_to_object.normalized()
	else:
		dir_to_object = (projected_pos - minimap_center).normalized()
	
	return minimap_center + dir_to_object * constraint_radius

func _update_compass_labels_physics(delta: float):
	"""Physics-based compass updates"""
	if compass_labels.is_empty():
		return
	
	var player_angle_deg = rad_to_deg(cached_player_rotation)
	
	# Normalize angle (optimized)
	player_angle_deg = fmod(player_angle_deg + 360.0, 360.0)
	
	for compass_data in compass_labels:
		var compass_text = compass_data.text
		var angle_diff = abs(player_angle_deg - compass_data.base_angle)
		
		# Handle wrap-around
		if angle_diff > 180.0:
			angle_diff = 360.0 - angle_diff
		
		var target_size = compass_font_size_min
		if angle_diff <= compass_activation_angle:
			var proximity_factor = 1.0 - (angle_diff / compass_activation_angle)
			target_size = lerp(compass_font_size_min, compass_font_size_max, proximity_factor)
		
		# Smooth size interpolation
		compass_target_sizes[compass_text] = target_size
		compass_current_sizes[compass_text] = lerp(
			compass_current_sizes[compass_text], 
			target_size, 
			delta * compass_lerp_speed
		)
		
		compass_data.label.add_theme_font_size_override("font_size", int(compass_current_sizes[compass_text]))

func _update_detected_enemies_physics():
	"""Physics-based enemy detection"""
	detected_enemies.clear()
	var all_enemies = get_tree().get_nodes_in_group("enemies")
	var player_pos = player.global_transform.origin
	
	for enemy in all_enemies:
		if not is_instance_valid(enemy):
			continue
		
		var distance = player_pos.distance_to(enemy.global_transform.origin)
		if distance <= enemy_detection_range:
			detected_enemies.append(enemy)

# ============================================================================
# OPTIMIZED HELPER FUNCTIONS
# ============================================================================
func _get_player_rotation_cached() -> float:
	"""Cached player rotation calculation"""
	var basis = player_head.global_transform.basis if player_head else player.global_transform.basis
	var forward = -basis.z
	return atan2(forward.x, -forward.z)

# ============================================================================
# UI CREATION FUNCTIONS - Unchanged but organized
# ============================================================================
func create_compass_labels():
	"""Create static compass with optimized structure"""
	var directions = [
		{"text": "N", "angle": 0}, {"text": "NE", "angle": 45},
		{"text": "E", "angle": 90}, {"text": "SE", "angle": 135},
		{"text": "S", "angle": 180}, {"text": "SW", "angle": 225},
		{"text": "W", "angle": 270}, {"text": "NW", "angle": 315}
	]
	
	var display_radius = minimap_radius + compass_offset
	
	# Pre-allocate array
	compass_labels.resize(directions.size())
	
	for i in range(directions.size()):
		var dir = directions[i]
		var label = Label.new()
		label.text = dir.text
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", int(compass_font_size_min))
		
		# Set colors
		if dir.text in ["N", "S", "E", "W"]:
			label.add_theme_color_override("font_color", Color.WHITE)
		else:
			label.add_theme_color_override("font_color", Color.GAINSBORO)
		
		label.z_index = 100
		
		# Position calculation
		var angle_rad = deg_to_rad(dir.angle)
		var pos = minimap_center + Vector2(sin(angle_rad), -cos(angle_rad)) * display_radius
		label.position = pos - label.size * 0.5
		
		add_child(label)
		compass_labels[i] = {"label": label, "base_angle": dir.angle, "text": dir.text}
		
		# Initialize size dictionaries
		compass_target_sizes[dir.text] = compass_font_size_min
		compass_current_sizes[dir.text] = compass_font_size_min

func create_player_marker():
	"""Create player marker with optimized materials"""
	player_marker_container = Control.new()
	player_marker_container.z_index = 200
	add_child(player_marker_container)

	# Create reusable shader
	var circle_shader = _create_optimized_circle_shader()

	# Black circle background
	var player_circle = ColorRect.new()
	player_circle.size = Vector2(player_marker_radius * 2, player_marker_radius * 2)
	player_circle.color = Color.BLACK
	player_circle.material = circle_shader
	player_marker_container.add_child(player_circle)

	# Gray center dot
	var player_dot = ColorRect.new()
	player_dot.size = Vector2(player_marker_radius, player_marker_radius)
	player_dot.color = Color.LIGHT_GRAY
	player_dot.material = circle_shader.duplicate()
	player_dot.position = (player_circle.size - player_dot.size) * 0.5
	player_marker_container.add_child(player_dot)

func _create_optimized_circle_shader() -> ShaderMaterial:
	"""Optimized shader for circular elements"""
	var circle_shader = ShaderMaterial.new()
	var shader = Shader.new()
	shader.code = """
		shader_type canvas_item;
		uniform float radius : hint_range(0.0, 1.0) = 0.5;
		
		void fragment() {
			vec2 uv_centered = UV - vec2(0.5);
			float dist = length(uv_centered);
			
			if (dist > radius) {
				discard;
			}
			
			COLOR = texture(TEXTURE, UV) * COLOR;
		}
	"""
	circle_shader.shader = shader
	circle_shader.set_shader_parameter("radius", 0.5)
	return circle_shader

func find_and_create_object_markers():
	"""Find and create object markers with optimization"""
	var tracked_objects = get_tree().get_nodes_in_group("tracking_objects")
	
	# Pre-allocate array
	object_markers_data.resize(tracked_objects.size())
	var valid_count = 0
	
	for obj in tracked_objects:
		if obj is Node3D and obj != player: 
			object_markers_data[valid_count] = _create_marker_data_for_object(obj)
			valid_count += 1
	
	# Resize to actual count
	object_markers_data.resize(valid_count)

func _create_marker_data_for_object(obj: Node3D) -> Dictionary:
	"""Create marker data structure for object"""
	var container = Control.new()
	container.z_index = 101
	add_child(container)
	
	var marker = ColorRect.new()
	marker.size = Vector2(8, 8)
	marker.color = Color.YELLOW
	marker.position = -marker.size * 0.5
	container.add_child(marker)
	
	var distance_label = Label.new()
	distance_label.text = "0m"
	distance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	distance_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	distance_label.add_theme_font_size_override("font_size", 14)
	distance_label.add_theme_color_override("font_color", Color.WHITE)
	distance_label.position = Vector2(-15, marker.size.y * 0.5 + 2)
	distance_label.size = Vector2(30, 15)
	container.add_child(distance_label)
	
	return {
		"container": container,
		"marker": marker,
		"distance_label": distance_label,
		"object": obj,
		"name": obj.name
	}

# ============================================================================
# DRAWING FUNCTIONS - Optimized for performance
# ============================================================================
func _draw():
	# Movement arrow
	if show_movement_arrow and is_moving:
		_draw_movement_arrow()
	
	if show_objective_pointer:
		_draw_objective_pointers()
		
	if show_enemy_indicators:
		_draw_enemy_indicators()

func _draw_movement_arrow():
	"""Optimized movement arrow drawing"""
	var player_marker_center = minimap_center + Vector2(player_marker_radius, player_marker_radius)
	var total_distance = player_marker_radius + arrow_distance_from_player
	var arrow_tip = player_marker_center + movement_direction * total_distance
	_draw_large_arrow_head(arrow_tip, movement_direction, movement_arrow_color, arrow_head_width)

func _draw_large_arrow_head(tip_pos: Vector2, direction: Vector2, color: Color, width: float):
	"""Optimized arrow head drawing"""
	var head_length = arrow_head_size
	var base_angle = direction.angle()
	var angle1 = base_angle + PI * 0.8
	var angle2 = base_angle - PI * 0.8
	
	var head_point1 = tip_pos + Vector2(cos(angle1), sin(angle1)) * head_length
	var head_point2 = tip_pos + Vector2(cos(angle2), sin(angle2)) * head_length
	
	draw_line(tip_pos, head_point1, color, width)
	draw_line(tip_pos, head_point2, color, width)

# ============================================================================
# OBJECTIVE AND ENEMY DRAWING - Optimized versions
# ============================================================================
func find_objective_objects():
	"""Find objective objects with error checking"""
	objective_objects = get_tree().get_nodes_in_group("objective_pointer")
	print("Minimap: Found objectives: ", objective_objects.size())

func find_enemy_objects():
	"""Find enemy objects - placeholder for future implementation"""
	print("Minimap: Looking for enemies in 'enemies' group")

func _draw_objective_pointers():
	"""Optimized objective pointer drawing"""
	if not minimap_camera:
		return
		
	var marker_constraint_radius = minimap_radius + 18
	
	for obj in objective_objects:
		if not is_instance_valid(obj):
			continue
			
		var obj_pos = obj.global_transform.origin
		var player_pos = player.global_transform.origin
		var distance_to_object = player_pos.distance_to(obj_pos)
		
		var projected_pos = minimap_camera.unproject_position(obj_pos)
		var is_behind = minimap_camera.is_position_behind(obj_pos)
		
		var final_pos = projected_pos
		
		if is_behind or (projected_pos - minimap_center).length() > marker_constraint_radius:
			var dir_to_object = _calculate_direction_to_object(obj_pos, player_pos, projected_pos, is_behind)
			final_pos = minimap_center + dir_to_object * marker_constraint_radius
			_draw_objective_arrow(final_pos, dir_to_object, distance_to_object)
		else:
			_draw_objective_marker(projected_pos, distance_to_object)

func _calculate_direction_to_object(obj_pos: Vector3, player_pos: Vector3, projected_pos: Vector2, is_behind: bool) -> Vector2:
	"""Calculate direction to object for edge placement"""
	var dir_to_object: Vector2
	
	if is_behind:
		var world_dir = (obj_pos - player_pos).normalized()
		dir_to_object.x = world_dir.x * cos(-cached_player_rotation) - world_dir.z * sin(-cached_player_rotation)
		dir_to_object.y = world_dir.x * sin(-cached_player_rotation) + world_dir.z * cos(-cached_player_rotation)
		dir_to_object = dir_to_object.normalized()
	else:
		dir_to_object = (projected_pos - minimap_center).normalized()
	
	return dir_to_object

func _draw_objective_marker(pos: Vector2, distance: float):
	"""Draw objective marker inside minimap"""
	var size = 13.5
	
	draw_circle(pos, size, objective_arrow_color)
	draw_arc(pos, size, 0, TAU, 40, Color.WHITE, 3.0)
	
	# Exclamation mark
	var exclamation_width = 4.0
	var line_height = size * 0.6
	var dot_size = 2.0
	
	var line_start = pos + Vector2(0, -line_height * 0.5)
	var line_end = pos + Vector2(0, line_height * 0.5 - 3)
	draw_line(line_start, line_end, Color.WHITE, exclamation_width)
	
	var dot_pos = pos + Vector2(0, line_height * 0.5)
	draw_circle(dot_pos, dot_size, Color.WHITE)
	
	_draw_distance_label(pos, distance)

func _draw_objective_arrow(pos: Vector2, direction: Vector2, distance: float):
	"""Draw objective arrow on minimap edge"""
	var arrow_size = objective_arrow_size * 1.2
	var angle = direction.angle()
	
	var tip = pos
	var base_left = pos + Vector2(cos(angle + PI * 0.8), sin(angle + PI * 0.8)) * arrow_size
	var base_right = pos + Vector2(cos(angle - PI * 0.8), sin(angle - PI * 0.8)) * arrow_size
	
	var triangle_points = PackedVector2Array([tip, base_left, base_right])
	
	draw_colored_polygon(triangle_points, objective_arrow_color)
	
	# Dark outline
	for i in range(triangle_points.size()):
		var next_i = (i + 1) % triangle_points.size()
		draw_line(triangle_points[i], triangle_points[next_i], Color.DARK_BLUE, 1.5)
	
	_draw_distance_label(pos, distance)

func _draw_distance_label(pos: Vector2, distance: float):
	"""Optimized distance label drawing"""
	var distance_text = str(int(distance)) + "m"
	var text_pos = pos + Vector2(0, 32.5)
	
	var font = ThemeDB.fallback_font
	var font_size = 12
	var text_size = font.get_string_size(distance_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	
	# Black outline for contrast
	for offset_x in range(-1, 2):
		for offset_y in range(-1, 2):
			if offset_x != 0 or offset_y != 0:
				draw_string(font, text_pos + Vector2(offset_x, offset_y) - text_size * 0.5, distance_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color.BLACK)
	
	# White main text
	draw_string(font, text_pos - text_size * 0.5, distance_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color.WHITE)

func _draw_enemy_indicators():
	"""Optimized enemy indicator drawing"""
	if not minimap_camera:
		return
		
	var marker_constraint_radius = minimap_radius + 18
	
	for enemy in detected_enemies:
		if not is_instance_valid(enemy):
			continue
			
		var enemy_pos = enemy.global_transform.origin
		var player_pos = player.global_transform.origin
		
		var projected_pos = minimap_camera.unproject_position(enemy_pos)
		var is_behind = minimap_camera.is_position_behind(enemy_pos)
		
		var final_pos = projected_pos
		
		if is_behind or (projected_pos - minimap_center).length() > marker_constraint_radius:
			var dir_to_enemy = _calculate_direction_to_object(enemy_pos, player_pos, projected_pos, is_behind)
			final_pos = minimap_center + dir_to_enemy * marker_constraint_radius
			_draw_enemy_triangle(final_pos, enemy_triangle_size * 1.2, enemy_color_hostile)
		else:
			_draw_enemy_triangle(projected_pos, enemy_triangle_size, enemy_color_hostile)

func _draw_enemy_triangle(pos: Vector2, size: float, color: Color):
	"""Draw optimized enemy triangle"""
	var big_size = size * 1.8
	
	var points = PackedVector2Array([
		pos + Vector2(0, -big_size),
		pos + Vector2(-big_size * 0.8, big_size * 0.6),
		pos + Vector2(big_size * 0.8, big_size * 0.6)
	])
	
	draw_colored_polygon(points, color)
	
	# Thick dark outline
	for i in range(points.size()):
		var next_i = (i + 1) % points.size()
		draw_line(points[i], points[next_i], Color.DARK_RED, 2.5)
	
	# Inner highlight
	var inner_size = big_size * 0.7
	var inner_points = PackedVector2Array([
		pos + Vector2(0, -inner_size),
		pos + Vector2(-inner_size * 0.8, inner_size * 0.6),
		pos + Vector2(inner_size * 0.8, inner_size * 0.6)
	])
	
	for i in range(inner_points.size()):
		var next_i = (i + 1) % inner_points.size()
		draw_line(inner_points[i], inner_points[next_i], Color.LIGHT_CORAL, 1.0)

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================
func refresh_tracked_objects():
	"""Refresh the list of tracked objects"""
	for item in object_markers_data:
		if is_instance_valid(item.container):
			item.container.queue_free()
	object_markers_data.clear()
	find_and_create_object_markers()

func set_movement_arrow_settings(show: bool, size: float = 12.0, width: float = 4.0, color: Color = Color.CYAN):
	"""Configure movement arrow settings"""
	show_movement_arrow = show
	arrow_head_size = size
	arrow_head_width = width
	movement_arrow_color = color

func refresh_enemy_objects():
	"""Refresh enemy objects list"""
	find_enemy_objects()
