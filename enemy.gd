extends CharacterBody3D
#enemyBase
# ============================================================================
# НАСТРОЙКИ ВРАГА
# ============================================================================


@export var zombie_model_node: Node3D = null
@export var model_forward_offset: float = 90.0
@export var is_active: bool = true  # Включен ли враг
@export var spawn_disabled: bool = false  # Галочка "не создавать"

@export var move_speed: float = 2.0
@export var wander_radius: float = 20.0
@export var change_direction_time: float = 3.0
@export var visible_time: float = 30.0
@export var invisible_time: float = 10.0
@export var ground_height: float = 0.0

# НОВЫЕ ФИШКИ ДЛЯ ПРОТОТИПА
@export var chase_player: bool = true         # ИЗМЕНЕНО: по умолчанию преследует
@export var chase_distance: float = 15.0       # Дистанция начала преследования
@export var chase_speed: float = 3.5           # Скорость преследования
@export var flee_distance: float = 5.0         # Дистанция бегства от игрока
@export var flee_speed: float = 4.0            # Скорость бегства
@export var attack_distance: float = 2.5       # ИЗМЕНЕНО: увеличил дистанцию атаки
@export var damage_to_player: int = 10         # Урон игроку
@export var attack_cooldown: float = 1.5       # ИЗМЕНЕНО: быстрее атакует
@export var health: int = 100                  # Здоровье врага
@export var show_health_bar: bool = false      # Показывать полоску здоровья

# НОВЫЕ НАСТРОЙКИ ДЛЯ KNOCKBACK СИСТЕМЫ
@export var knockback_resistance: float = 0.5  # Сопротивление отталкиванию
@export var max_stun_duration: float = 1.0     # Максимальная длительность оглушения

# НОВЫЕ НАСТРОЙКИ ДЛЯ ВИЗУАЛЬНЫХ ЭФФЕКТОВ
@export var hit_color_duration: float = 0.3    # Длительность желтого цвета при попадании
@export var respawn_interval: float = 60.0     # НОВОЕ: Интервал респавна в секундах (1 минута)

# ============================================================================
# ПЕРЕМЕННЫЕ СОСТОЯНИЯ
# ============================================================================
var spawn_position: Vector3
var current_direction: Vector3
var direction_timer: float = 0.0
var visibility_timer: float = 0.0
var is_visible: bool = true
var player: Node3D = null

# Новые переменные
enum EnemyState { WANDERING, CHASING, FLEEING, ATTACKING, STUNNED }
var current_state: EnemyState = EnemyState.WANDERING
var last_attack_time: float = 0.0
var max_health: int

# ПЕРЕМЕННЫЕ ДЛЯ KNOCKBACK СИСТЕМЫ
var is_stunned: bool = false
var knockback_velocity: Vector3 = Vector3.ZERO
var knockback_decay: float = 5.0  # Скорость затухания отталкивания

# НОВЫЕ ПЕРЕМЕННЫЕ ДЛЯ ВИЗУАЛЬНЫХ ЭФФЕКТОВ
var original_material: Material = null
var hit_material: StandardMaterial3D = null
var mesh_instance: MeshInstance3D = null
var is_hit_color_active: bool = false
var hit_color_timer: float = 0.0

# ДОБАВЬ ЭТУ СТРОКУ:
var targeting_ring: MeshInstance3D = null  # <-- ВОТ ЭТА!
# НОВЫЕ ПЕРЕМЕННЫЕ ДЛЯ ПРИЦЕЛИВАНИЯ
# ПЕРЕМЕННЫЕ ДЛЯ ПРИЦЕЛИВАНИЯ (УЛУЧШЕННЫЕ)
var is_targeted: bool = false  # Флаг - находится ли враг в прицеле
var targeting_tween: Tween = null  # Единый Tween для анимации
var targeting_stability_timer: float = 0.0  # Таймер для стабилизации
var min_targeting_time: float = 0.1  # Минимальное время показа кольца (в секундах)

# НОВЫЕ ПЕРЕМЕННЫЕ ДЛЯ РЕСПАВНА
var respawn_timer: float = 0.0
var is_dead: bool = false

# ============================================================================
# ИНИЦИАЛИЗАЦИЯ
# ============================================================================
func _ready():
	collision_layer = 2 # Установите в соответствии с вашими слоями
	collision_mask = 1  # Установите в соответствии с вашими слоями
	
	spawn_position = global_transform.origin
	spawn_position.y = ground_height
	global_transform.origin = spawn_position
	max_health = health # Сохраняем максимальное здоровье
	
	add_to_group("enemies")
	setup_visual_materials()  # НОВОЕ: Настройка материалов
	find_player()
	randomize_direction()
	create_targeting_ring()
	direction_timer = randf() * change_direction_time
	
	if spawn_disabled:
		queue_free()  # Полностью удаляем из памяти
		return
		
	
		
func setup_visual_materials():
	"""НОВОЕ: Настройка материалов для визуальных эффектов"""
	# Находим MeshInstance3D в дочерних узлах
	mesh_instance = find_child("MeshInstance3D")
	if not mesh_instance:
		# Если не найден как дочерний, возможно, это сам узел
		for child in get_children():
			if child is MeshInstance3D:
				mesh_instance = child
				break
	
	if mesh_instance:
		# Сохраняем оригинальный материал
		if mesh_instance.get_surface_override_material_count() > 0:
			original_material = mesh_instance.get_surface_override_material(0)
		else:
			original_material = mesh_instance.mesh.surface_get_material(0) if mesh_instance.mesh else null
		
		# Создаем материал для эффекта попадания (желтый)
		hit_material = StandardMaterial3D.new()
		hit_material.albedo_color = Color.YELLOW
		hit_material.emission_enabled = true
		hit_material.emission = Color.YELLOW * 0.3  # Легкое свечение
		
		# Если оригинального материала нет, создаем красный
		if not original_material:
			var red_material = StandardMaterial3D.new()
			red_material.albedo_color = Color.RED
			mesh_instance.set_surface_override_material(0, red_material)
			original_material = red_material
		
	else:
		print("Enemy.gd: ⚠️ MeshInstance3D не найден для %s!" % name)

func find_player():
	# Ищем игрока в группе "player"
	player = get_tree().get_first_node_in_group("player")
	if not player:
		var player_nodes = get_tree().get_nodes_in_group("player")
		if player_nodes.size() > 0:
			player = player_nodes[0]
	
	if not player:
		printerr("Enemy.gd: Игрок не найден в группе 'player' для врага '%s'!" % name)

# ============================================================================
# ОСНОВНОЙ ЦИКЛ
# ============================================================================
func _physics_process(delta):
	
	if not is_active:
		return  # Не обрабатываем, если враг неактивен
		
	update_timers(delta)
	update_visual_effects(delta)  # НОВОЕ: Обновление визуальных эффектов
	
	# НОВОЕ: Обработка респавна
	if is_dead:
		update_respawn_timer(delta)
		return
	
	if not is_visible:
		return
	
	# Определяем состояние на основе близости игрока
	update_state()
	
	# Обновляем движение в зависимости от состояния
	update_movement_by_state(delta)
	
	# Обновляем knockback
	update_knockback(delta)
	
	move_and_slide()
	rotate_towards_movement()
	check_height()

func update_visual_effects(delta):
	"""НОВОЕ: Обновление визуальных эффектов"""
	if is_hit_color_active:
		hit_color_timer -= delta
		if hit_color_timer <= 0.0:
			# Возвращаем оригинальный цвет
			reset_to_original_color()

func update_respawn_timer(delta):
	"""НОВОЕ: Обновление таймера респавна"""
	respawn_timer -= delta
	if respawn_timer <= 0.0:
		respawn_after_death()

func update_state():
	"""Определяет текущее состояние врага"""
	# Если оглушен, не меняем состояние
	if is_stunned:
		current_state = EnemyState.STUNNED
		return
		
	if not player or not is_instance_valid(player):
		current_state = EnemyState.WANDERING
		return
	
	var distance_to_player = get_distance_to_player()
	
	# ИЗМЕНЕНО: Более агрессивная логика атаки
	if distance_to_player <= attack_distance:
		current_state = EnemyState.ATTACKING
	elif chase_player and distance_to_player <= chase_distance:
		current_state = EnemyState.CHASING
	elif distance_to_player <= flee_distance and current_state == EnemyState.FLEEING:
		# Продолжаем бежать только если уже в режиме бегства
		current_state = EnemyState.FLEEING
	else:
		current_state = EnemyState.WANDERING

func update_movement_by_state(delta):
	"""Обновляет движение в зависимости от состояния"""
	match current_state:
		EnemyState.WANDERING:
			update_wandering_movement(delta)
		EnemyState.CHASING:
			update_chasing_movement(delta)
		EnemyState.FLEEING:
			update_fleeing_movement(delta)
		EnemyState.ATTACKING:
			update_attacking_movement(delta)
		EnemyState.STUNNED:
			update_stunned_movement(delta)
	
	# Применяем гравитацию
	if is_on_floor():
		velocity.y = 0
	else:
		velocity.y += ProjectSettings.get_setting("physics/3d/default_gravity") * delta
		velocity.y = max(velocity.y, -20.0)

func update_wandering_movement(delta):
	"""Обычное блуждание"""
	var distance_from_spawn = global_transform.origin.distance_to(spawn_position)
	
	if distance_from_spawn > wander_radius:
		current_direction = (spawn_position - global_transform.origin).normalized()
	
	velocity.x = current_direction.x * move_speed
	velocity.z = current_direction.z * move_speed

func update_chasing_movement(delta):
	"""Преследование игрока"""
	if player and is_instance_valid(player):
		current_direction = (player.global_transform.origin - global_transform.origin).normalized()
		velocity.x = current_direction.x * chase_speed
		velocity.z = current_direction.z * chase_speed
		

func update_fleeing_movement(delta):
	"""Бегство от игрока"""
	if player and is_instance_valid(player):
		current_direction = (global_transform.origin - player.global_transform.origin).normalized()
		velocity.x = current_direction.x * flee_speed
		velocity.z = current_direction.z * flee_speed

func update_attacking_movement(delta):
	"""ИЗМЕНЕНО: Атака - медленно приближается и атакует"""
	# Медленно двигаемся к игроку для атаки
	if player and is_instance_valid(player):
		current_direction = (player.global_transform.origin - global_transform.origin).normalized()
		velocity.x = current_direction.x * (move_speed * 0.5)  # Медленнее при атаке
		velocity.z = current_direction.z * (move_speed * 0.5)
	
	# Атакуем с кулдауном
	var current_time = Time.get_ticks_msec() / 1000.0
	if current_time - last_attack_time >= attack_cooldown:
		attack_player()
		last_attack_time = current_time

func update_stunned_movement(delta):
	"""Движение в оглушенном состоянии - только инерция"""
	velocity.x = 0
	velocity.z = 0

func attack_player():
	"""УЛУЧШЕНО: Атакует игрока с лучшей обратной связью"""
	if player and is_instance_valid(player):
		var distance = get_distance_to_player()
	
		
		if player.has_method("take_damage"):
			var attack_direction = (player.global_transform.origin - global_transform.origin).normalized()
			player.take_damage(damage_to_player, global_transform.origin, attack_direction)
		else:
			print("Enemy.gd: ⚠️ У игрока нет метода take_damage!")

# ============================================================================
# KNOCKBACK СИСТЕМА
# ============================================================================
func apply_knockback(force: Vector3):
	"""Применяет отталкивание к врагу от пули"""
	
	
	var actual_force = force * (1.0 - knockback_resistance)
	var horizontal_force = Vector3(actual_force.x, 0, actual_force.z)
	knockback_velocity += horizontal_force
	
	var max_knockback = 10.0
	if knockback_velocity.length() > max_knockback:
		knockback_velocity = knockback_velocity.normalized() * max_knockback
	
	var stun_duration = min(force.length() * 0.05, max_stun_duration)
	if stun_duration > 0.1:
		apply_stun_effect(stun_duration)

func update_knockback(delta):
	"""Обновляет эффект отталкивания"""
	if knockback_velocity.length() > 0.1:
		velocity.x += knockback_velocity.x
		velocity.z += knockback_velocity.z
		knockback_velocity = knockback_velocity.move_toward(Vector3.ZERO, knockback_decay * delta)
	else:
		knockback_velocity = Vector3.ZERO

func apply_stun_effect(duration: float):
	"""Кратковременное оглушение врага"""

	
	is_stunned = true
	
	var stun_timer = Timer.new()
	add_child(stun_timer)
	stun_timer.one_shot = true
	stun_timer.wait_time = duration
	
	stun_timer.timeout.connect(_on_stun_timeout.bind(stun_timer))
	stun_timer.start()

func _on_stun_timeout(timer: Timer):
	"""Восстанавливает врага после оглушения"""
	is_stunned = false
	timer.queue_free()


# ============================================================================
# НОВЫЕ ВИЗУАЛЬНЫЕ ЭФФЕКТЫ
# ============================================================================
func change_to_hit_color():
	"""НОВОЕ: Меняет цвет врага на желтый при попадании"""
	if mesh_instance and hit_material:
		mesh_instance.set_surface_override_material(0, hit_material)
		is_hit_color_active = true
		hit_color_timer = hit_color_duration
		

func reset_to_original_color():
	"""НОВОЕ: Возвращает оригинальный цвет врага"""
	if mesh_instance and original_material:
		mesh_instance.set_surface_override_material(0, original_material)
		is_hit_color_active = false
		hit_color_timer = 0.0


# ============================================================================
# СИСТЕМА ЗДОРОВЬЯ
# ============================================================================
func take_damage(amount: float, hit_position: Vector3, hit_normal: Vector3, bullet_type: String = "unknown", bullet_node: Node3D = null):
	"""УЛУЧШЕНО: Получает урон с визуальными эффектами"""
	health -= amount
	ComicEffects.show_effect_on_node(self, ComicEffects.EffectType.ENEMY_HIT)
	
	# НОВОЕ: Визуальный эффект попадания
	change_to_hit_color()
	
	# Логика для различных типов пуль
	match bullet_type:
		"pistol":
			print("Enemy.gd: Попадание из пистолета - легкий урон")
		"rifle":
			print("Enemy.gd: Попадание из винтовки - сильный урон")
		"shotgun":
			print("Enemy.gd: Попадание из дробовика - множественный урон")
		_:
			pass

	if health <= 0:
		die()

func die():
	"""ИЗМЕНЕНО: Смерть врага с таймером респавна"""
	ComicEffects.show_effect_on_node(self, ComicEffects.EffectType.ENEMY_DEATH)
	is_dead = true
	respawn_timer = respawn_interval
	
	# Скрываем врага но не удаляем
	set_visibility(false)
	set_physics_process(false)
	
	# Сбрасываем все эффекты
	reset_to_original_color()
	knockback_velocity = Vector3.ZERO
	is_stunned = false

func respawn_after_death():
	"""НОВОЕ: Респавн после смерти"""
	
	# Восстанавливаем состояние
	is_dead = false
	health = max_health
	respawn_timer = 0.0
	
	# Случайная позиция рядом с точкой спавна
	var random_offset = Vector3(randf_range(-5.0, 5.0), 0, randf_range(-5.0, 5.0))
	var new_position = spawn_position + random_offset
	new_position.y = ground_height + 1.0
	global_transform.origin = new_position
	
	# Сбрасываем все эффекты
	velocity = Vector3.ZERO
	knockback_velocity = Vector3.ZERO
	is_stunned = false
	reset_to_original_color()
	
	# Возвращаем видимость и физику
	set_visibility(true)
	set_physics_process(true)
	randomize_direction()

func heal(amount: int):
	"""Лечение"""
	health = min(health + amount, max_health)

# ============================================================================
# ТАЙМЕРЫ И УПРАВЛЕНИЕ
# ============================================================================
func update_timers(delta):
	# Таймер смены направления (только при блуждании)
	if current_state == EnemyState.WANDERING:
		direction_timer -= delta
		if direction_timer <= 0:
			randomize_direction()
			direction_timer = change_direction_time + randf() * 2.0

func randomize_direction():
	var angle = randf() * TAU
	current_direction = Vector3(cos(angle), 0, sin(angle)).normalized()

func set_visibility(visible_state: bool):
	is_visible = visible_state
	visible = visible_state
	
	if $CollisionShape3D:
		$CollisionShape3D.set_deferred("disabled", not visible_state)
	
	if visible_state:
		if not is_in_group("enemies"):
			add_to_group("enemies")
	else:
		if is_in_group("enemies"):
			remove_from_group("enemies")
	

func respawn():
	"""Обычный респавн (не после смерти)"""
	var random_offset = Vector3(randf_range(-5.0, 5.0), 0, randf_range(-5.0, 5.0))
	var new_position = spawn_position + random_offset
	new_position.y = ground_height + 1.0
	global_transform.origin = new_position
	velocity = Vector3.ZERO
	health = max_health
	
	knockback_velocity = Vector3.ZERO
	is_stunned = false
	reset_to_original_color()
	
	set_visibility(true)
	randomize_direction()

func check_height():
	if global_transform.origin.y < ground_height - 5.0:
		var corrected_pos = global_transform.origin
		corrected_pos.y = ground_height + 1.0
		global_transform.origin = corrected_pos
		velocity.y = 0
# ============================================================================
# УТИЛИТЫ
# ============================================================================
func get_distance_to_player() -> float:
	if player and is_instance_valid(player):
		return global_transform.origin.distance_to(player.global_transform.origin)
	return 9999.0

func is_player_nearby(radius: float = 10.0) -> bool:
	return get_distance_to_player() <= radius

func get_current_state_name() -> String:
	return EnemyState.keys()[current_state]

# ============================================================================
# API ДЛЯ РАСШИРЕНИЯ
# ============================================================================
func set_chase_mode(enabled: bool):
	"""Включает/выключает режим преследования"""
	chase_player = enabled

func set_aggressive(aggressive: bool):
	"""Делает врага агрессивным или пассивным"""
	if aggressive:
		chase_player = true
		damage_to_player = 15
		chase_speed = 4.0
		attack_cooldown = 1.0  # Быстрее атакует
	else:
		chase_player = false
		damage_to_player = 5
		chase_speed = 2.5
		attack_cooldown = 2.0

func set_knockback_resistance(resistance: float):
	"""Устанавливает сопротивление отталкиванию"""
	knockback_resistance = clamp(resistance, 0.0, 1.0)

func set_respawn_interval(seconds: float):
	"""НОВОЕ: Устанавливает интервал респавна"""
	respawn_interval = max(seconds, 5.0)  # Минимум 5 секунд

	
	# В Enemy.gd:
func create_targeting_ring():
	targeting_ring = MeshInstance3D.new()
	var ring_mesh = TorusMesh.new()
	ring_mesh.inner_radius = 0.8
	ring_mesh.outer_radius = 1.2
	
	targeting_ring.mesh = ring_mesh
	targeting_ring.position = Vector3(0, 0.1, 0)  # чуть над землей
	
	# Материал кольца
	var ring_material = StandardMaterial3D.new()
	ring_material.albedo_color = Color.RED
	ring_material.emission_enabled = true
	ring_material.emission = Color.RED * 0.5
	ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_material.albedo_color.a = 0.7  # полупрозрачность
	
	targeting_ring.material_override = ring_material
	add_child(targeting_ring)
	targeting_ring.visible = false

func show_targeting_ring():
	if not targeting_ring:
		return
		
	# Показываем кольцо только если оно еще не показано
	if not is_targeted:
		is_targeted = true
		targeting_ring.visible = true
		targeting_ring.scale = Vector3(1.0, 1.0, 1.0)  # Сбрасываем масштаб
		targeting_stability_timer = min_targeting_time  # Устанавливаем минимальное время показа
		
		
		# Останавливаем предыдущую анимацию, если есть
		if targeting_tween:
			targeting_tween.kill()
		
		# Создаем ОДНУ анимацию пульсации
		targeting_tween = create_tween()
		targeting_tween.set_loops()  # Бесконечные петли
		targeting_tween.tween_property(targeting_ring, "scale", Vector3(1.3, 1.0, 1.3), 0.5)
		targeting_tween.tween_property(targeting_ring, "scale", Vector3(1.0, 1.0, 1.0), 0.5)
	else:
		# Если кольцо уже показано, просто обновляем таймер стабилизации
		targeting_stability_timer = min_targeting_time

# ИСПРАВЛЕННАЯ ФУНКЦИЯ hide_targeting_ring() с защитой от мигания:
func hide_targeting_ring():
	if not targeting_ring:
		return
	
	# Обновляем таймер стабилизации каждый кадр
	if targeting_stability_timer > 0:
		targeting_stability_timer -= get_process_delta_time()
		return  # Не скрываем кольцо, пока не истечет минимальное время
		
	# Скрываем кольцо только если оно показано и прошло минимальное время
	if is_targeted:
		is_targeted = false
		targeting_ring.visible = false
		
		
		# Останавливаем анимацию
		if targeting_tween:
			targeting_tween.kill()
			targeting_tween = null
		
		# Сбрасываем масштаб
		targeting_ring.scale = Vector3(1.0, 1.0, 1.0)

# ДОБАВЬ ЭТУ ФУНКЦИЮ для очистки при удалении врага
func _exit_tree():
	if targeting_tween:
		targeting_tween.kill()
		targeting_tween = null
		
func rotate_towards_movement():
	"""Поворачивает модель врага в направлении движения с коррекцией"""
	if current_direction.length() > 0.1:
		var target_rotation = atan2(current_direction.x, current_direction.z)
		target_rotation += deg_to_rad(model_forward_offset)  # Применяем коррекцию
		
		var rotation_speed = 5.0
		rotation.y = lerp_angle(rotation.y, target_rotation, rotation_speed * get_physics_process_delta_time())

# Новая функция для управления активностью:
func set_enemy_active(active: bool):
	"""Включает/выключает врага во время игры"""
	is_active = active
	
	if active:
		# Включаем врага
		set_physics_process(true)
		set_process(true)
		visible = true
		if $CollisionShape3D:
			$CollisionShape3D.disabled = false
		if not is_in_group("enemies"):
			add_to_group("enemies")
	else:
		# Выключаем врага
		set_physics_process(false)
		set_process(false)
		visible = false
		if $CollisionShape3D:
			$CollisionShape3D.disabled = true
		if is_in_group("enemies"):
			remove_from_group("enemies")
