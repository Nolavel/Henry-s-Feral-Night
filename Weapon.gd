# WeaponPickup.gd - Collectible weapon on the ground
extends RigidBody3D

@export var weapon_type = "pistol"  # "pistol", "rifle", "shotgun"
@export var pickup_range = 2.0
@export var bobbing_speed = 2.0
@export var bobbing_amplitude = 0.3
@export var rotation_speed = 45.0  # Degrees per second

var initial_y_position = 0.0
var time_passed = 0.0
var can_be_picked_up = true

@onready var mesh_instance = $MeshInstance3D
@onready var collision_shape = $CollisionShape3D
@onready var area_3d = $Area3D  # For detection

func _ready():
	add_to_group("weapon_pickups")
	initial_y_position = global_position.y
	
	# Setup the weapon mesh based on type
	setup_weapon_mesh()
	
	# Setup Area3D for pickup detection
	setup_pickup_area()
	
	# Connect pickup signal
	if area_3d:
		area_3d.body_entered.connect(_on_body_entered)
		area_3d.body_exited.connect(_on_body_exited)

func setup_weapon_mesh():
	# Create different meshes for different weapon types
	if not mesh_instance:
		mesh_instance = MeshInstance3D.new()
		add_child(mesh_instance)
	
	var mesh: Mesh
	var material = StandardMaterial3D.new()
	
	match weapon_type:
		"pistol":
			mesh = BoxMesh.new()
			mesh.size = Vector3(0.2, 0.1, 0.4)  # Small rectangular shape
			material.albedo_color = Color.DARK_GRAY
		"rifle":
			mesh = BoxMesh.new() 
			mesh.size = Vector3(0.1, 0.1, 0.8)  # Long rectangular shape
			material.albedo_color = Color.BLACK
		"shotgun":
			mesh = BoxMesh.new()
			mesh.size = Vector3(0.15, 0.15, 0.6)  # Medium thick shape
			material.albedo_color = Color.DARK_BLUE
		_:
			mesh = SphereMesh.new()
			mesh.radius = 0.2
			material.albedo_color = Color.RED
	
	material.emission_enabled = true
	material.emission = material.albedo_color * 0.3
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material
	
	# Setup collision
	if not collision_shape:
		collision_shape = CollisionShape3D.new()
		add_child(collision_shape)
	
	var shape = BoxShape3D.new()
	shape.size = Vector3(0.5, 0.5, 0.5)  # Pickup area
	collision_shape.shape = shape

func setup_pickup_area():
	if not area_3d:
		area_3d = Area3D.new()
		add_child(area_3d)
		
		var area_collision = CollisionShape3D.new()
		area_3d.add_child(area_collision)
		
		var area_shape = SphereShape3D.new()
		area_shape.radius = pickup_range
		area_collision.shape = area_shape

func _physics_process(delta):
	if not can_be_picked_up:
		return
		
	time_passed += delta
	
	# Bobbing animation
	var bobbing_offset = sin(time_passed * bobbing_speed) * bobbing_amplitude
	global_position.y = initial_y_position + bobbing_offset
	
	# Rotation animation
	rotate_y(deg_to_rad(rotation_speed * delta))

func _on_body_entered(body):
	if body.is_in_group("player_group") and can_be_picked_up:
		pickup_weapon(body)

func _on_body_exited(body):
	# Optional: Hide pickup UI hint
	pass

func pickup_weapon(player):
	print("Player picked up: ", weapon_type)
	
	# Add weapon to player inventory
	if player.has_method("add_weapon"):
		player.add_weapon(weapon_type)
	
	# Disable pickup
	can_be_picked_up = false
	visible = false
	
	# Remove from scene after a short delay
	await get_tree().create_timer(0.1).timeout
	queue_free()
