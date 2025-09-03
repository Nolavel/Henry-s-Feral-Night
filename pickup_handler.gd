# ✅ Script: PickupHandler.gd
# (Eng) Handles item pickup logic for weapons/ammo/backpacks, processes all that shit safely
# (Rus) Обрабатывает логику подбора предметов для оружия/патронов/рюкзаков, процессит всю эту фигню безопасно
# 🏴‍☠️ Deprecated — old junk, not used / устарело, не используется

extends Node
class_name PickupHandler

@onready var pickup_notifier: PickupNotifier = $"../../UI/PickupNotifier"

func pickup_item(item: Node3D, player: Player) -> bool:
	# (Eng) Main pickup dispatcher - figures out what kind of crap we're dealing with
	# (Rus) Основной диспетчер подбора - выясняет с какой фигнёй мы имеем дело
	if not item or not is_instance_valid(item) or not player:
		return false
	
	if item is WeaponBase:
		return pickup_weapon(item as WeaponBase, player)
	elif item is AmmoPickup:
		return pickup_ammo(item as AmmoPickup, player)
	elif has_method_safe(item, "get_backpack_type"):
		return pickup_backpack(item, player)
	else:
		print("PickupHandler: Неизвестный тип предмета: %s" % item.get_class())
		return false

func pickup_weapon(weapon: WeaponBase, player: Player) -> bool:
	# (Eng) Weapon pickup handler - adds gun to player inventory if they don't have this shit already
	# (Rus) Обработчик подбора оружия - добавляет пушку в инвентарь если у них ещё нет этой фигни
	if not weapon or not player or not player.inventory_manager:
		return false
	
	print("PickupHandler: Подбор оружия: %s" % weapon.weapon_type)
	
	if player.inventory_manager.has_weapon(weapon.weapon_type):
		print("PickupHandler: Оружие %s уже в инвентаре" % weapon.weapon_type)
		return false
	
	show_pickup_effects(weapon)
	return player.inventory_manager.pickup_weapon(weapon)

func pickup_ammo(ammo: AmmoPickup, player: Player) -> bool:
	# (Eng) Ammo pickup handler - gives player bullets for their guns
	# (Rus) Обработчик подбора патронов - даёт игроку пули для его пушек
	if not ammo or not player:
		return false
	
	print("PickupHandler: Подбор патронов: %s" % ammo.ammo_type)
	show_pickup_effects(ammo)
	return ammo.pickup_by_player(player)

func pickup_backpack(backpack: Node3D, player: Player) -> bool:
	# (Eng) Backpack pickup handler - only one backpack per player, no hoarding this crap
	# (Rus) Обработчик подбора рюкзака - только один рюкзак на игрока, без накопления этой фигни
	if not backpack or not player:
		return false
	
	print("PickupHandler: Подбор рюкзака")
	
	if player.has_backpack:
		print("PickupHandler: У игрока уже есть рюкзак")
		return false
	
	show_pickup_effects(backpack)
	
	var backpack_type = ""
	if has_method_safe(backpack, "get_backpack_type"):
		backpack_type = backpack.get_backpack_type()
	else:
		backpack_type = "Generic Backpack"
	
	var success = player.pickup_backpack(backpack_type)
	
	if success:
		# (Eng) Play pickup sound and clean up the world object
		# (Rus) Играем звук подбора и убираем объект из мира
		if has_property_safe(backpack, "pickup_sound") and backpack.pickup_sound:
			backpack.pickup_sound.play()
		if has_method_safe(backpack, "hide_backpack_in_world"):
			backpack.hide_backpack_in_world()
		backpack.queue_free.call_deferred()
	
	return success

func show_pickup_effects(item: Node3D):
	# (Eng) Visual feedback for pickup - shows comic effects and notifications
	# (Rus) Визуальная обратная связь для подбора - показывает комиксные эффекты и уведомления
	if not item:
		return
	if has_comic_effects():
		ComicEffects.show_effect_on_node(item, ComicEffects.EffectType.PICKUP)
		pickup_notifier.trigger_pickup_notification()
	var pickup_notifier = get_pickup_notifier()
	if pickup_notifier and has_method_safe(pickup_notifier, "trigger_pickup_notification"):
		pickup_notifier.trigger_pickup_notification()

func has_comic_effects() -> bool:
	# (Eng) Check if ComicEffects system is available
	# (Rus) Проверяем доступна ли система ComicEffects
	return ComicEffects != null

func get_pickup_notifier() -> Node:
	# (Eng) Find pickup notifier in scene tree - searches for UI feedback system
	# (Rus) Находим уведомлятель подбора в дереве сцены - ищет систему обратной связи UI
	var tree = Engine.get_main_loop() as SceneTree
	if tree:
		return tree.get_first_node_in_group("pickup_notifier")
	return null

func has_method_safe(obj: Node, method_name: String) -> bool:
	# (Eng) Safe method check - won't crash if object is fucked
	# (Rus) Безопасная проверка метода - не крашнется если объект сломан
	return obj != null and is_instance_valid(obj) and obj.has_method(method_name)

func has_property_safe(obj: Node, property_name: String) -> bool:
	# (Eng) Safe property check - paranoid validation to avoid crashes
	# (Rus) Безопасная проверка свойства - параноидальная валидация чтобы избежать крашей
	return obj != null and is_instance_valid(obj) and property_name in obj

func call_method_safe(obj: Node, method_name: String, args: Array = []) -> Variant:
	# (Eng) Safe method call - calls method only if it exists, returns null otherwise
	# (Rus) Безопасный вызов метода - вызывает метод только если он существует, иначе возвращает null
	if has_method_safe(obj, method_name):
		return obj.callv(method_name, args)
	return null

func is_pickupable(item: Node3D) -> bool:
	# (Eng) Validation check - determines if this piece of shit can be picked up
	# (Rus) Проверка валидации - определяет можно ли подобрать эту фигню
	if not item or not is_instance_valid(item):
		return false
	if item.is_in_group("Weapons") or item.is_in_group("Backpacks") or item.is_in_group("Pickups"):
		return true
	if item is WeaponBase or item is AmmoPickup:
		return true
	if has_method_safe(item, "can_be_picked_up"):
		return item.can_be_picked_up()
	return false

func get_pickup_type(item: Node3D) -> String:
	# (Eng) Type detection - figures out what category this item belongs to
	# (Rus) Определение типа - выясняет к какой категории относится этот предмет
	if not item:
		return "unknown"
	if item is WeaponBase:
		return "weapon"
	elif item is AmmoPickup:
		return "ammo"
	elif has_method_safe(item, "get_backpack_type"):
		return "backpack"
	else:
		return "unknown"

func can_player_pickup(item: Node3D, player: Player) -> bool:
	# (Eng) Player capacity check - makes sure player can actually take this shit
	# (Rus) Проверка вместимости игрока - убеждается что игрок может взять эту фигню
	if not is_pickupable(item) or not player:
		return false
	
	var pickup_type = get_pickup_type(item)
	match pickup_type:
		"weapon":
			var weapon = item as WeaponBase
			return not player.inventory_manager.has_weapon(weapon.weapon_type)
		"backpack":
			return not player.has_backpack
		"ammo":
			return true
		_:
			return false

func debug_pickup_attempt(item: Node3D, player: Player) -> Dictionary:
	# (Eng) Debug info dump - returns all the shit we need to troubleshoot pickup issues
	# (Rus) Дамп отладочной информации - возвращает всю фигню нужную для траблшутинга проблем подбора
	return {
		"item_valid": item != null and is_instance_valid(item),
		"player_valid": player != null and is_instance_valid(player),
		"item_type": get_pickup_type(item),
		"is_pickupable": is_pickupable(item),
		"can_pickup": can_player_pickup(item, player),
		"item_name": item.name if item else "null",
		"item_class": item.get_class() if item else "null"
	}
