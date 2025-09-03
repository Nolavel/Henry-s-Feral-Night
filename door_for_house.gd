# Door.gd - Fixed collision setup
extends Area3D

# Door state
var is_open: bool = false

# UI reference
var hint_ui: InteractionHintUI

# Player tracking
var player_in_range: bool = false
var player_reference: Node3D = null

# This flag prevents Area3D from interfering with ShapeCast logic
var ui_locked_by_shapecast: bool = false
@onready var animation = $Anima_Door_Open_Close
@onready var close_sound = $Close_Door
@onready var open_sound = $Open_Door

func _ready():
	print("🚪 Door: Initializing...")
	
	# ✨ ИСПРАВЛЕНИЕ: Устанавливаем правильные слои коллизии
	set_collision_layer_value(5, true)  # Слой 5 (16) - Interactables
	set_collision_mask_value(4, true)   # Может взаимодействовать с игроком (слой 4)
	
	print("🔧 Door: Установлены слои коллизии:")
	print("   - collision_layer: ", collision_layer, " (слой 5 = ", 1 << 4, ")")
	print("   - collision_mask: ", collision_mask, " (слой 4 = ", 1 << 3, ")")
	
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
	# Only process input if player is in range AND UI is shown
	if event.is_action_pressed("interact") and player_in_range:
		if hint_ui and not hint_ui.is_hidden():
			toggle_door()
			print("🎯 Door: Interact pressed - toggling door")

func toggle_door():
	"""Toggles door state and updates UI"""
	is_open = !is_open

	if is_open:
		print("🚪 Door opened")
		animation.play("Open")
		play_door_sound("Open")
		# Update UI to show "Close" option
		if hint_ui and player_in_range:
			hint_ui.show_prompt(InteractionHintUI.ActionType.CLOSE)
	else:
		print("🚪 Door closed")
		animation.play("Close")
		play_door_sound("Close")
		# Update UI to show "Open" option
		if hint_ui and player_in_range:
			hint_ui.show_prompt(InteractionHintUI.ActionType.OPEN)

# === SHAPECAST INTEGRATION ===
func interaction_triggered(source: Node3D):
	"""Called by InteractionDetector when ShapeCast detects this door"""
	print("🎯 Door: Interaction triggered by ShapeCast from %s" % source.name)
	
	# IMMEDIATELY show UI prompt based on current door state
	show_door_prompt()
	
	# Set player reference and range AFTER showing UI
	if source.get_parent() and source.get_parent().is_in_group("player"):
		player_reference = source.get_parent()
		player_in_range = true
		ui_locked_by_shapecast = true
		print("✅ Door: Player reference set")
	else:
		print("⚠️ Door: Source parent is not player, but showing UI anyway")
		player_in_range = true
		ui_locked_by_shapecast = true

func show_door_prompt():
	"""Shows the correct prompt based on door state"""
	if hint_ui:  # Не показываем UI во время анимации
		if is_open:
			hint_ui.show_prompt(InteractionHintUI.ActionType.CLOSE)
			print("✅ Door: Showing CLOSE prompt")
		else:
			hint_ui.show_prompt(InteractionHintUI.ActionType.OPEN)
			print("✅ Door: Showing OPEN prompt")

func hide_pickup_ui():
	"""Called when player leaves ShapeCast range"""
	player_in_range = false
	player_reference = null
	ui_locked_by_shapecast = false
	
	if hint_ui:
		hint_ui.hide_prompt()
		print("🚪 Door: UI hidden - player left range")

# === DOOR SOUND EFFECTS (optional) ===
func play_door_sound(sound_type: String):
	"""Проигрывает звуки двери"""
	match sound_type:
		"Open":
			print("🔊 Playing door open sound")
			open_sound.play()
		"Close":
			close_sound.play()
			print("🔊 Playing door close sound")
		"Lock":
			print("🔊 Playing door creak sound")
