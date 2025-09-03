# PickupUISystem.gd - Targeted optimization keeping proven logic
extends Control

class_name PickupUISystem

# ============================================================================
# EXPORT SETTINGS - Added performance controls
# ============================================================================
@export_group("Performance Settings")
@export var enable_ui_position_caching: bool = true
@export var ui_update_frequency: float = 30.0  # Reduced from 60fps
@export var style_caching_enabled: bool = true

# Temporary reference (keep your approach)
var InteractionHintUI

# ============================================================================
# UI COMPONENTS - Keep original structure
# ============================================================================
@onready var main_panel: Panel = $MainPanel
@onready var pickup_notifier = $"../PickupNotifier"

# Top row
@onready var top_row_container: HBoxContainer = $MainPanel/TOP_ROW_CONTAINER
@onready var name_box: Panel = $MainPanel/TOP_ROW_CONTAINER/NAME_BOX
@onready var name_label: Label = $"MainPanel/TOP_ROW_CONTAINER/NAME_BOX/LABEL NAME ITEM"
@onready var category_box: Panel = $MainPanel/TOP_ROW_CONTAINER/CATEGORY_BOX
@onready var category_label: Label = $"MainPanel/TOP_ROW_CONTAINER/CATEGORY_BOX/LABEL CATEGORY"
@onready var category_sprite: Sprite2D = $"MainPanel/TOP_ROW_CONTAINER/CATEGORY_BOX/BOX_SPRITE/SPRITE 2D CATEGORY"

# Center block
@onready var center_box: Panel = $MainPanel/CENTER_BOX
@onready var item_image: Sprite2D = $"MainPanel/CENTER_BOX/IMAGE ITEM"

# Bottom row
@onready var bottom_row_container: HBoxContainer = $MainPanel/BOTTOM_ROW_CONTAINER
@onready var special_box: Panel = $MainPanel/BOTTOM_ROW_CONTAINER/SPECIAL_BOX
@onready var special_marks_label: Label = $"MainPanel/BOTTOM_ROW_CONTAINER/SPECIAL_BOX/LABEL SPECIAL MARKS"
@onready var weight_box: Panel = $MainPanel/BOTTOM_ROW_CONTAINER/WEIGHT_BOX
@onready var weight_sprite: Sprite2D = $"MainPanel/BOTTOM_ROW_CONTAINER/WEIGHT_BOX/IMAGE OF WEIGHT"
@onready var weight_label: Label = $"MainPanel/BOTTOM_ROW_CONTAINER/WEIGHT_BOX/LABEL WEIGHT"

@export_group("Default UI Icons")
@export var default_weight_icon: Texture2D

# ============================================================================
# 3D LINES - Keep your working logic
# ============================================================================
var line_3d_node: Node3D = null
var vertical_line_mesh: MeshInstance3D = null
var line_particles: GPUParticles3D = null

# ============================================================================
# SYSTEM MANAGEMENT - Keep proven approach
# ============================================================================
var game_camera: Camera3D
var current_item: Node3D = null
var nearby_items: Array[Node3D] = []
var is_showing: bool = false
var current_tween: Tween

# ============================================================================
# OPTIMIZED CACHING - Only add what's beneficial
# ============================================================================
# Cache frequently accessed values
var _cached_screen_size: Vector2
var _cached_main_panel_half_size: Vector2
var _initial_ui_position: Vector2  # Позиция устанавливается один раз
var _ui_position_set: bool = false  # Флаг что позиция уже установлена

# Performance timers (убираем ненужные)
var _interaction_cooldown: float = 0.0  # Кулдаун для предотвращения двойной интеракции
var _interaction_cooldown_time: float = 0.5  # 0.5 секунды кулдаун

# Style caching (significant memory savings)
var _cached_styles: Dictionary = {}

# ============================================================================
# SETTINGS - Keep your working values
# ============================================================================
var ui_settings = {
	"panel_size": Vector2(200, 150),
	"panel_padding": 5,
	"box_margin": 3,
	"name_box_size": Vector2(120, 40),
	"category_box_size": Vector2(65, 40),
	"center_box_size": Vector2(190, 60),
	"special_box_size": Vector2(120, 40),
	"weight_box_size": Vector2(65, 40),
	"line_width": 2.0,
	"horizontal_line_length": 100,
	"line_offset_from_panel": 10
}

var style_colors = {
	"background": Color(0.1, 0.1, 0.1, 0.9),
	"box_background": Color(0.15, 0.15, 0.15, 0.8),
	"text_primary": Color(0.9, 0.9, 0.8, 1.0),
	"text_secondary": Color(0.7, 0.7, 0.6, 1.0),
	"line_color": Color(0.6, 0.4, 0.2, 0.8),
	"border_color": Color(0.4, 0.2, 0.1, 1.0)
}

var animation_settings = {
	"show_duration": 0.6,
	"hide_duration": 0.4,
	"scale_start": 2.0,
	"scale_normal": 1.0
}

signal item_pickup_requested(item: Node3D)

# ============================================================================
# INITIALIZATION - Optimized setup order
# ============================================================================
func _ready():
	# Initialize performance settings
	_interaction_cooldown_time = 0.5  # Кулдаун для предотвращения двойной интеракции
	
	# Cache screen properties once
	_cache_screen_properties()
	
	# Find InteractionHintUI (keep your approach)
	InteractionHintUI = get_tree().get_first_node_in_group("InteractionHintUI")
	if not InteractionHintUI:
		InteractionHintUI = get_parent().get_node_or_null("InteractionHintUI")
	if not InteractionHintUI:
		print("PickupUISystem: Warning - InteractionHintUI not found!")
	
	add_to_group("pickup_ui_system")
	visible = false
	reset_ui_state()
	find_game_camera()
	
	# Setup in efficient order
	setup_ui_layout()
	setup_ui_styles_optimized()  # Only optimize styles, keep rest
	setup_3d_lines()
	
	# Connect to items (keep deferred for smooth startup)
	call_deferred("connect_to_existing_items")

func _cache_screen_properties():
	"""Cache frequently used screen properties"""
	_cached_screen_size = get_viewport().get_visible_rect().size
	_cached_main_panel_half_size = ui_settings.panel_size * 0.5

# ============================================================================
# KEEP YOUR UI LAYOUT LOGIC - It works well
# ============================================================================
func setup_ui_layout():
	"""Keep your proven layout setup"""
	main_panel.size = ui_settings.panel_size
	
	# Top row
	top_row_container.position = Vector2(ui_settings.panel_padding, ui_settings.panel_padding)
	top_row_container.size = Vector2(ui_settings.panel_size.x - ui_settings.panel_padding * 2, ui_settings.name_box_size.y)
	top_row_container.add_theme_constant_override("separation", ui_settings.box_margin)
	
	name_box.custom_minimum_size = ui_settings.name_box_size
	category_box.custom_minimum_size = ui_settings.category_box_size
	
	# Center block
	center_box.position = Vector2(ui_settings.panel_padding, 
		ui_settings.panel_padding + ui_settings.name_box_size.y + ui_settings.box_margin)
	center_box.size = ui_settings.center_box_size
	
	# Bottom row
	var bottom_y = ui_settings.panel_padding + ui_settings.name_box_size.y + ui_settings.center_box_size.y + ui_settings.box_margin * 2
	bottom_row_container.position = Vector2(ui_settings.panel_padding, bottom_y)
	bottom_row_container.size = Vector2(ui_settings.panel_size.x - ui_settings.panel_padding * 2, ui_settings.special_box_size.y)
	bottom_row_container.add_theme_constant_override("separation", ui_settings.box_margin)
	
	special_box.custom_minimum_size = ui_settings.special_box_size
	weight_box.custom_minimum_size = ui_settings.weight_box_size

# ============================================================================
# KEEP YOUR 3D LINES SETUP - Don't break what works
# ============================================================================
func setup_3d_lines():
	"""Keep your working 3D lines setup"""
	call_deferred("_create_3d_lines_deferred")

func _create_3d_lines_deferred():
	"""Keep your proven 3D lines creation"""
	line_3d_node = Node3D.new()
	line_3d_node.name = "PickupUI_3D_Lines"
	get_tree().current_scene.add_child(line_3d_node)
	
	vertical_line_mesh = MeshInstance3D.new()
	vertical_line_mesh.name = "VerticalLine"
	line_3d_node.add_child(vertical_line_mesh)
	
	line_particles = GPUParticles3D.new()
	line_particles.name = "LineParticles"
	line_3d_node.add_child(line_particles)
	
	var line_material = StandardMaterial3D.new()
	line_material.albedo_color = style_colors.line_color
	line_material.flags_unshaded = true
	line_material.flags_transparent = true
	line_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	line_material.emission_enabled = true
	line_material.emission = style_colors.line_color * 1.2
	
	vertical_line_mesh.material_override = line_material
	setup_line_particles()

# ============================================================================
# KEEP YOUR CAMERA AND PARTICLE LOGIC
# ============================================================================
func find_game_camera():
	"""Keep your camera finding logic"""
	var cameras = get_tree().get_nodes_in_group("game_camera_group")
	if cameras.size() > 0:
		game_camera = cameras[0] as Camera3D
	else:
		game_camera = get_viewport().get_camera_3d()
		if game_camera:
			print("PickupUISystem: Camera found through viewport")
		else:
			print("PickupUISystem: Warning - Camera not found!")

func setup_line_particles():
	"""Keep your proven particle setup"""
	if not line_particles:
		return
	
	var particles_material = ParticleProcessMaterial.new()
	particles_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	particles_material.emission_box_extents = Vector3(0.1, 0.1, 0.1)
	particles_material.direction = Vector3(0, 1, 0)
	particles_material.initial_velocity_min = 0.5
	particles_material.initial_velocity_max = 1.5
	particles_material.gravity = Vector3(0, -2.0, 0)
	particles_material.scale_min = 0.1
	particles_material.scale_max = 0.3
	particles_material.color = style_colors.line_color
	particles_material.color_ramp = _create_particle_gradient()
	
	line_particles.process_material = particles_material
	line_particles.amount = 30
	line_particles.lifetime = 1.5
	line_particles.visibility_aabb = AABB(Vector3(-2, -5, -2), Vector3(4, 10, 4))
	line_particles.emitting = false
	
	var draw_material = StandardMaterial3D.new()
	draw_material.albedo_color = style_colors.line_color
	draw_material.emission_enabled = true
	draw_material.emission = style_colors.line_color * 0.8
	draw_material.flags_transparent = true
	draw_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw_material.flags_unshaded = true
	draw_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	
	line_particles.material_override = draw_material

func _create_particle_gradient() -> Gradient:
	"""Keep your particle gradient logic"""
	var gradient = Gradient.new()
	gradient.add_point(0.0, Color(style_colors.line_color.r, style_colors.line_color.g, style_colors.line_color.b, 1.0))
	gradient.add_point(0.7, Color(style_colors.line_color.r, style_colors.line_color.g, style_colors.line_color.b, 0.5))
	gradient.add_point(1.0, Color(style_colors.line_color.r, style_colors.line_color.g, style_colors.line_color.b, 0.0))
	return gradient

# ============================================================================
# OPTIMIZED STYLES ONLY - Leave everything else alone
# ============================================================================
func setup_ui_styles_optimized():
	"""Only optimize style creation with caching"""
	if not style_caching_enabled:
		setup_ui_styles_original()
		return
	
	# Check cache first
	if _cached_styles.has("main_panel"):
		main_panel.add_theme_stylebox_override("panel", _cached_styles.main_panel)
	else:
		# Create and cache main panel style
		var main_panel_style = StyleBoxFlat.new()
		main_panel_style.bg_color = style_colors.background
		main_panel_style.border_width_left = 2
		main_panel_style.border_width_right = 2
		main_panel_style.border_width_top = 2
		main_panel_style.border_width_bottom = 2
		main_panel_style.border_color = style_colors.border_color
		main_panel_style.corner_radius_top_left = 6
		main_panel_style.corner_radius_top_right = 6
		main_panel_style.corner_radius_bottom_left = 6
		main_panel_style.corner_radius_bottom_right = 6
		
		_cached_styles.main_panel = main_panel_style
		main_panel.add_theme_stylebox_override("panel", main_panel_style)
	
	# Box styles (create once, reuse)
	if not _cached_styles.has("box_style"):
		var box_style = StyleBoxFlat.new()
		box_style.bg_color = style_colors.box_background
		box_style.border_width_left = 1
		box_style.border_width_right = 1
		box_style.border_width_top = 1
		box_style.border_width_bottom = 1
		box_style.border_color = style_colors.border_color
		box_style.corner_radius_top_left = 3
		box_style.corner_radius_top_right = 3
		box_style.corner_radius_bottom_left = 3
		box_style.corner_radius_bottom_right = 3
		
		_cached_styles.box_style = box_style
	
	# Apply cached box styles
	var boxes = [name_box, category_box, center_box, special_box, weight_box]
	for box in boxes:
		if box:
			box.add_theme_stylebox_override("panel", _cached_styles.box_style.duplicate())

func setup_ui_styles_original():
	"""Fallback to your original style setup"""
	# Main panel style
	var main_panel_style = StyleBoxFlat.new()
	main_panel_style.bg_color = style_colors.background
	main_panel_style.border_width_left = 2
	main_panel_style.border_width_right = 2
	main_panel_style.border_width_top = 2
	main_panel_style.border_width_bottom = 2
	main_panel_style.border_color = style_colors.border_color
	main_panel_style.corner_radius_top_left = 6
	main_panel_style.corner_radius_top_right = 6
	main_panel_style.corner_radius_bottom_left = 6
	main_panel_style.corner_radius_bottom_right = 6
	
	if main_panel:
		main_panel.add_theme_stylebox_override("panel", main_panel_style)
	
	# Box styles
	var box_style = StyleBoxFlat.new()
	box_style.bg_color = style_colors.box_background
	box_style.border_width_left = 1
	box_style.border_width_right = 1
	box_style.border_width_top = 1
	box_style.border_width_bottom = 1
	box_style.border_color = style_colors.border_color
	box_style.corner_radius_top_left = 3
	box_style.corner_radius_top_right = 3
	box_style.corner_radius_bottom_left = 3
	box_style.corner_radius_bottom_right = 3
	
	# Apply styles to all boxes
	var boxes = [name_box, category_box, center_box, special_box, weight_box]
	for box in boxes:
		if box:
			box.add_theme_stylebox_override("panel", box_style.duplicate())

# ============================================================================
# KEEP YOUR REGISTRATION LOGIC - It works
# ============================================================================
func connect_to_existing_items():
	"""Keep your item connection logic"""
	var weapons = get_tree().get_nodes_in_group("Weapons")
	for weapon in weapons:
		if weapon is WeaponBase:
			register_weapon(weapon)
			
	var ammo_pickups = get_tree().get_nodes_in_group("Pickups")
	for pickup in ammo_pickups:
		if pickup is AmmoPickup:
			register_ammo(pickup)
	
	var backpacks = get_tree().get_nodes_in_group("Backpacks")
	for backpack in backpacks:
		register_backpack(backpack)

func register_weapon(weapon: WeaponBase):
	"""Keep your weapon registration"""
	if weapon.has_signal("ui_visibility_changed"):
		if not weapon.is_connected("ui_visibility_changed", _on_ui_visibility_changed):
			weapon.ui_visibility_changed.connect(_on_ui_visibility_changed)

func register_backpack(backpack: Node3D):
	"""Keep your backpack registration"""
	if backpack.has_signal("ui_visibility_changed"):
		if not backpack.is_connected("ui_visibility_changed", _on_ui_visibility_changed):
			backpack.ui_visibility_changed.connect(_on_ui_visibility_changed)

func register_ammo(ammo: AmmoPickup):
	"""Keep your ammo registration"""
	if ammo.has_signal("ui_visibility_changed"):
		if not ammo.is_connected("ui_visibility_changed", _on_ui_visibility_changed):
			ammo.ui_visibility_changed.connect(_on_ui_visibility_changed)

# ============================================================================
# KEEP YOUR DATA EXTRACTION - It's comprehensive and works
# ============================================================================
func get_item_data(item: Node3D) -> Dictionary:
	"""Keep your proven item data extraction"""
	var data = {
		"name": "Unknown Item",
		"category": "MISC", 
		"weight": 0.0,
		"special_info": "",
		"item_image": null,
		"category_image": null,
		"category_color": Color.WHITE
	}
	
	# Keep your weapon logic
	if item is WeaponBase:
		var weapon = item as WeaponBase
		if weapon.has_method("get_weapon_data_for_ui"):
			var weapon_data: Dictionary = weapon.get_weapon_data_for_ui()
			data["name"] = weapon_data.get("name", weapon.weapon_type.to_upper())
			data["category"] = weapon_data.get("category", "WEAPON")
			data["weight"] = weapon_data.get("weight", weapon.weapon_weight)
			data["special_info"] = weapon_data.get("special_info", weapon.get_special_marks_text())
			data["item_image"] = weapon_data.get("item_image", null)
			data["category_image"] = weapon_data.get("category_image", null)
			data["category_color"] = weapon_data.get("category_color", Color.ORANGE_RED)
		else:
			data["name"] = weapon.weapon_type.to_upper()
			data["category"] = "WEAPON"
			data["weight"] = weapon.weapon_weight
			data["special_info"] = weapon.get_special_marks_text()
			data["category_color"] = weapon.category_color
		
		if data["item_image"] == null and weapon.item_image:
			data["item_image"] = weapon.item_image
		if data["category_image"] == null and weapon.category_image:
			data["category_image"] = weapon.category_image
	
	# Keep your backpack logic
	elif item.has_method("get_backpack_type"):
		var backpack_type = item.get_backpack_type()
		data["name"] = backpack_type.to_upper()
		data["category"] = "EQUIPMENT"
		data["weight"] = item.backpack_weight if "backpack_weight" in item else 1.0
		
		if "weight_capacity_bonus" in item:
			data["special_info"] = "CAPACITY\n+%d KG" % item.weight_capacity_bonus
		else:
			data["special_info"] = "STORAGE\nCAPACITY"
		
		data["category_color"] = Color.PURPLE
		
		if item.item_image:
			data["item_image"] = item.item_image
		if item.category_image:
			data["category_image"] = item.category_image
		if "category_color" in item:
			data["category_color"] = item.category_color
			
	# Keep your ammo logic
	elif item is AmmoPickup:
		var ammo = item as AmmoPickup
		if ammo.has_method("get_ammo_data_for_ui"):
			var ammo_data: Dictionary = ammo.get_ammo_data_for_ui()
			data["name"] = ammo_data.get("name", ammo.ammo_type.to_upper() + " AMMO")
			data["category"] = ammo_data.get("category", "AMMO")
			data["weight"] = ammo_data.get("weight", ammo.ammo_weight)
			data["special_info"] = ammo_data.get("special_info", ammo.get_special_marks_text())
			data["item_image"] = ammo_data.get("item_image", null)
			data["category_image"] = ammo_data.get("category_image", null)
			data["category_color"] = ammo_data.get("category_color", Color.CYAN)
		else:
			data["name"] = ammo.ammo_type.to_upper() + " AMMO"
			data["category"] = "AMMO"
			data["weight"] = ammo.ammo_weight
			data["special_info"] = str(ammo.ammo_amount)
			data["category_color"] = ammo.category_color

		if data["item_image"] == null and ammo.item_image:
			data["item_image"] = ammo.item_image
		if data["category_image"] == null and ammo.category_image:
			data["category_image"] = ammo.category_image
	
	else:
		data["name"] = item.name.to_upper()
		data["category"] = "ITEM"
		data["weight"] = 0.5
		data["special_info"] = "UNKNOWN\nPROPERTIES"
		data["category_color"] = Color.LIGHT_GRAY
	
	return data

# ============================================================================
# KEEP YOUR UI CONTENT UPDATE - It handles everything correctly
# ============================================================================
func update_ui_content(data: Dictionary):
	"""Keep your proven UI content update"""
	name_label.text = data["name"]
	category_label.text = data["category"]
	weight_label.text = "%.1f KG" % data["weight"]
	special_marks_label.text = data["special_info"]
	
	# Colors
	category_label.modulate = data["category_color"]
	name_label.modulate = style_colors.text_primary
	weight_label.modulate = style_colors.text_secondary
	special_marks_label.modulate = style_colors.text_secondary
	
	# Image handling
	if data["item_image"] and item_image:
		item_image.texture = data["item_image"]
		item_image.visible = true
		item_image.modulate = Color.WHITE
	else:
		item_image.texture = null
		item_image.visible = true
		item_image.modulate = data["category_color"]
	
	if data["category_image"] and category_sprite:
		category_sprite.texture = data["category_image"]
		category_sprite.visible = true
		category_sprite.modulate = Color.WHITE
	else:
		if category_sprite:
			category_sprite.visible = false
	
	if weight_sprite:
		weight_sprite.visible = true

# ============================================================================
# KEEP YOUR ANIMATION LOGIC - It works perfectly
# ============================================================================
func show_ui_animated():
	"""Keep your proven animation system with fixed positioning"""
	if current_tween:
		current_tween.kill()
	
	reset_ui_state()
	visible = true
	is_showing = true
	
	# ИСПРАВЛЕНИЕ: Устанавливаем позицию UI один раз при показе
	_initial_ui_position = _calculate_optimal_ui_position()
	main_panel.global_position = _initial_ui_position  # Устанавливаем сразу
	_ui_position_set = true
	
	current_tween = create_tween()
	current_tween.set_parallel(true)
	
	current_tween.tween_property(main_panel, "scale", Vector2.ONE, animation_settings.show_duration * 0.6)
	current_tween.tween_property(main_panel, "modulate:a", 1.0, animation_settings.show_duration * 0.4)
	
	current_tween.tween_method(animate_lines_show, 0.0, 1.0, animation_settings.show_duration * 0.8).set_delay(0.2)

func hide_ui():
	"""Keep your proven hide animation with position reset"""
	if not is_showing:
		return
	
	if current_tween:
		current_tween.kill()
	
	# Сбрасываем флаг позиции
	_ui_position_set = false
	
	current_tween = create_tween()
	current_tween.set_parallel(true)
	
	current_tween.tween_property(main_panel, "scale", Vector2.ONE * animation_settings.scale_start, animation_settings.hide_duration)
	current_tween.tween_property(main_panel, "modulate:a", 0.0, animation_settings.hide_duration)
	
	current_tween.tween_method(animate_lines_hide, 1.0, 0.0, animation_settings.hide_duration * 0.6)
	
	current_tween.finished.connect(func():
		visible = false
		is_showing = false
		current_item = null
		_ui_position_set = false  # Сбрасываем флаг
		reset_ui_state()
	)

# ============================================================================
# KEEP YOUR 3D LINE ANIMATION - It's beautiful and works
# ============================================================================
func animate_lines_show(progress: float):
	"""Keep your beautiful line animation"""
	if not current_item or not game_camera or not line_3d_node:
		return
		
	# ДОБАВИТЬ ПРОВЕРКУ:
	if not is_instance_valid(current_item) or not current_item.is_inside_tree():
		return
	
	if not is_camera_isometric():
		if vertical_line_mesh:
			vertical_line_mesh.mesh = null
		if line_particles:
			line_particles.emitting = false
		return
	
	var item_3d_pos = current_item.global_position
	var ui_2d_pos = main_panel.global_position + main_panel.size / 2
	var ui_world_pos = game_camera.project_position(ui_2d_pos, item_3d_pos.y + 2.0)
	
	var vertical_start = item_3d_pos + Vector3(0, 0.2, 0)
	var vertical_end = ui_world_pos + Vector3(0, -1.5, 0)
	
	var current_vertical_end = vertical_start.lerp(vertical_end, progress)
	
	# Keep your pulsation effect
	var line_thickness = 0.04 * (1.0 + sin(Time.get_time_dict_from_system()["second"] * 3.0) * 0.2)
	var vertical_mesh = create_3d_line_mesh(vertical_start, current_vertical_end, line_thickness)
	vertical_line_mesh.mesh = vertical_mesh
	
	if line_particles and progress > 0.3:
		line_particles.global_position = current_vertical_end
		line_particles.emitting = true
		
		var particle_intensity = (progress - 0.3) / 0.7
		line_particles.emitting = particle_intensity > 0.1

func animate_lines_hide(progress: float):
	"""Keep your line hiding animation"""
	animate_lines_show(progress)

func is_camera_isometric() -> bool:
	"""Keep your camera detection logic"""
	var cameras = get_tree().get_nodes_in_group("game_camera_group")
	if cameras.size() > 0:
		var camera = cameras[0]
		if "is_isometric" in camera:
			return camera.is_isometric
		elif "rotation_degrees" in camera:
			return abs(camera.rotation_degrees.x + 30.0) < 10.0
	
	return true

# ============================================================================
# KEEP YOUR 3D LINE MESH CREATION - It's perfect
# ============================================================================
func create_3d_line_mesh(start_pos: Vector3, end_pos: Vector3, thickness: float = 0.02) -> ArrayMesh:
	"""Keep your beautiful tapered line mesh creation"""
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	
	var vertices = PackedVector3Array()
	var indices = PackedInt32Array()
	var normals = PackedVector3Array()
	var uvs = PackedVector2Array()
	
	var direction = (end_pos - start_pos).normalized()
	var up = Vector3.UP
	
	if abs(direction.dot(up)) > 0.9:
		up = Vector3.FORWARD
	
	# Keep your thickness variation
	var thickness_start = thickness * 0.2
	var thickness_end = thickness * 1.0
	
	var right_start = direction.cross(up).normalized() * thickness_start
	var forward_start = direction.cross(right_start).normalized() * thickness_start
	
	var right_end = direction.cross(up).normalized() * thickness_end
	var forward_end = direction.cross(right_end).normalized() * thickness_end
	
	# Keep your vertex creation
	vertices.append(start_pos + right_start + forward_start)
	vertices.append(start_pos - right_start + forward_start)
	vertices.append(start_pos - right_start - forward_start)
	vertices.append(start_pos + right_start - forward_start)
	
	vertices.append(end_pos + right_end + forward_end)
	vertices.append(end_pos - right_end + forward_end)
	vertices.append(end_pos - right_end - forward_end)
	vertices.append(end_pos + right_end - forward_end)
	
	# Keep your face indices
	var faces = [
		[0,2,1], [0,3,2],
		[4,5,6], [4,6,7],
		[0,1,5], [0,5,4],
		[2,7,6], [2,3,7],
		[1,2,6], [1,6,5],
		[0,4,7], [0,7,3]
	]
	
	for face in faces:
		indices.append(face[0])
		indices.append(face[1]) 
		indices.append(face[2])
	
	# Keep your normal calculation
	var vertex_normals = []
	for i in range(vertices.size()):
		var vertex_pos = vertices[i]
		if i < 4:
			var center_to_vertex = (vertex_pos - start_pos).normalized()
			vertex_normals.append(center_to_vertex)
		else:
			var center_to_vertex = (vertex_pos - end_pos).normalized()
			vertex_normals.append(center_to_vertex)
	
	for i in range(vertices.size()):
		normals.append(vertex_normals[i])
		if i < 4:
			uvs.append(Vector2(float(i) / 4.0, 0.0))
		else:
			uvs.append(Vector2(float(i - 4) / 4.0, 1.0))
	
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	
	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func reset_ui_state():
	"""Keep your UI state reset"""
	main_panel.scale = Vector2.ONE * animation_settings.scale_start
	main_panel.modulate.a = 0.0
	
	if vertical_line_mesh:
		vertical_line_mesh.mesh = null
	if line_particles:
		line_particles.emitting = false

# ============================================================================
# SIMPLIFIED POSITION UPDATE - Set position once, then smooth lerp
# ============================================================================
func _process(delta):
	"""Только обновление кулдауна интеракции и плавное движение UI"""
	# Обновляем кулдаун интеракции
	if _interaction_cooldown > 0:
		_interaction_cooldown -= delta
	
	# Плавное движение UI к целевой позиции (если показано)
	if is_showing and _ui_position_set:
		var current_pos = main_panel.global_position
		var distance_to_target = current_pos.distance_to(_initial_ui_position)
		
		# Плавно двигаем к целевой позиции
		if distance_to_target > 1.0:  # Если еще не достигли целевую позицию
			main_panel.global_position = current_pos.lerp(_initial_ui_position, delta * 8.0)

func _calculate_optimal_ui_position() -> Vector2:
	"""Вычисляет оптимальную позицию UI один раз при показе"""
	if not current_item or not game_camera:
		return Vector2.ZERO
	
	var item_3d_pos = current_item.global_position + Vector3(0, 3, 0)
	var item_2d_pos = game_camera.unproject_position(item_3d_pos)
	
	var player = get_tree().get_first_node_in_group("player")
	var screen_center = _cached_screen_size / 2
	var player_screen_pos = screen_center
	
	if player:
		player_screen_pos = game_camera.unproject_position(player.global_position)
	
	var panel_pos: Vector2
	
	if is_camera_isometric():
		# Изометрический режим: UI выше предмета с отталкиванием от игрока
		var offset_distance = 120.0  # Увеличено для лучшего отталкивания
		panel_pos = item_2d_pos - _cached_main_panel_half_size
		
		var distance_to_player = panel_pos.distance_to(player_screen_pos)
		if distance_to_player < offset_distance:
			# Плавное отталкивание от игрока
			var direction_from_player = (panel_pos - player_screen_pos).normalized()
			panel_pos = player_screen_pos + direction_from_player * offset_distance
	else:
		# Вид сверху: UI сбоку от предмета
		var side_offset = 200.0
		var center_exclusion_radius = 150.0
		
		var positions_to_try = [
			item_2d_pos + Vector2(side_offset, -50),   # Справа-сверху
			item_2d_pos + Vector2(-side_offset, -50),  # Слева-сверху
			item_2d_pos + Vector2(side_offset, 50),    # Справа-снизу
			item_2d_pos + Vector2(-side_offset, 50),   # Слева-снизу
			item_2d_pos + Vector2(0, -side_offset),    # Сверху
			item_2d_pos + Vector2(0, side_offset)      # Снизу
		]
		
		var best_pos = positions_to_try[0] - _cached_main_panel_half_size
		var best_distance = 0.0
		
		for pos in positions_to_try:
			var test_pos = pos - _cached_main_panel_half_size
			var distance_to_player = test_pos.distance_to(player_screen_pos)
			
			if distance_to_player > center_exclusion_radius and distance_to_player > best_distance:
				best_distance = distance_to_player
				best_pos = test_pos
		
		panel_pos = best_pos
	
	# Ограничиваем границами экрана
	panel_pos.x = clamp(panel_pos.x, 10, _cached_screen_size.x - ui_settings.panel_size.x - 10)
	panel_pos.y = clamp(panel_pos.y, 10, _cached_screen_size.y - ui_settings.panel_size.y - 50)
	
	return panel_pos

# ============================================================================
# KEEP ALL YOUR INPUT AND SIGNAL HANDLING
# ============================================================================
#ц

func _on_ui_visibility_changed(visible_state: bool, item_data: Dictionary):
	"""Keep your visibility change handler"""
	if visible_state:
		current_item = item_data.get("node_reference")
		if current_item:
			update_ui_content(item_data)
			show_ui_animated()
			
			if InteractionHintUI:
				InteractionHintUI.show_prompt(InteractionHintUI.ActionType.PICKUP)
	else:
		hide_ui()
		if InteractionHintUI:
			InteractionHintUI.hide_prompt()

# ============================================================================
# KEEP ALL YOUR PUBLIC API METHODS
# ============================================================================
func show_item_ui(item_data: Dictionary):
	"""Keep your ShapeCast UI method"""
	current_item = item_data.get("node_reference")
	if current_item:
		update_ui_content(item_data)
		show_ui_animated()
		if InteractionHintUI:
			InteractionHintUI.show_prompt(InteractionHintUI.ActionType.PICKUP)
		else:
			print("InteractionHintUI not found!")
		print("PickupUISystem: ShapeCast UI shown for: %s" % item_data.get("name", "Unknown"))

func hide_item_ui():
	"""Keep your hide UI method"""
	hide_ui()
	if InteractionHintUI:
		InteractionHintUI.hide_prompt()

func force_hide_prompt():
	"""Keep your force hide method"""
	if InteractionHintUI:
		InteractionHintUI.hide_prompt()
	hide_ui()

func register_new_item(item: Node3D):
	"""Keep your item registration"""
	if item is WeaponBase:
		register_weapon(item)
	elif item is AmmoPickup:
		register_ammo(item)
	elif item.has_method("get_backpack_type"):
		register_backpack(item)
	else:
		print("PickupUISystem: Unknown item type: %s" % item.name)

func force_hide():
	"""Keep your force hide method"""
	nearby_items.clear()
	hide_ui()
	
	if vertical_line_mesh:
		vertical_line_mesh.mesh = null
	if line_particles:
		line_particles.emitting = false

func is_ui_showing() -> bool:
	"""Keep your UI state check"""
	return is_showing

# ============================================================================
# PERFORMANCE MONITORING
# ============================================================================
func get_optimization_stats() -> Dictionary:
	"""New method to check optimization effectiveness"""
	return {
		"style_caching": style_caching_enabled,
		"cached_styles_count": _cached_styles.size(),
		"interaction_cooldown": _interaction_cooldown_time,
		"ui_position_set": _ui_position_set
	}
	
