# ✅ Script: PlayerInventoryManager.gd
# (Eng) Manages player inventory system, weapon switching, ammo handling and all that complex shit
# (Rus) Управляет системой инвентаря игрока, переключением оружия, патронами и всей этой сложной фигнёй
# ⚡ Prototype 🔧 WIP — raw, unfinished crap 🐛 Not Optimized / прототип, незавершённый, неоптимизированный

extends Node
class_name PlayerInventoryManager

# (Eng) Signals - notify other systems when inventory shit changes
# (Rus) Сигналы - уведомляют другие системы когда инвентарная фигня меняется
signal weapon_switched(weapon_type: String)
signal weapon_dropped(weapon_type: String)
signal ammo_changed(weapon_type: String, current: int, total: int)
signal inventory_updated()

# (Eng) Core inventory state - keeps track of all the weapons and bullshit
# (Rus) Основное состояние инвентаря - отслеживает всё оружие и фигню
var inventory: Dictionary = {} # {weapon_type: WeaponBase}
var active_weapon_type: String = ""
var current_weapon_area: WeaponBase = null
var current_weapon_visuals: Node3D = null

# (Eng) Backpack system - moved from Player, handles carrying capacity
# (Rus) Система рюкзака - перенесена из Player, управляет вместимостью
var has_backpack: bool = false
var current_backpack_type: String = ""
var backpack_node: Node3D = null
var backpack_ui: Node = null

# (Eng) Ammo storage - centralized bullet management so weapons don't hoard their own shit
# (Rus) Хранение патронов - централизованное управление пулями чтобы оружие не копило свою фигню
var stored_ammo: Dictionary = {
	"Wasteland Eagle": 0,
	"Enforcer 12-Gauge": 0,
	"Trail Boss Shotgun": 0,
	"Assault Auto-Rifle": 0
}

# (Eng) Node references - all the UI and game object connections we need
# (Rus) Ссылки на узлы - все UI и игровые объекты которые нам нужны
var player: CharacterBody3D
@onready var weapon_holder = $"../Head/WeaponHolder"
@onready var ammo_ui = $"../../UI/Ammo"
@onready var weapon_slot_ui = $"../../UI/Ammo/Arsenal"
@onready var ammo_ui_container = $"../../UI/visual_ammo_container"
@onready var reload_timer: Timer = $"../Head/WeaponHolder/ReloadTimer"
@onready var pickup_notifier: PickupNotifier = $"../../UI/PickupNotifier"
@onready var cartridge_manager: CartridgeManager = $"../Head/WeaponHolder/CartridgeManager"

# (Eng) Weapon slots on player spine - where visual models go when not active
# (Rus) Слоты оружия на спине игрока - куда идут визуальные модели когда не активны
@onready var Spine = $"../Spine"
@onready var Slot_Pistol = $"../Spine/SpineSlot_Pistol"
@onready var Slot_LA_Shotgun = $"../Spine/SpineSlot_Lever-Action Shotgun"
@onready var Slot_PA_Shotgun = $"../Spine/SpineSlot_Pump-Action Shotgun"
@onready var Slot_AA_Rifle = $"../Spine/SpineSlot_Assault Auto-Rifle"

# (Eng) Backpack node references - moved from Player class
# (Rus) Ссылки на узлы рюкзака - перенесены из класса Player
@onready var backpack_node_ref = $"../Backpack"
@onready var backpack_ui_ref = $"../../UI/Ammo/BackpackUI"

var is_reloading: bool = false

# (Eng) Weapon priority and config - defines which weapons are better and their stats
# (Rus) Приоритет и конфигурация оружия - определяет какое оружие лучше и их характеристики
const WEAPON_PRIORITY_ORDER = ["Wasteland Eagle", "Enforcer 12-Gauge", "Trail Boss Shotgun", "Assault Auto-Rifle"]

const WEAPON_CLIP_SIZES = {
	"Wasteland Eagle": 12,
	"Enforcer 12-Gauge": 5,
	"Trail Boss Shotgun": 8,
	"Assault Auto-Rifle": 30
}

func _ready():
	# (Eng) Connect to pickup system - listen for when player grabs stuff
	# (Rus) Подключаемся к системе подбора - слушаем когда игрок хватает барахло
	var pickup_system = get_tree().get_first_node_in_group("pickup_ui_system")
	if pickup_system:
		pickup_system.item_picked_up.connect(_on_item_picked_up)
		print("PlayerInventoryManager: Подключен к PickupUISystem")

func setup(player_ref: CharacterBody3D, weapon_holder_ref: Node3D):
	# (Eng) Initialize with player reference - connect this manager to actual player
	# (Rus) Инициализация со ссылкой на игрока - подключаем этот менеджер к реальному игроку
	player = player_ref
	weapon_holder = weapon_holder_ref
	
	if reload_timer:
		reload_timer.timeout.connect(_on_reload_timer_timeout)
	
	setup_backpack_system()

func setup_backpack_system():
	# (Eng) Backpack system initialization - moved from Player, handles carrying capacity bullshit
	# (Rus) Инициализация системы рюкзака - перенесена из Player, управляет фигнёй с вместимостью
	backpack_node = backpack_node_ref
	backpack_ui = backpack_ui_ref
	
	if is_instance_valid(backpack_node):
		backpack_node.visible = false  # Изначально скрыт
		print("PlayerInventoryManager: Система рюкзака инициализирована")
	else:
		printerr("PlayerInventoryManager: ❌ Backpack node не найден на игроке!")
	
	if not is_instance_valid(backpack_ui):
		printerr("PlayerInventoryManager: ❌ Backpack UI не найден!")

func try_pickup_backpack():
	# (Eng) Backpack pickup logic - scans for nearby backpacks and grabs the closest one
	# (Rus) Логика подбора рюкзака - сканит близлежащие рюкзаки и хватает ближайший
	if has_backpack:  # Используем переменную напрямую
		return

	var closest_backpack_area: BackpackPickup = null
	var min_distance = INF
	var pickup_range = 3.0

	var found_backpacks = get_tree().get_nodes_in_group("backpack_pickups")
	if found_backpacks.is_empty():
		return

	# (Eng) Find closest valid backpack - checks distance and pickup conditions
	# (Rus) Находим ближайший валидный рюкзак - проверяем расстояние и условия подбора
	for backpack_pickup in found_backpacks:
		var node_is_backpack = backpack_pickup is BackpackPickup
		var node_is_valid = is_instance_valid(backpack_pickup)
		
		var node_is_visible_in_world = false
		if node_is_valid and backpack_pickup.has_method("is_backpack_visible_in_world"):
			node_is_visible_in_world = backpack_pickup.is_backpack_visible_in_world()
		else:
			node_is_visible_in_world = backpack_pickup.visible

		var can_be_picked = false
		if node_is_valid and backpack_pickup.has_method("can_be_picked_up"):
			can_be_picked = backpack_pickup.can_be_picked_up()

		if node_is_backpack and node_is_valid and node_is_visible_in_world and can_be_picked:
			var distance = player.global_position.distance_to(backpack_pickup.global_position)
			if distance < min_distance and distance < pickup_range:
				min_distance = distance
				closest_backpack_area = backpack_pickup

	if closest_backpack_area:
		pickup_backpack(closest_backpack_area)
	else:
		print("PlayerInventoryManager: Не найдено подходящего рюкзака для подбора в радиусе.")

func pickup_backpack(backpack_pickup: BackpackPickup) -> bool:
	# (Eng) Actually pickup backpack - handles visual updates and inventory state changes
	# (Rus) Собственно подбираем рюкзак - обрабатываем визуальные обновления и изменения состояния
	if has_backpack:
		print("PlayerInventoryManager: У игрока уже есть рюкзак")
		return false
	
	print("PlayerInventoryManager: Подбор рюкзака")
	
	var backpack_type_to_add = backpack_pickup.get_backpack_type()
	
	# (Eng) Show backpack on player model - make it visible and add to groups
	# (Rus) Показываем рюкзак на модели игрока - делаем видимым и добавляем в группы
	if is_instance_valid(backpack_node):
		backpack_node.visible = true
		backpack_node.add_to_group("Backpacks")
		pickup_notifier.show_pickup_notification()
		print("PlayerInventoryManager: Рюкзак показан на игроке")
	else:
		printerr("PlayerInventoryManager: ❌ Узел Backpack не найден на игроке!")
		return false
		
	# (Eng) Update UI state - notify backpack UI about the pickup
	# (Rus) Обновляем состояние UI - уведомляем UI рюкзака о подборе
	if is_instance_valid(backpack_ui):
		if backpack_ui.has_method("_on_backpack_picked_up"):
			backpack_ui._on_backpack_picked_up(backpack_type_to_add)
		print("PlayerInventoryManager: UI рюкзака обновлен")
	else:
		printerr("PlayerInventoryManager: ❌ Узел Backpack UI не найден!")
	
	# (Eng) Update manager state and cleanup world object
	# (Rus) Обновляем состояние менеджера и убираем объект из мира
	has_backpack = true
	current_backpack_type = backpack_type_to_add
	
	if backpack_pickup.pickup_sound:
		backpack_pickup.pickup_sound.play()
	
	if backpack_pickup.has_method("hide_backpack_in_world"):
		backpack_pickup.hide_backpack_in_world()
	
	backpack_pickup.queue_free.call_deferred()
	
	print("PlayerInventoryManager: Рюкзак %s успешно подобран" % backpack_type_to_add)
	return true

func is_backpack_equipped() -> bool:
	# (Eng) Check if backpack is equipped - validates both state and visual node
	# (Rus) Проверяем экипирован ли рюкзак - валидируем и состояние и визуальный узел
	return has_backpack and is_instance_valid(backpack_node) and backpack_node.visible

func get_backpack_type() -> String:
	# (Eng) Get equipped backpack type - returns empty string if none
	# (Rus) Получаем тип экипированного рюкзака - возвращает пустую строку если нет
	return current_backpack_type if has_backpack else ""

func has_backpack_equipped() -> bool:
	# (Eng) Simple backpack check - just returns boolean state
	# (Rus) Простая проверка рюкзака - просто возвращает булевое состояние
	return has_backpack

func _on_reload_timer_timeout():
	# (Eng) Reload completion handler - moves ammo from reserve to clip when reload finishes
	# (Rus) Обработчик завершения перезарядки - перемещает патроны из резерва в обойму когда перезарядка закончена
	if is_instance_valid(current_weapon_area):
		var ammo_needed = current_weapon_area.clip_size - current_weapon_area.current_ammo_in_clip
		var ammo_to_take = min(ammo_needed, current_weapon_area.total_carried_ammo)
		
		current_weapon_area.current_ammo_in_clip += ammo_to_take
		current_weapon_area.total_carried_ammo -= ammo_to_take
		
		current_weapon_area.emit_signal("ammo_changed", current_weapon_area.weapon_type, current_weapon_area.current_ammo_in_clip, current_weapon_area.total_carried_ammo)
		
		is_reloading = false
		
		if weapon_slot_ui:
			weapon_slot_ui.on_ammo_restored(current_weapon_area.weapon_type)
		
		if ammo_ui:
			ammo_ui.on_reload_finished()
		
		update_ammo_display()
	else:
		is_reloading = false

func _on_item_picked_up(item_node: Node3D, item_data: Dictionary):
	# (Eng) Pickup system event handler - processes items grabbed through PickupUISystem
	# (Rus) Обработчик событий системы подбора - процессит предметы взятые через PickupUISystem
	print("PlayerInventoryManager: Получен сигнал подбора: %s" % item_data.get("name", "unknown"))
	
	if item_data.get("item_type") == "weapon" and item_node is WeaponBase:
		var success = pickup_weapon(item_node as WeaponBase)
		if success:
			print("PlayerInventoryManager: Оружие %s успешно подобрано" % item_data.get("name"))
		else:
			print("PlayerInventoryManager: Не удалось подобрать оружие %s" % item_data.get("name"))
	
	elif item_data.get("item_type") == "backpack" and item_node.has_method("get_backpack_type"):
		var success = pickup_backpack(item_node)
		if success:
			print("PlayerInventoryManager: Рюкзак %s успешно подобран" % item_data.get("name"))
		else:
			print("PlayerInventoryManager: Не удалось подобрать рюкзак %s" % item_data.get("name"))

func handle_input(event: InputEvent):
	# (Eng) Input handler - processes all inventory-related controls like pickup and weapon switching
	# (Rus) Обработчик ввода - процессит все контролы связанные с инвентарем типа подбора и переключения оружия
	if event.is_action_pressed("interact") and event.is_pressed():
		if not event.is_echo():
			# (Eng) Check if pickup UI is showing - let PickupUISystem handle if it's active
			# (Rus) Проверяем показывается ли UI подбора - пусть PickupUISystem обработает если активен
			var pickup_ui = get_tree().get_first_node_in_group("pickup_ui_system")
			if pickup_ui and pickup_ui.is_ui_showing():
				return  # Пропускаем, пусть PickupUISystem обработает
			
			try_pickup_weapon()
			try_pickup_backpack()
	
	# (Eng) Weapon switching hotkeys - direct weapon selection by number
	# (Rus) Горячие клавиши переключения оружия - прямой выбор оружия по номеру
	if event.is_action_pressed("switch_weapon_1"):
		handle_weapon_switch("Wasteland Eagle")
	elif event.is_action_pressed("switch_weapon_2"):
		handle_weapon_switch("Enforcer 12-Gauge")
	elif event.is_action_pressed("switch_weapon_3"):
		handle_weapon_switch("Trail Boss Shotgun")
	elif event.is_action_pressed("switch_weapon_4"):
		handle_weapon_switch("Assault Auto-Rifle")
	elif event.is_action_pressed("drop_weapon"):
		drop_current_weapon()

func try_pickup_weapon():
	# (Eng) Legacy weapon pickup method - scans world for weapons and grabs nearest valid one
	# (Rus) Устаревший метод подбора оружия - сканит мир на наличие оружия и хватает ближайшее валидное
	var closest_weapon_area: WeaponBase = null
	var min_distance = INF
	var pickup_range = 3.0

	var found_weapons = get_tree().get_nodes_in_group("Weapons")
	if found_weapons.is_empty():
		print("В сцене нет объектов в группе 'Weapons'.")
		return

	# (Eng) Find closest pickupable weapon - checks distance, visibility and duplicate prevention
	# (Rus) Находим ближайшее подбираемое оружие - проверяем расстояние, видимость и предотвращение дубликатов
	for weapon_node in found_weapons:
		var node_is_weapon_base = weapon_node is WeaponBase
		var node_is_valid = is_instance_valid(weapon_node)
		
		var node_is_visible_in_world = false
		if node_is_valid and weapon_node.has_method("is_weapon_visible_in_world"):
			node_is_visible_in_world = weapon_node.is_weapon_visible_in_world()
		else:
			node_is_visible_in_world = weapon_node.visible

		var can_be_picked = false
		if node_is_valid and weapon_node.has_method("can_be_picked_up"):
			can_be_picked = weapon_node.can_be_picked_up()

		if node_is_weapon_base and node_is_valid and node_is_visible_in_world:
			if inventory.has(weapon_node.weapon_type):
				continue
				
			if not can_be_picked:
				continue
			
			var distance = player.global_position.distance_to(weapon_node.global_position)
			if distance < min_distance and distance < pickup_range:
				min_distance = distance
				closest_weapon_area = weapon_node

	if closest_weapon_area:
		pickup_weapon(closest_weapon_area)

func attach_weapon_visual_to_slot(weapon: WeaponBase):
	# (Eng) Visual attachment to spine slots - moves weapon model to appropriate back slot when not active
	# (Rus) Прикрепление визуала к слотам на спине - перемещает модель оружия в соответствующий слот на спине когда не активно
	if not is_instance_valid(weapon) or not is_instance_valid(weapon.weapon_visuals):
		print("PlayerInventoryManager: Невалидное оружие или визуалы в attach_weapon_visual_to_slot")
		return

	var slot: Node3D = null
	match weapon.weapon_type:
		"Wasteland Eagle":
			slot = Slot_Pistol
		"Enforcer 12-Gauge":
			slot = Slot_PA_Shotgun
		"Trail Boss Shotgun":
			slot = Slot_LA_Shotgun
		"Assault Auto-Rifle":
			slot = Slot_AA_Rifle

	if not is_instance_valid(slot):
		print("PlayerInventoryManager: Слот не найден для оружия: %s" % weapon.weapon_type)
		return

	# (Eng) Move visual to slot - detach from old parent and attach to spine slot
	# (Rus) Перемещаем визуал в слот - отсоединяем от старого родителя и крепим к слоту на спине
	var visual: Node3D = weapon.weapon_visuals as Node3D
	if not is_instance_valid(visual):
		print("PlayerInventoryManager: weapon_visuals не является Node3D!")
		return

	if is_instance_valid(visual.get_parent()):
		visual.get_parent().remove_child(visual)

	slot.add_child(visual)
	
	# (Eng) Reset transform and show model - clean positioning for spine display
	# (Rus) Сбрасываем трансформацию и показываем модель - чистое позиционирование для показа на спине
	visual.transform = Transform3D.IDENTITY
	visual.visible = true

func pickup_weapon(weapon: WeaponBase) -> bool:
	# (Eng) Core weapon pickup logic - adds weapon to inventory and handles all the complex node shuffling bullshit
	# (Rus) Основная логика подбора оружия - добавляет оружие в инвентарь и обрабатывает всю сложную фигню с перестановкой узлов
	if not is_instance_valid(weapon):
		return false

	var weapon_type := weapon.weapon_type

	# (Eng) Duplicate check - prevent picking up same weapon type twice
	# (Rus) Проверка дубликатов - предотвращаем подбор одного типа оружия дважды
	if inventory.has(weapon_type):
		print("PlayerInventoryManager: Оружие %s уже в инвентаре" % weapon_type)
		return false

	# (Eng) Detach from world - remove weapon from scene tree
	# (Rus) Отсоединяем от мира - удаляем оружие из дерева сцены
	if weapon.get_parent():
		weapon.get_parent().remove_child(weapon)

	# (Eng) Setup ammo and signals - configure weapon stats and connect event handlers
	# (Rus) Настраиваем патроны и сигналы - конфигурируем характеристики оружия и подключаем обработчики событий
	setup_weapon_ammo(weapon)
	connect_weapon_signals(weapon)

	# (Eng) Add to inventory and notify UI - update inventory state and show pickup feedback
	# (Rus) Добавляем в инвентарь и уведомляем UI - обновляем состояние инвентаря и показываем обратную связь подбора
	inventory[weapon_type] = weapon
	pickup_notifier.show_pickup_notification()

	if weapon.has_method("hide_weapon_in_world"):
		weapon.hide_weapon_in_world()
	
	# (Eng) Auto-activate picked weapon - immediately switch to newly acquired weapon
	# (Rus) Автоактивация подобранного оружия - сразу переключаемся на новое приобретённое оружие
	switch_weapon(weapon_type)

	update_ui_after_pickup()
	inventory_updated.emit()
	reset_player_movement_state()
	return true
	
func setup_weapon_ammo(weapon: WeaponBase):
	# (Eng) Weapon ammo configuration - sets clip size and transfers stored ammo to weapon
	# (Rus) Конфигурация патронов оружия - устанавливает размер обоймы и переносит сохранённые патроны в оружие
	var weapon_type = weapon.weapon_type
	
	if WEAPON_CLIP_SIZES.has(weapon_type):
		weapon.clip_size = WEAPON_CLIP_SIZES[weapon_type]
	else:
		weapon.clip_size = 10
		push_error("PlayerInventoryManager: Неизвестный тип оружия: %s" % weapon_type)
	
	# (Eng) Full clip on pickup - new weapons start with full magazine
	# (Rus) Полная обойма при подборе - новое оружие начинает с полным магазином
	weapon.current_ammo_in_clip = weapon.clip_size
	
	# (Eng) Transfer stored ammo - move player's stored bullets to weapon reserve
	# (Rus) Переносим сохранённые патроны - перемещаем сохранённые пули игрока в резерв оружия
	if stored_ammo.has(weapon_type):
		weapon.total_carried_ammo = stored_ammo[weapon_type]
		stored_ammo[weapon_type] = 0  # Оружие "забирает" патроны
	else:
		weapon.total_carried_ammo = 0

func connect_weapon_signals(weapon: WeaponBase):
	# (Eng) Signal connection - hooks up weapon events to inventory manager handlers
	# (Rus) Подключение сигналов - подсоединяет события оружия к обработчикам менеджера инвентаря
	var signals_to_connect = [
		"no_ammo_left",
		"ammo_changed", 
		"fire_mode_changed",
		"auto_reload_started",
		"weapon_empty_timeout"
	]
	
	for signal_name in signals_to_connect:
		if weapon.has_signal(signal_name):
			var method_name = "_on_weapon_" + signal_name
			if has_method(method_name):
				if not weapon.is_connected(signal_name, Callable(self, method_name)):
					weapon.connect(signal_name, Callable(self, method_name))

func switch_weapon(weapon_type: String):
	# (Eng) Weapon switching logic - deactivates current weapon and activates new one
	# (Rus) Логика переключения оружия - деактивирует текущее оружие и активирует новое
	print("PlayerInventoryManager: Переключение на оружие: %s" % weapon_type)
	
	if current_weapon_area:
		deactivate_current_weapon()
	
	# (Eng) Validate weapon exists - check inventory has this weapon type
	# (Rus) Валидируем существование оружия - проверяем что в инвентаре есть этот тип оружия
	if not inventory.has(weapon_type):
		clear_current_weapon_state()
		return
	
	var new_weapon = inventory[weapon_type] as WeaponBase
	if not is_instance_valid(new_weapon):
		clear_current_weapon_state()
		return
	
	activate_weapon(new_weapon, weapon_type)

func activate_weapon(weapon: WeaponBase, weapon_type: String):
	# (Eng) Weapon activation - complex process of moving Area3D under player and visuals to WeaponHolder
	# (Rus) Активация оружия - сложный процесс перемещения Area3D под игрока и визуалов в WeaponHolder
	if not is_instance_valid(weapon):
		return

	if is_instance_valid(current_weapon_area):
		deactivate_current_weapon()

	current_weapon_area = weapon
	active_weapon_type = weapon_type

	# (Eng) Critical node placement - ensure weapon Area3D is under player for collision detection
	# (Rus) Критическое размещение узлов - гарантируем что Area3D оружия под игроком для определения коллизий
	if weapon.get_parent() != player:
		if weapon.get_parent():
			weapon.get_parent().remove_child(weapon)
		player.add_child(weapon)

	# (Eng) Activate weapon behavior - enable weapon logic and animations
	# (Rus) Активируем поведение оружия - включаем логику и анимации оружия
	if weapon.has_method("activate_weapon"):
		weapon.activate_weapon()
		
	# (Eng) Connect cartridge system - link weapon to shell ejection manager
	# (Rus) Подключаем систему гильз - связываем оружие с менеджером выброса гильз
	if is_instance_valid(cartridge_manager):
		cartridge_manager.connect_weapon(weapon)
		print("PlayerInventoryManager: CartridgeManager подключен к %s" % weapon_type)
	else:
		printerr("PlayerInventoryManager: ❌ CartridgeManager не найден!")

	# (Eng) Setup visual positioning - move weapon model to WeaponHolder for first-person view
	# (Rus) Настраиваем позиционирование визуала - перемещаем модель оружия в WeaponHolder для вида от первого лица
	setup_weapon_visuals(weapon, weapon_type)

	weapon_switched.emit(weapon_type)
	update_ammo_display()
	if weapon_slot_ui:
		weapon_slot_ui.on_weapon_activated(weapon_type)

func setup_weapon_visuals(weapon: WeaponBase, weapon_type: String):
	# (Eng) Visual setup nightmare - moves weapon model from Area3D to WeaponHolder with proper positioning
	# (Rus) Кошмар настройки визуала - перемещает модель оружия из Area3D в WeaponHolder с правильным позиционированием
	current_weapon_visuals = weapon.weapon_visuals
	
	if not is_instance_valid(current_weapon_visuals):
		push_error("PlayerInventoryManager: Визуальная часть оружия не найдена")
		return
	
	print("PlayerInventoryManager: Перемещаем визуальную часть в WeaponHolder")
	
	# (Eng) Critical node reparenting - move visuals from weapon to weapon holder for proper camera view
	# (Rus) Критическая смена родителя узла - перемещаем визуалы из оружия в холдер оружия для правильного вида камеры
	if current_weapon_visuals.get_parent() != weapon_holder:
		if current_weapon_visuals.get_parent():
			current_weapon_visuals.get_parent().remove_child(current_weapon_visuals)
		weapon_holder.add_child(current_weapon_visuals)
		print("PlayerInventoryManager: Визуальная часть добавлена в WeaponHolder")
	
	# (Eng) Reset transform - clean slate for positioning in first-person view
	# (Rus) Сбрасываем трансформацию - чистый лист для позиционирования в виде от первого лица
	current_weapon_visuals.transform = Transform3D.IDENTITY
	
	apply_weapon_display_settings(weapon_type)
	current_weapon_visuals.visible = true


func apply_weapon_display_settings(weapon_type: String):
	# (Eng) Per-weapon positioning - each weapon needs different offset/rotation for proper first-person view
	# (Rus) Позиционирование для каждого оружия - каждому оружию нужны разные смещения/поворот для правильного вида от первого лица
	if not current_weapon_visuals:
		return
	
	var weapon_display_settings = {
		"Wasteland Eagle": {
			"position": Vector3(0.4, 0, -0.75),
			"rotation_degrees": Vector3(0, 0, 0),
			"scale": Vector3(1, 1, 1)
		},
		"Enforcer 12-Gauge": {
			"position": Vector3(0.5, 0, -0.75),
			"rotation_degrees": Vector3(0, 0, 0),
			"scale": Vector3(1, 1, 1)
		},
		"Trail Boss Shotgun": {
			"position": Vector3(0.5, 0, -0.75),
			"rotation_degrees": Vector3(0, 0, 0),
			"scale": Vector3(1, 1, 1)
		},
		"Assault Auto-Rifle": {
			"position": Vector3(0.5, 0, -0.75),
			"rotation_degrees": Vector3(0, 0, 0),
			"scale": Vector3(1, 1, 1)
		}
	}
	
	if weapon_display_settings.has(weapon_type):
		var settings = weapon_display_settings[weapon_type]
		current_weapon_visuals.position = settings.position
		current_weapon_visuals.rotation_degrees = settings.rotation_degrees
		current_weapon_visuals.scale = settings.scale
		print("PlayerInventoryManager: Применены настройки отображения для %s" % weapon_type)
	else:
		# (Eng) Default positioning - fallback values if weapon isn't in config
		# (Rus) Позиционирование по умолчанию - запасные значения если оружия нет в конфиге
		current_weapon_visuals.position = Vector3(0.5, 0, -0.75)
		current_weapon_visuals.rotation = Vector3.ZERO
		current_weapon_visuals.scale = Vector3.ONE
		print("PlayerInventoryManager: Применены настройки по умолчанию для %s" % weapon_type)

func deactivate_current_weapon():
	# (Eng) Weapon deactivation process - disables weapon and moves visuals back to spine slots
	# (Rus) Процесс деактивации оружия - отключает оружие и перемещает визуалы обратно на слоты спины
	if not is_instance_valid(current_weapon_area):
		return

	print("PlayerInventoryManager: Деактивация текущего оружия: %s" % active_weapon_type)

	if weapon_slot_ui:
		weapon_slot_ui.on_weapon_deactivated(active_weapon_type)

	# (Eng) Disable weapon behavior - turn off weapon logic and animations
	# (Rus) Отключаем поведение оружия - выключаем логику и анимации оружия
	if current_weapon_area.has_method("deactivate_weapon"):
		current_weapon_area.deactivate_weapon()
		
	# (Eng) Disconnect cartridge system - unlink from shell ejection manager
	# (Rus) Отключаем систему гильз - отвязываем от менеджера выброса гильз
	if is_instance_valid(cartridge_manager):
		cartridge_manager.disconnect_current_weapon()
		print("PlayerInventoryManager: CartridgeManager отключен от %s" % active_weapon_type)

	# (Eng) Critical - return visual to spine slot BEFORE clearing variables
	# (Rus) Критично - возвращаем визуал на слот спины ДО очистки переменных
	attach_weapon_visual_to_slot(current_weapon_area)

	# (Eng) Remove Area3D from player - detach weapon collision from player
	# (Rus) Убираем Area3D из игрока - отсоединяем коллизию оружия от игрока
	if current_weapon_area.get_parent() == player:
		player.remove_child(current_weapon_area)

	# (Eng) Clear state variables - reset current weapon tracking
	# (Rus) Очищаем переменные состояния - сбрасываем отслеживание текущего оружия
	current_weapon_area = null
	active_weapon_type = ""
	current_weapon_visuals = null

func clear_current_weapon_state():
	# (Eng) State cleanup - resets all current weapon tracking variables
	# (Rus) Очистка состояния - сбрасывает все переменные отслеживания текущего оружия
	print("PlayerInventoryManager: Очистка состояния оружия")
	active_weapon_type = ""
	current_weapon_area = null
	current_weapon_visuals = null
	update_ammo_display()

func drop_current_weapon():
	# (Eng) Weapon dropping - removes weapon from inventory and places it back in world
	# (Rus) Выброс оружия - удаляет оружие из инвентаря и размещает его обратно в мире
	if active_weapon_type == "":
		print("PlayerInventoryManager: Нет активного оружия для выброса")
		return

	var weapon_to_drop := inventory.get(active_weapon_type) as WeaponBase
	if not is_instance_valid(weapon_to_drop):
		clear_current_weapon_state()
		return

	# (Eng) Optional deactivation sound - play audio feedback for dropping
	# (Rus) Опциональный звук деактивации - проигрываем звуковую обратную связь для выброса
	if weapon_to_drop.has_method("play_deactivate_sound"):
		weapon_to_drop.play_deactivate_sound()
		await get_tree().create_timer(0.37).timeout

	disconnect_weapon_signals(weapon_to_drop)

	# (Eng) Return to world - complex process of moving weapon back to scene with proper positioning
	# (Rus) Возвращаем в мир - сложный процесс перемещения оружия обратно в сцену с правильным позиционированием
	return_weapon_to_world(weapon_to_drop)

	# (Eng) Return ammo to shared pool - move weapon bullets back to player storage
	# (Rus) Возвращаем патроны в общий пул - перемещаем пули оружия обратно в хранилище игрока
	return_ammo_to_storage(active_weapon_type, weapon_to_drop.total_carried_ammo)

	inventory.erase(active_weapon_type)
	weapon_dropped.emit(active_weapon_type)
	if weapon_slot_ui:
		weapon_slot_ui.on_weapon_dropped()
		weapon_slot_ui.sync_with_player_inventory()

	clear_current_weapon_state()
	auto_switch_weapon()

func return_weapon_to_world(weapon: WeaponBase):
	# (Eng) World return nightmare - moves weapon from inventory back to world with proper node hierarchy
	# (Rus) Кошмар возвращения в мир - перемещает оружие из инвентаря обратно в мир с правильной иерархией узлов
	print("PlayerInventoryManager: Возвращаем оружие в мир")
	
	var weapon_visuals_node = current_weapon_visuals
	
	if not is_instance_valid(weapon_visuals_node) or not weapon_holder:
		push_error("PlayerInventoryManager: Ошибка при возвращении оружия в мир")
		return
	
	# (Eng) Remove visuals from WeaponHolder - detach from first-person view
	# (Rus) Убираем визуалы из WeaponHolder - отсоединяем от вида первого лица
	if weapon_visuals_node.get_parent() == weapon_holder:
		weapon_holder.remove_child(weapon_visuals_node)
		print("PlayerInventoryManager: Визуальная часть удалена из WeaponHolder")
	
	# (Eng) Remove Area3D from player - detach weapon collision from player
	# (Rus) Убираем Area3D из игрока - отсоединяем коллизию оружия от игрока
	if weapon.get_parent() == player:
		player.remove_child(weapon)
		print("PlayerInventoryManager: Area3D удален из игрока")
	
	# (Eng) Add to scene and position - place weapon in world near player
	# (Rus) Добавляем в сцену и позиционируем - размещаем оружие в мире рядом с игроком
	get_tree().current_scene.add_child(weapon)
	
	var drop_position = player.global_position + player.head.global_transform.basis.z * 1.0 + Vector3(0, 0.0, 0)
	weapon.global_position = drop_position
	print("PlayerInventoryManager: Оружие размещено в позиции: %s" % drop_position)
	
	# (Eng) Return visuals to weapon Area3D - restore proper parent-child relationship
	# (Rus) Возвращаем визуалы в Area3D оружия - восстанавливаем правильные отношения родитель-дочка
	if weapon_visuals_node.get_parent() != weapon:
		weapon.add_child(weapon_visuals_node)
		weapon_visuals_node.position = Vector3.ZERO
		weapon_visuals_node.rotation = Vector3.ZERO
		weapon_visuals_node.scale = Vector3.ONE
		print("PlayerInventoryManager: Визуальная часть возвращена под Area3D")
	
	# (Eng) Show in world - make weapon visible and pickupable again
	# (Rus) Показываем в мире - делаем оружие видимым и подбираемым снова
	if weapon.has_method("show_weapon_in_world"):
		weapon.show_weapon_in_world()
		print("PlayerInventoryManager: Оружие показано в мире")

func disconnect_weapon_signals(weapon: WeaponBase):
	# (Eng) Signal disconnection - unhook weapon events from inventory manager
	# (Rus) Отключение сигналов - отцепляем события оружия от менеджера инвентаря
	var signals_to_disconnect = [
		"no_ammo_left",
		"ammo_changed", 
		"fire_mode_changed",
		"auto_reload_started",
		"weapon_empty_timeout"
	]
	
	for signal_name in signals_to_disconnect:
		if weapon.has_signal(signal_name):
			var method_name = "_on_weapon_" + signal_name
			if weapon.is_connected(signal_name, Callable(self, method_name)):
				weapon.disconnect(signal_name, Callable(self, method_name))

func auto_switch_weapon():
	# (Eng) Smart weapon switching - automatically selects best available weapon with ammo
	# (Rus) Умное переключение оружия - автоматически выбирает лучшее доступное оружие с патронами
	print("PlayerInventoryManager: Автопереключение оружия")
	
	var best_weapon_type = ""
	
	# (Eng) Priority-based selection - searches weapons by priority order for one with ammo
	# (Rus) Выбор на основе приоритета - ищет оружие по порядку приоритета с патронами
	for weapon_type in WEAPON_PRIORITY_ORDER:
		if inventory.has(weapon_type):
			var weapon = inventory[weapon_type] as WeaponBase
			if is_instance_valid(weapon) and (weapon.current_ammo_in_clip > 0 or weapon.total_carried_ammo > 0):
				best_weapon_type = weapon_type
				break
	
	if best_weapon_type != "":
		switch_weapon(best_weapon_type)
		print("PlayerInventoryManager: Переключено на: %s" % best_weapon_type)
	else:
		clear_current_weapon_state()
		print("PlayerInventoryManager: Нет доступного оружия")

func add_ammo(ammo_type: String, amount: int): 
	# (Eng) Ammo addition - adds bullets to player storage and updates active weapon if needed
	# (Rus) Добавление патронов - добавляет пули в хранилище игрока и обновляет активное оружие если нужно
	if not stored_ammo.has(ammo_type):
		stored_ammo[ammo_type] = 0
	
	stored_ammo[ammo_type] += amount
	
	# (Eng) Update active weapon ammo - if we picked up ammo for current weapon, give it to the weapon
	# (Rus) Обновляем патроны активного оружия - если подобрали патроны для текущего оружия, даём их оружию
	if inventory.has(ammo_type):
		var weapon = inventory[ammo_type] as WeaponBase
		if is_instance_valid(weapon):
			weapon.total_carried_ammo = stored_ammo[ammo_type]
			
			if active_weapon_type == ammo_type and weapon.current_ammo_in_clip == 0:
				try_reload_weapon(weapon)
	
	if ammo_ui:
		ammo_ui.on_ammo_pickup(ammo_type, amount)
		pickup_notifier.show_pickup_notification()
	
	ammo_changed.emit(ammo_type, -1, stored_ammo[ammo_type])

func return_ammo_to_storage(weapon_type: String, amount: int):
	# (Eng) Ammo return - moves bullets from weapon back to player storage
	# (Rus) Возврат патронов - перемещает пули из оружия обратно в хранилище игрока
	if stored_ammo.has(weapon_type):
		stored_ammo[weapon_type] += amount
	else:
		stored_ammo[weapon_type] = amount

func handle_weapon_switch(weapon_type: String):
	# (Eng) Weapon switch handler - processes hotkey weapon selection with validation
	# (Rus) Обработчик переключения оружия - процессит выбор оружия горячими клавишами с валидацией
	if not inventory.has(weapon_type):
		if ammo_ui:
			ammo_ui.show_weapon_not_available(weapon_type)
		return
	
	if active_weapon_type == weapon_type:
		if ammo_ui:
			ammo_ui.animate_active_weapon_confirmation()
		return
	
	switch_weapon(weapon_type)
	
func try_reload_weapon(weapon: WeaponBase):
	# (Eng) Reload initiation - starts reload process if conditions are met
	# (Rus) Инициация перезарядки - запускает процесс перезарядки если условия соблюдены
	if is_reloading or not weapon:
		return
	
	if weapon.current_ammo_in_clip == weapon.clip_size or weapon.total_carried_ammo == 0:
		return

	is_reloading = true
	
	if ammo_ui:
		ammo_ui.on_reload_started()
	
	if weapon.has_method("play_reload_sound"):
		weapon.play_reload_sound()
	
	if is_instance_valid(reload_timer):
		reload_timer.wait_time = weapon.reload_time
		reload_timer.start()

func _on_weapon_no_ammo_left(weapon_type: String):
	# (Eng) Empty weapon handler - processes when weapon runs out of bullets
	# (Rus) Обработчик пустого оружия - процессит когда у оружия заканчиваются пули
	print("PlayerInventoryManager: Получен сигнал no_ammo_left от: %s" % weapon_type)
	
	if active_weapon_type == weapon_type:
		# (Eng) Check emotional state - don't interfere with weapon's emotional logic
		# (Rus) Проверяем эмоциональное состояние - не вмешиваемся в эмоциональную логику оружия
		if is_instance_valid(current_weapon_area):
			var weapon_is_trying_empty = current_weapon_area.get("is_trying_to_shoot_empty")
			
			if weapon_is_trying_empty == true:
				return
		
		# (Eng) Check for reserve ammo - auto-reload if we have bullets, otherwise switch weapons
		# (Rus) Проверяем резервные патроны - автоперезарядка если есть пули, иначе переключаем оружие
		if is_instance_valid(current_weapon_area) and current_weapon_area.total_carried_ammo > 0:
			print("PlayerInventoryManager: Есть патроны в запасе - ждем автоперезарядку")
		else:
			auto_switch_weapon()

func _on_weapon_ammo_changed(weapon_type: String, current_in_clip: int, total_ammo: int):
	# (Eng) Ammo change handler - synchronizes weapon ammo changes with storage
	# (Rus) Обработчик изменения патронов - синхронизирует изменения патронов оружия с хранилищем
	if stored_ammo.has(weapon_type):
		stored_ammo[weapon_type] = total_ammo
	
	if active_weapon_type == weapon_type:
		update_ammo_display()
	
	ammo_changed.emit(weapon_type, current_in_clip, total_ammo)

func _on_weapon_fire_mode_changed(weapon_type: String, new_mode: int):
	# (Eng) Fire mode change handler - updates UI when weapon switches between single/burst/auto
	# (Rus) Обработчик изменения режима стрельбы - обновляет UI когда оружие переключается между одиночным/очередным/авто
	if ammo_ui:
		var fire_mode_string = WeaponBase.FireMode.keys()[new_mode].to_lower()
		ammo_ui.on_fire_mode_changed(weapon_type, fire_mode_string)

func _on_weapon_auto_reload_started(weapon_type: String):
	# (Eng) Auto-reload handler - processes automatic reload initiation from weapon
	# (Rus) Обработчик автоперезарядки - процессит инициацию автоматической перезарядки от оружия
	if active_weapon_type == weapon_type and is_instance_valid(current_weapon_area):
		is_reloading = true
		
		if is_instance_valid(reload_timer):
			reload_timer.wait_time = current_weapon_area.reload_time
			reload_timer.start()
		
		if ammo_ui:
			ammo_ui.on_reload_started()

func _on_weapon_empty_timeout(weapon_type: String):
	# (Eng) Empty timeout handler - auto-switches weapons when current one is empty too long
	# (Rus) Обработчик таймаута пустоты - автопереключает оружие когда текущее слишком долго пустое
	if active_weapon_type == weapon_type:
		auto_switch_weapon()

func update_ammo_display():
	# (Eng) UI ammo update - refreshes ammunition display in UI with current weapon info
	# (Rus) Обновление UI патронов - обновляет отображение боеприпасов в UI с информацией о текущем оружии
	print("PlayerInventoryManager: Обновление отображения патронов")
	
	if ammo_ui:
		if is_reloading:
			ammo_ui.show_reloading()
			return

		if is_instance_valid(current_weapon_area):
			var weapon_name = current_weapon_area.weapon_type.capitalize()
			var current_ammo = current_weapon_area.current_ammo_in_clip
			var total_ammo = current_weapon_area.total_carried_ammo
			var weapon_type = current_weapon_area.weapon_type
			var fire_mode = ""
			
			# (Eng) Get fire mode - retrieve current shooting mode for display
			# (Rus) Получаем режим стрельбы - получаем текущий режим стрельбы для отображения
			if current_weapon_area.has_method("get_current_fire_mode_name"):
				fire_mode = current_weapon_area.get_current_fire_mode_name()
			
			ammo_ui.update_full_display(weapon_name, current_ammo, total_ammo, weapon_type, fire_mode)
			print("PlayerInventoryManager: Обновлен дисплей для %s: %d/%d" % [weapon_name, current_ammo, total_ammo])
		else:
			ammo_ui.show_no_weapon()
			print("PlayerInventoryManager: Показан дисплей 'нет оружия'")

func update_ui_after_pickup():
	# (Eng) UI pickup update - refreshes weapon slot UI after adding new weapon to inventory
	# (Rus) Обновление UI после подбора - обновляет UI слотов оружия после добавления нового оружия в инвентарь
	print("PlayerInventoryManager: Обновление UI после подбора")
	
	if weapon_slot_ui:
		weapon_slot_ui.on_weapon_picked_up()
		weapon_slot_ui.update_weapon_states_from_player()
		weapon_slot_ui.sync_with_player_inventory()
		print("PlayerInventoryManager: UI Arsenal обновлен")

func get_current_weapon() -> WeaponBase:
	# (Eng) Current weapon accessor - returns currently active weapon reference
	# (Rus) Аксессор текущего оружия - возвращает ссылку на текущее активное оружие
	return current_weapon_area

func has_weapon(weapon_type: String) -> bool:
	# (Eng) Weapon check - validates if specific weapon type exists in inventory
	# (Rus) Проверка оружия - валидирует есть ли определённый тип оружия в инвентаре
	return inventory.has(weapon_type)

func get_weapon_count() -> int:
	# (Eng) Weapon count - returns total number of weapons in inventory
	# (Rus) Количество оружия - возвращает общее число оружия в инвентаре
	return inventory.size()

func get_ammo_count(weapon_type: String) -> int:
	# (Eng) Ammo count - returns stored ammunition for specific weapon type
	# (Rus) Количество патронов - возвращает сохранённые боеприпасы для определённого типа оружия
	return stored_ammo.get(weapon_type, 0)

func is_weapon_active(weapon_type: String) -> bool:
	# (Eng) Active weapon check - validates if specified weapon is currently active
	# (Rus) Проверка активного оружия - валидирует активно ли указанное оружие в данный момент
	return active_weapon_type == weapon_type

func get_inventory() -> Dictionary:
	# (Eng) Inventory accessor - returns inventory dictionary for UI systems
	# (Rus) Аксессор инвентаря - возвращает словарь инвентаря для UI систем
	return inventory

func get_active_weapon_type() -> String:
	# (Eng) Active type accessor - returns currently active weapon type string
	# (Rus) Аксессор активного типа - возвращает строку типа текущего активного оружия
	return active_weapon_type

func get_stored_ammo() -> Dictionary:
	# (Eng) Stored ammo accessor - returns ammunition storage dictionary
	# (Rus) Аксессор сохранённых патронов - возвращает словарь хранилища боеприпасов
	return stored_ammo
	
func get_cartridge_manager() -> CartridgeManager:
	# (Eng) Cartridge manager accessor - returns shell ejection system reference for other systems
	# (Rus) Аксессор менеджера гильз - возвращает ссылку на систему выброса гильз для других систем
	return cartridge_manager

func is_cartridge_system_ready() -> bool:
	# (Eng) Cartridge system check - validates if shell ejection system is ready to use
	# (Rus) Проверка системы гильз - валидирует готова ли система выброса гильз к использованию
	return is_instance_valid(cartridge_manager)
	
	
func reset_player_movement_state():
	"""Сбрасывает все состояния движения после подбора предметов"""
	if not player:
		return
	
	# Сброс velocity игрока
	player.velocity = Vector3.ZERO
	
	# Сброс состояний в movement controller
	if player.movement_controller and player.movement_controller.has_method("reset_movement_state"):
		player.movement_controller.reset_movement_state()
	
	# Сброс состояний головы
	var head = player.get_node_or_null("Head")
	if head and head.has_method("reset_head_state"):
		head.reset_head_state()
	
	print("PlayerInventoryManager: Состояние движения игрока сброшено после подбора")
