# AmmoPickup.gd - Updated for PickupUISystem integration
extends Area3D
class_name AmmoPickup

const PlayerClass = preload("res://player.gd")

@export var ammo_type: String = "unknown"
@export var ammo_amount: int = 30

# Материалы для разных типов патронов
@export var pistol_material: StandardMaterial3D
@export var rifle_material: StandardMaterial3D  
@export var shotgun_material: StandardMaterial3D
@export var automatic_material: StandardMaterial3D

# === NEW: IMAGE EXPORTS FOR UI SYSTEM (like WeaponBase) ===
@export_group("UI Images")
@export var item_image: Texture2D  # Main ammo image for CENTER_BOX
@export var category_image: Texture2D  # Category icon for CATEGORY_BOX (ammo type icon)

# Optional: Alternative paths if you prefer string paths
@export_subgroup("Image Paths (Alternative)")
@export_file("*.png", "*.jpg", "*.svg") var item_image_path: String = ""
@export_file("*.png", "*.jpg", "*.svg") var category_image_path: String = ""

# === UI SETTINGS (like WeaponBase) ===
@export_group("UI Settings")
@export var category_color: Color = Color.CYAN  # Color for ammo category display
@export var ammo_weight: float = 0.5  # Weight in KG for UI display
@export_multiline var special_marks_text: String = ""  # Custom text for special marks in UI

@onready var mesh_instance: MeshInstance3D = $CollisionShape3D/weapon_box/ammo_LOW
@onready var pick_up_ammo_sound = $pick_up_ammo_sound

# Переменные для анимации растворения
var dissolve_material: ShaderMaterial
var is_being_picked_up: bool = false
var dissolve_tween: Tween

@export var pickup_range: float = 3.0  # Дистанция для подбора
@export var show_ui_distance: float = 5.0  # Дистанция для показа UI

# ДОБАВИТЬ к переменным состояния:
signal ui_visibility_changed(visible: bool, item_data: Dictionary)

var player_in_range: bool = false
var player_reference: Node3D = null
var is_ui_visible: bool = false
var ui_locked_by_shapecast := false

# === REMOVED: All billboard variables and functionality ===
# БИЛБОРД ПОЛНОСТЬЮ УДАЛЕН - больше не нужен!

func _ready():
	add_to_group("Pickups")

	# === NEW: LOAD IMAGES ===
	load_images_from_paths()
	load_default_ammo_images()
	
	# Настройка материала в зависимости от типа патронов
	setup_material_by_type()
	
	# === NEW: Автоматическая настройка свойств патронов ===
	setup_ammo_properties_by_type()
	
	# Создаем материал с dissolve shader
	create_dissolve_material()
	
	# === РЕГИСТРАЦИЯ В PICKUP UI SYSTEM ===
	register_with_pickup_system()

func setup_ammo_properties_by_type():
	"""Настраивает калибр, вес и количество патронов для каждого типа оружия"""
	
	# Данные по калибрам и характеристикам
	var ammo_properties = {
		"Wasteland Eagle": {
			"caliber": ".50 AE",
			"clip_size": 12,
			"weight_per_round": 0.04,  # 40г за патрон
			"base_weight": 0.1         # Вес упаковки
		},
		"Enforcer 12-Gauge": {
			"caliber": "12 GAUGE",
			"clip_size": 5,
			"weight_per_round": 0.08,  # 80г за патрон (винтовочные патроны тяжелее)
			"base_weight": 0.1
		},
		"Trail Boss Shotgun": {
			"caliber": "20 GAUGE",
			"clip_size": 8,
			"weight_per_round": 0.06,  # 60г за дробовой патрон
			"base_weight": 0.1
		},
		"Assault Auto-Rifle": {
			"caliber": "5.56x45mm",
			"clip_size": 30,
			"weight_per_round": 0.02,  # 20г за автоматный патрон
			"base_weight": 0.15        # Больше упаковка для автомата
		}
	}
	
	if ammo_properties.has(ammo_type):
		var props = ammo_properties[ammo_type]
		
		# Настраиваем special_marks_text (ТОЛЬКО количество)
		special_marks_text = "QTY: %d" % ammo_amount
		
		# Рассчитываем вес (базовый вес + вес патронов)
		ammo_weight = props.base_weight + (ammo_amount * props.weight_per_round)
		
		# Устанавливаем цвет категории по типу оружия
		match ammo_type:
			"Wasteland Eagle":
				category_color = Color.STEEL_BLUE      # Синий для пистолета
			"Enforcer 12-Gauge":
				category_color = Color.FOREST_GREEN    # Зеленый для винтовки
			"Trail Boss Shotgun":
				category_color = Color.FIREBRICK       # Красный для дробовика
			"Assault Auto-Rifle":
				category_color = Color.DARK_ORANGE     # Оранжевый для автомата
		
	else:
		# Значения по умолчанию
		special_marks_text = "QTY: %d" % ammo_amount
		ammo_weight = 0.5
		category_color = Color.GRAY

func get_caliber_for_ammo_type() -> String:
	"""Возвращает калибр для данного типа патронов"""
	var calibers = {
		"Wasteland Eagle": ".50 AE",
		"Enforcer 12-Gauge": "12 GAUGE", 
		"Trail Boss Shotgun": "20 GAUGE",
		"Assault Auto-Rifle": "5.56x45mm"
	}
	
	return calibers.get(ammo_type, "UNKNOWN")

# === REMOVED: All _process, billboard, and distance tracking code ===
# Больше не отслеживаем расстояние до игрока - это делает PickupUISystem!

func register_with_pickup_system():
	"""Регистрирует патроны в PickupUISystem"""
	# Ждем один кадр чтобы система успела инициализироваться
	await get_tree().process_frame
	
	var pickup_systems = get_tree().get_nodes_in_group("pickup_ui_system")
	if pickup_systems.size() > 0:
		var pickup_system = pickup_systems[0]
		if pickup_system.has_method("register_ammo"):
			pickup_system.register_ammo(self)
		else:
			print("AmmoPickup: ⚠️ PickupUISystem не имеет метода register_ammo")
	else:
		print("AmmoPickup: ⚠️ PickupUISystem не найден")

func setup_material_by_type():
	"""Устанавливает материал в зависимости от типа патронов"""
	if not mesh_instance:
		printerr("AmmoPickup: MeshInstance3D не найден!")
		return
		
	match ammo_type:
		"Wasteland Eagle":
			if pistol_material:
				mesh_instance.material_override = pistol_material
			else:
				printerr("AmmoPickup: pistol_material не назначен!")
		"Enforcer 12-Gauge":
			if rifle_material:
				mesh_instance.material_override = rifle_material
			else:
				printerr("AmmoPickup: rifle_material не назначен!")
		"Trail Boss Shotgun":
			if shotgun_material:
				mesh_instance.material_override = shotgun_material
			else:
				printerr("AmmoPickup: shotgun_material не назначен!")
		"Assault Auto-Rifle":
			if automatic_material:
				mesh_instance.material_override = automatic_material
			else:
				printerr("AmmoPickup: automatic_material не назначен!")
		_:
			printerr("AmmoPickup: Неизвестный ammo_type '%s'." % ammo_type)

func create_dissolve_material():
	"""Создает материал с dissolve shader для анимации исчезновения"""
	if not mesh_instance:
		return
		
	# Загружаем shader
	var dissolve_shader = load("res://shaders/dissolve_shader_material.gdshader") as Shader
	if not dissolve_shader:
		return
	
	# Создаем материал с shader'ом
	dissolve_material = ShaderMaterial.new()
	dissolve_material.shader = dissolve_shader
	
	# Копируем текущий материал (если есть) в dissolve материал
	var current_material = mesh_instance.get_surface_override_material(0)
	if current_material and current_material is StandardMaterial3D:
		var std_mat = current_material as StandardMaterial3D
		
		# Устанавливаем цвет и текстуру в dissolve материал
		dissolve_material.set_shader_parameter("albedo_color", std_mat.albedo_color)
		if std_mat.albedo_texture:
			dissolve_material.set_shader_parameter("albedo_texture", std_mat.albedo_texture)
	else:
		# Если материала нет, используем цвет по типу патронов
		dissolve_material.set_shader_parameter("albedo_color", get_ammo_color())
	
	# Настраиваем параметры dissolve
	dissolve_material.set_shader_parameter("dissolve_amount", 0.0)
	dissolve_material.set_shader_parameter("dissolve_color", Color(0.0, 1.0, 1.0, 1.0)) # Голубое свечение
	dissolve_material.set_shader_parameter("dissolve_width", 0.15)
	dissolve_material.set_shader_parameter("dissolve_type", 3) # Шумовое растворение
	dissolve_material.set_shader_parameter("noise_scale", 4.0)
	dissolve_material.set_shader_parameter("glow_intensity", 2.5)

# === CHANGED: Manual pickup instead of automatic ===
func _on_body_entered(body: Node3D):
	"""Обрабатывает вход игрока в зону - ТЕПЕРЬ НЕ ПОДБИРАЕТ АВТОМАТИЧЕСКИ"""
	if body.is_in_group("player"):
		print("AmmoPickup: Игрок вошел в зону %s - ждем команды подбора через PickupUISystem" % ammo_type)
		# Больше не подбираем автоматически - это делает PickupUISystem при нажатии "pickup"

# === NEW: Manual pickup method for PickupUISystem ===
func pickup_by_player(player_node: Node3D) -> bool:
	"""Подбирает патроны игроком (вызывается PickupUISystem)"""
	if is_being_picked_up:
		return false
		
	var player_script = player_node as PlayerClass
	if player_script:
		is_being_picked_up = true
		
		# Отключаем коллизию отложенно
		set_deferred("monitoring", false)
		set_deferred("monitorable", false)
		
		# ИСПРАВЛЕНИЕ: Используем inventory_manager вместо прямого вызова
		if player_script.inventory_manager:
			player_script.inventory_manager.add_ammo(ammo_type, ammo_amount)
			print("AmmoPickup: ✅ Игрок подобрал %d патронов типа %s через InventoryManager." % [ammo_amount, ammo_type])
		else:
			printerr("AmmoPickup: ❌ InventoryManager не найден у игрока!")
			return false
		
		# Запускаем звук и анимацию растворения
		start_pickup_sequence()
		return true
	else:
		printerr("AmmoPickup: ❌ Переданный узел не является Player.")
		return false

func start_pickup_sequence():
	"""Запускает последовательность подбора: звук + анимация растворения"""
	# Воспроизводим звук
	if pick_up_ammo_sound:
		pick_up_ammo_sound.play()
	
	# Переключаемся на dissolve материал
	if dissolve_material and mesh_instance:
		mesh_instance.material_override = dissolve_material
	
	# Запускаем анимацию растворения
	start_dissolve_animation()

func start_dissolve_animation():
	"""Запускает анимацию растворения мэша"""
	if dissolve_tween:
		dissolve_tween.kill()
	
	dissolve_tween = create_tween()
	dissolve_tween.set_ease(Tween.EASE_IN_OUT)
	dissolve_tween.set_trans(Tween.TRANS_CUBIC)
	
	# Анимируем dissolve_amount от 0.0 до 1.0 за 1 секунду
	var dissolve_callback = func(value: float):
		if dissolve_material:
			dissolve_material.set_shader_parameter("dissolve_amount", value)
	
	dissolve_tween.tween_method(dissolve_callback, 0.0, 1.0, 1.0)
	
	# Когда анимация завершится, удаляем объект
	dissolve_tween.tween_callback(finish_pickup)

func finish_pickup():
	"""Завершает процесс подбора и удаляет объект"""
	print("AmmoPickup: Анимация растворения завершена, удаляем объект.")
	queue_free()

func get_ammo_color() -> Color:
	"""Возвращает цвет для данного типа патронов"""
	match ammo_type:
		"Wasteland Eagle":
			return Color.BLUE
		"Enforcer 12-Gauge":
			return Color.GREEN  
		"Trail Boss Shotgun":
			return Color.RED
		"Assault Auto-Rifle":
			return Color.ORANGE
		_:
			return Color.WHITE

# === NEW: IMAGE LOADING FUNCTIONS (like WeaponBase) ===
func load_images_from_paths():
	"""Loads images from file paths if textures not assigned directly"""
	
	# Load item image
	if not item_image and item_image_path != "":
		if ResourceLoader.exists(item_image_path):
			item_image = load(item_image_path) as Texture2D
			if item_image:
				print("AmmoPickup: ✅ Item image loaded from: %s" % item_image_path)
			else:
				printerr("AmmoPickup: ❌ Failed to load item image: %s" % item_image_path)
		else:
			printerr("AmmoPickup: ❌ Item image file not found: %s" % item_image_path)
	
	# Load category image
	if not category_image and category_image_path != "":
		if ResourceLoader.exists(category_image_path):
			category_image = load(category_image_path) as Texture2D
			if category_image:
				print("AmmoPickup: ✅ Category image loaded from: %s" % category_image_path)
			else:
				printerr("AmmoPickup: ❌ Failed to load category image: %s" % category_image_path)
		else:
			printerr("AmmoPickup: ❌ Category image file not found: %s" % category_image_path)

func load_default_ammo_images():
	"""Loads default images based on ammo type if not already set"""
	
	# ONE category icon for ALL ammo - because all ammo is just "AMMO" category
	var ammo_category_icon_path = "res://UI/Images/Icons/ammo_icon.png"
	
	# Default ammo images (individual ammo images + universal category icon)
	var default_ammo_images = {
		"Wasteland Eagle": "res://UI/Images/Ammo/wasteland_eagle_ammo.png",
		"Enforcer 12-Gauge": "res://UI/Images/Ammo/enforcer_12gauge_ammo.png", 
		"Trail Boss Shotgun": "res://UI/Images/Ammo/trail_boss_shotgun_ammo.png",
		"Assault Auto-Rifle": "res://UI/Images/Ammo/assault_auto_rifle_ammo.png",
	}
	
	if not default_ammo_images.has(ammo_type):
		return
	
	var ammo_image_path = default_ammo_images[ammo_type]
	
	# Load individual ammo image if not already set
	if not item_image:
		if ResourceLoader.exists(ammo_image_path):
			item_image = load(ammo_image_path) as Texture2D
			if item_image:
				pass
			else:
				printerr("AmmoPickup: ❌ Failed to load default item image for %s" % ammo_type)
		else:
			print("AmmoPickup: ⚠️ Default item image not found: %s" % ammo_image_path)
	
	# Load UNIVERSAL category icon for ALL ammo if not already set
	if not category_image:
		if ResourceLoader.exists(ammo_category_icon_path):
			category_image = load(ammo_category_icon_path) as Texture2D
			if category_image:
				pass
			else:
				printerr("AmmoPickup: ❌ Failed to load ammo category icon")
		else:
			print("AmmoPickup: ⚠️ Universal ammo category icon not found: %s" % ammo_category_icon_path)

# === NEW: MAIN UI DATA FUNCTION (like WeaponBase.get_weapon_data_for_ui) ===
func get_ammo_data_for_ui() -> Dictionary:
	"""Returns ammo data for UI system with images (like WeaponBase)"""
	
	# Получаем калибр для отображения в имени
	var caliber = get_caliber_for_ammo_type()
	
	return {
		# Basic ammo info - КАЛИБР В ИМЕНИ!
		"name": caliber,  # Например: ".50 AE AMMO" или "12 GAUGE AMMO"
		"category": "AMMO",
		"weight": ammo_weight,
		"special_info": get_special_marks_text(),  # Только количество: "QTY: 12"
		"description": get_ammo_description(),
		
		# Visual data
		"item_image": item_image,  # Main ammo image for CENTER_BOX
		"category_image": category_image,  # Category icon for CATEGORY_BOX
		"category_color": category_color,
		
		# World data
		"world_position": global_position,
		"node_reference": self,
		"can_pickup": can_be_picked_up(),
		
		# Ammo-specific data
		"ammo_type": ammo_type,
		"ammo_amount": ammo_amount,
		"item_type": "ammo"  # For UI system to identify item type
	}

func get_special_marks_text() -> String:
	"""Returns special marks text - только количество патронов"""
	if special_marks_text != "":
		# Use custom text from editor (уже настроено в setup_ammo_properties_by_type как "QTY: X")
		return special_marks_text
	else:
		# Fallback: только количество
		return "QTY: %d" % ammo_amount

func get_ammo_description() -> String:
	"""Returns ammo description based on type"""
	var descriptions = {
		"Wasteland Eagle": "Патроны калибра .50 для пистолета пустошей.",
		"Enforcer 12-Gauge": "Винтовочные патроны 12-го калибра.",
		"Trail Boss Shotgun": "Дробовые патроны для помпового дробовика.",
		"Assault Auto-Rifle": "Патроны для автоматической винтовки.",
	}
	
	return descriptions.get(ammo_type, "Боеприпасы для выжившего.")

# === NEW: UTILITY FUNCTIONS ===
func can_be_picked_up() -> bool:
	"""Checks if ammo can be picked up"""
	return not is_being_picked_up

func get_ammo_type() -> String:
	"""Returns ammo type"""
	return ammo_type

func get_ammo_amount() -> int:
	"""Returns ammo amount"""
	return ammo_amount

func has_item_image() -> bool:
	"""Checks if ammo has main image"""
	return item_image != null

func has_category_image() -> bool:
	"""Checks if ammo has category image"""
	return category_image != null

func get_category_color() -> Color:
	"""Returns category color for UI"""
	return category_color

# === NEW: IMAGE UTILITY FUNCTIONS ===
func set_item_image_from_path(path: String):
	"""Sets item image from file path (runtime method)"""
	if ResourceLoader.exists(path):
		var texture = load(path) as Texture2D
		if texture:
			item_image = texture
		else:
			printerr("AmmoPickup: Failed to load item image: %s" % path)
	else:
		printerr("AmmoPickup: Image file not found: %s" % path)

func set_category_image_from_path(path: String):
	"""Sets category image from file path (runtime method)"""
	if ResourceLoader.exists(path):
		var texture = load(path) as Texture2D
		if texture:
			category_image = texture
		else:
			printerr("AmmoPickup: Failed to load category image: %s" % path)
	else:
		printerr("AmmoPickup: Image file not found: %s" % path)

func show_pickup_ui():
	"""Показывает UI подбора"""
	if not is_ui_visible:
		is_ui_visible = true
		var item_data = get_ammo_data_for_ui()
		emit_signal("ui_visibility_changed", true, item_data)  # 🔧 СИГНАЛ

func hide_pickup_ui():
	"""Скрывает UI подбора"""
	if is_ui_visible:
		is_ui_visible = false
		var item_data = get_ammo_data_for_ui()
		emit_signal("ui_visibility_changed", false, item_data)  # 🔧 СИГНАЛ

# ДОБАВИТЬ _process логику (как в BackpackPickup):
func _process(delta):
	if ui_locked_by_shapecast:
		return  # 🚀 Полностью игнорим UI-логику, пока ShapeCast держит

	if not player_reference or not is_instance_valid(player_reference):
		return

	var distance = global_position.distance_to(player_reference.global_position)
	if distance <= show_ui_distance and not is_ui_visible:
		show_pickup_ui()
	elif distance > show_ui_distance and is_ui_visible:
		hide_pickup_ui()

# ДОБАВИТЬ interaction_triggered (как в BackpackPickup):
func interaction_triggered(source: Node3D):
	player_reference = source.get_parent() if source.get_parent() else source
	player_in_range = true

	if source is ShapeCast3D:
		ui_locked_by_shapecast = true
		if not is_ui_visible:
			show_pickup_ui()
	else:
		ui_locked_by_shapecast = false
		show_pickup_ui()
