# PhysicsTestObject.gd - Взрывающаяся бочка с уроном игроку + ЗВУКИ И ЭФФЕКТЫ
extends RigidBody3D

class_name PhysicsTestObject

@export var object_type: String = "barrel"
@export var mass_multiplier: float = 1.0
@export var bounce_force_multiplier: float = 1.0
@export var health: float = 100.0
@export var show_damage_numbers: bool = true

# ВЗРЫВ И УРОН ИГРОКУ
@export var explosion_damage: float = 50.0  # Урон от взрыва
@export var explosion_radius: float = 10.0  # Радиус взрыва
@export var max_explosion_damage: float = 80.0  # Максимальный урон (в центре)

# ЗВУКОВЫЕ ЭФФЕКТЫ
@export var hit_sounds: Array[AudioStream] = []  # Массив звуков попадания по металлу
@export var explosion_sound: AudioStream  # Звук взрыва
@export var audio_volume: float = 0.8  # Громкость звуков

var max_health: float
var is_destroyed: bool = false

# Теперь ищем любой Node3D (твой GLB файл бочки)
@onready var visual_model: Node3D = $barrel
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

# АУДИО ПЛЕЕРЫ
@onready var hit_audio_player = $hit_audio_player
@onready var explosion_audio_player = $explosion_audio_player

# Для доступа к MeshInstance3D внутри GLB модели
var mesh_instance: MeshInstance3D

func _ready():
	max_health = health
	
	# Настройка физики для перемещения игроком
	can_sleep = true
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	
	# Добавляем в группу для поиска пулями
	add_to_group("physics_objects")
	
	# Ищем MeshInstance3D внутри GLB модели
	find_mesh_instance()
	
	# Настраиваем массу
	mass = 8.0 * mass_multiplier
	
	# Настройка материала
	setup_physics_material()
	
	# ЗАГРУЖАЕМ СТАНДАРТНЫЕ ЗВУКИ ЕСЛИ НЕ НАЗНАЧЕНЫ
	load_default_sounds()


func load_default_sounds():
	"""Загружает стандартные звуки если не назначены в редакторе"""
	# Если массив звуков попадания пуст, пытаемся загрузить стандартные
	if hit_sounds.size() == 0:
		# Добавьте сюда пути к вашим звукам попадания по металлу
		var default_hit_paths = [
			"res://Sounds/SFX/barrel_hit_sounds/hit_sounds_barrel_1.mp3", 
			"res://Sounds/SFX/barrel_hit_sounds/hit_sounds_barrel_2.mp3",
			"res://Sounds/SFX/barrel_hit_sounds/hit_sounds_barrel_3.mp3"
		]
		
		for path in default_hit_paths:
			if ResourceLoader.exists(path):
				var sound = load(path) as AudioStream
				if sound:
					hit_sounds.append(sound)
					print("PhysicsTestObject.gd: ✅ Загружен звук попадания: %s" % path)
			else:
				print("PhysicsTestObject.gd: ⚠️ Звук не найден: %s" % path)
	
	# Если звук взрыва не назначен, пытаемся загрузить стандартный
	if not explosion_sound:
		var explosion_path = "res://Audio/SFX/explosion.ogg"
		if ResourceLoader.exists(explosion_path):
			explosion_sound = load(explosion_path)
			print("PhysicsTestObject.gd: ✅ Загружен звук взрыва: %s" % explosion_path)
		else:
			print("PhysicsTestObject.gd: ⚠️ Звук взрыва не найден: %s" % explosion_path)

func find_mesh_instance():
	"""Ищет MeshInstance3D внутри загруженной GLB модели"""
	if visual_model:
		# Ищем MeshInstance3D в детях GLB модели
		mesh_instance = find_mesh_instance_recursive(visual_model)
		if mesh_instance:
			pass
		else:
			print("PhysicsTestObject.gd: ⚠️ MeshInstance3D не найден в модели")

func find_mesh_instance_recursive(node: Node) -> MeshInstance3D:
	"""Рекурсивно ищет MeshInstance3D"""
	if node is MeshInstance3D:
		return node as MeshInstance3D
	
	for child in node.get_children():
		var result = find_mesh_instance_recursive(child)
		if result:
			return result
	
	return null

func setup_physics_material():
	"""Настраивает физический материал для отскоков"""
	var physics_material = PhysicsMaterial.new()
	physics_material.bounce = 0.4  # Отскок
	physics_material.friction = 0.7  # Трение
	physics_material_override = physics_material

func take_damage(amount: float, hit_position: Vector3, hit_normal: Vector3, bullet_type: String = "unknown", bullet_node: Node3D = null):
	"""Получение урона от пули"""
	health -= amount	
	# Визуальный эффект попадания
	create_hit_effect(hit_position, hit_normal)
	
	# Показываем числа урона
	if show_damage_numbers:
		show_damage_number(amount, hit_position)
	
	# Дополнительная сила от попадания
	var impulse_force = -hit_normal * 5.0 * bounce_force_multiplier
	apply_impulse(impulse_force, hit_position - global_transform.origin)
	
	# Уничтожение при 0 HP
	if health <= 0 and not is_destroyed:
		destroy_object()

func create_hit_effect(pos: Vector3, normal: Vector3):
	"""Создает эффект попадания + ЗВУК"""
	ComicEffects.show_effect_on_node(self, ComicEffects.EffectType.OBJECT_HIT)
	
	# ВОСПРОИЗВОДИМ СЛУЧАЙНЫЙ ЗВУК ПОПАДАНИЯ ПО МЕТАЛЛУ
	play_random_hit_sound()
	
	# Временное изменение цвета при попадании
	flash_damage_color()

func play_random_hit_sound():
	"""Воспроизводит случайный звук попадания по металлу"""
	if hit_sounds.size() == 0 or not hit_audio_player:
		print("PhysicsTestObject.gd: ⚠️ Нет звуков попадания или аудио плеера")
		return
	
	# Выбираем случайный звук
	var random_index = randi() % hit_sounds.size()
	var selected_sound = hit_sounds[random_index]
	
	if selected_sound:
		hit_audio_player.stream = selected_sound
		hit_audio_player.play()
		print("PhysicsTestObject.gd: 🔊 Воспроизводим звук попадания #%d" % random_index)
	else:
		print("PhysicsTestObject.gd: ⚠️ Выбранный звук попадания невалиден")

func flash_damage_color():
	"""Мигает красным при получении урона"""
	if not mesh_instance:
		return
		
	# Получаем оригинальный материал
	var original_material = mesh_instance.get_surface_override_material(0)
	if not original_material:
		original_material = mesh_instance.mesh.surface_get_material(0)
	
	# Создаем материал для эффекта урона
	var damage_material: StandardMaterial3D
	if original_material:
		damage_material = original_material.duplicate()
	else:
		damage_material = StandardMaterial3D.new()
	
	damage_material.albedo_color = Color.RED
	damage_material.emission = Color.RED
	damage_material.emission_energy = 0.3
	
	# Применяем эффект
	mesh_instance.set_surface_override_material(0, damage_material)
	
	# Возвращаем оригинальный материал через 0.1 секунды
	await get_tree().create_timer(0.1).timeout
	if mesh_instance and is_instance_valid(mesh_instance):
		mesh_instance.set_surface_override_material(0, original_material)

func show_damage_number(amount: float, position: Vector3):
	"""Показывает числа урона"""
	# TODO: Добавить 3D Label для отображения урона

func destroy_object():
	"""Уничтожает объект с ВЗРЫВОМ и уроном игроку"""
	is_destroyed = true
	
	# ВЗРЫВ с уроном игроку
	create_explosion_damage()
	
	# Эффект взрыва + ЗВУК + ВИЗУАЛЬНЫЙ ШАР
	create_destruction_effect()
	
	# Удаляем через секунду (чтобы эффекты успели проиграться)
	await get_tree().create_timer(1.0).timeout
	if is_instance_valid(self):
		queue_free()

func create_explosion_damage():
	"""Наносит урон игроку в зависимости от расстояния"""
	# Ищем игрока
	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return
	
	var distance = global_transform.origin.distance_to(player.global_transform.origin)
	
	if distance > explosion_radius:
		return
	
	# Вычисляем урон по расстоянию
	var damage_factor = 1.0 - (distance / explosion_radius)  # От 1.0 (близко) до 0.0 (далеко)
	var actual_damage = max_explosion_damage * damage_factor
	
	# Наносим урон игроку
	if player.has_method("take_damage"):
		player.take_damage(actual_damage, global_transform.origin, Vector3.UP, "explosion")
	elif player.has_method("damage"):
		player.damage(actual_damage)
	else:
		print("PhysicsTestObject.gd: ⚠️ У игрока нет метода для получения урона")
	
	# Отталкиваем игрока
	if player.has_method("apply_knockback"):
		var knockback_direction = (player.global_transform.origin - global_transform.origin).normalized()
		var knockback_force = knockback_direction * (50.0 * damage_factor)
		player.apply_knockback(knockback_force)
		print("PhysicsTestObject.gd: 💨 Игрок оттолкнут силой: %s" % knockback_force)

func create_destruction_effect():
	"""Создает эффект разрушения + ЗВУК ВЗРЫВА + КРАСНЫЙ ШАР"""
	ComicEffects.show_effect_on_node(self, ComicEffects.EffectType.EXPLOSION)
	
	# ВОСПРОИЗВОДИМ ЗВУК ВЗРЫВА
	play_explosion_sound()
	
	# СОЗДАЕМ КРАСНЫЙ ШАР ВЗРЫВА
	create_explosion_sphere()
	
	if not mesh_instance:
		return
		
	# Создаем эффект разрушения
	var destruction_material = StandardMaterial3D.new()
	destruction_material.albedo_color = Color.BLACK
	destruction_material.emission = Color.ORANGE
	destruction_material.emission_energy = 0.8
	
	mesh_instance.set_surface_override_material(0, destruction_material)
	
	# Добавляем вращение
	angular_velocity = Vector3(randf_range(-5, 5), randf_range(-5, 5), randf_range(-5, 5))

func play_explosion_sound():
	"""Воспроизводит звук взрыва"""
	if not explosion_sound or not explosion_audio_player:
		print("PhysicsTestObject.gd: ⚠️ Нет звука взрыва или аудио плеера")
		return
	
	explosion_audio_player.stream = explosion_sound
	explosion_audio_player.play()
	print("PhysicsTestObject.gd: 💥🔊 Воспроизводим звук взрыва")

func create_explosion_sphere():
	"""Создает красный полупрозрачный шар взрыва с твином от 1x1 до 10x10"""
	# Создаем узел для шара
	var explosion_sphere = MeshInstance3D.new()
	explosion_sphere.name = "ExplosionSphere"
	
	# Создаем сферу
	var sphere_mesh = SphereMesh.new()
	sphere_mesh.radius = 0.5  # Начальный радиус (будет масштабироваться)
	sphere_mesh.height = 1.0
	explosion_sphere.mesh = sphere_mesh
	
	# Создаем материал для красного полупрозрачного шара
	var explosion_material = StandardMaterial3D.new()
	explosion_material.albedo_color = Color(1.0, 0.2, 0.0, 0.6)  # Красный с прозрачностью
	explosion_material.emission = Color(1.0, 0.4, 0.0)  # Оранжевое свечение
	explosion_material.emission_energy = 2.0
	explosion_material.flags_transparent = true
	explosion_material.no_depth_test = true
	explosion_material.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	
	explosion_sphere.material_override = explosion_material
	
	# Добавляем в сцену на позиции взрыва
	get_tree().root.add_child(explosion_sphere)
	explosion_sphere.global_position = global_position
	
	# Начальный масштаб 1x1x1
	explosion_sphere.scale = Vector3(1, 1, 1)
	
	# СОЗДАЕМ ТВИН ДЛЯ АНИМАЦИИ РАСШИРЕНИЯ
	var tween = create_tween()
	tween.set_parallel(true)  # Позволяет запускать несколько анимаций одновременно
	
	# Анимация расширения от 1x1x1 до 10x10x10 за 0.3 секунды
	tween.tween_property(explosion_sphere, "scale", Vector3(10, 10, 10), 0.3)
	
	# ИСПРАВЛЕННАЯ анимация прозрачности - используем lambda функцию
	tween.tween_method(func(alpha: float): fade_explosion_sphere(explosion_sphere, alpha), 0.6, 0.0, 0.5)
	
	# Удаляем шар через 0.5 секунд
	tween.tween_callback(explosion_sphere.queue_free).set_delay(0.5)
	
	print("PhysicsTestObject.gd: 🔴 Создан шар взрыва с анимацией масштаба")

func fade_explosion_sphere(sphere: MeshInstance3D, alpha: float):
	"""Постепенно делает шар взрыва прозрачным"""
	if not is_instance_valid(sphere) or not sphere.material_override:
		return
	
	var material = sphere.material_override as StandardMaterial3D
	if material:
		var current_color = material.albedo_color
		material.albedo_color = Color(current_color.r, current_color.g, current_color.b, alpha)

# Функция для отладки - показывает структуру узлов
func debug_node_structure(node: Node = null, indent: int = 0):
	"""Отображает структуру узлов для отладки"""
	if not node:
		node = self
	
	var spaces = ""
	for i in indent:
		spaces += "  "
	
	print("%s%s (%s)" % [spaces, node.name, node.get_class()])
	
	for child in node.get_children():
		debug_node_structure(child, indent + 1)
