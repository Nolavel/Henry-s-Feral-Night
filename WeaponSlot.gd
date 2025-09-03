extends Control
class_name WeaponSlot

# Animation settings
@export var spawn_duration: float = 0.5
@export var outline_shader_material: ShaderMaterial # Drag your ShaderMaterial here from the inspector
var default_material: Material # Stores the default material of weapon textures

# Mapping weapon types from your Player.gd to slots
var weapon_type_to_slot = {
	"Wasteland Eagle": 0,     # Pistol
	"Enforcer 12-Gauge": 1,   # Shotgun 1
	"Trail Boss Shotgun": 2,  # Shotgun 2
	"Assault Auto-Rifle": 3   # Automatic Rifle
}

# Positions for each slot
var weapon_positions = {
	0: {"position": Vector2(-1, 35), "rotation": -74, "scale": 0.075},
	1: {"position": Vector2(65, 0), "rotation": 0, "scale": 0.05},
	2: {"position": Vector2(118, 0), "rotation": 0, "scale": 0.05},
	3: {"position": Vector2(170, 0), "rotation": 0, "scale": 0.05}
}

# Active weapon indicator sprite
var active_indicator: Sprite2D = null
var base_indicator_scale: Vector2 = Vector2(0.039, 0.041) # Base size of the indicator

# Indicator positions for each slot
var indicator_positions = {
	0: Vector2(30, 60),   # Pistol
	1: Vector2(85, 60),   # Shotgun 1
	2: Vector2(140, 60),  # Shotgun 2
	3: Vector2(195, 60)   # Automatic Rifle
}

var active_weapons = {}   # Tracks which weapons are active (in inventory)
var weapon_states = {}    # Weapon states: normal, active, no_ammo

# Variable to manage the indicator's tween
var _indicator_tween: Tween = null

# The single shader material for active weapon/indicator glow
var active_weapon_shader: ShaderMaterial = null

func _ready() -> void:
	hide_all_weapons()
	create_active_indicator()
	setup_single_shader()
	
	# Save the default material of one of the slots, if it exists
	var all_textures = find_children("*", "TextureRect", true, false)
	if all_textures.size() > 0:
		default_material = all_textures[0].material

func setup_single_shader():
	"""Creates the single shader for active weapon/indicator glow."""
	if not outline_shader_material:
		# Create a new ShaderMaterial with the glow shader
		active_weapon_shader = ShaderMaterial.new()
		var glow_shader = load("res://UI/shaders/weapon_glow.gdshader") # Make sure this shader file exists
		
		if glow_shader:
			active_weapon_shader.shader = glow_shader
			# Configure parameters for good visibility
			active_weapon_shader.set_shader_parameter("glow_intensity", 2.5)
			active_weapon_shader.set_shader_parameter("glow_color", Color.CYAN)
			active_weapon_shader.set_shader_parameter("pulse_speed", 4.0)
			active_weapon_shader.set_shader_parameter("pulse_strength", 0.8)
			active_weapon_shader.set_shader_parameter("enable_pulse", true) # Ensure pulse is enabled by default for active
			print("Created unified glow shader for active weapon/indicator.")
		else:
			printerr("Failed to load shader weapon_glow.gdshader.")
	else:
		# Use the shader from the inspector if it was assigned
		active_weapon_shader = outline_shader_material
		print("Using shader from inspector.")

func hide_all_weapons():
	var all_textures = find_children("*", "TextureRect", true, false)
	for texture_node in all_textures:
		texture_node.visible = false

# MAIN FUNCTIONS FOR YOUR PLAYER.GD:

func on_weapon_picked_up():
	"""Called from Player.gd when a weapon is picked up."""
	var player = get_tree().get_first_node_in_group("player")
	if player and player.inventory_manager and player.inventory_manager.active_weapon_type != "":
		show_weapon_with_animation(player.inventory_manager.active_weapon_type)
		set_weapon_state(player.inventory_manager.active_weapon_type, "normal")

func on_weapon_dropped():
	"""Called from Player.gd when a weapon is dropped."""
	var player = get_tree().get_first_node_in_group("player")
	if player and player.inventory_manager:
		for weapon_type in active_weapons.keys():
			if not player.inventory_manager.has_weapon(weapon_type):
				hide_weapon_with_animation(weapon_type)

func on_weapon_activated(weapon_type: String):
	"""Called when a weapon becomes active in hand."""
	hide_active_indicator() # Ensure old indicator is hidden
	set_weapon_state(weapon_type, "active")
	print("WeaponSlot: Weapon %s is now active." % weapon_type)

func on_weapon_deactivated(weapon_type: String):
	"""Called when a weapon is unequipped."""
	set_weapon_state(weapon_type, "normal") 
	print("WeaponSlot: Weapon %s is no longer active." % weapon_type)

func on_weapon_no_ammo(weapon_type: String):
	"""Called when a weapon runs out of ammo."""
	set_weapon_state(weapon_type, "no_ammo")
	print("WeaponSlot: Weapon %s ran out of ammo." % weapon_type)

func on_ammo_restored(weapon_type: String):
	"""Called when ammo is restored (pickup or reload)."""
	pulse_indicator()
	animate_ammo_pickup(weapon_type)
	
	var player = get_tree().get_first_node_in_group("player")
	if player and player.inventory_manager and player.inventory_manager.active_weapon_type == weapon_type:
		set_weapon_state(weapon_type, "active")
	else:
		set_weapon_state(weapon_type, "normal")
	print("WeaponSlot: Ammo for %s restored." % weapon_type)

func show_weapon_with_animation(weapon_type: String):
	"""Shows a specific weapon with animation."""
	if not weapon_type_to_slot.has(weapon_type):
		return
		
	var slot_index = weapon_type_to_slot[weapon_type]
	var all_textures = find_children("*", "TextureRect", true, false)
	
	if slot_index >= all_textures.size():
		return
		
	var weapon_node = all_textures[slot_index]
	var config = weapon_positions[slot_index]
	
	# Set the correct position
	weapon_node.position = config.position
	
	# Initial state for animation
	weapon_node.scale = Vector2.ZERO
	weapon_node.rotation_degrees = config.rotation + 180 # Start with an offset rotation
	weapon_node.modulate = Color(1, 1, 1, 0) # Fully transparent
	weapon_node.visible = true
	
	# Appearance animation
	var tween = create_tween()
	tween.set_parallel(true)
	
	var final_scale = Vector2(config.scale, config.scale)
	tween.tween_property(weapon_node, "scale", final_scale, spawn_duration)
	tween.tween_property(weapon_node, "rotation_degrees", config.rotation, spawn_duration) # Animate rotation to target
	tween.tween_property(weapon_node, "modulate", Color.WHITE, spawn_duration * 0.7) # Animate to full white
	
	active_weapons[weapon_type] = true
	weapon_states[weapon_type] = "normal"
	print("Weapon shown: %s in slot %d" % [weapon_type, slot_index])

func hide_weapon_with_animation(weapon_type: String):
	"""Hides a specific weapon with animation."""
	if not weapon_type_to_slot.has(weapon_type):
		return
		
	var slot_index = weapon_type_to_slot[weapon_type]
	var all_textures = find_children("*", "TextureRect", true, false)
	
	if slot_index >= all_textures.size():
		return
		
	var weapon_node = all_textures[slot_index]
	
	# Disappearance animation
	var tween = create_tween()
	tween.set_parallel(true)
	
	tween.tween_property(weapon_node, "scale", Vector2.ZERO, spawn_duration * 0.5)
	tween.tween_property(weapon_node, "modulate", Color(1, 1, 1, 0), spawn_duration * 0.3)
	
	tween.tween_callback(func(): weapon_node.visible = false).set_delay(spawn_duration * 0.5)
	
	active_weapons.erase(weapon_type)
	weapon_states.erase(weapon_type)
	
	# Hide indicator if the active weapon is being hidden
	var player = get_tree().get_first_node_in_group("player")
	if player and player.inventory_manager and player.inventory_manager.active_weapon_type == weapon_type:
		hide_active_indicator()
	print("Weapon hidden: %s from slot %d" % [weapon_type, slot_index])

func set_weapon_state(weapon_type: String, state: String):
	"""Sets the weapon state: normal, active, no_ammo."""
	if not weapon_type_to_slot.has(weapon_type):
		return
		
	var slot_index = weapon_type_to_slot[weapon_type]
	var all_textures = find_children("*", "TextureRect", true, false)
	
	if slot_index >= all_textures.size():
		return
		
	var weapon_node = all_textures[slot_index]
	var config = weapon_positions[slot_index]
	weapon_states[weapon_type] = state
	
	# Apply visual effects based on state
	match state:
		"normal":
			weapon_node.modulate = Color(0.6, 0.6, 0.6, 1.0) # Slightly lighter for better visibility
			var tween = create_tween()
			tween.tween_property(weapon_node, "scale", Vector2(config.scale - 0.01, config.scale - 0.01), 0.3)
			hide_active_indicator() # Hide indicator if weapon is not active
			weapon_node.material = default_material # Reset material
			
		"active":
			weapon_node.modulate = Color.WHITE
			var tween = create_tween()
			tween.tween_property(weapon_node, "scale", Vector2(config.scale + 0.005, config.scale + 0.005), 0.3) # Slightly enlarge
			show_active_indicator(slot_index) # Show indicator for active weapon
			
			# Apply the unified shader
			if active_weapon_shader and active_weapon_shader.shader:
				weapon_node.material = active_weapon_shader
				print("Shader applied to active weapon: %s" % weapon_type)
			else:
				print("Shader not available for: %s" % weapon_type)
				weapon_node.material = default_material
				
		"no_ammo":
			weapon_node.modulate = Color(1.0, 0.4, 0.4, 1.0) # Brighter red
			var tween = create_tween()
			tween.tween_property(weapon_node, "scale", Vector2(config.scale - 0.015, config.scale - 0.015), 0.3) # Even smaller
			hide_active_indicator() # Hide indicator if no ammo (or keep, but change color)
			weapon_node.material = default_material
			
func animate_ammo_pickup(weapon_type: String):
	"""Weapon icon pulsation on ammo pickup."""
	if not weapon_type_to_slot.has(weapon_type):
		return
		
	var slot_index = weapon_type_to_slot[weapon_type]
	var all_textures = find_children("*", "TextureRect", true, false)
	
	if slot_index >= all_textures.size():
		return
		
	var weapon_node = all_textures[slot_index]
	var config = weapon_positions[slot_index]
	
	# Weapon pulsation - 3 quick impulses
	var current_scale = weapon_node.scale
	var tween = create_tween()
	
	for i in range(3):
		tween.tween_property(weapon_node, "scale", current_scale * 1.3, 0.15)
		tween.tween_property(weapon_node, "scale", current_scale, 0.15)
	
	print("Weapon pulsation on ammo pickup for: %s" % weapon_type)

# SYNCHRONIZATION WITH PLAYER INVENTORY
func sync_with_player_inventory():
	"""Synchronizes UI with player inventory."""
	var player = get_tree().get_first_node_in_group("player")
	if not player or not player.inventory_manager:
		return
		
	# Show weapons that are in inventory
	for weapon_type in player.inventory_manager.inventory.keys():
		if not active_weapons.has(weapon_type):
			show_weapon_with_animation(weapon_type)
	
	# Hide weapons that are not in inventory
	for weapon_type in active_weapons.keys():
		if not player.inventory_manager.has_weapon(weapon_type):
			hide_weapon_with_animation(weapon_type)
	
	# Update weapon states
	update_weapon_states_from_player()

func update_weapon_states_from_player():
	"""Updates weapon states based on player data."""
	var player = get_tree().get_first_node_in_group("player")
	if not player or not player.inventory_manager:
		return
	
	for weapon_type in active_weapons.keys():
		if not player.inventory_manager.has_weapon(weapon_type):
			continue
			
		var weapon = player.inventory_manager.inventory[weapon_type]
		var has_ammo = weapon.current_ammo_in_clip > 0 or weapon.total_carried_ammo > 0
		
		if player.inventory_manager.active_weapon_type == weapon_type:
			if has_ammo:
				set_weapon_state(weapon_type, "active")
			else:
				set_weapon_state(weapon_type, "no_ammo")
		else:
			if has_ammo:
				set_weapon_state(weapon_type, "normal")
			else:
				set_weapon_state(weapon_type, "no_ammo")

# === FUNCTIONS FOR SPRITE2D INDICATOR ===

func create_active_indicator():
	"""Creates the active weapon indicator sprite."""
	if active_indicator != null:
		return
		
	active_indicator = Sprite2D.new()
	
	# Try to load your custom texture
	var custom_texture = load("res://UI/textures/pointer_img.png")
	
	if custom_texture:
		active_indicator.texture = custom_texture
		active_indicator.scale = base_indicator_scale
		# active_indicator.centered = true # In Godot 4 Sprite2D is centered by default.
		print("Loaded custom indicator texture.")
	else:
		# Create a temporary LARGE square for visibility
		var image = Image.create(64, 64, false, Image.FORMAT_RGBA8)
		image.fill(Color.GREEN)
		var texture = ImageTexture.new()
		texture.set_image(image)
		active_indicator.texture = texture
		active_indicator.scale = Vector2(0.3, 0.3) # Large green square for debugging
		# active_indicator.centered = true # In Godot 4 Sprite2D is centered by default.
		print("Created LARGE temporary green square for indicator.")
	
	active_indicator.visible = false
	active_indicator.position = Vector2.ZERO # Initial position, will be overwritten
	active_indicator.rotation_degrees = -180 # NEW: Initial rotation of the indicator
	active_indicator.modulate = Color(1, 1, 1, 0) # NEW: Start fully transparent
	add_child(active_indicator)
	print("Created active weapon indicator.")

func _stop_indicator_tween():
	if _indicator_tween and _indicator_tween.is_valid():
		_indicator_tween.kill()
		_indicator_tween = null

func show_active_indicator(slot_index: int):
	"""Shows the indicator on the specified slot with animation."""
	if not active_indicator or not indicator_positions.has(slot_index):
		print("ERROR: Indicator or position not found for slot %d." % slot_index)
		return
		
	_stop_indicator_tween() # STOP PREVIOUS INDICATOR TWEEN
	
	var target_pos = indicator_positions[slot_index]
	
	# Set initial states for indicator appearance animation
	active_indicator.position = target_pos 
	active_indicator.scale = Vector2.ZERO # Start with zero scale
	active_indicator.rotation_degrees = -180 # NEW: Start with -180 rotation
	active_indicator.modulate = Color(1, 1, 1, 0) # Start fully transparent
	active_indicator.visible = true # Make visible for tween to start working
	
	# APPLY SHADER TO INDICATOR
	if active_weapon_shader and active_weapon_shader.shader:
		active_indicator.material = active_weapon_shader
		# If the shader has a parameter to enable/disable pulsing, enable it
		if active_weapon_shader.get_shader_parameter("enable_pulse") != null:
			active_weapon_shader.set_shader_parameter("enable_pulse", true)
		print("Shader applied to indicator on slot: %d" % slot_index)
	else:
		active_indicator.material = null # Or default_material, if you want
		print("Shader not available for indicator.")

	# Animate indicator appearance (scale and modulate)
	_indicator_tween = create_tween()
	_indicator_tween.set_parallel(true)
	
	_indicator_tween.tween_property(active_indicator, "scale", base_indicator_scale, 0.3)
	_indicator_tween.tween_property(active_indicator, "modulate", Color.WHITE, 0.3) # Animate appearance (from transparent to white)
	
	print("Indicator shown/moved to slot %d at position %s." % [slot_index, target_pos])

func hide_active_indicator():
	"""Hides the indicator with animation."""
	if not active_indicator or not active_indicator.visible:
		return
		
	_stop_indicator_tween() # STOP PREVIOUS INDICATOR TWEEN
	
	_indicator_tween = create_tween()
	_indicator_tween.set_parallel(true)
	
	_indicator_tween.tween_property(active_indicator, "scale", Vector2.ZERO, 0.3)
	_indicator_tween.tween_property(active_indicator, "modulate", Color(1, 1, 1, 0), 0.2)
	
	_indicator_tween.tween_callback(func(): # Hide only after animation completes
		if is_instance_valid(active_indicator):
			active_indicator.visible = false
			active_indicator.modulate = Color.WHITE # Reset modulate for next appearance
			active_indicator.scale = base_indicator_scale # Reset scale
			active_indicator.rotation_degrees = -180 # Reset rotation for next appearance
			# RESET SHADER FROM INDICATOR
			active_indicator.material = null # Important to remove shader when not active
			if active_weapon_shader and active_weapon_shader.get_shader_parameter("enable_pulse") != null:
				active_weapon_shader.set_shader_parameter("enable_pulse", false)
	)
	
	print("Indicator hidden.")

func pulse_indicator():
	"""Pulsation of the indicator on ammo pickup."""
	if not active_indicator or not active_indicator.visible:
		return
	
	_stop_indicator_tween() # STOP PREVIOUS INDICATOR TWEEN
	
	# Pulsation will now animate a shader parameter
	if active_weapon_shader and active_weapon_shader.shader and \
	   active_weapon_shader.get_shader_parameter("glow_intensity") != null:
		
		var original_glow_intensity = active_weapon_shader.get_shader_parameter("glow_intensity")
		
		_indicator_tween = create_tween()
		_indicator_tween.set_parallel(true)
		
		for i in range(3):
			# Increase glow intensity
			_indicator_tween.tween_method(func(value): 
				if is_instance_valid(active_weapon_shader): # Ensure shader is still valid during tween
					active_weapon_shader.set_shader_parameter("glow_intensity", value), 
				original_glow_intensity, original_glow_intensity * 2.0, 0.1)
			# Return to original intensity
			_indicator_tween.tween_method(func(value): 
				if is_instance_valid(active_weapon_shader): # Ensure shader is still valid during tween
					active_weapon_shader.set_shader_parameter("glow_intensity", value), 
				original_glow_intensity * 2.0, original_glow_intensity, 0.1).set_delay(0.1)
		
		# Ensure that after pulsation, intensity returns to original
		_indicator_tween.tween_callback(func():
			if is_instance_valid(active_weapon_shader):
				active_weapon_shader.set_shader_parameter("glow_intensity", original_glow_intensity)
				# Ensure enable_pulse remains true if it should be pulsing normally
				if active_weapon_shader.get_shader_parameter("enable_pulse") != null:
					active_weapon_shader.set_shader_parameter("enable_pulse", true)
		)
		
		print("Indicator pulsation with shader on ammo pickup.")
	else:
		# If shader is not configured, use old scale pulsation
		var current_scale = active_indicator.scale
		var original_modulate = active_indicator.modulate
		
		_indicator_tween = create_tween()
		_indicator_tween.set_parallel(true)
		
		for i in range(3):
			_indicator_tween.tween_property(active_indicator, "scale", current_scale * 1.5, 0.1)
			_indicator_tween.tween_property(active_indicator, "modulate", Color(0.8, 0.8, 0.8, 1.0), 0.1)
			_indicator_tween.tween_property(active_indicator, "scale", current_scale, 0.1).set_delay(0.1)
			_indicator_tween.tween_property(active_indicator, "modulate", original_modulate, 0.1).set_delay(0.1)
		
		_indicator_tween.tween_callback(func():
			if is_instance_valid(active_indicator):
				active_indicator.scale = base_indicator_scale
				active_indicator.modulate = Color.WHITE
		)
		print("Indicator pulsation (old) on ammo pickup.")


func _exit_tree():
	_stop_indicator_tween() # Stop tween on exiting tree
