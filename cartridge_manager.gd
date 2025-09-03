# CartridgeManager.gd - Минимальная рабочая версия
extends Node3D
class_name CartridgeManager

var current_weapon: WeaponBase = null
@onready var weapon_holder: Node3D = $".."

func connect_weapon(weapon: WeaponBase):
	if current_weapon and is_instance_valid(current_weapon):
		if current_weapon.is_connected("cartridge_ejected", Callable(self, "_on_cartridge_ejected")):
			current_weapon.disconnect("cartridge_ejected", Callable(self, "_on_cartridge_ejected"))
	
	current_weapon = weapon
	if current_weapon:
		if not current_weapon.is_connected("cartridge_ejected", Callable(self, "_on_cartridge_ejected")):
			current_weapon.connect("cartridge_ejected", Callable(self, "_on_cartridge_ejected"))

func _on_cartridge_ejected(spawn_transform: Transform3D):
	if not current_weapon:
		return
		
	# Задержка только для дробовиков
	if current_weapon.weapon_type in ["Enforcer 12-Gauge", "Trail Boss Shotgun"]:
		await get_tree().create_timer(0.85).timeout
		if not is_instance_valid(current_weapon):
			return
	
	create_cartridge_simple(current_weapon.weapon_type)

func create_cartridge_simple(weapon_type: String):
	var cartridge = RigidBody3D.new()
	var mesh = MeshInstance3D.new()
	var shape = CollisionShape3D.new()
	
	# Размеры и цвета
	var capsule_mesh = CapsuleMesh.new()
	var capsule_shape = CapsuleShape3D.new()
	var material = StandardMaterial3D.new()
	
	match weapon_type:
		"Wasteland Eagle":
			capsule_mesh.radius = 0.015
			capsule_mesh.height = 0.06
			material.albedo_color = Color.BLACK
		"Assault Auto-Rifle": 
			capsule_mesh.radius = 0.01    # Тоньше пистолетной
			capsule_mesh.height = 0.1     # Длиннее пистолетной
			material.albedo_color = Color.BLACK
		"Enforcer 12-Gauge", "Trail Boss Shotgun":
			capsule_mesh.radius = 0.015    # Шире пистолетной  
			capsule_mesh.height = 0.115     # Намного длиннее
			material.albedo_color = Color.RED
		_:
			capsule_mesh.radius = 0.08
			capsule_mesh.height = 0.3
			material.albedo_color = Color.GRAY
	
	capsule_shape.radius = capsule_mesh.radius
	capsule_shape.height = capsule_mesh.height
	
	material.metallic = 0.7
	material.roughness = 0.3
	
	# Настройка
	mesh.mesh = capsule_mesh
	mesh.material_override = material
	shape.shape = capsule_shape
	
	cartridge.add_child(mesh)
	cartridge.add_child(shape)
	cartridge.mass = 0.01
	cartridge.collision_layer = 64
	cartridge.collision_mask = 1
	cartridge.linear_damp = 2.0     # Торможение движения
	cartridge.angular_damp = 3.0    # Торможение вращения  
	cartridge.can_sleep = true      # Позволяет "заснуть" когда почти не движется
	
	# Добавляем в сцену
	get_tree().root.add_child(cartridge)
	cartridge.global_position = weapon_holder.global_position + Vector3(0.2, 0.1, 0)
	
	# Простой импульс вправо и вверх
	#cartridge.apply_central_impulse(Vector3(3, 4, 0))
	cartridge.apply_central_impulse(Vector3(
	randf_range(2.0, 4.0),    # X: от 2 до 4 (вправо с разбросом)
	randf_range(3.0, 5.0),    # Y: от 3 до 5 (вверх с разбросом)  
	randf_range(-1.0, 1.0)    # Z: от -1 до 1 (вперед/назад)
))
	cartridge.apply_torque_impulse(Vector3(randf_range(-5,5), randf_range(-5,5), randf_range(-5,5)))
	
	# Удаление через 5 секунд
	var timer = Timer.new()
	timer.wait_time = 5.0
	timer.one_shot = true
	timer.timeout.connect(func(): cartridge.queue_free())
	cartridge.add_child(timer)
	timer.start()

func disconnect_current_weapon():
	connect_weapon(null)
