# WeaponSystem.gd - Add this to your Player script or as separate component
extends Node3D

@export var weapon_holder_offset = Vector3(0.3, 0, -0.2)  # Offset from player center

# Available weapons
var available_weapons = []
var current_weapon_index = 0
var current_weapon_mesh: MeshInstance3D

# Weapon attachment point
@onready var weapon_holder = $WeaponHolder

func _ready():
	# Create weapon holder if it doesn't exist
	if not weapon_holder:
		weapon_holder = Node3D.new()
		weapon_holder.name = "WeaponHolder" 
		add_child(weapon_holder)
		weapon_holder.position = weapon_holder_offset
	
	# Start with no weapon
	current_weapon_mesh = null

func add_weapon(weapon_type: String):
	if weapon_type in available_weapons:
		print("Player already has: ", weapon_type)
		return
	
	available_weapons.append(weapon_type)
	print("Added weapon: ", weapon_type, " | Total weapons: ", available_weapons.size())
	
	# If this is the first weapon, equip it
	if available_weapons.size() == 1:
		equip_weapon(0)

func equip_weapon(weapon_index: int):
	if weapon_index < 0 or weapon_index >= available_weapons.size():
		return
	
	current_weapon_index = weapon_index
	var weapon_type = available_weapons[current_weapon_index]
	
	# Remove old weapon mesh
	if current_weapon_mesh:
		current_weapon_mesh.queue_free()
	
	# Create new weapon mesh
	create_weapon_mesh(weapon_type)
	print("Equipped: ", weapon_type)

func create_weapon_mesh(weapon_type: String):
	current_weapon_mesh = MeshInstance3D.new()
	weapon_holder.add_child(current_weapon_mesh)
	
	var mesh: Mesh
	var material = StandardMaterial3D.new()
	
	match weapon_type:
		"pistol":
			mesh = BoxMesh.new()
			mesh.size = Vector3(0.15, 0.08, 0.3)
			material.albedo_color = Color.GRAY
			current_weapon_mesh.position = Vector3(0, 0, 0)
			current_weapon_mesh.rotation_degrees = Vector3(0, 0, 0)
		"rifle":
			mesh = BoxMesh.new()
			mesh.size = Vector3(0.08, 0.08, 0.6)
			material.albedo_color = Color.BLACK
			current_weapon_mesh.position = Vector3(0, 0, -0.2)
			current_weapon_mesh.rotation_degrees = Vector3(0, 0, 0)
		"shotgun":
			mesh = BoxMesh.new() 
			mesh.size = Vector3(0.12, 0.12, 0.5)
			material.albedo_color = Color.DARK_BLUE
			current_weapon_mesh.position = Vector3(0, 0, -0.15)
			current_weapon_mesh.rotation_degrees = Vector3(0, 0, 0)
		_:
			mesh = SphereMesh.new()
			mesh.radius = 0.1
			material.albedo_color = Color.RED
	
	current_weapon_mesh.mesh = mesh
	current_weapon_mesh.material_override = material

func switch_weapon():
	if available_weapons.size() <= 1:
		return
	
	current_weapon_index = (current_weapon_index + 1) % available_weapons.size()
	equip_weapon(current_weapon_index)

func get_current_weapon() -> String:
	if available_weapons.size() == 0:
		return ""
	return available_weapons[current_weapon_index]

func _input(event):
	# Switch weapons with number keys
	if event.is_action_pressed("weapon_1") and available_weapons.size() > 0:
		equip_weapon(0)
	elif event.is_action_pressed("weapon_2") and available_weapons.size() > 1:
		equip_weapon(1)
	elif event.is_action_pressed("weapon_3") and available_weapons.size() > 2:
		equip_weapon(2)
	elif event.is_action_pressed("switch_weapon"):
		switch_weapon()
