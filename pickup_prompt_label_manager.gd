# InteractionHintUI.gd - Optimized interaction hint system
extends Control
class_name InteractionHintUI

# ============================================================================
# EXPORT SETTINGS
# ============================================================================
@export_group("Visual Settings")
@export var font_file: FontFile
@export var triangle_size: float = 12.0

@export_group("Colors")
@export var pickup_color: Color = Color("#FF8C42")  # Orange - available
@export var blocked_color: Color = Color("#CC2936") # Red - error/no space
@export var white_color: Color = Color("#F5F5F5")   # White for key

@export_group("Performance")
@export var enable_triangle_updates: bool = true  # Can disable for performance

# ============================================================================
# CACHED COMPONENTS
# ============================================================================
var pickup_label: RichTextLabel
var triangle_container: Control  # Container for all triangles

# Triangles stored in array for efficient iteration
var triangles: Array[Polygon2D] = []

# ============================================================================
# OPTIMIZED STATE MANAGEMENT
# ============================================================================
enum PromptState { SHOWN, HIDDEN }
var current_state: PromptState = PromptState.HIDDEN

enum ActionType {
	PICKUP, NO_SPACE, OPEN, CLOSE, SEARCH, TURN_ON, 
	TURN_OFF, TALK, OPERATE, PULL, PRESS, LOOT
}

# Cached values to avoid repeated calculations
var _cached_control_size: Vector2
var _last_known_size: Vector2
var _size_changed: bool = false

# Pre-formatted action text cache
var _action_text_cache: Dictionary = {}
var _bbcode_cache: Dictionary = {}

# ============================================================================
# INITIALIZATION
# ============================================================================
func _ready():
	add_to_group("InteractionHintUI")
	visible = false
	
	# Cache action texts
	_build_action_text_cache()
	
	# Create optimized UI
	_create_optimized_ui()
	_setup_optimized_components()

func _build_action_text_cache():
	"""Pre-build action text cache for performance"""
	_action_text_cache = {
		ActionType.PICKUP: "Pick Up",
		ActionType.NO_SPACE: "No Space",
		ActionType.OPEN: "Open",
		ActionType.CLOSE: "Close",
		ActionType.SEARCH: "Search",
		ActionType.TURN_ON: "Turn On",
		ActionType.TURN_OFF: "Turn Off",
		ActionType.TALK: "Talk",
		ActionType.OPERATE: "Operate",
		ActionType.PULL: "Pull",
		ActionType.PRESS: "Press",
		ActionType.LOOT: "Loot"
	}

func _create_optimized_ui():
	"""Create UI with optimized structure"""
	# Set fixed size
	var label_width = 160
	var label_height = 40
	
	custom_minimum_size = Vector2(label_width, label_height)
	size = Vector2(label_width, label_height)
	_cached_control_size = size
	_last_known_size = size

	# Create label
	pickup_label = RichTextLabel.new()
	pickup_label.name = "PickupLabel"
	pickup_label.bbcode_enabled = true
	pickup_label.position = Vector2(20, 8)
	pickup_label.size = Vector2(label_width - 40, label_height - 16)
	add_child(pickup_label)

	# Create triangle container for better organization
	triangle_container = Control.new()
	triangle_container.name = "TriangleContainer"
	triangle_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(triangle_container)

	# Create triangles efficiently
	_create_optimized_triangles()

func _create_optimized_triangles():
	"""Create triangles with optimized setup"""
	var triangle_configs = [
		{"name": "TopLeft", "corner": "top_left"},
		{"name": "TopRight", "corner": "top_right"},
		{"name": "BottomLeft", "corner": "bottom_left"},
		{"name": "BottomRight", "corner": "bottom_right"}
	]
	
	triangles.clear()
	triangles.resize(4)  # Pre-allocate array
	
	for i in range(triangle_configs.size()):
		var config = triangle_configs[i]
		var triangle = Polygon2D.new()
		triangle.name = config.name
		triangle.color = pickup_color
		triangle.polygon = _get_triangle_points(config.corner)
		triangle_container.add_child(triangle)
		triangles[i] = triangle
	
	# Set initial positions
	_update_triangle_positions()

func _get_triangle_points(corner: String) -> PackedVector2Array:
	"""Get triangle points for specific corner (cached)"""
	match corner:
		"top_left":
			return PackedVector2Array([Vector2(0, 0), Vector2(triangle_size, 0), Vector2(0, triangle_size)])
		"top_right":
			return PackedVector2Array([Vector2(0, 0), Vector2(-triangle_size, 0), Vector2(0, triangle_size)])
		"bottom_left":
			return PackedVector2Array([Vector2(0, 0), Vector2(triangle_size, 0), Vector2(0, -triangle_size)])
		"bottom_right":
			return PackedVector2Array([Vector2(0, 0), Vector2(-triangle_size, 0), Vector2(0, -triangle_size)])
		_:
			return PackedVector2Array()

func _setup_optimized_components():
	"""Setup components with optimization"""
	if pickup_label:
		pickup_label.fit_content = true
		pickup_label.scroll_active = false
		if font_file:
			pickup_label.add_theme_font_override("normal_font", font_file)

# ============================================================================
# OPTIMIZED PHYSICS PROCESS - Only when needed
# ============================================================================
func _physics_process(_delta):
	"""Only update when visible and size changed"""
	if not visible or not enable_triangle_updates:
		return
	
	# Check if size actually changed
	if size != _last_known_size:
		_size_changed = true
		_last_known_size = size
		_cached_control_size = size
		_update_triangle_positions()

func _update_triangle_positions():
	"""Update triangle positions efficiently"""
	if triangles.size() != 4:
		return
	
	var control_size = _cached_control_size
	
	# Update all triangles in one pass
	triangles[0].position = Vector2(0, 0)  # Top left
	triangles[1].position = Vector2(control_size.x, 0)  # Top right
	triangles[2].position = Vector2(0, control_size.y)  # Bottom left
	triangles[3].position = Vector2(control_size.x, control_size.y)  # Bottom right

# ============================================================================
# OPTIMIZED PROMPT DISPLAY
# ============================================================================
func show_prompt(action: ActionType, key: String = "E"):
	"""Optimized prompt display with caching"""
	current_state = PromptState.SHOWN
	visible = true

	var action_text = _action_text_cache.get(action, "Unknown")
	var color_to_use = blocked_color if action == ActionType.NO_SPACE else pickup_color
	
	# Use cached BBCode or create new
	var cache_key = "%s_%s_%s" % [action, key, color_to_use.to_html(false)]
	var bbcode_text = _bbcode_cache.get(cache_key)
	
	if not bbcode_text:
		bbcode_text = _generate_bbcode_text(action, action_text, key, color_to_use)
		_bbcode_cache[cache_key] = bbcode_text
	
	pickup_label.text = bbcode_text
	_update_triangle_colors_optimized(color_to_use)

func _generate_bbcode_text(action: ActionType, action_text: String, key: String, color_to_use: Color) -> String:
	"""Generate BBCode text efficiently"""
	if action == ActionType.NO_SPACE:
		return "[center][color=#%s]%s[/color][/center]" % [color_to_use.to_html(false), action_text]
	else:
		return "[center][color=#%s]%s [/color][color=#%s][%s][/color][/center]" % [
			color_to_use.to_html(false), action_text, white_color.to_html(false), key
		]

func _update_triangle_colors_optimized(color: Color):
	"""Update triangle colors efficiently"""
	for triangle in triangles:
		if triangle:
			triangle.color = color

# ============================================================================
# OPTIMIZED HIDE FUNCTIONALITY
# ============================================================================
func hide_prompt():
	"""Optimized hiding with proper async handling"""
	current_state = PromptState.HIDDEN
	
	# Create tween for smooth fade instead of timer
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.3)
	
	await tween.finished
	visible = false
	modulate.a = 1.0  # Reset for next show

# ============================================================================
# LEGACY COMPATIBILITY METHODS
# ============================================================================
func show_pickup_prompt():
	"""Legacy wrapper for pickup"""
	show_prompt(ActionType.PICKUP)

func show_no_space_prompt():
	"""Legacy wrapper for no space"""
	show_prompt(ActionType.NO_SPACE)

func update_triangle_colors(color: Color):
	"""Legacy method - now optimized"""
	_update_triangle_colors_optimized(color)

# ============================================================================
# STATE CHECKING
# ============================================================================
func is_hidden() -> bool:
	"""Check if prompt is hidden"""
	return current_state == PromptState.HIDDEN

func is_showing() -> bool:
	"""Check if prompt is showing"""
	return current_state == PromptState.SHOWN

# ============================================================================
# DYNAMIC CONTENT METHODS
# ============================================================================
func show_custom_prompt(text: String, key: String = "E", color: Color = Color.WHITE):
	"""Show custom prompt with any text"""
	current_state = PromptState.SHOWN
	visible = true
	
	var bbcode_text = "[center][color=#%s]%s [/color][color=#%s][%s][/color][/center]" % [
		color.to_html(false), text, white_color.to_html(false), key
	]
	
	pickup_label.text = bbcode_text
	_update_triangle_colors_optimized(color)

func set_triangle_size(new_size: float):
	"""Dynamically change triangle size"""
	if triangle_size == new_size:
		return
	
	triangle_size = new_size
	_recreate_triangles()

func _recreate_triangles():
	"""Recreate triangles with new size"""
	# Clear existing triangles
	for triangle in triangles:
		if triangle:
			triangle.queue_free()
	
	triangles.clear()
	
	# Recreate with new size
	_create_optimized_triangles()

# ============================================================================
# PERFORMANCE MONITORING
# ============================================================================
func get_performance_stats() -> Dictionary:
	"""Get performance statistics"""
	return {
		"bbcode_cache_size": _bbcode_cache.size(),
		"action_cache_size": _action_text_cache.size(),
		"triangles_count": triangles.size(),
		"triangle_updates_enabled": enable_triangle_updates,
		"current_state": PromptState.keys()[current_state],
		"size_changed_recently": _size_changed
	}

func clear_caches():
	"""Clear caches to free memory if needed"""
	_bbcode_cache.clear()
	print("InteractionHintUI: Caches cleared")

# ============================================================================
# BATCH OPERATIONS FOR MULTIPLE PROMPTS
# ============================================================================
func show_prompt_with_duration(action: ActionType, key: String = "E", duration: float = 3.0):
	"""Show prompt for specific duration"""
	show_prompt(action, key)
	
	# Auto-hide after duration
	var timer = get_tree().create_timer(duration)
	await timer.timeout
	
	if current_state == PromptState.SHOWN:  # Only hide if still showing
		hide_prompt()

func update_prompt_text_only(action: ActionType, key: String = "E"):
	"""Update only text without changing triangles (performance optimization)"""
	if current_state != PromptState.SHOWN:
		return
	
	var action_text = _action_text_cache.get(action, "Unknown")
	var color_to_use = blocked_color if action == ActionType.NO_SPACE else pickup_color
	
	var cache_key = "%s_%s_%s" % [action, key, color_to_use.to_html(false)]
	var bbcode_text = _bbcode_cache.get(cache_key)
	
	if not bbcode_text:
		bbcode_text = _generate_bbcode_text(action, action_text, key, color_to_use)
		_bbcode_cache[cache_key] = bbcode_text
	
	pickup_label.text = bbcode_text
	# Intentionally skip triangle color update for performanceц
