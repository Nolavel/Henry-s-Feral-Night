extends TextureRect

# ============================================================================
# EXPORT VARIABLES
# ============================================================================
@export_group("Player References")
@export var player: CharacterBody3D
@export var camera_height: float = 2000.0

@export_group("Direction Arrow")
@export var show_direction_arrow: bool = true
@export var arrow_head_size: float = 15.0
@export var arrow_width: float = 4.0
@export var arrow_color: Color = Color.CYAN

# ============================================================================
# INTERNAL VARIABLES
# ============================================================================
@onready var camera_regional: Camera3D = $"../../SubViewport/CameraRegional"
@onready var sub_viewport: SubViewport = $"../../SubViewport"
@onready var distance_label: Label = $"../DistanceLabel"

var player_rotation: float = 0.0
var player_screen_pos: Vector2
var last_player_pos: Vector3
var distance_travelled: float = 0.0   # в метрах

# ============================================================================
# INITIALIZATION
# ============================================================================
func _ready():
	# Setup texture
	if sub_viewport:
		texture = sub_viewport.get_texture()
	
	# Check player
	if not player:
		printerr("Minimap: Player not assigned!")
		set_process(false)
		return
	
	# Setup camera position
	if camera_regional:
		_update_camera_position()
	last_player_pos = player.global_position
# ============================================================================
# PROCESS
# ============================================================================
func _process(_delta):
	if not player:
		return
		
	# === Подсчёт пройденного расстояния ===
	var current_pos: Vector3 = player.global_position
	var step: float = last_player_pos.distance_to(current_pos)
	distance_travelled += step
	last_player_pos = current_pos
	distance_label.text = "Пройдено: %.1f м" % distance_travelled
	# Update camera to follow player
	_update_camera_position()
	
	# Update player rotation for arrow
	_update_player_rotation()
	
	# Update player position on minimap
	_update_player_screen_position()
	
	# Redraw minimap
	queue_redraw()

# ============================================================================
# CAMERA UPDATE
# ============================================================================
func _update_camera_position():
	"""Update camera to follow player from above"""
	if not camera_regional or not player:
		return
	
	var player_pos = player.global_position
	camera_regional.global_position = Vector3(
		player_pos.x,
		camera_height,
		player_pos.z
	)
	
	# Camera looks straight down
	camera_regional.rotation_degrees = Vector3(-90, 0, 0)

# ============================================================================
# PLAYER ROTATION
# ============================================================================
func _update_player_rotation():
	"""Get player's facing direction"""
	var forward = -player.global_transform.basis.z
	player_rotation = atan2(forward.x, forward.z)

func _update_player_screen_position():
	"""Get player position on minimap texture"""
	if not camera_regional or not player or not sub_viewport:
		return
	
	# Get player 3D position
	var player_3d_pos = player.global_position
	
	# Project to camera 2D space
	var viewport_pos = camera_regional.unproject_position(player_3d_pos)
	
	# Get viewport size (128x128)
	var viewport_size = sub_viewport.size
	
	# Get TextureRect size (200x200)
	var texture_size = size
	
	# Scale from viewport to texture coordinates
	player_screen_pos = Vector2(
		(viewport_pos.x / viewport_size.x) * texture_size.x,
		(viewport_pos.y / viewport_size.y) * texture_size.y
	)

# ============================================================================
# DRAWING
# ============================================================================
# ============================================================================
# DRAWING
# ============================================================================
func _draw():
	# Рисуем точку игрока на миникарте
	_draw_player_dot()

func _draw_player_dot():
	"""Рисует красную точку (игрока) с черной окантовкой"""
	if player_screen_pos == null:
		return
	
	var outer_radius = 8.0    # радиус черной окантовки
	var inner_radius = 4.0    # радиус красной точки
	
	# Черный внешний круг
	draw_circle(player_screen_pos, outer_radius, Color.BLACK)
	
	# Красный внутренний круг
	draw_circle(player_screen_pos, inner_radius, Color.RED)
