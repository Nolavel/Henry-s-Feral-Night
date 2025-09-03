# PickupNotifier.gd - Optimized pickup notification system
extends Control

class_name PickupNotifier

# ============================================================================
# EXPORT SETTINGS - Better organization
# ============================================================================
@export_group("Visual Settings")
@export var sphere_size: int = 10
@export var sphere_color: Color = Color.GRAY
@export var rotation_radius: float = 25.0

@export_group("Animation Settings")
@export var rotation_speed: float = 8.0
@export var show_duration: float = 0.65
@export var fade_duration: float = 0.2

@export_group("Trail Settings")
@export var trail_length: int = 8
@export var trail_width: float = 3.0
@export var trail_color: Color = Color(0.7, 0.7, 0.7, 0.6)

@export_group("Performance Settings")
@export var update_frequency: float = 30.0  # Reduced from 60fps to 30fps

# ============================================================================
# CACHED COMPONENTS - Avoid repeated node searches
# ============================================================================
var sphere1: Control
var sphere2: Control
var container: Control
var trail1: Line2D
var trail2: Line2D

# Pre-allocated arrays to avoid garbage collection
var trail_points1: PackedVector2Array
var trail_points2: PackedVector2Array

# Cached textures to avoid recreation
var _cached_sphere_texture: ImageTexture
var _cached_width_curve: Curve
var _cached_gradient: Gradient

# ============================================================================
# OPTIMIZED STATE VARIABLES
# ============================================================================
var is_showing: bool = false
var rotation_angle: float = 0.0
var current_tween: Tween

# Performance optimization
var _update_timer: float = 0.0
var _update_interval: float
var _center_position: Vector2  # Cached center position
var _half_sphere_size: float   # Cached half sphere size

# Animation reference
@onready var animation = $Pickup_spritePN/Anima_spritePN

# ============================================================================
# INITIALIZATION - Optimized setup
# ============================================================================
func _ready():
	# Calculate update interval
	_update_interval = 1.0 / update_frequency
	
	# Cache common calculations
	_half_sphere_size = sphere_size * 0.5
	
	# Initialize with hidden state
	visible = false
	modulate.a = 0.0
	
	# Setup components in order
	_setup_main_container()
	_create_cached_resources()
	_create_spheres_optimized()
	_create_trails_optimized()
	
	# Pre-allocate trail arrays
	trail_points1 = PackedVector2Array()
	trail_points2 = PackedVector2Array()
	trail_points1.resize(trail_length)
	trail_points2.resize(trail_length)
	
	# Initialize with zero vectors
	trail_points1.fill(Vector2.ZERO)
	trail_points2.fill(Vector2.ZERO)

func _setup_main_container():
	"""Optimized container setup"""
	container = Control.new()
	container.name = "SphereContainer"
	add_child(container)
	
	# Cache center position
	container.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	var container_size = Vector2(rotation_radius * 2 + sphere_size, rotation_radius * 2 + sphere_size)
	container.size = container_size
	container.position = -container_size * 0.5
	
	# Cache center for later use
	_center_position = container_size * 0.5

func _create_cached_resources():
	"""Create reusable resources once"""
	# Cache sphere texture
	_cached_sphere_texture = _create_optimized_circle_texture(sphere_size, sphere_color)
	
	# Cache width curve for trails
	_cached_width_curve = Curve.new()
	_cached_width_curve.add_point(Vector2(0.0, 1.0))
	_cached_width_curve.add_point(Vector2(0.5, 0.6))
	_cached_width_curve.add_point(Vector2(1.0, 0.1))
	
	# Cache gradient for trails
	_cached_gradient = Gradient.new()
	_cached_gradient.add_point(0.0, Color(trail_color.r, trail_color.g, trail_color.b, 0.8))
	_cached_gradient.add_point(0.6, Color(trail_color.r, trail_color.g, trail_color.b, 0.4))
	_cached_gradient.add_point(1.0, Color(trail_color.r, trail_color.g, trail_color.b, 0.0))

func _create_optimized_circle_texture(size: int, color: Color) -> ImageTexture:
	"""Optimized circle texture creation"""
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center = Vector2(size * 0.5, size * 0.5)
	var radius = size * 0.5 - 1
	var radius_sq = radius * radius  # Use squared distance to avoid sqrt
	
	# Optimized circle drawing
	for x in range(size):
		for y in range(size):
			var dx = x - center.x
			var dy = y - center.y
			var distance_sq = dx * dx + dy * dy
			
			if distance_sq <= radius_sq:
				var alpha = 1.0
				# Simple antialiasing only on edges
				var distance = sqrt(distance_sq)
				if distance > radius - 1.0:
					alpha = 1.0 - (distance - (radius - 1.0))
				
				img.set_pixel(x, y, Color(color.r, color.g, color.b, color.a * alpha))
			else:
				img.set_pixel(x, y, Color.TRANSPARENT)
	
	var texture = ImageTexture.new()
	texture.set_image(img)
	return texture

func _create_spheres_optimized():
	"""Optimized sphere creation using cached texture"""
	sphere1 = _create_single_sphere("Sphere1")
	container.add_child(sphere1)
	
	sphere2 = _create_single_sphere("Sphere2")
	container.add_child(sphere2)

func _create_single_sphere(sphere_name: String) -> Control:
	"""Create optimized sphere using cached texture"""
	var sphere = Control.new()
	sphere.name = sphere_name
	sphere.size = Vector2(sphere_size, sphere_size)
	
	var sphere_texture_rect = TextureRect.new()
	sphere_texture_rect.name = "SphereVisual"
	sphere_texture_rect.size = Vector2(sphere_size, sphere_size)
	sphere_texture_rect.texture = _cached_sphere_texture
	sphere_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sphere.add_child(sphere_texture_rect)
	
	return sphere

func _create_trails_optimized():
	"""Optimized trail creation"""
	trail1 = _create_single_trail("Trail1")
	container.add_child(trail1)
	
	trail2 = _create_single_trail("Trail2")
	container.add_child(trail2)

func _create_single_trail(trail_name: String) -> Line2D:
	"""Create optimized trail with cached resources"""
	var trail = Line2D.new()
	trail.name = trail_name
	trail.width = trail_width
	trail.default_color = trail_color
	trail.joint_mode = Line2D.LINE_JOINT_ROUND
	trail.begin_cap_mode = Line2D.LINE_CAP_ROUND
	trail.end_cap_mode = Line2D.LINE_CAP_ROUND
	trail.antialiased = true
	
	# Use cached resources
	trail.width_curve = _cached_width_curve
	trail.gradient = _cached_gradient
	
	return trail

# ============================================================================
# OPTIMIZED PHYSICS PROCESS - Moved from _process
# ============================================================================
func _physics_process(delta):
	"""Optimized update loop using physics process"""
	if not is_showing or not visible:
		return
	
	# Update with controlled frequency
	_update_timer += delta
	if _update_timer >= _update_interval:
		_update_rotation_and_positions(_update_timer)
		_update_trails_optimized()
		_update_timer = 0.0
	else:
		# Still update rotation every frame for smooth visual
		rotation_angle += rotation_speed * delta
		if rotation_angle > TAU:
			rotation_angle -= TAU

func _update_rotation_and_positions(delta: float):
	"""Optimized position updates"""
	if not sphere1 or not sphere2:
		return
	
	# Pre-calculate trigonometric values
	var cos_angle = cos(rotation_angle)
	var sin_angle = sin(rotation_angle)
	
	# Calculate positions using cached values
	var pos1 = Vector2(
		_center_position.x + cos_angle * rotation_radius - _half_sphere_size,
		_center_position.y + sin_angle * rotation_radius - _half_sphere_size
	)
	
	var pos2 = Vector2(
		_center_position.x - cos_angle * rotation_radius - _half_sphere_size,
		_center_position.y - sin_angle * rotation_radius - _half_sphere_size
	)
	
	sphere1.position = pos1
	sphere2.position = pos2

func _update_trails_optimized():
	"""Optimized trail updates using PackedVector2Array"""
	if not trail1 or not trail2:
		return
	
	# Pre-calculate trigonometric values
	var cos_angle = cos(rotation_angle)
	var sin_angle = sin(rotation_angle)
	
	# Calculate sphere centers
	var sphere1_center = Vector2(
		_center_position.x + cos_angle * rotation_radius,
		_center_position.y + sin_angle * rotation_radius
	)
	
	var sphere2_center = Vector2(
		_center_position.x - cos_angle * rotation_radius,
		_center_position.y - sin_angle * rotation_radius
	)
	
	# Shift trail points efficiently
	for i in range(trail_length - 1, 0, -1):
		trail_points1[i] = trail_points1[i - 1]
		trail_points2[i] = trail_points2[i - 1]
	
	# Add new points
	trail_points1[0] = sphere1_center
	trail_points2[0] = sphere2_center
	
	# Update Line2D trails
	_update_single_trail(trail1, trail_points1)
	_update_single_trail(trail2, trail_points2)

func _update_single_trail(trail_line: Line2D, points: PackedVector2Array):
	"""Optimized trail line update"""
	trail_line.clear_points()
	
	# Add only valid points (non-zero)
	for point in points:
		if point != Vector2.ZERO:
			trail_line.add_point(point)

# ============================================================================
# OPTIMIZED NOTIFICATION METHODS
# ============================================================================
func show_pickup_notification():
	"""Optimized notification display"""
	if is_showing:
		return
	animation.play("pulse")
	is_showing = true
	visible = true
	rotation_angle = 0.0
	

	animation.play("pulse")
	
	# Clear trails efficiently
	_clear_trails_optimized()
	
	# Stop existing tween
	if current_tween:
		current_tween.kill()
	
	modulate.a = 0.0
	
	# Create optimized tween
	current_tween = create_tween()
	current_tween.set_parallel(true)
	
	# Fade in
	current_tween.tween_property(self, "modulate:a", 1.0, fade_duration)
	
	# Auto-hide with delay
	current_tween.tween_callback(hide_notification).set_delay(show_duration - fade_duration)

func hide_notification():
	"""Optimized notification hiding"""
	if not is_showing:
		return
	
	if current_tween:
		current_tween.kill()
	
	current_tween = create_tween()
	current_tween.tween_property(self, "modulate:a", 0.0, fade_duration)
	
	current_tween.finished.connect(_on_hide_complete, CONNECT_ONE_SHOT)

func _on_hide_complete():
	"""Cleanup after hiding"""
	visible = false
	is_showing = false
	rotation_angle = 0.0
	_clear_trails_optimized()

func _clear_trails_optimized():
	"""Optimized trail clearing"""
	if trail1:
		trail1.clear_points()
	if trail2:
		trail2.clear_points()
	
	# Reset arrays efficiently
	trail_points1.fill(Vector2.ZERO)
	trail_points2.fill(Vector2.ZERO)

# ============================================================================
# PUBLIC API - Optimized methods
# ============================================================================
func trigger_pickup_notification():
	"""Public method to trigger notification"""
	show_pickup_notification()

func is_notification_showing() -> bool:
	"""Check if notification is active"""
	return is_showing

func set_sphere_color(new_color: Color):
	"""Optimized color change with texture caching"""
	if sphere_color == new_color:
		return  # No change needed
	
	sphere_color = new_color
	trail_color = Color(new_color.r * 0.8, new_color.g * 0.8, new_color.b * 0.8, 0.6)
	
	# Recreate cached texture
	_cached_sphere_texture = _create_optimized_circle_texture(sphere_size, new_color)
	
	# Update sphere textures
	_update_sphere_textures()
	
	# Update trail colors
	_update_trail_colors()

func _update_sphere_textures():
	"""Update sphere textures with cached texture"""
	var spheres = [sphere1, sphere2]
	for sphere in spheres:
		if sphere and sphere.has_node("SphereVisual"):
			var texture_rect = sphere.get_node("SphereVisual") as TextureRect
			texture_rect.texture = _cached_sphere_texture

func _update_trail_colors():
	"""Update trail colors efficiently"""
	var trails = [trail1, trail2]
	for trail in trails:
		if trail:
			trail.default_color = trail_color
	
	# Update cached gradient
	_cached_gradient = Gradient.new()
	_cached_gradient.add_point(0.0, Color(trail_color.r, trail_color.g, trail_color.b, 0.8))
	_cached_gradient.add_point(0.6, Color(trail_color.r, trail_color.g, trail_color.b, 0.4))
	_cached_gradient.add_point(1.0, Color(trail_color.r, trail_color.g, trail_color.b, 0.0))
	
	# Apply to trails
	for trail in trails:
		if trail:
			trail.gradient = _cached_gradient

func set_rotation_speed(new_speed: float):
	"""Optimized speed change"""
	rotation_speed = new_speed

func set_show_duration(new_duration: float):
	"""Optimized duration change"""
	show_duration = new_duration

func set_update_frequency(new_frequency: float):
	"""Change update frequency for performance tuning"""
	update_frequency = clamp(new_frequency, 10.0, 60.0)  # Reasonable limits
	_update_interval = 1.0 / update_frequency

# ============================================================================
# SIGNAL INTEGRATION
# ============================================================================
func _on_item_picked_up(item_name: String = ""):
	"""Signal handler for item pickup"""
	trigger_pickup_notification()

# ============================================================================
# PERFORMANCE MONITORING
# ============================================================================
func get_performance_stats() -> Dictionary:
	"""Get performance statistics for debugging"""
	return {
		"update_frequency": update_frequency,
		"trail_length": trail_length,
		"is_showing": is_showing,
		"cached_textures": _cached_sphere_texture != null,
		"cached_resources": _cached_width_curve != null and _cached_gradient != null
	}
