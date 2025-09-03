# ✅ Script: Player.gd
# (Eng) Main player controller with component delegation, inventory management and all that architectural clusterfuck bullshit
# (Rus) Основной контроллер игрока с делегированием компонентов, управлением инвентарем и всем этим архитектурным пиздецом
# 🔧 WIP ⚡ Prototype 🐛 Not Optimized — raw, unfinished crap, demo mechanics, eats resources / сырая, незавершённая хуйня, демо-механика, жрёт ресурсы

extends CharacterBody3D

class_name Player

# (Eng) Component references - dependency hell because we need to access everything from everywhere like idiots
# (Rus) Ссылки на компоненты - ад зависимостей потому что нам нужно получать доступ ко всему отовсюду как дебилам
@onready var movement_controller: PlayerMovementController = $PlayerMovementController
@onready var inventory_manager: PlayerInventoryManager = $PlayerInventoryManager
@onready var health_system: PlayerHealthSystem = $PlayerHealthSystem
@onready var sprint_system: PlayerSprintSystem = $PlayerSprintSystem

# (Eng) Node references - hardcoded paths because proper node resolution is too advanced
# (Rus) Ссылки на узлы - хардкод путей потому что нормальное разрешение узлов слишком продвинуто
@onready var head: Node3D = $"Head"
@onready var weapon_holder: Node3D = $Head/WeaponHolder
@onready var survival_ui: SurvivalUI = $"../UI/SurvivalUI"

# (Eng) State flags - boolean flags because proper state machine is apparently too hard
# (Rus) Флаги состояния - булевые флаги потому что нормальная машина состояний видимо слишком сложна
var movement_enabled: bool = true
var input_enabled: bool = true

# (Eng) Event signals - spam other systems with player updates every fucking frame
# (Rus) Сигналы событий - спамим другие системы обновлениями игрока каждый блядский кадр
signal movement_changed(is_moving: bool)
signal jump_performed()
signal health_changed(current_health: float, max_health: float)
signal player_took_damage(amountw: float, damage_type: String)

func _ready():
	# (Eng) Component initialization clusterfuck - connect this player mess to all subsystems
	# (Rus) Пиздец инициализации компонентов - подключаем этот игровой беспорядок ко всем подсистемам
	add_to_group("player")

	# (Eng) Null checks because apparently proper node setup is optional
	# (Rus) Проверки на null потому что видимо нормальная настройка узлов опциональна
	if not is_instance_valid(head) or not head is Node3D:
		printerr("ОШИБКА: Узел 'Head' не найден или не является Node3D. Движение, привязанное к голове, не будет работать!")
	
	if not is_instance_valid(weapon_holder) or not weapon_holder is Node3D:
		printerr("ОШИБКА: Узел 'WeaponHolder' не найден или не является Node3D. Оружие не будет прикреплено!")

	# (Eng) Setup hell - initialize every fucking component because modular design is pain
	# (Rus) Ад настройки - инициализируем каждый блядский компонент потому что модульный дизайн это боль
	setup_movement_controller()
	setup_sprint_system() 
	setup_health_system()
	setup_inventory_manager()  # Теперь здесь инициализируется и рюкзак
	
	# (Eng) UI connection spam - connect signals to UI because proper event bus is too advanced
	# (Rus) Спам подключения UI - подключаем сигналы к UI потому что нормальная шина событий слишком продвинута
	if survival_ui:
		movement_changed.connect(survival_ui._on_player_movement_changed)
		jump_performed.connect(survival_ui._on_player_jumped)
		health_changed.connect(survival_ui._on_player_health_changed)
		player_took_damage.connect(survival_ui._on_player_took_damage)
		
func set_movement_enabled(enabled: bool):
	# (Eng) Movement lockdown - nuclear option to stop player when shit hits the fan
	# (Rus) Блокировка движения - ядерный вариант остановить игрока когда всё идёт по пизде
	movement_enabled = enabled
	input_enabled = enabled  # Блокируем весь ввод
	
	print("Player: Движение %s" % ("включено" if enabled else "заблокировано"))
	
	# (Eng) Force stop everything - because graceful shutdown is for weaklings
	# (Rus) Принудительно останавливаем всё - потому что изящное завершение для слабаков
	if not enabled:
		velocity = Vector3.ZERO
		
		# (Eng) Component shutdown cascade - stop all movement subsystems like dominoes
		# (Rus) Каскадное отключение компонентов - останавливаем все подсистемы движения как домино
		if movement_controller:
			movement_controller.set_movement_speed(0)
		
		if sprint_system:
			sprint_system.force_stop_sprint()

func _input(event):
	# (Eng) Input handler clusterfuck - process everything in one giant function because separation is overrated
	# (Rus) Пиздец обработчика ввода - процессим всё в одной гигантской функции потому что разделение переоценено
	if not input_enabled:
		return
		
	# (Eng) Mouse handling - delegate head movement because apparently the head can think for itself
	# (Rus) Обработка мыши - делегируем движение головы потому что видимо голова может думать сама
	if event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			if is_instance_valid(head) and head.has_method("handle_mouse_input"):
				head.handle_mouse_input(event)
			else:
				printerr("Player: Head node invalid or does not have 'handle_mouse_input' method.")
	
	# (Eng) Interaction delegation hell - pass input to inventory manager because direct handling is too simple
	# (Rus) Ад делегирования взаимодействий - передаём ввод менеджеру инвентаря потому что прямая обработка слишком проста
	if event.is_action("interact") and event.is_pressed():
		if not event.is_echo():
			inventory_manager.handle_input(event)
			return  # Важно: return здесь, чтобы не обрабатывать дважды
	
	# (Eng) Shooting logic - delegate to weapon because player shouldn't know how guns work apparently
	# (Rus) Логика стрельбы - делегируем оружию потому что игрок видимо не должен знать как работают пушки
	if event.is_action_pressed("shoot"):
		var current_weapon = inventory_manager.get_current_weapon()
		if is_instance_valid(current_weapon) and not inventory_manager.is_reloading:
			if current_weapon.has_method("shoot"):
				current_weapon.shoot(-head.global_transform.basis.z)
				
	# (Eng) Fire mode switching - because apparently weapons need multiple ways to kill people
	# (Rus) Переключение режима стрельбы - потому что видимо оружию нужны разные способы убивать людей
	if event.is_action_pressed("toggle_fire_mode"):
		var current_weapon = inventory_manager.get_current_weapon()
		if is_instance_valid(current_weapon):
			if current_weapon.has_method("can_toggle_fire_mode") and current_weapon.can_toggle_fire_mode():
				current_weapon.toggle_fire_mode()
			
	# (Eng) Camera switching - simple feature that somehow needs its own function
	# (Rus) Переключение камеры - простая функция которой почему-то нужна своя функция
	if event.is_action_pressed("switch_camera_mode"):
		switch_camera_mode()
			
	# (Eng) More delegation hell - pass weapon switching to inventory manager because consistency is dead
	# (Rus) Больше ада делегирования - передаём переключение оружия менеджеру инвентаря потому что последовательность мертва
	inventory_manager.handle_input(event)

func _physics_process(delta):
	# (Eng) Main physics loop - movement processing clusterfuck that runs every frame like performance doesn't matter
	# (Rus) Основной физический цикл - пиздец обработки движения который работает каждый кадр как будто производительность не важна
	if not movement_enabled:
		# (Eng) Force stop everything - nuclear option when movement is disabled
		# (Rus) Принудительно останавливаем всё - ядерный вариант когда движение отключено
		velocity = Vector3.ZERO  # Принудительно останавливаем
		move_and_slide()  # Применяем остановку
		return
		
	# (Eng) Input gathering - collect player intentions every frame because polling is apparently the only way
	# (Rus) Сбор ввода - собираем намерения игрока каждый кадр потому что опрос видимо единственный способ
	var input_vector = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var is_trying_to_sprint = Input.is_action_pressed("run")
	
	# (Eng) Component delegation cascade - pass everything to specialized systems because the player is apparently incompetent
	# (Rus) Каскад делегирования компонентов - передаём всё специализированным системам потому что игрок видимо некомпетентен
	if movement_controller:
		movement_controller.handle_movement(delta, input_vector)
		
	if sprint_system:
		sprint_system.update_sprint(delta, is_trying_to_sprint, movement_controller.is_moving())
	
	if health_system:
		health_system.handle_regeneration(delta)

func trigger_camera_shake(magnitude: float, speed: float, duration: float):
	# (Eng) Camera shake delegation - find camera and make it wobble because immersion is more important than vision
	# (Rus) Делегирование тряски камеры - находим камеру и заставляем её дрожать потому что погружение важнее зрения
	var camera_node = get_tree().get_first_node_in_group("game_camera_group")
	if camera_node:
		if camera_node.has_method("start_shake"):
			camera_node.start_shake(magnitude, speed, duration)
		else:
			printerr("Player: Camera node found, but does not have 'start_shake' method!")
	else:
		printerr("Player: Camera node not found in 'game_camera_group'!")
		
func take_damage(amount: float, damage_position: Vector3 = Vector3.ZERO, damage_normal: Vector3 = Vector3.UP, damage_type: String = "unknown"):
	# (Eng) Damage delegation - pass pain to health system because player shouldn't feel his own suffering
	# (Rus) Делегирование урона - передаём боль системе здоровья потому что игрок не должен чувствовать свои собственные страдания
	var health_system = get_node_or_null("PlayerHealthSystem")
	if health_system:
		health_system.take_damage(amount, damage_position, damage_normal, damage_type)

func heal(amount: float):
	# (Eng) Healing delegation - pass wellness to health system because positive feelings are also outsourced
	# (Rus) Делегирование лечения - передаём оздоровление системе здоровья потому что позитивные чувства тоже на аутсорсе
	var health_system = get_node_or_null("PlayerHealthSystem")
	if health_system:
		health_system.heal(amount)

func apply_knockback(knockback_force: Vector3):
	# (Eng) Knockback delegation - pass physics impact to movement system because player shouldn't handle his own momentum
	# (Rus) Делегирование отталкивания - передаём физический удар системе движения потому что игрок не должен обрабатывать свой собственный импульс
	if movement_controller:
		movement_controller.apply_knockback(knockback_force)

func update_ammo_display():
	# (Eng) UI update delegation - pass display updates to inventory because player shouldn't know what he's carrying
	# (Rus) Делегирование обновления UI - передаём обновления дисплея инвентарю потому что игрок не должен знать что он носит
	if inventory_manager:
		inventory_manager.update_ammo_display()

func switch_camera_mode():
	# (Eng) Camera mode switching - hardcoded camera manipulation because proper camera system is too advanced
	# (Rus) Переключение режима камеры - хардкод манипуляций камерой потому что нормальная система камеры слишком продвинута
	
	var camera = get_node_or_null("res://CameraFollow.gd")
	if camera:
		camera.target_is_isometric = !camera.target_is_isometric
		
		if camera.has_method("show_camera_mode_label"):
			camera.show_camera_mode_label()
	else:
		# (Eng) Debug spam when shit doesn't work - because proper logging is for professionals
		# (Rus) Спам отладки когда хуйня не работает - потому что нормальное логирование для профессионалов
		printerr("Player: Камера не найдена!")
		print("Player: Родитель игрока: %s" % get_parent().name)
		print("Player: Дети родителя:")
		for child in get_parent().get_children():
			print("  - %s (%s)" % [child.name, child.get_class()])

# (Eng) Backpack compatibility methods - delegate everything to inventory manager because consistency is a foreign concept
# (Rus) Методы совместимости с рюкзаком - делегируем всё менеджеру инвентаря потому что последовательность это иностранная концепция
func is_backpack_equipped() -> bool:
	# (Eng) Backpack check delegation - because player apparently doesn't know what's on his back
	# (Rus) Делегирование проверки рюкзака - потому что игрок видимо не знает что у него на спине
	return inventory_manager.is_backpack_equipped() if inventory_manager else false

func get_backpack_type() -> String:
	# (Eng) Backpack type delegation - because player can't identify his own equipment
	# (Rus) Делегирование типа рюкзака - потому что игрок не может идентифицировать своё собственное снаряжение
	return inventory_manager.get_backpack_type() if inventory_manager else ""

func has_backpack() -> bool:
	# (Eng) Another backpack check - because one wasn't enough apparently
	# (Rus) Ещё одна проверка рюкзака - потому что одной видимо было недостаточно
	return inventory_manager.has_backpack_equipped() if inventory_manager else false
	
func is_moving() -> bool:
	# (Eng) Movement check delegation - because player doesn't know if he's walking
	# (Rus) Делегирование проверки движения - потому что игрок не знает идёт ли он
	return movement_controller.is_moving() if movement_controller else velocity.length() > 0.1

func setup_movement_controller():
	# (Eng) Movement controller setup - connect movement system to player because modular design is pain
	# (Rus) Настройка контроллера движения - подключаем систему движения к игроку потому что модульный дизайн это боль
	if movement_controller:
		movement_controller.setup(self, head)
		movement_controller.movement_state_changed.connect(_on_movement_state_changed)
		movement_controller.wall_bounce_triggered.connect(_on_wall_bounce_triggered)
	else:
		push_error("Player: PlayerMovementController не найден!")

func _on_movement_state_changed(is_moving: bool):
	# (Eng) Movement state signal handler - emit signal to other systems because direct communication is forbidden
	# (Rus) Обработчик сигнала состояния движения - испускаем сигнал другим системам потому что прямое общение запрещено
	movement_changed.emit(is_moving)

func _on_wall_bounce_triggered(force: Vector3):
	# (Eng) Wall bounce handler - empty function because handling wall collisions is apparently optional
	# (Rus) Обработчик отскока от стены - пустая функция потому что обработка столкновений со стенами видимо опциональна
	pass
	
func setup_sprint_system():
	# (Eng) Sprint system setup - connect running mechanics because basic locomotion needs its own module
	# (Rus) Настройка системы спринта - подключаем механику бега потому что базовое передвижение нуждается в своём модуле
	if sprint_system:
		sprint_system.setup(movement_controller)
		sprint_system.sprint_state_changed.connect(_on_sprint_state_changed)
	else:
		push_error("Player: PlayerSprintSystem не найден!")

func setup_health_system():
	# (Eng) Health system setup - connect life management because staying alive is complicated
	# (Rus) Настройка системы здоровья - подключаем управление жизнью потому что оставаться живым сложно
	var health_system = get_node_or_null("PlayerHealthSystem")
	if health_system:
		health_system.setup(self)
		health_system.health_changed.connect(_on_health_changed)
		health_system.player_took_damage.connect(_on_player_took_damage)
		health_system.player_died.connect(_on_player_died)
	else:
		push_error("Player: PlayerHealthSystem не найден!")

func _on_sprint_state_changed(is_sprinting: bool):
	# (Eng) Sprint state handler - empty function because sprinting feedback is apparently unnecessary
	# (Rus) Обработчик состояния спринта - пустая функция потому что обратная связь спринта видимо не нужна
	pass

func _on_health_changed(health_percentage: float, max_health: float):
	# (Eng) Health change signal relay - pass health updates to UI because direct health display is too simple
	# (Rus) Ретрансляция сигнала изменения здоровья - передаём обновления здоровья в UI потому что прямое отображение здоровья слишком просто
	health_changed.emit(health_percentage, max_health)

func _on_player_took_damage(amount: float, damage_type: String):
	# (Eng) Damage signal relay - inform UI about pain because suffering needs documentation
	# (Rus) Ретрансляция сигнала урона - информируем UI о боли потому что страдания нуждаются в документации
	player_took_damage.emit(amount, damage_type)

func _on_player_died(cause: String):
	# (Eng) Death handler - log player demise because death requires proper paperwork
	# (Rus) Обработчик смерти - логируем кончину игрока потому что смерть требует соответствующей бумажной работы
	print("Player: Игрок умер от: %s" % cause)
	
func setup_inventory_manager():
	# (Eng) Inventory manager setup - connect item management because carrying stuff is rocket science
	# (Rus) Настройка менеджера инвентаря - подключаем управление предметами потому что носить барахло это ракетостроение
	if inventory_manager:
		inventory_manager.setup(self, weapon_holder)
		print("Player: InventoryManager настроен")
	else:
		push_error("Player: PlayerInventoryManager не найден!")

# (Eng) UI compatibility methods - wrapper functions because direct access to components would be chaos
# (Rus) Методы совместимости с UI - функции-обёртки потому что прямой доступ к компонентам был бы хаосом
func get_current_weapon() -> WeaponBase:
	# (Eng) Current weapon getter - delegate to inventory because player doesn't know what's in his hands
	# (Rus) Получатель текущего оружия - делегируем инвентарю потому что игрок не знает что у него в руках
	return inventory_manager.get_current_weapon() if inventory_manager else null

func has_weapon(weapon_type: String) -> bool:
	# (Eng) Weapon check delegation - because player can't remember what guns he owns
	# (Rus) Делегирование проверки оружия - потому что игрок не может вспомнить какие пушки у него есть
	return inventory_manager.has_weapon(weapon_type) if inventory_manager else false

func get_weapon_count() -> int:
	# (Eng) Weapon count delegation - because counting to 4 is apparently difficult
	# (Rus) Делегирование подсчёта оружия - потому что считать до 4 видимо сложно
	return inventory_manager.get_weapon_count() if inventory_manager else 0

func get_ammo_count(weapon_type: String) -> int:
	# (Eng) Ammo count delegation - because player can't count bullets
	# (Rus) Делегирование подсчёта патронов - потому что игрок не может считать пули
	return inventory_manager.get_ammo_count(weapon_type) if inventory_manager else 0

func is_weapon_active(weapon_type: String) -> bool:
	# (Eng) Active weapon check - because player doesn't know what he's holding
	# (Rus) Проверка активного оружия - потому что игрок не знает что он держит
	return inventory_manager.is_weapon_active(weapon_type) if inventory_manager else false

# (Eng) Movement state getters - more wrapper functions because encapsulation is apparently mandatory
# (Rus) Получатели состояния движения - больше функций-обёрток потому что инкапсуляция видимо обязательна
func is_movement_enabled() -> bool:
	# (Eng) Movement state getter - because accessing boolean directly would be anarchy
	# (Rus) Получатель состояния движения - потому что прямой доступ к булевой переменной был бы анархией
	return movement_enabled

func is_input_enabled() -> bool:
	# (Eng) Input state getter - another boolean wrapper because consistency demands it
	# (Rus) Получатель состояния ввода - ещё одна булевая обёртка потому что последовательность этого требует
	return input_enabled

func force_stop_all():
	# (Eng) Emergency stop - nuclear option to halt everything when the game breaks
	# (Rus) Экстренная остановка - ядерный вариант остановить всё когда игра ломается
	velocity = Vector3.ZERO
	
	if movement_controller:
		movement_controller.set_movement_speed(0)
	
	if sprint_system:
		sprint_system.force_stop_sprint()

func add_ammo_to_player_inventory(ammo_type: String, amount: int):
	# (Eng) Ammo addition delegation - because player can't put bullets in his own pocket
	# (Rus) Делегирование добавления патронов - потому что игрок не может положить пули в свой собственный карман
	if inventory_manager:
		inventory_manager.add_ammo(ammo_type, amount)
	else:
		printerr("Player: InventoryManager не найден для добавления патронов!")















## Player.gd - Обновленная версия с делегированием к компонентам
#extends CharacterBody3D
#
#class_name Player
#
#@onready var movement_controller: PlayerMovementController = $PlayerMovementController
#@onready var inventory_manager: PlayerInventoryManager = $PlayerInventoryManager
#@onready var health_system: PlayerHealthSystem = $PlayerHealthSystem
#@onready var sprint_system: PlayerSprintSystem = $PlayerSprintSystem
#
#@onready var head: Node3D = $"Head"
#@onready var weapon_holder: Node3D = $Head/WeaponHolder
#@onready var survival_ui: SurvivalUI = $"../UI/SurvivalUI"
#
#var movement_enabled: bool = true
#var input_enabled: bool = true
#
#signal movement_changed(is_moving: bool)
#signal jump_performed()
#signal health_changed(current_health: float, max_health: float)
#signal player_took_damage(amountw: float, damage_type: String)
#
#func _ready():
	#add_to_group("player")
#
	#if not is_instance_valid(head) or not head is Node3D:
		#printerr("ОШИБКА: Узел 'Head' не найден или не является Node3D. Движение, привязанное к голове, не будет работать!")
	#
	#if not is_instance_valid(weapon_holder) or not weapon_holder is Node3D:
		#printerr("ОШИБКА: Узел 'WeaponHolder' не найден или не является Node3D. Оружие не будет прикреплено!")
#
	## Инициализация компонентов
	#setup_movement_controller()
	#setup_sprint_system() 
	#setup_health_system()
	#setup_inventory_manager()  # Теперь здесь инициализируется и рюкзак
	#
	## Подключение к SurvivalUI
	##var survival_ui = get_node("../UI/SurvivalUI")
	#if survival_ui:
		#movement_changed.connect(survival_ui._on_player_movement_changed)
		#jump_performed.connect(survival_ui._on_player_jumped)
		#health_changed.connect(survival_ui._on_player_health_changed)
		#player_took_damage.connect(survival_ui._on_player_took_damage)
		#
#func set_movement_enabled(enabled: bool):
	#movement_enabled = enabled
	#input_enabled = enabled  # Блокируем весь ввод
	#
	#print("Player: Движение %s" % ("включено" if enabled else "заблокировано"))
	#
	## Останавливаем игрока при блокировке
	#if not enabled:
		#velocity = Vector3.ZERO
		#
		## Останавливаем компоненты движения
		#if movement_controller:
			#movement_controller.set_movement_speed(0)
		#
		## Останавливаем спринт
		#if sprint_system:
			#sprint_system.force_stop_sprint()
#
#func _input(event):
	#if not input_enabled:
		#return
	## Обработка мыши для поворота головы
	#if event is InputEventMouseMotion:
		#if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			#if is_instance_valid(head) and head.has_method("handle_mouse_input"):
				#head.handle_mouse_input(event)
			#else:
				#printerr("Player: Head node invalid or does not have 'handle_mouse_input' method.")
	#
	## ДЕЛЕГИРУЕМ ОБРАБОТКУ ВЗАИМОДЕЙСТВИЯ К INVENTORY MANAGER
	#if event.is_action("interact") and event.is_pressed():
		#if not event.is_echo():
			#inventory_manager.handle_input(event)
			#return  # Важно: return здесь, чтобы не обрабатывать дважды
	#
	## Обработка стрельбы
	#if event.is_action_pressed("shoot"):
		#var current_weapon = inventory_manager.get_current_weapon()
		#if is_instance_valid(current_weapon) and not inventory_manager.is_reloading:
			#if current_weapon.has_method("shoot"):
				#current_weapon.shoot(-head.global_transform.basis.z)
				#
	## Переключение режима стрельбы
	#if event.is_action_pressed("toggle_fire_mode"):
		#var current_weapon = inventory_manager.get_current_weapon()
		#if is_instance_valid(current_weapon):
			#if current_weapon.has_method("can_toggle_fire_mode") and current_weapon.can_toggle_fire_mode():
				#current_weapon.toggle_fire_mode()
			#
	## Переключение камеры
	#if event.is_action_pressed("switch_camera_mode"):
		#switch_camera_mode()
			#
	## ДЕЛЕГИРУЕМ ВСЕ ПЕРЕКЛЮЧЕНИЕ ОРУЖИЯ К INVENTORY MANAGER
	#inventory_manager.handle_input(event)
#
#func _physics_process(delta):
	#if not movement_enabled:
		#velocity = Vector3.ZERO  # Принудительно останавливаем
		#move_and_slide()  # Применяем остановку
		#return
	## Делегируем движение контроллеру
	#var input_vector = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	#var is_trying_to_sprint = Input.is_action_pressed("run")
	#
	#if movement_controller:
		#movement_controller.handle_movement(delta, input_vector)
		#
	#if sprint_system:
		#sprint_system.update_sprint(delta, is_trying_to_sprint, movement_controller.is_moving())
	#
	#if health_system:
		#health_system.handle_regeneration(delta)
#
#func trigger_camera_shake(magnitude: float, speed: float, duration: float):
	#var camera_node = get_tree().get_first_node_in_group("game_camera_group")
	#if camera_node:
		#if camera_node.has_method("start_shake"):
			#camera_node.start_shake(magnitude, speed, duration)
		#else:
			#printerr("Player: Camera node found, but does not have 'start_shake' method!")
	#else:
		#printerr("Player: Camera node not found in 'game_camera_group'!")
		#
#func take_damage(amount: float, damage_position: Vector3 = Vector3.ZERO, damage_normal: Vector3 = Vector3.UP, damage_type: String = "unknown"):
	#"""Делегируем урон системе здоровья"""
	#var health_system = get_node_or_null("PlayerHealthSystem")
	#if health_system:
		#health_system.take_damage(amount, damage_position, damage_normal, damage_type)
#
#func heal(amount: float):
	#"""Делегируем лечение системе здоровья"""
	#var health_system = get_node_or_null("PlayerHealthSystem")
	#if health_system:
		#health_system.heal(amount)
#
#func apply_knockback(knockback_force: Vector3):
	#"""Делегируем отталкивание системе движения"""
	#if movement_controller:
		#movement_controller.apply_knockback(knockback_force)
#
## ДЕЛЕГИРУЕМ ОБНОВЛЕНИЕ ДИСПЛЕЯ ПАТРОНОВ К INVENTORY MANAGER
#func update_ammo_display():
	#"""Обновляет отображение патронов через InventoryManager"""
	#if inventory_manager:
		#inventory_manager.update_ammo_display()
#
#func switch_camera_mode():
	#"""Простое переключение камеры"""
	#
	#var camera = get_node_or_null("res://CameraFollow.gd")
	#if camera:
		#camera.target_is_isometric = !camera.target_is_isometric
		#
		#if camera.has_method("show_camera_mode_label"):
			#camera.show_camera_mode_label()
	#else:
		#printerr("Player: Камера не найдена!")
		#print("Player: Родитель игрока: %s" % get_parent().name)
		#print("Player: Дети родителя:")
		#for child in get_parent().get_children():
			#print("  - %s (%s)" % [child.name, child.get_class()])
#
## МЕТОДЫ ДЛЯ СОВМЕСТИМОСТИ С РЮКЗАКОМ (делегируют к InventoryManager)
#func is_backpack_equipped() -> bool:
	#"""Проверяет, экипирован ли рюкзак через InventoryManager"""
	#return inventory_manager.is_backpack_equipped() if inventory_manager else false
#
#func get_backpack_type() -> String:
	#"""Возвращает тип рюкзака через InventoryManager"""
	#return inventory_manager.get_backpack_type() if inventory_manager else ""
#
#func has_backpack() -> bool:
	#"""Проверяет наличие рюкзака через InventoryManager"""
	#return inventory_manager.has_backpack_equipped() if inventory_manager else false
	#
#func is_moving() -> bool:
	#"""Делегируем проверку движения контроллеру"""
	#return movement_controller.is_moving() if movement_controller else velocity.length() > 0.1
#
#func setup_movement_controller():
	#"""Настройка контроллера движения"""
	#if movement_controller:
		#movement_controller.setup(self, head)
		#movement_controller.movement_state_changed.connect(_on_movement_state_changed)
		#movement_controller.wall_bounce_triggered.connect(_on_wall_bounce_triggered)
	#else:
		#push_error("Player: PlayerMovementController не найден!")
#
#func _on_movement_state_changed(is_moving: bool):
	#"""Обрабатывает сигнал изменения движения"""
	#movement_changed.emit(is_moving)
#
#func _on_wall_bounce_triggered(force: Vector3):
	#"""Обрабатывает сигнал отскока от стены"""
	#pass
	#
#func setup_sprint_system():
	#"""Настройка системы спринта"""
	#if sprint_system:
		#sprint_system.setup(movement_controller)
		#sprint_system.sprint_state_changed.connect(_on_sprint_state_changed)
	#else:
		#push_error("Player: PlayerSprintSystem не найден!")
#
#func setup_health_system():
	#"""Настройка системы здоровья"""
	#var health_system = get_node_or_null("PlayerHealthSystem")
	#if health_system:
		#health_system.setup(self)
		#health_system.health_changed.connect(_on_health_changed)
		#health_system.player_took_damage.connect(_on_player_took_damage)
		#health_system.player_died.connect(_on_player_died)
	#else:
		#push_error("Player: PlayerHealthSystem не найден!")
#
#func _on_sprint_state_changed(is_sprinting: bool):
	#"""Обрабатывает изменение состояния спринта"""
	#pass
#
#func _on_health_changed(health_percentage: float, max_health: float):
	#"""Обрабатывает изменение здоровья"""
	#health_changed.emit(health_percentage, max_health)
#
#func _on_player_took_damage(amount: float, damage_type: String):
	#"""Обрабатывает получение урона"""
	#player_took_damage.emit(amount, damage_type)
#
#func _on_player_died(cause: String):
	#"""Обрабатывает смерть игрока"""
	#print("Player: Игрок умер от: %s" % cause)
	#
#func setup_inventory_manager():
	#"""Настройка менеджера инвентаря"""
	#if inventory_manager:
		#inventory_manager.setup(self, weapon_holder)
		#print("Player: InventoryManager настроен")
	#else:
		#push_error("Player: PlayerInventoryManager не найден!")
#
## === МЕТОДЫ ДЛЯ СОВМЕСТИМОСТИ С UI ===
#func get_current_weapon() -> WeaponBase:
	#"""Возвращает текущее активное оружие через InventoryManager"""
	#return inventory_manager.get_current_weapon() if inventory_manager else null
#
#func has_weapon(weapon_type: String) -> bool:
	#"""Проверяет наличие оружия через InventoryManager"""
	#return inventory_manager.has_weapon(weapon_type) if inventory_manager else false
#
#func get_weapon_count() -> int:
	#"""Возвращает количество оружия через InventoryManager"""
	#return inventory_manager.get_weapon_count() if inventory_manager else 0
#
#func get_ammo_count(weapon_type: String) -> int:
	#"""Возвращает количество патронов через InventoryManager"""
	#return inventory_manager.get_ammo_count(weapon_type) if inventory_manager else 0
#
#func is_weapon_active(weapon_type: String) -> bool:
	#"""Проверяет активность оружия через InventoryManager"""
	#return inventory_manager.is_weapon_active(weapon_type) if inventory_manager else false
#
## Добавьте дополнительные методы для полной блокировки
#func is_movement_enabled() -> bool:
	#return movement_enabled
#
#func is_input_enabled() -> bool:
	#return input_enabled
#
#func force_stop_all():
	#"""Принудительно останавливает все действия игрока"""
	#velocity = Vector3.ZERO
	#
	#if movement_controller:
		#movement_controller.set_movement_speed(0)
	#
	#if sprint_system:
		#sprint_system.force_stop_sprint()
#
## === МЕТОДЫ ДЛЯ ДОБАВЛЕНИЯ ПАТРОНОВ ===
#func add_ammo_to_player_inventory(ammo_type: String, amount: int):
	#"""Добавляет патроны через InventoryManager"""
	#if inventory_manager:
		#inventory_manager.add_ammo(ammo_type, amount)
	#else:
		#printerr("Player: InventoryManager не найден для добавления патронов!")
#
#
#
