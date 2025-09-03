extends Node3D

# ============================================================================
# НАСТРОЙКИ ЗОМБИ
# ============================================================================
@export var move_speed: float = 2.0
@export var wander_radius: float = 15.0
@export var change_direction_time: float = 3.0
@export var ground_height: float = 0.0

# AI ПОВЕДЕНИЕ
@export var chase_player: bool = true
@export var chase_distance: float = 12.0
@export var chase_speed: float = 3.0
@export var attack_distance: float = 2.0
@export var damage_to_player: int = 15
@export var attack_cooldown: float = 2.0
@export var health: int = 100

# KNOCKBACK СИСТЕМА
@export var knockback_resistance: float = 0.3
@export var max_stun_duration: float = 1.5

# ВИЗУАЛЬНЫЕ ЭФФЕКТЫ
@export var hit_color_duration: float = 0.5
@export var respawn_interval: float = 45.0

# ============================================================================
# КОМПОНЕНТЫ И ПЕРЕМЕННЫЕ
# ============================================================================
@onready var animation_tree: AnimationTree = $AnimationTree
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var rigid_body: RigidBody3D = $Node/Skeleton3D/Ch10/Zombie
@onready var collision_shape: CollisionShape3D = $Node/Skeleton3D/Ch10/Zombie/CollisionShape3D

# СОСТОЯНИЕ ЗОМБИ
var spawn_position: Vector3
var current_direction: Vector3
var direction_timer: float = 0.0
var player: Node3D = null

enum ZombieState { WANDERING, CHASING, ATTACKING, STUNNED, DEAD }
var current_state: ZombieState = ZombieState.WANDERING
var last_attack_time: float = 0.0
var max_health: int

# АНИМАЦИЯ - ПАРАМЕТРЫ ДЛЯ BLENDTREE
var movement_blend: float = 0.0
var attack_weight: float = 0.0
var hit_weight: float = 0.0
var death_weight: float = 0.0

var is_moving: bool = false
var is_attacking_now: bool = false
var is_dead: bool = false

# KNOCKBACK СИСТЕМА
var is_stunned: bool = false
var knockback_velocity: Vector3 = Vector3.ZERO
var knockback_decay: float = 5.0

# ВИЗУАЛЬНЫЕ ЭФФЕКТЫ
var original_material: Material = null
var hit_material: StandardMaterial3D = null
var mesh_instance: MeshInstance3D = null
var is_hit_color_active: bool = false
var hit_color_timer: float = 0.0

# РЕСПАВН
var respawn_timer: float = 0.0

# ============================================================================
# ИНИЦИАЛИЗАЦИЯ
# ============================================================================
func _ready():
	spawn_position = global_transform.origin
	spawn_position.y = ground_height + 0.5
	
	max_health = health
	
	add_to_group("enemies")
	setup_animation_tree()
	setup_visual_materials()
	setup_rigid_body()
	find_player()
	randomize_direction()
	
	direction_timer = randf() * change_direction_time
	
	print("Zombie.gd: Зомби %s создан в позиции %s" % [name, spawn_position])

func setup_animation_tree():
	"""Настройка AnimationTree для BlendTree"""
	if animation_tree:
		animation_tree.active = true
		
		animation_tree.set("parameters/movement_blend/blend_amount", 0.0)
		animation_tree.set("parameters/attack_add/add_amount", 0.0)
		animation_tree.set("parameters/hit_add/add_amount", 0.0)
		animation_tree.set("parameters/death_add/add_amount", 0.0)
		
		print("Zombie.gd: AnimationTree BlendTree активирован для %s" % name)
	
	if animation_player:
		animation_player.animation_finished.connect(_on_animation_player_animation_finished)
		print("Zombie.gd: AnimationPlayer подключен для %s" % name)

func setup_rigid_body():
	"""ИСПРАВЛЕННАЯ настройка RigidBody3D"""
	if rigid_body:
		# КЛЮЧЕВОЕ ИЗМЕНЕНИЕ: Используем обычный RigidBody3D режим, НЕ Kinematic
		rigid_body.gravity_scale = 1.0
		rigid_body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC # Заморозим только позицию по Y
		
		
		# Устанавливаем массу и демпфинг для стабильности
		rigid_body.mass = 1.0
		rigid_body.linear_damp = 2.0  # Демпфинг линейного движения
		rigid_body.angular_damp = 5.0 # Демпфинг углового движения
		
		# Позиция
		rigid_body.global_position = spawn_position
		
		print("Zombie.gd: RigidBody3D настроен для %s" % name)
		
		if collision_shape and collision_shape.shape:
			print("Zombie.gd: ✅ Коллизия настроена для RigidBody3D: %s" % collision_shape.shape.get_class())
		else:
			print("Zombie.gd: ❌ Коллизия НЕ настроена для RigidBody3D!")
	else:
		print("Zombie.gd: ❌ RigidBody3D не найден по пути: $Node/Skeleton3D/Ch10/Zombie")

func setup_visual_materials():
	"""Настройка материалов для визуальных эффектов"""
	mesh_instance = find_child("MeshInstance3D", true, false)
	
	if not mesh_instance:
		var skeleton = find_child("Skeleton3D", true, false)
		if skeleton:
			mesh_instance = skeleton.find_child("MeshInstance3D", true, false)
	
	if mesh_instance:
		if mesh_instance.get_surface_override_material_count() > 0:
			original_material = mesh_instance.get_surface_override_material(0)
		else:
			original_material = mesh_instance.mesh.surface_get_material(0) if mesh_instance.mesh else null
		
		hit_material = StandardMaterial3D.new()
		hit_material.albedo_color = Color.YELLOW
		hit_material.emission_enabled = true
		hit_material.emission = Color.YELLOW * 0.3
		
		print("Zombie.gd: Материалы настроены для %s" % name)
	else:
		print("Zombie.gd: ⚠️ MeshInstance3D не найден для %s!" % name)

func find_player():
	"""Поиск игрока в сцене"""
	player = get_tree().get_first_node_in_group("player")
	if not player:
		printerr("Zombie.gd: Игрок не найден в группе 'player'!")

# ============================================================================
# ОСНОВНОЙ ЦИКЛ
# ============================================================================
func _physics_process(delta):
	update_timers(delta)
	update_visual_effects(delta)
	
	if is_dead:
		update_respawn_timer(delta)
	else:
		update_state()
		update_movement_by_state(delta)
		update_knockback(delta)
		
		# УПРОЩЕННАЯ СИНХРОНИЗАЦИЯ: Просто копируем позицию RigidBody
		if rigid_body:
			global_position = rigid_body.global_position
		
	update_blend_tree_animations(delta)

func update_state():
	"""Определяет текущее состояние зомби"""
	if is_stunned:
		current_state = ZombieState.STUNNED
		return
		
	if not player or not is_instance_valid(player):
		current_state = ZombieState.WANDERING
		return
	
	var distance_to_player = get_distance_to_player()
	
	if distance_to_player <= attack_distance:
		current_state = ZombieState.ATTACKING
	elif chase_player and distance_to_player <= chase_distance:
		current_state = ZombieState.CHASING
	else:
		current_state = ZombieState.WANDERING

func update_movement_by_state(delta):
	"""ИСПРАВЛЕННОЕ обновление движения через apply_central_impulse"""
	if not rigid_body:
		return
	
	var target_velocity = Vector3.ZERO
	
	match current_state:
		ZombieState.WANDERING:
			target_velocity = update_wandering_movement()
			is_moving = target_velocity.length() > 0.1
			
		ZombieState.CHASING:
			target_velocity = update_chasing_movement()
			is_moving = true
			
		ZombieState.ATTACKING:
			target_velocity = update_attacking_movement()
			is_moving = target_velocity.length() > 0.1
			
		ZombieState.STUNNED:
			target_velocity = Vector3.ZERO
			is_moving = false
	
	# НОВЫЙ ПОДХОД: Используем apply_central_impulse для плавного движения
	if target_velocity.length() > 0.1:
		var current_horizontal_velocity = Vector3(rigid_body.linear_velocity.x, 0, rigid_body.linear_velocity.z)
		var velocity_difference = target_velocity - current_horizontal_velocity
		
		# Применяем импульс только если разница достаточно большая
		if velocity_difference.length() > 0.1:
			var impulse_force = velocity_difference * rigid_body.mass * 2.0
			# Ограничиваем силу импульса
			impulse_force = impulse_force.limit_length(10.0)
			rigid_body.apply_central_impulse(impulse_force)

func update_wandering_movement() -> Vector3:
	"""Блуждание по области"""
	var distance_from_spawn = rigid_body.global_transform.origin.distance_to(spawn_position)
	
	if distance_from_spawn > wander_radius:
		current_direction = (spawn_position - rigid_body.global_transform.origin).normalized()
	
	return Vector3(current_direction.x * move_speed, 0, current_direction.z * move_speed)

func update_chasing_movement() -> Vector3:
	"""Преследование игрока"""
	if player and is_instance_valid(player) and rigid_body:
		current_direction = (player.global_transform.origin - rigid_body.global_transform.origin).normalized()
		
		# Поворот к игроку
		var target_position = player.global_transform.origin
		target_position.y = rigid_body.global_transform.origin.y
		
		var direction_to_player = (target_position - rigid_body.global_transform.origin).normalized()
		if direction_to_player.length() > 0.1:
			var target_rotation_y = atan2(direction_to_player.x, direction_to_player.z)
			
			# ИСПРАВЛЕНИЕ: Используем transform вместо прямого изменения rotation
			var current_transform = rigid_body.transform
			var target_basis = Basis(Vector3.UP, target_rotation_y)
			current_transform.basis = current_transform.basis.slerp(target_basis, 5.0 * get_physics_process_delta_time())
			rigid_body.transform = current_transform
		
		return Vector3(current_direction.x * chase_speed, 0, current_direction.z * chase_speed)
	return Vector3.ZERO

func update_attacking_movement() -> Vector3:
	"""Атака игрока"""
	if player and is_instance_valid(player) and rigid_body:
		current_direction = (player.global_transform.origin - rigid_body.global_transform.origin).normalized()
		
		# Поворот к игроку при атаке
		var target_position = player.global_transform.origin
		target_position.y = rigid_body.global_transform.origin.y
		
		var direction_to_player = (target_position - rigid_body.global_transform.origin).normalized()
		if direction_to_player.length() > 0.1:
			var target_rotation_y = atan2(direction_to_player.x, direction_to_player.z)
			var current_transform = rigid_body.transform
			var target_basis = Basis(Vector3.UP, target_rotation_y)
			current_transform.basis = current_transform.basis.slerp(target_basis, 8.0 * get_physics_process_delta_time())
			rigid_body.transform = current_transform
		
		var current_time = Time.get_ticks_msec() / 1000.0
		if current_time - last_attack_time >= attack_cooldown:
			attack_player()
			last_attack_time = current_time
		
		return Vector3(current_direction.x * (move_speed * 0.3), 0, current_direction.z * (move_speed * 0.3))
	return Vector3.ZERO

func update_blend_tree_animations(delta):
	"""Обновляет параметры BlendTree с плавными переходами"""
	
	var target_movement = 1.0 if is_moving and not is_dead else 0.0
	movement_blend = lerp(movement_blend, target_movement, 8.0 * delta)
	
	var target_attack = 1.0 if is_attacking_now and not is_dead else 0.0
	attack_weight = lerp(attack_weight, target_attack, 12.0 * delta)
	
	var target_hit = 1.0 if current_state == ZombieState.STUNNED and not is_dead else 0.0
	hit_weight = lerp(hit_weight, target_hit, 15.0 * delta)
	
	var target_death = 1.0 if is_dead else 0.0
	death_weight = lerp(death_weight, target_death, 5.0 * delta)
	
	if animation_tree and animation_tree.active:
		var tree_root = animation_tree.tree_root
		if tree_root:
			_safe_set_parameter("parameters/movement_blend/blend_amount", movement_blend)
			_safe_set_parameter("parameters/attack_add/add_amount", attack_weight)
			_safe_set_parameter("parameters/hit_add/add_amount", hit_weight)
			_safe_set_parameter("parameters/death_add/add_amount", death_weight)

func _safe_set_parameter(param_path: String, value: float):
	if animation_tree.has_method("get") and animation_tree.get(param_path) != null:
		animation_tree.set(param_path, value)
	else:
		animation_tree.set(param_path, value)

# ============================================================================
# АНИМАЦИЯ - ОБРАБОТЧИКИ
# ============================================================================
func _on_animation_player_animation_finished(anim_name: String):
	"""Обработчик завершения анимаций"""
	print("Zombie.gd: 🎬 Анимация '%s' завершена для %s" % [anim_name, name])
	
	match anim_name:
		"Attack":
			is_attacking_now = false
		"HitReaction":
			pass
		"Death":
			pass

# ============================================================================
# БОЕВАЯ СИСТЕМА
# ============================================================================
func attack_player():
	"""Атакует игрока"""
	if player and is_instance_valid(player) and not is_attacking_now:
		is_attacking_now = true
		var distance = get_distance_to_player()
		print("Zombie.gd: 🧟 Зомби %s начинает атаку! Расстояние: %.1f" % [name, distance])
		
		var attack_timer = Timer.new()
		add_child(attack_timer)
		attack_timer.one_shot = true
		attack_timer.wait_time = 2.0
		attack_timer.timeout.connect(_force_stop_attack.bind(attack_timer))
		attack_timer.start()
		
		if player.has_method("take_damage"):
			var attack_direction = (player.global_transform.origin - rigid_body.global_transform.origin).normalized()
			player.take_damage(damage_to_player, rigid_body.global_transform.origin, attack_direction)

func _force_stop_attack(timer: Timer):
	if is_attacking_now:
		print("Zombie.gd: ⏰ Принудительно завершаем атаку для %s" % name)
		is_attacking_now = false
	timer.queue_free()

func take_damage(amount: float, hit_position: Vector3, hit_normal: Vector3, bullet_type: String = "unknown", bullet_node: Node3D = null):
	"""Получает урон"""
	health -= amount
	print("Zombie.gd: 💥 Зомби %s получил урон: %.1f. Осталось: %.1f" % [name, amount, health])
	
	change_to_hit_color()
	
	if hit_normal != Vector3.ZERO:
		var knockback_force = hit_normal * amount * 0.5
		apply_knockback(knockback_force)
	
	if health <= 0:
		die()

func die():
	"""Смерть зомби"""
	print("Zombie.gd: 💀 Зомби %s умер!" % name)
	
	is_dead = true
	is_moving = false
	is_attacking_now = false
	current_state = ZombieState.DEAD
	respawn_timer = respawn_interval
	
	if rigid_body:
		rigid_body.linear_velocity = Vector3.ZERO
		rigid_body.angular_velocity = Vector3.ZERO
		# Используем freeze для остановки физики
		rigid_body.freeze = true

func respawn_after_death():
	"""Респавн после смерти"""
	print("Zombie.gd: 🔄 Зомби %s респавнится!" % name)
	
	is_dead = false
	health = max_health
	respawn_timer = 0.0
	current_state = ZombieState.WANDERING
	
	movement_blend = 0.0
	attack_weight = 0.0
	hit_weight = 0.0
	death_weight = 0.0
	
	var random_offset = Vector3(randf_range(-3.0, 3.0), 0, randf_range(-3.0, 3.0))
	var new_position = spawn_position + random_offset
	new_position.y = ground_height + 0.5
	
	if rigid_body:
		rigid_body.freeze = false # Размораживаем физику
		rigid_body.global_position = new_position
		rigid_body.linear_velocity = Vector3.ZERO
		rigid_body.angular_velocity = Vector3.ZERO
	
	# Синхронизируем родительский узел
	global_position = rigid_body.global_position
	
	reset_to_original_color()
	knockback_velocity = Vector3.ZERO
	is_stunned = false
	randomize_direction()

# ============================================================================
# KNOCKBACK СИСТЕМА - ИСПРАВЛЕННАЯ
# ============================================================================
func apply_knockback(force: Vector3):
	"""ИСПРАВЛЕННОЕ применение отталкивания"""
	if is_dead or not rigid_body:
		return
		
	var actual_force = force * (1.0 - knockback_resistance)
	
	# Применяем knockback как импульс, а не через переменную velocity
	var impulse = Vector3(actual_force.x, 0, actual_force.z) * rigid_body.mass
	impulse = impulse.limit_length(15.0) # Ограничиваем силу
	
	rigid_body.apply_central_impulse(impulse)
	
	var stun_duration = min(force.length() * 0.03, max_stun_duration)
	if stun_duration > 0.1:
		apply_stun_effect(stun_duration)

func update_knockback(delta):
	"""Упрощенное обновление knockback - теперь физика сама справляется"""
	# Больше не нужно вручную управлять knockback_velocity
	# RigidBody3D сам обработает импульсы и демпфинг
	pass

func apply_stun_effect(duration: float):
	"""Оглушение зомби"""
	print("Zombie.gd: Зомби %s оглушен на %.1f секунд" % [name, duration])
	
	is_stunned = true
	current_state = ZombieState.STUNNED
	
	var stun_timer = Timer.new()
	add_child(stun_timer)
	stun_timer.one_shot = true
	stun_timer.wait_time = duration
	stun_timer.timeout.connect(_on_stun_timeout.bind(stun_timer))
	stun_timer.start()

func _on_stun_timeout(timer: Timer):
	"""Восстановление после оглушения"""
	is_stunned = false
	timer.queue_free()
	print("Zombie.gd: Зомби %s восстановился после оглушения" % name)

# ============================================================================
# ВИЗУАЛЬНЫЕ ЭФФЕКТЫ
# ============================================================================
func change_to_hit_color():
	"""Меняет цвет на желтый при попадании"""
	if mesh_instance and hit_material:
		mesh_instance.set_surface_override_material(0, hit_material)
		is_hit_color_active = true
		hit_color_timer = hit_color_duration

func reset_to_original_color():
	"""Возвращает оригинальный цвет"""
	if mesh_instance and original_material:
		mesh_instance.set_surface_override_material(0, original_material)
		is_hit_color_active = false
		hit_color_timer = 0.0

func update_visual_effects(delta):
	"""Обновляет визуальные эффекты"""
	if is_hit_color_active:
		hit_color_timer -= delta
		if hit_color_timer <= 0.0:
			reset_to_original_color()

func update_respawn_timer(delta):
	"""Обновляет таймер респавна"""
	respawn_timer -= delta
	if respawn_timer <= 0.0:
		respawn_after_death()

# ============================================================================
# ТАЙМЕРЫ И УТИЛИТЫ
# ============================================================================
func update_timers(delta):
	"""Обновляет таймеры"""
	if current_state == ZombieState.WANDERING:
		direction_timer -= delta
		if direction_timer <= 0:
			randomize_direction()
			direction_timer = change_direction_time + randf() * 2.0

func randomize_direction():
	"""Генерирует случайное направление"""
	var angle = randf() * TAU
	current_direction = Vector3(cos(angle), 0, sin(angle)).normalized()

func get_distance_to_player() -> float:
	"""Возвращает расстояние до игрока"""
	if player and is_instance_valid(player) and rigid_body:
		return rigid_body.global_transform.origin.distance_to(player.global_transform.origin)
	return 9999.0

# ============================================================================
# ОТЛАДКА
# ============================================================================
func debug_status():
	"""Выводит статус зомби"""
	print("=== ЗОМБИ %s ===" % name)
	print("Состояние: ", ZombieState.keys()[current_state])
	print("Здоровье: ", health, "/", max_health)
	if rigid_body:
		print("Позиция RigidBody3D: ", rigid_body.global_transform.origin)
		print("Скорость RigidBody3D: ", rigid_body.linear_velocity)
	print("Позиция AuxScene (скрипта): ", global_transform.origin)
	print("Движется: ", is_moving)
	print("Атакует: ", is_attacking_now)
	print("Мертв: ", is_dead)
	print("Оглушен: ", is_stunned)
	print("Расстояние до игрока: ", get_distance_to_player())
	print("=== АНИМАЦИИ ===")
	print("movement_blend: %.2f" % movement_blend)
	print("attack_weight: %.2f" % attack_weight)
	print("hit_weight: %.2f" % hit_weight)
	print("death_weight: %.2f" % death_weight)
	print("============")

func _input(event):
	if event.is_action_pressed("ui_accept"):
		debug_status()
	
	if event.is_action_pressed("ui_select"):
		take_damage(25, global_position, Vector3.BACK)
