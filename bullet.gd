# Bullet.gd - Умеренный магнетизм (для "коррекции полета")
extends CharacterBody3D

class_name Bullet

@export var speed: float = 100.0
@export var damage: float = 10.0
@export var life_time: float = 3.0
@export var impact_force: float = 20.0
@export var bullet_type: String = "standard"

@export var enable_magnetic: bool = false
@export var magnetic_range: float = 0.0
@export var magnetic_strength: float = 0.0
@export var magnetic_max_angle: float = 0.0 
@export var max_lock_time: float = 0.0 

var _direction: Vector3 = Vector3.FORWARD
var _is_initialized: bool = false
var _shooter_body: Node3D

# ПЕРЕМЕННЫЕ ДЛЯ МАГНЕТИЗМА
var target_enemy: Node3D = null
var original_direction: Vector3 # Сохраняем начальное направление для определения "прямого" полета
var magnetic_active: bool = false
var target_lock_timer: float = 0.0
var closest_distance_achieved: float = 999.0

@onready var collision_shape: CollisionShape3D = $CollisionShape3D
var mesh_instance: MeshInstance3D

# FLASH EFFECT VARIABLES
var flash_tween: Tween = null
var original_material: Material = null
var is_flashing: bool = false

var flash_light: OmniLight3D = null

func initialize(spawn_position: Vector3, initial_direction: Vector3, initial_speed: float, b_type: String, shooter: Node3D = null):
	"""
	Инициализирует пулю с заданной позицией, направлением, скоростью и типом.
	Вызывается при создании пули.
	"""
	global_transform.origin = spawn_position
	
	_direction = initial_direction.normalized()
	original_direction = _direction # Сохраняем оригинальное направление для магнетизма
	speed = initial_speed
	bullet_type = b_type
	_shooter_body = shooter
	
	# Настройка слоев и масок коллизий
	collision_layer = 4 # Пример: Слой пули
	collision_mask = 11 # Пример: Пуля сталкивается со слоями 1 (стены), 2 (враги), 8 (физические объекты)
	
	look_at(global_transform.origin + _direction, Vector3.UP)
	
	if is_instance_valid(mesh_instance):
		mesh_instance.visible = true
	
	setup_magnetic_for_weapon_type() # Вызываем настройку магнетизма
	
	var timer = Timer.new()
	add_child(timer)
	timer.one_shot = true
	timer.wait_time = life_time
	timer.timeout.connect(on_life_time_timeout)
	timer.start()
	
	_is_initialized = true
	
	if not is_instance_valid(mesh_instance):
		mesh_instance = MeshInstance3D.new()
		add_child(mesh_instance)
		print("Bullet.gd: MeshInstance3D создан для пули типа:", bullet_type)
	
	setup_bullet_mesh()

	# Запускаем вспышку через небольшую задержку
	create_flash_effect()
	
func _ready():
	"""Вызывается, когда узел пули входит в дерево сцены."""

func _physics_process(delta):
	"""
	Обрабатывает физические обновления пули, включая движение и магнетизм.
	"""
	if not _is_initialized:
		return
	
	if enable_magnetic:
		update_magnetic_attraction(delta)
	
	velocity = _direction * speed # Пуля всегда летит по текущему _direction
	
	var collision = move_and_collide(velocity * delta)
	if collision:
		handle_collision(collision)

func setup_bullet_mesh():
	"""Создает реалистичную форму пули"""
	if is_instance_valid(mesh_instance):
		var bullet_mesh = CapsuleMesh.new()
		bullet_mesh.radius = 0.02
		bullet_mesh.height = 0.08
		
		mesh_instance.mesh = bullet_mesh
		
		# ЯРКИЙ материал пули
		var bullet_material = StandardMaterial3D.new()
		bullet_material.flags_unshaded = true # Убираем тени
		bullet_material.albedo_color = Color(1.0, 0.8, 0.3) # Яркий желтый!
		bullet_material.emission_enabled = true
		bullet_material.emission = Color(0.8, 0.6, 0.1) # Светится
		
		mesh_instance.material_override = bullet_material
		mesh_instance.rotation_degrees = Vector3(90, 0, 0)
		
		print("Bullet.gd: Яркая желтая пуля создана!")

	
# ============================================================================
# УМЕРЕННАЯ МАГНЕТИЧЕСКАЯ СИСТЕМА (для "коррекции полета")
# ============================================================================

func setup_magnetic_for_weapon_type():
	"""
	Устанавливает параметры магнетизма для пули в зависимости от ее типа.
	Эти параметры предназначены для "коррекции полета", а не для "наводящей ракеты".
	"""
	match bullet_type:
		"Wasteland Eagle":
			enable_magnetic = true
			magnetic_range = 35.0     # Очень малый радиус обнаружения цели
			magnetic_strength = 1.86  # Очень слабая сила притяжения
			magnetic_max_angle = 10.0 # Очень узкий конус поиска цели (в градусах)
			max_lock_time = 0.75      # Короткое время удержания цели
		"Enforcer 12-Gauge":
			enable_magnetic = true
			magnetic_range = 45.0     # Умеренный радиус для винтовки
			magnetic_strength = 1.75  # Еще слабее, чем у пистолета
			magnetic_max_angle = 10.0 # Ультра-узкий конус, почти прямо
			max_lock_time = 0.75
		"Trail Boss Shotgun":
			enable_magnetic = true
			magnetic_range = 40.0     # Очень малый радиус для дробовика
			magnetic_strength = 2.5  # Чуть сильнее для дробовика (для ближнего боя)
			magnetic_max_angle = 15.0 # Шире конус для дробовика, но все еще узкий
			max_lock_time = 0.75
		"Assault Auto-Rifle": # Умеренные настройки для автомата
			enable_magnetic = true
			magnetic_range = 40.0
			magnetic_strength = 2.2
			magnetic_max_angle = 20.5
			max_lock_time = 0.75
		_: # Для всех остальных типов оружия или если тип не определен
			enable_magnetic = false
			magnetic_range = 0.0
			magnetic_strength = 0.0
			magnetic_max_angle = 0.0
			max_lock_time = 0.0
	

func update_magnetic_attraction(delta):
	"""
	ИСПРАВЛЕННАЯ версия: Более мягкие условия потери цели для автомата
	"""
	if target_enemy:
		target_lock_timer += delta
	
	# Проверяем текущую цель - БОЛЕЕ МЯГКИЕ условия потери
	if target_enemy and is_instance_valid(target_enemy):
		var distance = global_transform.origin.distance_to(target_enemy.global_transform.origin)
		
		# Отслеживаем минимальное расстояние
		if distance < closest_distance_achieved:
			closest_distance_achieved = distance
		
		# Вычисляем углы
		var to_target_normalized = (target_enemy.global_transform.origin - global_transform.origin).normalized()
		var angle_to_target_from_original = rad_to_deg(acos(original_direction.dot(to_target_normalized)))
		var angle_to_current_direction = rad_to_deg(acos(_direction.dot(to_target_normalized)))
		
		# БОЛЕЕ МЯГКИЕ условия потери цели:
		var should_lose_target = false
		
		# 1. Цель слишком далеко (в 4 раза больше радиуса вместо 3)
		if distance > magnetic_range * 4.0:
			should_lose_target = true
			
		
		# 2. Истек таймер (увеличенное время)
		elif target_lock_timer > max_lock_time:
			should_lose_target = true
			
		
		# 3. МЯГЧЕ: Угол от начального направления (увеличили множитель с 1.5 до 2.0)
		elif angle_to_target_from_original > magnetic_max_angle * 2.0:
			should_lose_target = true
			
		# 4. МЯГЧЕ: Угол от текущего направления (увеличили множитель с 2.0 до 2.5)
		elif angle_to_current_direction > magnetic_max_angle * 2.5:
			should_lose_target = true
			
		
		# 5. Препятствие (оставили как есть)
		elif not has_clear_path_to_enemy(target_enemy):
			should_lose_target = true
			

		if should_lose_target:
			lose_target()
			return
	
	# Поиск новой цели
	if not target_enemy:
		find_new_target()
	
	# Применяем магнетическую силу
	if target_enemy:
		apply_magnetic_force(delta)

func find_new_target():
	"""
	ИСПРАВЛЕННАЯ версия: Более широкий поиск для автомата
	"""
	var best_target: Node3D = null
	var best_score: float = -INF
	
	var all_targets = []
	all_targets.append_array(get_tree().get_nodes_in_group("enemies"))
	all_targets.append_array(get_tree().get_nodes_in_group("physics_objects"))
	
	for target in all_targets:
		if not is_instance_valid(target) or not target.is_visible():
			continue
		
		var target_pos = target.global_transform.origin
		var distance = global_transform.origin.distance_to(target_pos)
		
		# Проверяем дистанцию
		if distance > magnetic_range:
			continue
		
		var to_target = (target_pos - global_transform.origin).normalized()
		var angle = rad_to_deg(acos(original_direction.dot(to_target)))
		
		# ИСПРАВЛЕНО: Для автомата используем множитель 1.5 вместо 1.0
		var angle_limit = magnetic_max_angle
		if bullet_type == "automatic":
			angle_limit = magnetic_max_angle * 1.5  # Шире конус для автомата
		
		if angle > angle_limit:
			continue
		
		# Проверяем препятствия
		if not has_clear_path_to_enemy(target):
			continue
		
		# Система оценки (без изменений)
		var angle_factor = 1.0 - (angle / angle_limit)
		var distance_factor = 1.0 - (distance / magnetic_range)
		var score = (angle_factor * 2.0) + (distance_factor * 1.0)
		
		if score > best_score:
			best_score = score
			best_target = target
	
	if best_target:
		acquire_target(best_target)

func has_clear_path_to_enemy(enemy: Node3D) -> bool:
	"""
	Выполняет проверку лучом, чтобы убедиться, что между пулей и целью нет препятствий.
	"""
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		global_transform.origin,
		enemy.global_transform.origin
	)
	
	query.collision_mask = 1 
	
	var exclude_array = [self]
	if _shooter_body and is_instance_valid(_shooter_body):
		exclude_array.append(_shooter_body)
	
	query.exclude = exclude_array
	
	var result = space_state.intersect_ray(query)
	var is_clear = result.is_empty()
	
	if not is_clear:
		pass
	
	return is_clear

func acquire_target(target: Node3D):
	"""Захватывает цель для магнетического притяжения."""
	target_enemy = target
	magnetic_active = true
	target_lock_timer = 0.0
	closest_distance_achieved = global_transform.origin.distance_to(target.global_transform.origin)

func lose_target():
	"""Теряет текущую цель магнетического притяжения."""
	if target_enemy:
		pass
	target_enemy = null
	magnetic_active = false
	target_lock_timer = 0.0
	closest_distance_achieved = 999.0

func apply_magnetic_force(delta):
	"""
	Применяет плавную коррекцию траектории пули в сторону цели.
	"""
	var target_pos = target_enemy.global_transform.origin
	var distance = global_transform.origin.distance_to(target_pos)
	
	# Предсказание движения цели для более точного наведения
	var predicted_pos = predict_enemy_position(target_enemy, distance)
	var to_predicted = (predicted_pos - global_transform.origin).normalized()
	
	# Расчет силы притяжения, зависящей от расстояния
	var distance_factor = 1.0 - (distance / magnetic_range)
	distance_factor = max(distance_factor, 0.1) # Минимум 10% силы, даже если далеко в радиусе
	
	# Сбалансированная сила поворота (очень маленькая для "коррекции")
	var attraction_force = magnetic_strength * distance_factor * delta 
	attraction_force = min(attraction_force, 0.01) # Максимум 1% поворота за кадр (очень плавно)
	
	# Плавный поворот: интерполируем текущее направление к направлению на цель
	var new_direction = _direction.lerp(to_predicted, attraction_force).normalized()
	
	# Дополнительное ограничение угла поворота, чтобы избежать резких движений
	# Поворот не более половины magnetic_max_angle
	var angle_limit_rad = deg_to_rad(magnetic_max_angle / 2.0) 
	if _direction.angle_to(new_direction) > angle_limit_rad:
		new_direction = _direction.slerp(new_direction, angle_limit_rad / _direction.angle_to(new_direction))
	
	_direction = new_direction.normalized() # Убеждаемся, что направление нормализовано
	
	# Поворачиваем визуальную модель пули, чтобы она смотрела по направлению полета
	look_at(global_transform.origin + _direction, Vector3.UP)
	

func predict_enemy_position(enemy: Node3D, distance: float) -> Vector3:
	"""
	Предсказывает будущую позицию врага для более точного наведения.
	"""
	var current_pos = enemy.global_transform.origin
	
	var enemy_velocity = Vector3.ZERO
	if enemy.has_method("get_velocity"):
		enemy_velocity = enemy.get_velocity()
	elif enemy is CharacterBody3D:
		enemy_velocity = enemy.velocity
	
	var time_to_impact = distance / speed # Время, за которое пуля достигнет текущей позиции врага
	var predicted_pos = current_pos + (enemy_velocity * time_to_impact)
	
	return predicted_pos

# ============================================================================
# СИСТЕМА СТОЛКНОВЕНИЙ
# ============================================================================

func handle_collision(collision: KinematicCollision3D):
	"""
	Обрабатывает столкновения пули с другими объектами.
	"""
	var collider = collision.get_collider()
	var impact_normal = collision.get_normal()
	var impact_position = collision.get_position()
	
	# Игнорируем столкновения с другими пулями
	if collider is Bullet:
		return
	
	if collider == _shooter_body:
		print("Bullet.gd: ⚠️ Пуля '%s' столкнулась со стрелком - игнорируем!" % bullet_type)
		return
	
	
	
	# Нанесение урона, если у объекта есть метод take_damage
	if collider and collider.has_method("take_damage"):
		collider.take_damage(damage, impact_position, impact_normal, bullet_type, self)
	
	# Применение импульса к RigidBody3D
	if collider is RigidBody3D:
		var impulse = -impact_normal * impact_force
		collider.apply_central_impulse(impulse)
	# Применение отталкивания к CharacterBody3D
	elif collider is CharacterBody3D:
		if collider.has_method("apply_knockback"):
			var knockback_force = -impact_normal * impact_force * 0.1
			collider.apply_knockback(knockback_force)
		else:
			print("Bullet.gd: ⚠️ CharacterBody3D '%s' не имеет метода apply_knockback()" % collider.name)
	
	# Создание эффекта попадания и удаление пули
	create_impact_effect(impact_position, impact_normal)
	queue_free()

func create_impact_effect(pos: Vector3, normal: Vector3):
	"""Создает визуальный эффект в месте столкновения."""
	# Здесь вы можете добавить код для спавна частиц, декалей и т.д.

func on_life_time_timeout():
	"""Вызывается по истечении времени жизни пули."""
	queue_free()

func set_collision_layers(layer: int, mask: int):
	"""Устанавливает слои и маски коллизий для пули."""
	collision_layer = layer
	collision_mask = mask
	print("Bullet.gd: Установлены collision layer: %d, mask: %d для пули '%s'" % [layer, mask, bullet_type])

func set_magnetic_properties(enabled: bool, range: float = 15.0, strength: float = 3.0, max_angle: float = 90.0):
	"""
	Динамически устанавливает магнетические свойства пули.
	Используется, если нужно переопределить настройки по умолчанию из setup_magnetic_for_weapon_type().
	"""
	enable_magnetic = enabled
	magnetic_range = range
	magnetic_strength = strength
	magnetic_max_angle = max_angle

func disable_magnetic():
	"""Полностью отключает магнетизм для этой пули."""
	enable_magnetic = false
	lose_target()
	
func create_flash_effect():
	"""Создает кратковременную желтоватую вспышку пули с освещением"""
	if is_flashing or not is_instance_valid(mesh_instance):
		return
		
	is_flashing = true
	
	# Сохраняем оригинальный материал
	original_material = mesh_instance.material_override
	
	# Создаем ЯРКИЙ материал вспышки
	var flash_material = StandardMaterial3D.new()
	flash_material.flags_unshaded = true
	flash_material.albedo_color = Color(1.2, 1.0, 0.4, 1.0) # Более яркий желтый
	flash_material.emission_enabled = true
	flash_material.emission = Color(2.0, 1.5, 0.2) # ОЧЕНЬ яркое свечение!
	flash_material.emission_energy = 3.0 # Увеличиваем энергию свечения
	
	# Применяем материал вспышки
	mesh_instance.material_override = flash_material
	
	# Создаем OmniLight3D для освещения окружения
	flash_light = OmniLight3D.new()
	add_child(flash_light)
	flash_light.light_color = Color(1.0, 0.8, 0.3) # Желтоватый свет
	flash_light.light_energy = 0.25 # Яркость света
	flash_light.omni_range = 1.0 # Радиус освещения
	flash_light.omni_attenuation = 2.0 # Затухание света
	
	# Делаем пулю чуть больше во время вспышки
	var original_scale = mesh_instance.scale
	mesh_instance.scale = original_scale * 1.3
	
	# Создаем Tween для плавного эффекта
	flash_tween = create_tween()
	flash_tween.set_parallel(true) # Позволяет несколько анимаций одновременно
	
	# Анимация затухания света
	flash_tween.tween_property(flash_light, "light_energy", 0.0, 0.15)
	
	# Анимация возврата размера пули
	flash_tween.tween_property(mesh_instance, "scale", original_scale, 0.1)
	
	# Возврат материала через callback
	flash_tween.tween_callback(restore_original_material).set_delay(0.12)

func restore_original_material():
	"""Возвращает оригинальный материал после вспышки"""
	if is_instance_valid(mesh_instance) and original_material:
		mesh_instance.material_override = original_material
	
	# Удаляем свет
	if is_instance_valid(flash_light):
		flash_light.queue_free()
		flash_light = null
		
	is_flashing = false
	print("Bullet.gd: Вспышка завершена")
