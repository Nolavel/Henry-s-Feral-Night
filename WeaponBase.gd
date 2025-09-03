# WeaponBase.gd - Улучшенная версия с специфичными для оружия режимами стрельбы
extends Area3D

class_name WeaponBase

@export var weapon_type: String = "unknown"
@export var damage: float = 10.0
@export var fire_rate: float = 0.5
@export var bullet_speed: float = 50.0

@export var clip_size: int = 10
@export var reload_time: float = 2.0
var current_ammo_in_clip: int = 0
var total_carried_ammo: int = 0
var is_reloading: bool = false # Новый флаг для отслеживания перезарядки

@export var bullet_scene: PackedScene
@export var pellets_per_shot: int = 1
@export var spread_angle: float = 0.0
@export var weapon_color: Color = Color.WHITE

# === MUZZLE FLASH CUSTOMIZATION ===
@export_group("Muzzle Flash Effects")
@export_range(0.5, 5.0, 0.1) var blast_line_length: float = 2.0  # Длина серой линии выстрела
@export_range(0.3, 3.0, 0.1) var flash_cone_scale: float = 1.0   # Масштаб конуса вспышки

enum MuzzleFlashColor { 
	ORANGE_RED,      # Классический оранжево-красный
	YELLOW_ORANGE,   # Яркий желто-оранжевый  
	BLUE_WHITE,      # Холодный сине-белый
	GREEN_YELLOW,    # Зелено-желтый (особый порох)
	PURE_WHITE       # Чистый белый (очень яркая вспышка)
}

@export var muzzle_flash_color: MuzzleFlashColor = MuzzleFlashColor.ORANGE_RED

# --- ПОЛНАЯ ЗВУКОВАЯ СИСТЕМА ---
@export var shoot_sound: AudioStream # Звук выстрела
@export var reload_sound: AudioStream # Звук перезарядки
@export var empty_clip_sound: AudioStream # Звук пустой обоймы (щелчок)
@export var activate_sound: AudioStream # Звук активации (вытащил оружие)
@export var deactivate_sound: AudioStream # Звук деактивации (спрятал оружие)

# AudioStreamPlayer'ы для всех звуков
@onready var shoot_audio = $ShootAudio
@onready var reload_audio = $ReloadAudio
@onready var empty_clip_audio = $EmptyClipAudio
@onready var weapon_action_audio = $WeaponActionAudio # Для активации/деактивации

# === NEW: IMAGE EXPORTS FOR UI SYSTEM ===
@export_group("UI Images")
@export var item_image: Texture2D  # Main weapon image for CENTER_BOX
@export var category_image: Texture2D  # Category icon for CATEGORY_BOX (weapon type icon)

# Optional: Alternative paths if you prefer string paths
@export_subgroup("Image Paths (Alternative)")
@export_file("*.png", "*.jpg", "*.svg") var item_image_path: String = ""
@export_file("*.png", "*.jpg", "*.svg") var category_image_path: String = ""

# === UI SETTINGS ===
@export_group("UI Settings")
@export var category_color: Color = Color.ORANGE_RED  # Color for weapon category display
@export var weapon_weight: float = 2.5  # Weight in KG for UI display
@export_multiline var special_marks_text: String = ""  # Custom text for special marks in UI

# --- УЛУЧШЕННАЯ СИСТЕМА РЕЖИМОВ СТРЕЛЬБЫ ---
enum FireMode { SINGLE, BURST, AUTO }

# Доступные режимы для каждого типа оружия
var weapon_fire_modes = {
	"Wasteland Eagle": [FireMode.SINGLE], # Только одиночные выстрелы
	"Enforcer 12-Gauge": [FireMode.SINGLE], # Только одиночные выстрелы
	"Trail Boss Shotgun": [FireMode.SINGLE], # Только одиночные выстрелы
	"Assault Auto-Rifle": [FireMode.SINGLE, FireMode.BURST, FireMode.AUTO], # Все режимы
	"Suppressor MG": [FireMode.AUTO], # Только автоматический
}

# Текущий активный режим стрельбы
var current_fire_mode: FireMode
var current_mode_index: int = 0

# Параметры для режима BURST (только для автоматов)
@export_range(1, 10) var burst_shots: int = 3
@export var burst_delay: float = 0.08

# Внутренние переменные для BURST
var _burst_shots_fired: int = 0
var _burst_timer: Timer

@onready var weapon_visuals: Node3D = $WeaponVisuals
@onready var weapon_mesh: MeshInstance3D = $WeaponVisuals/WeaponMesh
@onready var shoot_timer: Timer = $ShootTimer
@onready var muzzle_flash_point: Node3D = $WeaponVisuals/MuzzleFlashPoint


var empty_clip_timer: Timer # Таймер для отслеживания бездействия при пустой обойме
var is_trying_to_shoot_empty: bool = false # Флаг попыток стрельбы с пустой обоймой
@export var auto_reload_delay: float = 1.0 # Время бездействия до автоперезарядки

signal ui_visibility_changed(visible: bool, item_data: Dictionary)
signal cartridge_ejected(transform: Transform3D)

# ДОБАВИТЬ к существующим переменным (как в BackpackPickup):
var player_in_range: bool = false
var player_reference: Node3D = null
var is_ui_visible: bool = false
var ui_locked_by_shapecast := false
@export var pickup_range: float = 3.0  # Дистанция для подбора
@export var show_ui_distance: float = 5.0

# ДОБАВИТЬ К ПЕРЕМЕННЫМ КЛАССА:
var cartridge_pool: Array[RigidBody3D] = []
var max_cartridges_in_world: int = 15
var cartridge_lifetime: float = 5.0

signal no_ammo_left(weapon_type)
signal ammo_changed(weapon_type, current_in_clip, total_ammo)
signal weapon_reloaded(weapon_type, current_in_clip, total_ammo)
signal fire_mode_changed(weapon_type, new_mode) # Только для оружия с несколькими режимами
signal auto_reload_started(weapon_type)
signal weapon_empty_timeout(weapon_type) # НОВЫЙ СИГНАЛ

# Словарь с путями к пулям
var bullet_paths = {
	"Wasteland Eagle": "res://Bullets/Wasteland Eagle_bullet.tscn",
	"Enforcer 12-Gauge": "res://Bullets/Enforcer 12-Gauge_bullet.tscn",
	"Trail Boss Shotgun": "res://Bullets/Trail Boss Shotgun_pellet.tscn",
	"Assault Auto-Rifle": "res://Bullets/Assault Auto-Rifle_bullet.tscn",
	"Suppressor MG": "res://Bullets/machinegun_bullet.tscn",
}

func _ready():
	
	
	# === NEW: LOAD IMAGES ===
	load_images_from_paths()
	load_default_weapon_images()
	
	_initialize_fire_modes()
	load_all_weapon_sounds()
	
	_burst_timer = Timer.new()
	add_child(_burst_timer)
	_burst_timer.one_shot = true
	_burst_timer.timeout.connect(_on_burst_timer_timeout)
	
	if not bullet_scene and bullet_paths.has(weapon_type):
		var bullet_path = bullet_paths[weapon_type]
		
		if ResourceLoader.exists(bullet_path):
			bullet_scene = load(bullet_path)
			if bullet_scene:
				pass
			else:
				printerr("WeaponBase.gd: ❌ Ошибка загрузки пули для %s из %s" % [weapon_type, bullet_path])
		else:
			printerr("WeaponBase.gd: ❌ Файл пули не найден: %s" % bullet_path)
	elif bullet_scene:
		print("WeaponBase.gd: ✅ bullet_scene уже назначена вручную для %s: %s" % [weapon_type, bullet_scene.resource_path])
	else:
		printerr("WeaponBase.gd: ❌ Неизвестный тип оружия '%s' или не найден путь к пуле!" % weapon_type)
	
	if is_instance_valid(weapon_visuals):
		if not is_instance_valid(weapon_mesh):
			weapon_mesh = weapon_visuals.find_child("WeaponMesh", true, false) as MeshInstance3D
		

	if is_instance_valid(shoot_timer):
		# В _ready подключаем только сигнал стрельбы по умолчанию
		if not shoot_timer.is_connected("timeout", Callable(self, "_on_shoot_timer_timeout")):
			shoot_timer.timeout.connect(_on_shoot_timer_timeout)
	else:
		printerr("WeaponBase.gd: ОШИБКА! ShootTimer не найден для ", name)
	
	if is_instance_valid(weapon_visuals):
		var initial_muzzle_point = weapon_visuals.find_child("MuzzleFlashPoint", true, false) as Node3D
		if initial_muzzle_point:
			muzzle_flash_point = initial_muzzle_point
		else:
			printerr("WeaponBase.gd: MuzzleFlashPoint не найден в weapon_visuals для %s!" % name)
			muzzle_flash_point = self
	else:
		printerr("WeaponBase.gd: weapon_visuals не валиден! Не могу найти MuzzleFlashPoint." % name)
		muzzle_flash_point = self

	if is_in_group("Weapons"):
		show_weapon_in_world()
	else:
		hide_weapon_in_world()
		
	match weapon_type:
		"Wasteland Eagle":
			reload_time = 2.5
		"Enforcer 12-Gauge":
			reload_time = 3.5
		"Trail Boss Shotgun":
			reload_time = 4.0
		"Assault Auto-Rifle":
			reload_time = 3.0
		_:
			reload_time = 2.0
	
	
	# Создаем таймер для автоперезарядки при пустой обойме
	empty_clip_timer = Timer.new()
	add_child(empty_clip_timer)
	empty_clip_timer.one_shot = true
	empty_clip_timer.timeout.connect(_on_empty_clip_timer_timeout)
	
	call_deferred("update_static_body_data")
			
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
		
func _initialize_fire_modes():
	"""Инициализирует доступные режимы стрельбы для данного типа оружия"""
	if weapon_fire_modes.has(weapon_type):
		var available_modes = weapon_fire_modes[weapon_type]
		current_fire_mode = available_modes[0]
		current_mode_index = 0
		print("WeaponBase.gd: Для %s доступны режимы: %s. Текущий: %s" % [
			weapon_type,
			_modes_to_string(available_modes),
			FireMode.keys()[current_fire_mode]
		])
	else:
		current_fire_mode = FireMode.SINGLE
		current_mode_index = 0
		print("WeaponBase.gd: Неизвестный тип оружия %s, используем SINGLE режим" % weapon_type)

func _weapon_supports_burst() -> bool:
	"""Проверяет, поддерживает ли данное оружие режим BURST"""
	if weapon_fire_modes.has(weapon_type):
		return FireMode.BURST in weapon_fire_modes[weapon_type]
	return false

func _weapon_supports_multiple_modes() -> bool:
	"""Проверяет, поддерживает ли данное оружие переключение режимов"""
	if weapon_fire_modes.has(weapon_type):
		return weapon_fire_modes[weapon_type].size() > 1
	return false

func _modes_to_string(modes: Array) -> String:
	"""Конвертирует массив режимов в читаемую строку"""
	var mode_names = []
	for mode in modes:
		mode_names.append(FireMode.keys()[mode])
	return str(mode_names)

func can_toggle_fire_mode() -> bool:
	"""Возвращает true, если данное оружие может переключать режимы стрельбы"""
	return _weapon_supports_multiple_modes()

func toggle_fire_mode():
	"""Переключает режим стрельбы (только для оружия с несколькими режимами)"""
	if not _weapon_supports_multiple_modes() or is_reloading:
		return
	
	var available_modes = weapon_fire_modes[weapon_type]
	current_mode_index = (current_mode_index + 1) % available_modes.size()
	current_fire_mode = available_modes[current_mode_index]
	
	emit_signal("fire_mode_changed", weapon_type, current_fire_mode)
	
	_burst_shots_fired = 0
	if is_instance_valid(_burst_timer):
		_burst_timer.stop()
	shoot_timer.stop()

func get_current_fire_mode_name() -> String:
	"""Возвращает название текущего режима стрельбы"""
	return FireMode.keys()[current_fire_mode]

func shoot(direction: Vector3):
	
	print("ВЫСТРЕЛ: %s, режим: %s, таймер остановлен: %s, перезарядка: %s, патроны: %d" % [
		weapon_type,
		FireMode.keys()[current_fire_mode],
		shoot_timer.is_stopped(),
		is_reloading,
		current_ammo_in_clip
	])

	if is_reloading:
		print("WeaponBase.gd: ❌ Оружие перезаряжается, выстрел невозможен.")
		return

	# ЭМОЦИОНАЛЬНАЯ ЛОГИКА: Обработка пустой обоймы
	if current_ammo_in_clip <= 0:
		
		# Воспроизводим звук пустой обоймы при каждой попытке
		play_empty_clip_sound()
		ComicEffects.show_effect_on_node(weapon_visuals, ComicEffects.EffectType.OBJECT_HIT, "EMPTY!")
		
		# УСТАНАВЛИВАЕМ ЭМОЦИОНАЛЬНОЕ СОСТОЯНИЕ
		is_trying_to_shoot_empty = true
		
		# Перезапускаем таймер автоперезарядки
		if is_instance_valid(empty_clip_timer):
			empty_clip_timer.stop()
			empty_clip_timer.wait_time = auto_reload_delay
			empty_clip_timer.start()
		
		# ТЕПЕРЬ отправляем сигнал (Player должен проверить эмоциональное состояние)
		emit_signal("no_ammo_left", weapon_type)
		return

	# Если есть патроны - сбрасываем эмоциональное состояние
	if is_trying_to_shoot_empty:
		is_trying_to_shoot_empty = false
		if is_instance_valid(empty_clip_timer):
			empty_clip_timer.stop()

	# Остальная логика стрельбы...
	if not shoot_timer.is_stopped():
		return

	match current_fire_mode:
		FireMode.SINGLE:
			_perform_shot(direction)
			_start_timer_safely(shoot_timer, fire_rate, "SINGLE")
		FireMode.BURST:
			if _burst_shots_fired == 0:
				_perform_shot(direction)
				_burst_shots_fired += 1
				
				if _burst_shots_fired < burst_shots and current_ammo_in_clip > 0:
					_start_timer_safely(_burst_timer, burst_delay, "BURST_CONTINUE")
				else:
					_burst_shots_fired = 0
					_start_timer_safely(shoot_timer, fire_rate, "BURST_END")
		FireMode.AUTO:
			_perform_shot(direction)
			_start_timer_safely(shoot_timer, fire_rate, "AUTO")

func _perform_shot(direction: Vector3):
	"""Выполняет один выстрел"""
	current_ammo_in_clip -= 1
	emit_signal("ammo_changed", weapon_type, current_ammo_in_clip, total_carried_ammo)
	
	# ДОБАВЛЕНО: сброс флага при успешном выстреле
	if is_trying_to_shoot_empty:
		is_trying_to_shoot_empty = false
		if is_instance_valid(empty_clip_timer):
			empty_clip_timer.stop()
	
	play_shoot_sound()
	ComicEffects.show_effect_on_node(weapon_visuals, ComicEffects.EffectType.PLAYER_SHOOT)
	create_muzzle_flash_effect(direction)
	if bullet_scene and is_instance_valid(muzzle_flash_point):
		var spawn_pos = muzzle_flash_point.global_transform.origin
		
		for i in range(pellets_per_shot):
			var bullet_instance = bullet_scene.instantiate() as Bullet
			if bullet_instance:
				var spread_direction = direction
				if spread_angle > 0.0:
					var random_angle_h = randf_range(-deg_to_rad(spread_angle), deg_to_rad(spread_angle))
					var random_angle_v = randf_range(-deg_to_rad(spread_angle), deg_to_rad(spread_angle))
					var base_basis = Basis.looking_at(direction, Vector3.UP, true)
					spread_direction = base_basis.rotated(base_basis.y, random_angle_h).rotated(base_basis.x, random_angle_v).z.normalized()
				
				get_tree().root.add_child(bullet_instance)
				bullet_instance.initialize(spawn_pos, spread_direction, bullet_speed, weapon_type, get_parent())
			else:
				printerr("ОТЛАДКА: ❌ Не удалось создать пулю #%d!" % i)
	else:
		printerr("WeaponBase.gd: ❌ Нет bullet_scene или muzzle_flash_point для %s!" % weapon_type)
	
	var muzzle_tf = muzzle_flash_point.global_transform if is_instance_valid(muzzle_flash_point) else global_transform
	emit_signal("cartridge_ejected", muzzle_tf)	
	#if current_ammo_in_clip == 0:
		#emit_signal("no_ammo_left", weapon_type)

func _on_shoot_timer_timeout():
	"""Основной таймер стрельбы завершен"""

func _on_burst_timer_timeout():
	"""Обрабатывает выстрелы внутри очереди (только для BURST режима)"""
	if current_fire_mode != FireMode.BURST or _burst_shots_fired >= burst_shots or is_reloading:
		_burst_shots_fired = 0
		return
		
	if current_ammo_in_clip > 0:
		var shoot_direction = Vector3.FORWARD
		var player_node = get_parent()
		if is_instance_valid(player_node) and player_node.has_node("Head"):
			var head_node = player_node.get_node("Head")
			if is_instance_valid(head_node):
				shoot_direction = -head_node.global_transform.basis.z.normalized()

		_perform_shot(shoot_direction)
		_burst_shots_fired += 1
		
		if _burst_shots_fired < burst_shots and current_ammo_in_clip > 0:
			_start_timer_safely(_burst_timer, burst_delay, "BURST_CONTINUE_TIMEOUT")
		else:
			_burst_shots_fired = 0
			_start_timer_safely(shoot_timer, fire_rate, "BURST_END_TIMEOUT")
	else:
		_burst_shots_fired = 0
		emit_signal("no_ammo_left", weapon_type)
		
func _on_empty_clip_timer_timeout():
	"""Срабатывает через 1.0 сек бездействия при попытках стрельбы с пустой обоймой"""
	
	# Сбрасываем эмоциональное состояние
	is_trying_to_shoot_empty = false
	
	# Решаем что делать дальше
	if total_carried_ammo > 0:
		emit_signal("auto_reload_started", weapon_type)
		start_reload()
	else:
		emit_signal("weapon_empty_timeout", weapon_type)

func _start_timer_safely(timer: Timer, wait_time: float, context: String):
	"""Безопасный запуск таймера с проверками"""
	if not is_instance_valid(timer):
		return
	
	if not timer.is_inside_tree():
		return
	
	if not is_inside_tree():
		return
	
	timer.wait_time = wait_time
	timer.start()

func _on_body_entered(body: Node3D):
	if body.is_in_group("player"):
		print("WeaponBase.gd: Player entered weapon Area3D: ", weapon_type)

func can_be_picked_up() -> bool:
	return true

func hide_weapon_in_world():
	if is_instance_valid(weapon_visuals):
		weapon_visuals.visible = false
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	set_physics_process(false)

func show_weapon_in_world():
	if is_instance_valid(weapon_visuals):
		weapon_visuals.visible = true
	set_deferred("monitoring", true)
	set_deferred("monitorable", true)
	set_physics_process(true)

func add_ammo(amount: int):
	total_carried_ammo += amount
	emit_signal("ammo_changed", weapon_type, current_ammo_in_clip, total_carried_ammo)

func start_reload():
	# Проверка, что перезарядка уже не идёт
	if is_reloading:
		return
	
	if current_ammo_in_clip < clip_size and total_carried_ammo > 0:
		is_reloading = true
		play_reload_sound()
		
		# Задержка перед началом перезарядки (чтобы звук успел начаться)
		await get_tree().create_timer(0.9).timeout
		
		# КРИТИЧЕСКИЕ ПРОВЕРКИ перед использованием таймера
		if not is_instance_valid(shoot_timer):
			printerr("WeaponBase.gd: shoot_timer не валиден при перезарядке!")
			is_reloading = false
			return
		
		if not shoot_timer.is_inside_tree():
			printerr("WeaponBase.gd: shoot_timer не в дереве сцены при перезарядке!")
			is_reloading = false
			return
		
		if not is_inside_tree():
			printerr("WeaponBase.gd: WeaponBase не в дереве сцены при перезарядке!")
			is_reloading = false
			return
		
		# Настройка таймера для перезарядки
		shoot_timer.wait_time = reload_time
		
		# Отключаем старый сигнал
		if shoot_timer.is_connected("timeout", Callable(self, "_on_shoot_timer_timeout")):
			shoot_timer.timeout.disconnect(_on_shoot_timer_timeout)
		# Подключаем новый сигнал перезарядки
		if not shoot_timer.is_connected("timeout", Callable(self, "_on_reload_timer_timeout")):
			shoot_timer.timeout.connect(_on_reload_timer_timeout)
		
		shoot_timer.start()
		print("WeaponBase.gd: Перезарядка %s начата успешно" % weapon_type)
	else:
		print("WeaponBase.gd: Невозможно перезарядить %s: нет патронов или обойма полна." % weapon_type)

# Измененная функция в WeaponBase.gd
func _on_reload_timer_timeout():

	# Отключаем сигнал перезарядки
	if shoot_timer.is_connected("timeout", Callable(self, "_on_reload_timer_timeout")):
		shoot_timer.timeout.disconnect(_on_reload_timer_timeout)
	# Возвращаем сигнал стрельбы
	if not shoot_timer.is_connected("timeout", Callable(self, "_on_shoot_timer_timeout")):
		shoot_timer.timeout.connect(_on_shoot_timer_timeout)

	var ammo_needed = clip_size - current_ammo_in_clip
	var ammo_to_take = min(ammo_needed, total_carried_ammo)

	current_ammo_in_clip += ammo_to_take
	total_carried_ammo -= ammo_to_take

	is_reloading = false # Сброс флага перезарядки в WeaponBase

	emit_signal("ammo_changed", weapon_type, current_ammo_in_clip, total_carried_ammo)
	# emit_signal("weapon_reloaded", weapon_type, current_ammo_in_clip, total_carried_ammo) # <-- Эту строку удаляем

func activate_weapon():
	play_activate_sound()
	
	if is_instance_valid(weapon_visuals):
		var new_muzzle_point = weapon_visuals.find_child("MuzzleFlashPoint", true, false) as Node3D
		if new_muzzle_point:
			muzzle_flash_point = new_muzzle_point
	
	_burst_shots_fired = 0
	is_trying_to_shoot_empty = false  # ДОБАВЛЕНО: сброс флага
	
	if is_instance_valid(_burst_timer):
		_burst_timer.stop()
	if is_instance_valid(shoot_timer):
		shoot_timer.stop()
		if shoot_timer.is_connected("timeout", Callable(self, "_on_reload_timer_timeout")):
			shoot_timer.timeout.disconnect(_on_reload_timer_timeout)
		if not shoot_timer.is_connected("timeout", Callable(self, "_on_shoot_timer_timeout")):
			shoot_timer.timeout.connect(_on_shoot_timer_timeout)
	
	# ДОБАВЛЕНО: остановка таймера автоперезарядки
	if is_instance_valid(empty_clip_timer):
		empty_clip_timer.stop()
	
	is_reloading = false
	
	emit_signal("ammo_changed", weapon_type, current_ammo_in_clip, total_carried_ammo)
	show_weapon_in_world()
	set_physics_process(true)

func deactivate_weapon():
	play_deactivate_sound()
	
	if is_instance_valid(shoot_timer):
		shoot_timer.stop()
	if is_instance_valid(_burst_timer):
		_burst_timer.stop()
	if is_instance_valid(empty_clip_timer):  # ДОБАВЛЕНО: остановка таймера
		empty_clip_timer.stop()
		
	_burst_shots_fired = 0
	is_trying_to_shoot_empty = false  # ДОБАВЛЕНО: сброс флага
	is_reloading = false

	if is_instance_valid(weapon_visuals):
		if is_instance_valid(weapon_visuals.get_parent()) and weapon_visuals.get_parent() != self:
			weapon_visuals.get_parent().remove_child(weapon_visuals)
			self.add_child(weapon_visuals)
			weapon_visuals.position = Vector3.ZERO
			weapon_visuals.rotation = Vector3.ZERO
			weapon_visuals.scale = Vector3(1,1,1)
		hide_weapon_in_world()
	set_physics_process(false)
	
	
func load_specific_sound(sound_name: String, sound_path: String, audio_player: AudioStreamPlayer):
	if ResourceLoader.exists(sound_path):
		var loaded_sound = load(sound_path)
		if loaded_sound:
			match sound_name:
				"shoot":
					shoot_sound = loaded_sound
					if audio_player:
						audio_player.stream = loaded_sound
				"reload":
					reload_sound = loaded_sound
					if audio_player:
						audio_player.stream = loaded_sound
				"empty_clip":
					empty_clip_sound = loaded_sound
					if audio_player:
						audio_player.stream = loaded_sound
				"activate":
					activate_sound = loaded_sound
				"deactivate":
					deactivate_sound = loaded_sound
			
			print("WeaponBase.gd: ✅ Звук '%s' загружен для %s" % [sound_name, weapon_type])
		else:
			print("WeaponBase.gd: ❌ Ошибка загрузки звука '%s': %s" % [sound_name, sound_path])
	else:
		print("WeaponBase.gd: ⚠️ Файл звука '%s' не найден: %s" % [sound_name, sound_path])

func load_all_weapon_sounds():
	var weapon_sounds = {
		"Wasteland Eagle": {
			"shoot": "res://Sounds/SFX/Weapons/Desert-Eagle Pistol_Sounds/s_pistol.mp3",
			"reload": "res://Sounds/SFX/Weapons/Desert-Eagle Pistol_Sounds/reload_pistol.mp3",
			"empty_clip": "res://Sounds/SFX/Weapons/Desert-Eagle Pistol_Sounds/empty_magazine_pistol.mp3",
			"activate": "res://Sounds/SFX/Weapons/Desert-Eagle Pistol_Sounds/Pistol_activate.mp3",
			"deactivate": "res://Sounds/SFX/Weapons/Desert-Eagle Pistol_Sounds/Fall down gun.mp3"
		},
		"Enforcer 12-Gauge": {
			"shoot": "res://Sounds/SFX/Weapons/Enforcer 12-Gauge_Sounds/Enforcer 12-Gauge-shooting.mp3",
			"reload": "res://Sounds/SFX/Weapons/Enforcer 12-Gauge_Sounds/Enforcer 12-Gauge-shoot-Reload.mp3",
			"empty_clip": "res://Sounds/SFX/Weapons/Enforcer 12-Gauge_Sounds/Enforcer 12-Gauge-shoot-empty-clip.mp3",
			"activate": "res://Sounds/SFX/Weapons/Enforcer 12-Gauge_Sounds/Enforcer 12-Gauge-shoot-Activate.mp3",
			"deactivate": "res://Sounds/SFX/Weapons/Enforcer 12-Gauge_Sounds/Enforcer 12-Gauge-shoot-Deactivate.mp3"
		},
		"Trail Boss Shotgun": {
			"shoot": "res://Sounds/SFX/Weapons/Trail Boss Shotgun_Sounds/Trail Boss Shotgun_sooting.mp3",
			"reload": "res://Sounds/SFX/Weapons/Trail Boss Shotgun_Sounds/Trail Boss Shotgun_Reload.mp3",
			"empty_clip": "res://Sounds/SFX/Weapons/Trail Boss Shotgun_Sounds/Trail Boss Shotgun_empty_clip.mp3",
			"activate": "res://Sounds/SFX/Weapons/Trail Boss Shotgun_Sounds/Trail Boss Shotgun_Activate.mp3",
			"deactivate": "res://Sounds/SFX/Weapons/Trail Boss Shotgun_Sounds/Trail Boss Shotgun_Deactivate.mp3"
		},
		"Assault Auto-Rifle": {
			"shoot": "res://Sounds/AutoRifle/auto_rifle_shoot.ogg",
			"reload": "res://Sounds/AutoRifle/auto_rifle_reload.ogg",
			"empty_clip": "res://Sounds/AutoRifle/auto_rifle_empty_click.ogg",
			"activate": "res://Sounds/AutoRifle/auto_rifle_draw.ogg",
			"deactivate": "res://Sounds/AutoRifle/auto_rifle_holster.ogg"
		}
	}
	
	if not weapon_sounds.has(weapon_type):
		return
	
	var sounds = weapon_sounds[weapon_type]
	
	load_specific_sound("shoot", sounds.shoot, shoot_audio)
	load_specific_sound("reload", sounds.reload, reload_audio)
	load_specific_sound("empty_clip", sounds.empty_clip, empty_clip_audio)
	load_specific_sound("activate", sounds.activate, weapon_action_audio)
	load_specific_sound("deactivate", sounds.deactivate, weapon_action_audio)

func play_shoot_sound():
	if is_instance_valid(shoot_audio) and shoot_audio.stream:
		shoot_audio.play()
	else:
		print("WeaponBase.gd: ❌ Не могу воспроизвести звук выстрела: shoot_audio=%s, stream=%s" % [shoot_audio, shoot_audio.stream if shoot_audio else "нет"])

func play_reload_sound():
	print("🔄 Воспроизводим звук перезарядки для %s" % weapon_type)
	
	if not is_instance_valid(reload_audio):
		printerr("❌ reload_audio НЕ ВАЛИДЕН!")
		return
	
	if not reload_audio.stream:
		printerr("❌ У reload_audio НЕТ stream!")
		if reload_sound:
			reload_audio.stream = reload_sound
		else:
			printerr("❌ reload_sound тоже пуст!")
			return
	
	if not reload_audio.is_inside_tree():
		printerr("❌ reload_audio НЕ В ДЕРЕВЕ СЦЕНЫ!")
		return
	
	reload_audio.play()


func play_empty_clip_sound():
	if is_instance_valid(empty_clip_audio) and empty_clip_audio.stream:
		empty_clip_audio.play()
	else:
		print("WeaponBase.gd: ❌ Не могу воспроизвести звук пустой обоймы: empty_clip_audio=%s, stream=%s" % [empty_clip_audio, empty_clip_audio.stream if empty_clip_audio else "нет"])

func play_activate_sound():
	if is_instance_valid(weapon_action_audio) and activate_sound:
		weapon_action_audio.stream = activate_sound
		weapon_action_audio.play()
	else:
		print("WeaponBase.gd: ❌ Не могу воспроизвести звук активации: weapon_action_audio=%s, activate_sound=%s" % [weapon_action_audio, activate_sound])

func play_deactivate_sound():
	if is_instance_valid(weapon_action_audio) and deactivate_sound:
		weapon_action_audio.stream = deactivate_sound
		weapon_action_audio.play()
	else:
		print("WeaponBase.gd: ❌ Не могу воспроизвести звук деактивации: weapon_action_audio=%s, deactivate_sound=%s" % [weapon_action_audio, deactivate_sound])

# === NEW: IMAGE LOADING FUNCTIONS ===
func load_images_from_paths():
	"""Loads images from file paths if textures not assigned directly"""
	
	# Load item image
	if not item_image and item_image_path != "":
		if ResourceLoader.exists(item_image_path):
			item_image = load(item_image_path) as Texture2D
			if item_image:
				pass
			else:
				printerr("WeaponBase.gd: ❌ Failed to load item image: %s" % item_image_path)
		else:
			printerr("WeaponBase.gd: ❌ Item image file not found: %s" % item_image_path)
	
	# Load category image
	if not category_image and category_image_path != "":
		if ResourceLoader.exists(category_image_path):
			category_image = load(category_image_path) as Texture2D
			if category_image:
				pass
			else:
				printerr("WeaponBase.gd: ❌ Failed to load category image: %s" % category_image_path)
		else:
			printerr("WeaponBase.gd: ❌ Category image file not found: %s" % category_image_path)

func load_default_weapon_images():
	"""Loads default images based on weapon type if not already set"""
	
	# ONE category icon for ALL weapons - because all weapons are just "WEAPON" category
	var weapon_category_icon_path = "res://UI/Images/Icons/weapon_icon.png"
	
	# Default weapon images (individual weapon images + universal category icon)
	var default_weapon_images = {
		"Wasteland Eagle": "res://UI/Images/Weapons/wasteland_eagle.png",
		"Enforcer 12-Gauge": "res://UI/Images/Weapons/enforcer_12gauge.png", 
		"Trail Boss Shotgun": "res://UI/Images/Weapons/trail_boss_shotgun.png",
		"Assault Auto-Rifle": "res://UI/Images/Weapons/assault_auto_rifle.png",
		"Suppressor MG": "res://UI/Images/Weapons/suppressor_mg.png"
	}
	
	if not default_weapon_images.has(weapon_type):
		return
	
	var weapon_image_path = default_weapon_images[weapon_type]
	
	# Load individual weapon image if not already set
	if not item_image:
		if ResourceLoader.exists(weapon_image_path):
			item_image = load(weapon_image_path) as Texture2D
			if item_image:
				pass
			else:
				printerr("WeaponBase.gd: ❌ Failed to load default item image for %s" % weapon_type)
		else:
			print("WeaponBase.gd: ⚠️ Default item image not found: %s" % weapon_image_path)
	
	# Load UNIVERSAL category icon for ALL weapons if not already set
	if not category_image:
		if ResourceLoader.exists(weapon_category_icon_path):
			category_image = load(weapon_category_icon_path) as Texture2D
			if category_image:
				pass
			else:
				printerr("WeaponBase.gd: ❌ Failed to load weapon category icon")
		else:
			print("WeaponBase.gd: ⚠️ Universal weapon category icon not found: %s" % weapon_category_icon_path)

# === NEW: IMAGE UTILITY FUNCTIONS ===
func set_item_image_from_path(path: String):
	"""Sets item image from file path (runtime method)"""
	if ResourceLoader.exists(path):
		var texture = load(path) as Texture2D
		if texture:
			item_image = texture
		else:
			printerr("WeaponBase.gd: Failed to load item image: %s" % path)
	else:
		printerr("WeaponBase.gd: Image file not found: %s" % path)

func set_category_image_from_path(path: String):
	"""Sets category image from file path (runtime method)"""
	if ResourceLoader.exists(path):
		var texture = load(path) as Texture2D
		if texture:
			category_image = texture
		else:
			printerr("WeaponBase.gd: Failed to load category image: %s" % path)
	else:
		printerr("WeaponBase.gd: Image file not found: %s" % path)

func has_item_image() -> bool:
	"""Checks if weapon has main image"""
	return item_image != null

func has_category_image() -> bool:
	"""Checks if weapon has category image"""
	return category_image != null

func get_category_color() -> Color:
	"""Returns category color for UI"""
	return category_color

# === NEW: ENHANCED DATA FUNCTION FOR UI ===
func get_weapon_data_for_ui() -> Dictionary:
	"""Returns weapon data for UI system with images"""
	
	# БЕЗОПАСНАЯ ПРОВЕРКА ПОЗИЦИИ
	var world_pos = Vector3.ZERO
	if is_inside_tree():
		world_pos = global_position
	
	return {
		# Basic weapon info
		"name": weapon_type.to_upper(),
		"category": "WEAPON",
		"weight": weapon_weight,
		"special_info": get_special_marks_text(),
		"description": get_weapon_description(),
		
		# Visual data
		"item_image": item_image,
		"category_image": category_image,
		"category_color": category_color,
		
		# World data
		"world_position": world_pos,  # ← ИСПРАВЛЕНО
		"node_reference": self,
		"can_pickup": can_be_picked_up(),
		
		# Weapon-specific data
		"weapon_type": weapon_type,
		"damage": damage,
		"fire_rate": fire_rate,
		"current_fire_mode": get_current_fire_mode_name() if _weapon_supports_multiple_modes() else "SINGLE",
		"item_type": "weapon"
	}


func get_special_marks_text() -> String:
	"""Returns special marks text - custom or auto-generated"""
	if special_marks_text != "":
		# Use custom text from editor
		return special_marks_text
	else:
		# Auto-generate based on weapon stats
		return "DMG: %.0f\nRATE: %.1fs" % [damage, fire_rate]

func get_weapon_description() -> String:
	"""Returns weapon description based on type"""
	var descriptions = {
		"Wasteland Eagle": "Мощный пистолет пустошей. Надёжный спутник выжившего.",
		"Enforcer 12-Gauge": "Компактный дробовик. Эффективен на близких дистанциях.",
		"Trail Boss Shotgun": "Классический помповый дробовик. Проверенная временем классика.",
		"Assault Auto-Rifle": "Автоматическая винтовка. Универсальное оружие для боя.",
		"Suppressor MG": "Пулемёт с глушителем. Для тихого уничтожения."
	}
	
	return descriptions.get(weapon_type, "Оружие выжившего.")


func get_weapon_type() -> String:
	return weapon_type

func get_damage() -> float:
	return damage

func get_fire_rate() -> float:
	return fire_rate

func get_clip_size() -> int:
	return clip_size
	
# === SHAPECAST INTERACTION ===
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

func show_pickup_ui():
	"""Показывает UI подбора"""
	if not is_ui_visible:
		is_ui_visible = true
		var item_data = get_weapon_data_for_ui()
		emit_signal("ui_visibility_changed", true, item_data)  # 🔧 СИГНАЛ

func hide_pickup_ui():
	"""Скрывает UI подбора"""
	if is_ui_visible:
		is_ui_visible = false
		var item_data = get_weapon_data_for_ui()
		emit_signal("ui_visibility_changed", false, item_data)  # 🔧 СИГНАЛ
		
func create_muzzle_flash_effect(shoot_direction: Vector3 = Vector3.FORWARD):
	"""Создает MESH-based эффект вспышки выстрела + линия выстрела + реалистичная световая вспышка"""
	if not is_instance_valid(muzzle_flash_point):
		return
	
	# === ОСНОВНОЙ КОНУС ВСПЫШКИ ===
	var flash_mesh = MeshInstance3D.new()
	
	var cone_mesh = CylinderMesh.new()
	cone_mesh.top_radius = 0.03
	cone_mesh.bottom_radius = 0.2
	cone_mesh.height = 0.5
	
	flash_mesh.mesh = cone_mesh
	
	# Светящийся материал - используем выбранный цвет
	var flash_material = StandardMaterial3D.new()
	flash_material.emission_enabled = true
	flash_material.emission = get_muzzle_flash_color()  # КАСТОМНЫЙ ЦВЕТ
	flash_material.emission_energy = 3.0
	flash_material.albedo_color = get_muzzle_flash_color().lightened(0.3)
	flash_material.flags_transparent = true
	flash_material.flags_unshaded = true
	
	flash_mesh.material_override = flash_material
	muzzle_flash_point.add_child(flash_mesh)
	
	flash_mesh.rotation_degrees = Vector3(0, 0, 90)
	flash_mesh.position = Vector3(-0.159, 0, 0)
	
	# === СЕРАЯ ЛИНИЯ ВЫСТРЕЛА ===
	var blast_line = MeshInstance3D.new()
	
	var line_mesh = CylinderMesh.new()
	line_mesh.top_radius = 0.02
	line_mesh.bottom_radius = 0.02
	line_mesh.height = blast_line_length  # КАСТОМНАЯ ДЛИНА ИЗ ЭКСПОРТА
	
	blast_line.mesh = line_mesh
	
	# Серый полупрозрачный материал
	var line_material = StandardMaterial3D.new()
	line_material.albedo_color = Color(0.7, 0.7, 0.7, 0.6)
	line_material.flags_transparent = true
	line_material.flags_unshaded = true
	
	blast_line.material_override = line_material
	muzzle_flash_point.add_child(blast_line)
	
	blast_line.rotation = muzzle_flash_point.rotation
	blast_line.rotation_degrees.z += 90  
	blast_line.position = Vector3(-2.0, 0, 0)
	
	# === ОСНОВНОЙ НАПРАВЛЕННЫЙ СВЕТ ===
	var main_light = SpotLight3D.new()
	muzzle_flash_point.add_child(main_light)
	main_light.light_energy = 0.005
	main_light.light_color = get_muzzle_flash_color()  # КАСТОМНЫЙ ЦВЕТ СВЕТА
	main_light.spot_range = 10.0
	main_light.spot_angle = 20.0
	main_light.position = Vector3(6.0, 1.0, 0)
	main_light.rotation_degrees = Vector3(0, 90, 0)
	
	# === УЛУЧШЕННАЯ АНИМАЦИЯ ===
	var tween = create_tween()
	tween.set_parallel(true)
	
	# Анимация основного конуса
	flash_mesh.scale = Vector3.ZERO
	var target_scale = Vector3(flash_cone_scale, flash_cone_scale, flash_cone_scale)  # КАСТОМНЫЙ МАСШТАБ
	tween.tween_property(flash_mesh, "scale", target_scale, 0.05)
	tween.tween_property(flash_mesh, "scale", Vector3.ZERO, 0.1).set_delay(0.05)
	
	# Пульсация яркости конуса
	tween.tween_method(func(energy: float): flash_material.emission_energy = energy, 3.0, 0.0, 0.15)
	
	# Анимация серой линии - масштабируется по Y (длине)
	blast_line.scale = Vector3(1, 0.1, 1)
	tween.tween_property(blast_line, "scale", Vector3(1, 1, 1), 0.03)
	tween.tween_property(blast_line, "scale", Vector3(1, 0.1, 1), 0.07).set_delay(0.03)
	
	# АНИМАЦИЯ ОСНОВНОГО НАПРАВЛЕННОГО СВЕТА
	main_light.light_energy = 0.0
	tween.tween_property(main_light, "light_energy", 6.0, 0.02)
	tween.tween_property(main_light, "light_energy", 0.0, 0.08).set_delay(0.02)
	
	# Удаление объектов
	tween.tween_callback(flash_mesh.queue_free).set_delay(0.15)
	tween.tween_callback(blast_line.queue_free).set_delay(0.1)
	tween.tween_callback(main_light.queue_free).set_delay(0.1)
	
	print("Enhanced muzzle flash создан для %s (цвет: %s, длина линии: %.1f)" % [weapon_type, MuzzleFlashColor.keys()[muzzle_flash_color], blast_line_length])

func get_muzzle_flash_color() -> Color:
	"""Возвращает цвет вспышки на основе выбранного enum"""
	match muzzle_flash_color:
		MuzzleFlashColor.ORANGE_RED:
			return Color.ORANGE_RED
		MuzzleFlashColor.YELLOW_ORANGE:
			return Color(1.0, 0.6, 0.0)
		MuzzleFlashColor.BLUE_WHITE:
			return Color(0.8, 0.9, 1.0)
		MuzzleFlashColor.GREEN_YELLOW:
			return Color(0.7, 1.0, 0.3)
		MuzzleFlashColor.PURE_WHITE:
			return Color.WHITE
		_:
			return Color.ORANGE_RED
			
func get_item_data() -> Dictionary:
	return {
		"name": weapon_type.to_upper(),
		"category": "WEAPON",
		"weight": weapon_weight,
		"special_info": get_special_marks_text(),
		"description": get_weapon_description(),
	}

func update_static_body_data():
	if is_instance_valid(weapon_visuals):
		add_to_group("inventory_items")  # Добавляем в правильную группу
		
		var static_body = weapon_visuals.find_child("StaticBody3D", true, false)
		if static_body and static_body.has_method("set_item_data"):
			static_body.set_item_data(get_item_data())
