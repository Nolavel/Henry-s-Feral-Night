# BackpackPickup.gd - Enhanced version with image exports and UI integration
extends Area3D
class_name BackpackPickup

const PlayerClass = preload("res://player.gd")

# === BASIC BACKPACK DATA ===
@export var backpack_type: String = "Old Backpack"
@export var backpack_weight: float = 2.0
@export var backpack_description: String = "Увеличивает переносимый вес"
@export var weight_capacity_bonus: int = 10

# === NEW: IMAGE EXPORTS FOR UI SYSTEM ===
@export_group("UI Images")
@export var item_image: Texture2D  # Основное изображение предмета для CENTER_BOX
@export var category_image: Texture2D  # Иконка категории для CATEGORY_BOX

# Optional: Alternative paths if you prefer string paths
@export_subgroup("Image Paths (Alternative)")
@export_file("*.png", "*.jpg", "*.svg") var item_image_path: String = ""
@export_file("*.png", "*.jpg", "*.svg") var category_image_path: String = ""

# === UI SETTINGS ===
@export_group("UI Settings")
@export var pickup_range: float = 3.0
@export var show_ui_distance: float = 5.0
@export var category_color: Color = Color.PURPLE  # Color for category display

# === COMPONENT REFERENCES ===
@onready var backpack_mesh: MeshInstance3D = $CollisionShape3D/Backpack/world/geometry_0
@onready var pickup_sound = $Backpack_Pickup
@onready var backpack_ui = $"../../../UI/Ammo/BackpackUI"

# === STATE VARIABLES ===
var player_in_range: bool = false
var player_reference: Node3D = null
var is_ui_visible: bool = false
var ui_locked_by_shapecast := false

# === SIGNALS ===
signal backpack_picked_up(backpack_type: String)
signal ui_visibility_changed(visible: bool, item_data: Dictionary)

func _ready():
	collision_layer = 5  # Слой interactable objects
	collision_mask = 5 # player
	add_to_group("Backpacks")
	add_to_group("backpack_pickups")
	add_to_group("pickupable_items")
	
	# Load images from paths if textures not set directly
	load_images_from_paths()
	
	# Connect to UI systems
	connect_to_backpack_ui()
	connect_to_pickup_ui_system()

func load_images_from_paths():
	"""Loads images from file paths if direct textures not assigned"""
	
	# Load item image
	if not item_image and item_image_path != "":
		if ResourceLoader.exists(item_image_path):
			item_image = load(item_image_path) as Texture2D
			if item_image:
				print("BackpackPickup: ✅ Item image loaded from: %s" % item_image_path)
			else:
				printerr("BackpackPickup: ❌ Failed to load item image: %s" % item_image_path)
		else:
			printerr("BackpackPickup: ❌ Item image file not found: %s" % item_image_path)
	
	# Load category image
	if not category_image and category_image_path != "":
		if ResourceLoader.exists(category_image_path):
			category_image = load(category_image_path) as Texture2D
			if category_image:
				print("BackpackPickup: ✅ Category image loaded from: %s" % category_image_path)
			else:
				printerr("BackpackPickup: ❌ Failed to load category image: %s" % category_image_path)
		else:
			printerr("BackpackPickup: ❌ Category image file not found: %s" % category_image_path)

func _process(delta):
	if ui_locked_by_shapecast:
		return  # 🚀 Полностью игнорим UI-логику, пока ShapeCast держит

	if not player_reference or not is_instance_valid(player_reference):
		return

	var distance = global_position.distance_to(player_reference.global_position)
	if distance <= show_ui_distance and not is_ui_visible:
		show_pickup_ui()
	elif distance > show_ui_distance and is_ui_visible:
		hide_pickup_ui()


func connect_to_backpack_ui():
	"""Connects to existing BackpackUI system"""
	var backpack_ui = find_backpack_ui_in_scene()
	
	if backpack_ui and backpack_ui.has_method("_on_backpack_picked_up"):
		if not backpack_picked_up.is_connected(backpack_ui._on_backpack_picked_up):
			backpack_picked_up.connect(backpack_ui._on_backpack_picked_up)
			print("BackpackPickup: ✅ Connected to BackpackUI: %s" % backpack_ui.name)
	else:
		printerr("BackpackPickup: ❌ BackpackUI not found in scene!")

func connect_to_pickup_ui_system():
	"""Connects to new PickupUISystem"""
	var pickup_ui_systems = get_tree().get_nodes_in_group("pickup_ui_system")
	
	for ui_system in pickup_ui_systems:
		if ui_system.has_method("register_new_item"):
			ui_system.register_new_item(self)
			print("BackpackPickup: ✅ Connected to PickupUISystem")
			break

func find_backpack_ui_in_scene() -> Node:
	"""Finds BackpackUI in scene tree"""
	var ui_nodes = get_tree().get_nodes_in_group("backpack_ui")
	if ui_nodes.size() > 0:
		return ui_nodes[0]
	
	var root = get_tree().current_scene
	if root:
		return find_node_by_name_recursive(root, "BackpackUI")
	
	var ui_paths = [
		"UI/Ammo/BackpackUI",
		"../UI/BackpackUI", 
		"../../UI/BackpackUI",
		"BackpackUI"
	]
	
	for path in ui_paths:
		var node = get_node_or_null(path)
		if node:
			return node
	
	return null

func find_node_by_name_recursive(node: Node, target_name: String) -> Node:
	"""Recursively searches for node by name"""
	if node.name == target_name:
		return node
	
	for child in node.get_children():
		var result = find_node_by_name_recursive(child, target_name)
		if result:
			return result
	
	return null

func _on_body_entered(body: Node3D):
	"""Handles player entering pickup zone"""
	#if body.is_in_group("player"):
		#print("BackpackPickup: Player entered backpack zone: %s" % backpack_type)
		#player_reference = body
		#player_in_range = true

func _on_body_exited(body: Node3D):
	"""Handles player exiting pickup zone"""
	#if body.is_in_group("player"):
		#print("BackpackPickup: Player left backpack zone: %s" % backpack_type)
		#player_in_range = false
		#if is_ui_visible:
			#hide_pickup_ui()

func show_pickup_ui():
	"""Shows pickup UI"""
	if not is_ui_visible:
		is_ui_visible = true
		var item_data = get_item_data()
		emit_signal("ui_visibility_changed", true, item_data)
		print("BackpackPickup: Showing UI for %s" % backpack_type)

func hide_pickup_ui():
	"""Hides pickup UI"""
	if is_ui_visible:
		is_ui_visible = false
		var item_data = get_item_data()
		emit_signal("ui_visibility_changed", false, item_data)
		print("BackpackPickup: Hiding UI for %s" % backpack_type)

func get_item_data() -> Dictionary:
	"""Returns item data for UI system with images"""
	return {
		# Basic item info
		"name": backpack_type.to_upper(),
		"category": "EQUIPMENT",
		"weight": backpack_weight,
		"special_info": "CAPACITY\n+%d KG" % weight_capacity_bonus,
		"description": backpack_description,
		
		# Visual data
		"item_image": item_image,  # Main item image for CENTER_BOX
		"category_image": category_image,  # Category icon for CATEGORY_BOX
		"category_color": category_color,
		
		# World data
		"world_position": global_position,
		"node_reference": self,
		"can_pickup": can_be_picked_up(),
		
		# Backpack-specific data
		"weight_capacity_bonus": weight_capacity_bonus,
		"backpack_type": backpack_type,
		"item_type": "backpack"  # For UI system to identify item type
	}

# === UTILITY METHODS ===
func can_be_picked_up() -> bool:
	"""Checks if backpack can be picked up"""
	return true

func is_backpack_visible_in_world() -> bool:
	"""Checks if backpack is visible in world"""
	if is_instance_valid(backpack_mesh):
		return backpack_mesh.visible
	return false

func hide_backpack_in_world():
	"""Hides backpack in world"""
	if is_instance_valid(backpack_mesh):
		backpack_mesh.visible = false
		print("BackpackPickup: Backpack %s hidden in world." % backpack_type)
	
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	set_physics_process(false)
	
	if is_ui_visible:
		hide_pickup_ui()
	
	pickup_sound.play()

func show_backpack_in_world():
	"""Shows backpack in world"""
	if is_instance_valid(backpack_mesh):
		backpack_mesh.visible = true
		print("BackpackPickup: Backpack %s shown in world." % backpack_type)
	
	set_deferred("monitoring", true)
	set_deferred("monitorable", true)
	set_physics_process(true)

func get_backpack_type() -> String:
	"""Returns backpack type"""
	return backpack_type

func pickup_backpack() -> Dictionary:
	"""Picks up backpack with UI integration"""
	if can_be_picked_up():
		var item_data = get_item_data()
		
		if is_ui_visible:
			hide_pickup_ui()
		
		emit_signal("backpack_picked_up", backpack_type)
		hide_backpack_in_world()
		
		print("BackpackPickup: Backpack %s picked up" % backpack_type)
		
		# Remove after sound finishes
		var timer = Timer.new()
		add_child(timer)
		timer.wait_time = 1.0
		timer.one_shot = true
		timer.timeout.connect(func(): queue_free())
		timer.start()
		
		return item_data
	else:
		print("BackpackPickup: Cannot pick up %s" % backpack_type)
		return {}

func get_category_color() -> Color:
	"""Returns category color for UI"""
	return category_color

# === HELPER METHODS FOR IMAGES ===
func set_item_image_from_path(path: String):
	"""Sets item image from file path (runtime method)"""
	if ResourceLoader.exists(path):
		var texture = load(path) as Texture2D
		if texture:
			item_image = texture
			print("BackpackPickup: Item image set from: %s" % path)
		else:
			printerr("BackpackPickup: Failed to load item image: %s" % path)
	else:
		printerr("BackpackPickup: Image file not found: %s" % path)

func set_category_image_from_path(path: String):
	"""Sets category image from file path (runtime method)"""
	if ResourceLoader.exists(path):
		var texture = load(path) as Texture2D
		if texture:
			category_image = texture
			print("BackpackPickup: Category image set from: %s" % path)
		else:
			printerr("BackpackPickup: Failed to load category image: %s" % path)
	else:
		printerr("BackpackPickup: Image file not found: %s" % path)

func has_item_image() -> bool:
	"""Checks if item has main image"""
	return item_image != null

func has_category_image() -> bool:
	"""Checks if item has category image"""
	return category_image != null
	
func interaction_triggered(source: Node3D):
	print("BackpackPickup: Interaction triggered by ShapeCast from %s" % source.name)
	player_reference = source
	player_in_range = true

	if source is ShapeCast3D:
		ui_locked_by_shapecast = true
		if not is_ui_visible:
			show_pickup_ui()
	else:
		ui_locked_by_shapecast = false
		show_pickup_ui()
