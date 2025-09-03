# Door.gd - Improved door script for ShapeCast interaction
extends Node3D

# Door state
var is_open: bool = false

# UI reference
var hint_ui: InteractionHintUI

# Player tracking
var player_in_range: bool = false
var player_reference: Node3D = null

# This flag prevents Area3D from interfering with ShapeCast logic
var ui_locked_by_shapecast: bool = false

func _ready():
	debug_door_setup()
	print("🚪 Door: Initializing...")
	
	# Get UI by group
	var ui_nodes = get_tree().get_nodes_in_group("InteractionHintUI")
	if ui_nodes.size() > 0:
		hint_ui = ui_nodes[0]
		print("✅ Door: UI found")
	else:
		printerr("❌ Door: InteractionHintUI not found!")
	
	# Add to interactable group so ShapeCast can find us
	add_to_group("interactable_objects")
	print("✅ Door: Added to interactable_objects group")
	
	# Hide prompt at start
	if hint_ui:
		hint_ui.hide_prompt()

func _input(event):
	if event.is_action_pressed("ui_select"):  # Q key
		print("🚪 DOOR DEBUG:")
		print("  - Name: ", name)
		print("  - Position: ", global_position)
		print("  - Children count: ", get_children().size())
		
		for i in range(get_children().size()):
			var child = get_children()[i]
			print("    Child ", i, ": ", child.name, " (", child.get_class(), ")")
			
			if child is CollisionShape3D:
				print("      ✅ COLLISION FOUND!")
				print("      - Layer: ", child.collision_layer)
				print("      - Mask: ", child.collision_mask)
				print("      - Shape: ", child.shape)
				print("      - Disabled: ", child.disabled)
			
		# Принудительный тест UI
		player_in_range = true
		if hint_ui:
			show_door_prompt()
			print("🚪 UI forcefully shown")

func toggle_door():
	"""Toggles door state and updates UI"""
	is_open = !is_open
	
	if is_open:
		print("🚪 Door opened")
		# Update UI to show "Close" option
		if hint_ui and player_in_range:
			hint_ui.show_prompt(InteractionHintUI.ActionType.CLOSE)
	else:
		print("🚪 Door closed") 
		# Update UI to show "Open" option
		if hint_ui and player_in_range:
			hint_ui.show_prompt(InteractionHintUI.ActionType.OPEN)

# === SHAPECAST INTEGRATION ===
func interaction_triggered(source: Node3D):
	"""Called by InteractionDetector when ShapeCast detects this door"""
	print("🎯 Door: Interaction triggered by ShapeCast from %s" % source.name)
	
	# Set player reference and range
	if source.get_parent().is_in_group("player"):
		player_reference = source.get_parent()
		player_in_range = true
		ui_locked_by_shapecast = true
		
		# Show appropriate UI prompt
		show_door_prompt()
	else:
		printerr("❌ Door: Source parent is not player!")

func show_door_prompt():
	"""Shows the correct prompt based on door state"""
	if hint_ui:
		if is_open:
			hint_ui.show_prompt(InteractionHintUI.ActionType.CLOSE)
		else:
			hint_ui.show_prompt(InteractionHintUI.ActionType.OPEN)
		print("✅ Door: Showing %s prompt" % ("CLOSE" if is_open else "OPEN"))

func hide_pickup_ui():
	"""Called when player leaves ShapeCast range"""
	player_in_range = false
	player_reference = null
	ui_locked_by_shapecast = false
	
	if hint_ui:
		hint_ui.hide_prompt()
		print("🚪 Door: UI hidden - player left range")

# === DEBUGGING ===
func debug_door_state():
	"""Debug function - call from console"""
	print("=== DOOR DEBUG ===")
	print("Is open: ", is_open)
	print("Player in range: ", player_in_range)
	print("UI locked by shapecast: ", ui_locked_by_shapecast)
	print("Player reference: ", player_reference.name if player_reference else "None")
	print("UI visible: ", hint_ui.visible if hint_ui else "No UI")
	print("=== END DEBUG ===")
	
func debug_door_setup():
	print("=== DOOR DEBUG SETUP ===")
	print("Door name: ", name)
	print("Door position: ", global_position)
	
	# Проверяем группы
	print("Door groups: ", get_groups())
	if not is_in_group("interactable_objects"):
		printerr("❌ Door NOT in 'interactable_objects' group!")
		add_to_group("interactable_objects")
		print("✅ Added to 'interactable_objects' group")
	
	# Проверяем CollisionShape3D
	var collision_shapes = []
	for child in get_children():
		if child is CollisionShape3D:
			collision_shapes.append(child)
			print("✅ Found CollisionShape3D: ", child.name)
			print("   - Layer: ", child.collision_layer)
			print("   - Mask: ", child.collision_mask) 
			print("   - Shape: ", child.shape)
			
			# Проверяем слой
			if child.collision_layer != 5:  # Layer 5 = 2^4 = 16
				printerr("❌ Wrong collision layer! Should be 16 (Layer 5)")
				child.collision_layer = 5
				print("✅ Fixed collision layer to 16")
	
	if collision_shapes.size() == 0:
		printerr("❌ NO CollisionShape3D found! Door won't be detected!")
	
	# Проверяем расстояние до игрока
	var player = get_tree().get_first_node_in_group("player")
	if player:
		var distance = global_position.distance_to(player.global_position)
		print("Distance to player: ", distance, " meters")
		if distance > 3.0:
			print("⚠️ Door is far from player (>3m) - move closer to test")
	else:
		printerr("❌ Player not found!")
	
	print("=== END DOOR DEBUG ===")
