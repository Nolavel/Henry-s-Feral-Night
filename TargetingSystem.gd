extends Node3D

@export var targeting_range: float = 40.0 # Радиус обнаружения противников
@export var rotation_speed: float = 5.0  # Скорость поворота оружия при прицеливании на врага

@onready var player_node: CharacterBody3D = get_parent()
@onready var weapon_holder: Node3D = player_node.find_child("WeaponHolder")

func _physics_process(delta):
	if not is_instance_valid(player_node):
		printerr("AimComponent: ОШИБКА: player_node невалиден! Убедитесь, что AimComponent является дочерним элементом Player.")
		return
	if not is_instance_valid(weapon_holder):
		printerr("AimComponent: ОШИБКА: weapon_holder невалиден! Убедитесь, что Player/WeaponHolder существует.")
		return

	if not is_instance_valid(player_node.current_weapon_area):
		return

	var current_weapon = player_node.current_weapon_area
	var muzzle_flash_point: Node3D = weapon_holder.get_node_or_null("WeaponVisuals/MuzzleFlashPoint")

	if not is_instance_valid(muzzle_flash_point):
		printerr("AimComponent: MuzzleFlashPoint не найден по пути 'WeaponVisuals/MuzzleFlashPoint'.")
		return
		
	var muzzle_point_global_pos: Vector3 = muzzle_flash_point.global_transform.origin

	var closest_enemy: Node3D = null
	var enemy_target_pos: Vector3 = Vector3.ZERO  # FIX: объявляем заранее
	var min_distance_sq: float = targeting_range * targeting_range

	var enemies: Array = get_tree().get_nodes_in_group("enemies")

	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue

		var temp_target_pos: Vector3 = Vector3(enemy.global_transform.origin.x, weapon_holder.global_transform.origin.y, enemy.global_transform.origin.z)
		var distance_sq: float = muzzle_point_global_pos.distance_squared_to(temp_target_pos)

		if distance_sq < min_distance_sq:
			closest_enemy = enemy
			enemy_target_pos = temp_target_pos  # FIX: сохраняем сюда позицию цели
			min_distance_sq = distance_sq

	if closest_enemy:
		print("AimComponent: Прицеливаемся на: %s. Расстояние: %.2f" % [closest_enemy.name, sqrt(min_distance_sq)])

		var desired_transform: Transform3D = weapon_holder.global_transform.looking_at(enemy_target_pos, Vector3.UP)
		weapon_holder.global_transform.basis = weapon_holder.global_transform.basis.slerp(desired_transform.basis, rotation_speed * delta)
