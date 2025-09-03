# ✅ Script: InteractionDetector.gd
# (Eng) Interaction detection system with ShapeCast polling, item pickup logic and all that experimental clusterfuck
# (Rus) Система обнаружения взаимодействий с опросом ShapeCast, логикой подбора предметов и всем этим экспериментальным пиздецом
# 🔧 WIP ⚡ Prototype 🐛 Not Optimized — raw, unfinished crap, demo mechanics, eats resources / сырая, незавершённая хуйня, демо-механика, жрёт ресурсы
# ⚠ WARNING: This part is experimental and unstable / ВНИМАНИЕ: Этот кусок экспериментальный и нестабильный

extends Node3D

@onready var shape_cast: ShapeCast3D = $Cast_Zone_Player

# (Eng) Collision tracking arrays - memory allocation nightmare because we duplicate arrays every fucking frame
# (Rus) Массивы отслеживания коллизий - кошмар аллокации памяти потому что мы дублируем массивы каждый блядский кадр
var previous_collisions: Array[Node3D] = []
var current_collisions: Array[Node3D] = []

# (Eng) Interaction state - more variables to track because proper state management is apparently too hard
# (Rus) Состояние взаимодействия - больше переменных для отслеживания потому что нормальное управление состоянием видимо слишком сложно
var current_interactable_item: Node3D = null
var interaction_cooldown: float = 0.0

var player: Player

func _ready():
	# (Eng) Player reference acquisition - dependency injection through parent casting like amateurs
	# (Rus) Получение ссылки на игрока - внедрение зависимости через каст родителя как любители
	player = get_parent() as Player
	if not player:
		push_error("InteractionDetector: Должен быть дочерним элементом Player!")
		return
	
	# (Eng) ShapeCast configuration - hardcoded collision mask because configuration files are for losers
	# (Rus) Конфигурация ShapeCast - хардкод маски коллизий потому что конфигурационные файлы для лузеров
	if shape_cast:
		shape_cast.collision_mask = 5  # Слой 5 (Interactables)
		shape_cast.enabled = true
		print("InteractionDetector: ShapeCast настроен с маской %d" % shape_cast.collision_mask)

func _physics_process(delta):
	# (Eng) Main interaction clusterfuck - runs every physics frame because performance optimization is overrated
	# (Rus) Основной пиздец взаимодействий - работает каждый физический кадр потому что оптимизация производительности переоценена
	
	# (Eng) Cooldown decrement - manual timer management because using Timer nodes would be too convenient
	# (Rus) Уменьшение кулдауна - ручное управление таймером потому что использование узлов Timer было бы слишком удобно
	if interaction_cooldown > 0:
		interaction_cooldown -= delta
	
	if not shape_cast or not shape_cast.enabled:
		return
	
	# (Eng) Force shape cast update - manual polling because signals and proper event handling are for advanced developers
	# (Rus) Принуждение обновления shape cast - ручной опрос потому что сигналы и нормальная обработка событий для продвинутых разработчиков
	shape_cast.force_shapecast_update()
	
	# (Eng) Validity filtering hell - clean invalid objects because our reference management is fucked
	# (Rus) Ад фильтрации валидности - очищаем невалидные объекты потому что наше управление ссылками просрано
	previous_collisions = previous_collisions.filter(func(obj): return is_instance_valid(obj))
	
	current_collisions.clear()
	
	# (Eng) Closest item detection - iterate through all collisions every frame like performance doesn't matter
	# (Rus) Обнаружение ближайшего предмета - итерируемся по всем коллизиям каждый кадр как будто производительность не важна
	var closest_interactable: Node3D = null
	var closest_distance: float = INF
	
	if shape_cast.is_colliding():
		var collision_count = shape_cast.get_collision_count()
		
		# (Eng) Collision processing loop - check every fucking collision because broad phase filtering is rocket science
		# (Rus) Цикл обработки коллизий - проверяем каждую блядскую коллизию потому что широкофазовая фильтрация это ракетостроение
		for i in range(collision_count):
			var collider = shape_cast.get_collider(i)
			
			if collider and is_instance_valid(collider):
				current_collisions.append(collider)
				
				# (Eng) Pickupable item detection - complex logic for what should be simple type checking
				# (Rus) Обнаружение подбираемых предметов - сложная логика для того что должно быть простой проверкой типа
				if is_pickupable(collider):
					var distance = global_position.distance_to(collider.global_position)
					if distance < closest_distance:
						closest_distance = distance
						closest_interactable = collider
				
				if collider not in previous_collisions:
					handle_interaction_enter(collider)
	
	current_interactable_item = closest_interactable
	
	# (Eng) Exit detection loop - more iteration hell because efficient delta detection is apparently impossible
	# (Rus) Цикл обнаружения выхода - больше итерационного ада потому что эффективное обнаружение дельты видимо невозможно
	for prev_collider in previous_collisions:
		if is_instance_valid(prev_collider) and prev_collider not in current_collisions:
			handle_interaction_exit(prev_collider)
	
	# (Eng) Array duplication hell - create new array every frame because memory allocation is free apparently
	# (Rus) Ад дублирования массивов - создаём новый массив каждый кадр потому что аллокация памяти видимо бесплатная
	previous_collisions = current_collisions.duplicate()

func _input(event):
	# (Eng) Input handling - mixed with interaction logic because separation of concerns is overrated
	# (Rus) Обработка ввода - смешана с логикой взаимодействий потому что разделение ответственности переоценено
	if event.is_action_pressed("interact") and interaction_cooldown <= 0:
		if current_interactable_item and is_instance_valid(current_interactable_item):
			pickup_item(current_interactable_item)

func is_pickupable(obj: Node3D) -> bool:
	# (Eng) Pickupable detection nightmare - multiple ways to check the same fucking thing because consistency is for losers
	# (Rus) Кошмар обнаружения подбираемых предметов - несколько способов проверить одну и ту же хуйню потому что последовательность для лузеров
	if not obj:
		return false
	
	# (Eng) Group membership checks - because apparently we need three different ways to identify items
	# (Rus) Проверки принадлежности к группам - потому что видимо нам нужны три разных способа идентификации предметов
	if obj.is_in_group("Weapons") or obj.is_in_group("Backpacks") or obj.is_in_group("Pickups"):
		return true
	
	# (Eng) Type checks - redundant type validation because group checks weren't enough
	# (Rus) Проверки типов - избыточная валидация типов потому что проверки групп было недостаточно
	if obj is WeaponBase or obj is AmmoPickup:
		return true
	
	# (Eng) Method existence checks - third way to check pickupability because why not make it even more complex
	# (Rus) Проверки существования методов - третий способ проверить подбираемость потому что почему бы не сделать это ещё сложнее
	if obj.has_method("can_be_picked_up"):
		return obj.can_be_picked_up()
	
	return false

func pickup_item(item: Node3D):
	# (Eng) Main pickup dispatcher - type checking hell and UI manipulation clusterfuck
	# (Rus) Основной диспетчер подбора - ад проверки типов и пиздец манипуляции UI
	print("InteractionDetector: Попытка подбора предмета: %s" % item.name)
	
	# (Eng) Manual cooldown setting - because using proper state machines would be too advanced
	# (Rus) Ручная установка кулдауна - потому что использование нормальных машин состояний было бы слишком продвинуто
	interaction_cooldown = 0.5
	
	if not player:
		print("InteractionDetector: Ошибка - Player не найден!")
		return
	
	# (Eng) Direct UI manipulation - reaching into other systems because proper event flow is for professionals
	# (Rus) Прямая манипуляция UI - лезем в другие системы потому что нормальный поток событий для профессионалов
	var pickup_ui = get_tree().get_first_node_in_group("pickup_ui_system")
	if pickup_ui:
		pickup_ui.force_hide_prompt()
	
	# (Eng) Type-based dispatch hell - multiple ways to handle pickup because polymorphism is apparently too complicated
	# (Rus) Ад диспетчеризации по типам - несколько способов обработки подбора потому что полиморфизм видимо слишком сложен
	if item is WeaponBase:
		pickup_weapon(item)
	elif item is AmmoPickup:
		pickup_ammo(item)
	elif item.has_method("get_backpack_type"):
		pickup_backpack(item)
	else:
		print("InteractionDetector: Неизвестный тип предмета: %s" % item.get_class())

func pickup_weapon(weapon: WeaponBase):
	# (Eng) Weapon pickup through InventoryManager - proper delegation for once, but with excessive logging
	# (Rus) Подбор оружия через InventoryManager - нормальная делегация на этот раз, но с избыточным логированием
	print("InteractionDetector: Подбор оружия: %s" % weapon.weapon_type)
	
	if player.inventory_manager:
		var success = player.inventory_manager.pickup_weapon(weapon)
		if success:
			print("InteractionDetector: Оружие %s успешно подобрано" % weapon.weapon_type)
			
			# (Eng) Comic effects spam - because every action needs visual feedback even when it kills performance
			# (Rus) Спам комиксных эффектов - потому что каждому действию нужна визуальная обратная связь даже когда это убивает производительность
			if ComicEffects:
				ComicEffects.show_effect_on_node(player, ComicEffects.EffectType.PICKUP)
		else:
			print("InteractionDetector: Не удалось подобрать оружие %s" % weapon.weapon_type)
	else:
		printerr("InteractionDetector: InventoryManager не найден у игрока!")

func pickup_ammo(ammo: AmmoPickup):
	# (Eng) Ammo pickup - delegates to ammo object but still handles effects here because consistency is dead
	# (Rus) Подбор патронов - делегирует к объекту патронов но всё ещё обрабатывает эффекты здесь потому что последовательность мертва
	print("InteractionDetector: Подбор патронов: %s" % ammo.ammo_type)
	
	var pickup_success = ammo.pickup_by_player(player)
	if pickup_success:
		# (Eng) More effect spam on wrong object - showing effects on ammo instead of player because logic is optional
		# (Rus) Больше спама эффектов на неправильном объекте - показываем эффекты на патронах вместо игрока потому что логика опциональна
		if ComicEffects:
			ComicEffects.show_effect_on_node(ammo, ComicEffects.EffectType.PICKUP)
		print("InteractionDetector: Патроны успешно подобраны")
	else:
		print("InteractionDetector: Не удалось подобрать патроны")

func pickup_backpack(backpack: Node3D):
	# (Eng) Backpack pickup through InventoryManager - another proper delegation mixed with effect spam
	# (Rus) Подбор рюкзака через InventoryManager - ещё одна нормальная делегация смешанная со спамом эффектов
	print("InteractionDetector: Подбор рюкзака")
	
	if player.inventory_manager:
		var success = player.inventory_manager.pickup_backpack(backpack)
		if success:
			print("InteractionDetector: Рюкзак успешно подобран")
			
			# (Eng) Effect spam again - because apparently every pickup needs the same visual feedback
			# (Rus) Снова спам эффектов - потому что видимо каждому подбору нужна одинаковая визуальная обратная связь
			if ComicEffects:
				ComicEffects.show_effect_on_node(backpack, ComicEffects.EffectType.PICKUP)
		else:
			print("InteractionDetector: Не удалось подобрать рюкзак")
	else:
		printerr("InteractionDetector: InventoryManager не найден у игрока!")

func handle_interaction_enter(obj: Node3D):
	# (Eng) Enter interaction handler - method calling clusterfuck and type-based dispatch hell
	# (Rus) Обработчик входа во взаимодействие - пиздец вызова методов и ад диспетчеризации по типам
	print("InteractionDetector: Вход в зону: %s" % obj.name)
	
	# (Eng) Dynamic method calling - call methods that may or may not exist because error handling is for the weak
	# (Rus) Динамический вызов методов - вызываем методы которые могут существовать а могут и нет потому что обработка ошибок для слабых
	if obj.has_method("interaction_triggered"):
		obj.interaction_triggered(shape_cast)
	
	# (Eng) Group-based dispatch clusterfuck - handle different object types with separate functions because polymorphism is scary
	# (Rus) Пиздец диспетчеризации по группам - обрабатываем разные типы объектов отдельными функциями потому что полиморфизм страшен
	if obj.is_in_group("pickupable_items"):
		handle_pickupable_item(obj)
	elif obj.is_in_group("Weapons"):
		handle_weapon_item(obj)
	elif obj.is_in_group("Backpacks"):
		handle_backpack_item(obj)
	elif obj.is_in_group("interactable_objects"):
		handle_interact_obj(obj)

func handle_interaction_exit(obj: Node3D):
	# (Eng) Exit interaction handler - clean up the mess we made during enter
	# (Rus) Обработчик выхода из взаимодействия - убираем беспорядок который мы наделали при входе
	print("InteractionDetector: Выход из зоны: %s" % obj.name)
	
	# (Eng) Manual state cleanup - reset flags on objects because proper state management is too hard
	# (Rus) Ручная очистка состояния - сбрасываем флаги на объектах потому что нормальное управление состоянием слишком сложно
	if obj.has_method("set_ui_locked_by_shapecast"):
		obj.ui_locked_by_shapecast = false
	
	# (Eng) UI cleanup calls - more direct manipulation of other systems
	# (Rus) Вызовы очистки UI - больше прямых манипуляций других систем
	if obj.has_method("hide_pickup_ui"):
		obj.hide_pickup_ui()

func handle_pickupable_item(item: Node3D):
	# (Eng) Pickupable item specific handling - set magic properties on objects because proper interfaces are too complex
	# (Rus) Специфичная обработка подбираемых предметов - устанавливаем магические свойства на объекты потому что нормальные интерфейсы слишком сложны
	
	# (Eng) Duck typing hell - check for properties by string name because type safety is overrated
	# (Rus) Ад утиной типизации - проверяем свойства по строковому имени потому что безопасность типов переоценена
	if "ui_locked_by_shapecast" in item:
		item.ui_locked_by_shapecast = true
	
	# (Eng) Reference injection through property assignment - dependency injection at its worst
	# (Rus) Внедрение ссылок через присваивание свойств - внедрение зависимостей в худшем виде
	if "player_reference" in item:
		item.player_reference = player
	
	if "player_in_range" in item:
		item.player_in_range = true

func handle_interact_obj(object: Node3D):
	# (Eng) Interactive object handler - empty function because implementation is apparently optional
	# (Rus) Обработчик интерактивных объектов - пустая функция потому что реализация видимо опциональна
	pass

func handle_weapon_item(weapon: Node3D):
	# (Eng) Weapon-specific handler - just delegates to pickupable handler because code reuse is for wimps
	# (Rus) Специфичный обработчик оружия - просто делегирует к обработчику подбираемых потому что переиспользование кода для слабаков
	handle_pickupable_item(weapon)

func handle_backpack_item(backpack: Node3D):
	# (Eng) Backpack-specific handler - another delegation to the same function because we love redundancy
	# (Rus) Специфичный обработчик рюкзака - ещё одна делегация к той же функции потому что мы любим избыточность
	handle_pickupable_item(backpack)
