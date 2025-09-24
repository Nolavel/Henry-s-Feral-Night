extends Node3D
class_name InventoryManager

# === ПАРАМЕТРЫ ИНВЕНТАРЯ ===
@export_group("Настройки инвентаря")
@export var max_slots: int = 30
@export var max_stack_size: int = 64
@export var auto_pickup_radius: float = 2.0
@export var auto_pickup_enabled: bool = true

@export_group("Быстрый доступ")
@export var hotbar_slots: int = 9
@export var quick_use_enabled: bool = true

# === СОСТОЯНИЕ ИНВЕНТАРЯ ===
var _player: CharacterBody3D
var _inventory_slots: Array[InventorySlot] = []
var _hotbar_slots_array: Array[InventorySlot] = []
var _selected_hotbar_index: int = 0
var _pickup_area: Area3D
var _is_inventory_open: bool = false

# === СИГНАЛЫ ===
signal inventory_changed
signal item_added(item: Item, slot_index: int)
signal item_removed(item: Item, slot_index: int)
signal item_used(item: Item, slot_index: int)
signal hotbar_selection_changed(new_index: int)
signal inventory_full
signal item_dropped(item: Item, world_position: Vector3)

# === КЛАССЫ ДАННЫХ ===
class InventorySlot:
	var item: Item = null
	var quantity: int = 0
	var is_locked: bool = false
	
	func is_empty() -> bool:
		return item == null or quantity <= 0
	
	func can_add_item(new_item: Item, amount: int, max_stack: int) -> bool:
		if is_locked:
			return false
		if is_empty():
			return true
		return item.id == new_item.id and (quantity + amount) <= max_stack
	
	func add_item(new_item: Item, amount: int, max_stack: int) -> int:
		if not can_add_item(new_item, amount, max_stack):
			return 0
		
		if is_empty():
			item = new_item
			quantity = min(amount, max_stack)
		else:
			var can_add = min(amount, max_stack - quantity)
			quantity += can_add
			return can_add
		
		return amount
	
	func remove_item(amount: int) -> int:
		if is_empty() or is_locked:
			return 0
		
		var removed = min(amount, quantity)
		quantity -= removed
		
		if quantity <= 0:
			item = null
			quantity = 0
		
		return removed

class Item:
	var id: String
	var name: String
	var description: String
	var icon: Texture2D
	var max_stack_size: int = 64
	var item_type: ItemType
	var use_action: String = ""
	var value: int = 0
	
	enum ItemType {
		CONSUMABLE,
		TOOL,
		WEAPON,
		ARMOR,
		MATERIAL,
		QUEST,
		MISC
	}
	
	func _init(item_id: String = "", item_name: String = "", max_stack: int = 64):
		id = item_id
		name = item_name
		max_stack_size = max_stack

func setup(player: CharacterBody3D) -> void:
	_player = player
	_initialize_inventory()
	_setup_pickup_area()
	_connect_input_signals()

func _initialize_inventory() -> void:
	# Создаем слоты инвентаря
	_inventory_slots.clear()
	for i in range(max_slots):
		_inventory_slots.append(InventorySlot.new())
	
	# Настраиваем хотбар (первые N слотов)
	_hotbar_slots_array.clear()
	for i in range(min(hotbar_slots, max_slots)):
		_hotbar_slots_array.append(_inventory_slots[i])

func _setup_pickup_area() -> void:
	# Создаем область для автоподбора предметов
	_pickup_area = Area3D.new()
	var collision_shape = CollisionShape3D.new()
	var sphere_shape = SphereShape3D.new()
	sphere_shape.radius = auto_pickup_radius
	collision_shape.shape = sphere_shape
	
	_pickup_area.add_child(collision_shape)
	add_child(_pickup_area)
	
	_pickup_area.body_entered.connect(_on_pickup_area_entered)

func _connect_input_signals() -> void:
	# Подключаем обработку ввода для хотбара
	pass # Будет обрабатываться в _input()

func _input(event: InputEvent) -> void:
	if not _player:
		return
	
	_handle_hotbar_input(event)
	_handle_inventory_input(event)

func _handle_hotbar_input(event: InputEvent) -> void:
	# Переключение слотов хотбара колесиком мыши
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			select_previous_hotbar_slot()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			select_next_hotbar_slot()
	
	# Прямой выбор слота цифрами
	if event is InputEventKey and event.pressed:
		for i in range(min(9, hotbar_slots)):
			if event.keycode == KEY_1 + i:
				select_hotbar_slot(i)
				break

func _handle_inventory_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_I:
			toggle_inventory()
		elif event.keycode == KEY_Q:
			drop_selected_item()
		elif event.keycode == KEY_E and quick_use_enabled:
			use_selected_item()

#func _physics_process(delta: float) -> void:
	#if auto_pickup_enabled:
		#_check_auto_pickup()

#func _check_auto_pickup() -> void:
	## Автоподбор предметов в радиусе
	#var bodies = _pickup_area.get_overlapping_bodies()
	#for body in bodies:
		#if body.has_method("get_item") and body.has_method("pickup"):
			#var item = body.get_item()
			#if add_item(item):
				#body.pickup()

func _on_pickup_area_entered(body: Node3D) -> void:
	# Дополнительная логика при входе в зону подбора
	pass

# === ОСНОВНЫЕ МЕТОДЫ ИНВЕНТАРЯ ===
func add_item(item: Item, quantity: int = 1) -> bool:
	if not item or quantity <= 0:
		return false
	
	var remaining = quantity
	
	# Сначала пытаемся добавить к существующим стакам
	for i in range(_inventory_slots.size()):
		var slot = _inventory_slots[i]
		if not slot.is_empty() and slot.item.id == item.id:
			var added = slot.add_item(item, remaining, item.max_stack_size)
			remaining -= added
			if added > 0:
				item_added.emit(item, i)
			if remaining <= 0:
				break
	
	# Затем заполняем пустые слоты
	if remaining > 0:
		for i in range(_inventory_slots.size()):
			var slot = _inventory_slots[i]
			if slot.is_empty():
				var added = slot.add_item(item, remaining, item.max_stack_size)
				remaining -= added
				if added > 0:
					item_added.emit(item, i)
				if remaining <= 0:
					break
	
	if remaining < quantity:
		inventory_changed.emit()
	
	if remaining > 0:
		inventory_full.emit()
		return false
	
	return true

func remove_item(item_id: String, quantity: int = 1) -> int:
	if quantity <= 0:
		return 0
	
	var remaining = quantity
	
	for i in range(_inventory_slots.size()):
		var slot = _inventory_slots[i]
		if not slot.is_empty() and slot.item.id == item_id:
			var removed = slot.remove_item(remaining)
			remaining -= removed
			if removed > 0:
				item_removed.emit(slot.item, i)
			if remaining <= 0:
				break
	
	if remaining < quantity:
		inventory_changed.emit()
	
	return quantity - remaining

func remove_item_from_slot(slot_index: int, quantity: int = 1) -> int:
	if slot_index < 0 or slot_index >= _inventory_slots.size():
		return 0
	
	var slot = _inventory_slots[slot_index]
	var removed = slot.remove_item(quantity)
	
	if removed > 0:
		item_removed.emit(slot.item, slot_index)
		inventory_changed.emit()
	
	return removed

func get_item_count(item_id: String) -> int:
	var count = 0
	for slot in _inventory_slots:
		if not slot.is_empty() and slot.item.id == item_id:
			count += slot.quantity
	return count

func has_item(item_id: String, quantity: int = 1) -> bool:
	return get_item_count(item_id) >= quantity

func find_item_slot(item_id: String) -> int:
	for i in range(_inventory_slots.size()):
		var slot = _inventory_slots[i]
		if not slot.is_empty() and slot.item.id == item_id:
			return i
	return -1

# === МЕТОДЫ ХОТБАРА ===
func select_hotbar_slot(index: int) -> void:
	if index < 0 or index >= _hotbar_slots_array.size():
		return
	
	_selected_hotbar_index = index
	hotbar_selection_changed.emit(index)

func select_next_hotbar_slot() -> void:
	var next_index = (_selected_hotbar_index + 1) % _hotbar_slots_array.size()
	select_hotbar_slot(next_index)

func select_previous_hotbar_slot() -> void:
	var prev_index = (_selected_hotbar_index - 1 + _hotbar_slots_array.size()) % _hotbar_slots_array.size()
	select_hotbar_slot(prev_index)

func get_selected_item() -> Item:
	if _selected_hotbar_index >= 0 and _selected_hotbar_index < _hotbar_slots_array.size():
		var slot = _hotbar_slots_array[_selected_hotbar_index]
		return slot.item
	return null

func use_selected_item() -> bool:
	var item = get_selected_item()
	if not item:
		return false
	
	var success = _use_item(item, _selected_hotbar_index)
	if success:
		item_used.emit(item, _selected_hotbar_index)
		remove_item_from_slot(_selected_hotbar_index, 1)
	
	return success

func drop_selected_item(quantity: int = 1) -> void:
	if _selected_hotbar_index < 0 or _selected_hotbar_index >= _hotbar_slots_array.size():
		return
	
	var slot = _hotbar_slots_array[_selected_hotbar_index]
	if slot.is_empty():
		return
	
	var drop_amount = min(quantity, slot.quantity)
	var dropped_item = slot.item
	
	remove_item_from_slot(_selected_hotbar_index, drop_amount)
	_drop_item_to_world(dropped_item, drop_amount)

func _drop_item_to_world(item: Item, quantity: int) -> void:
	if not _player:
		return
	
	var drop_position = _player.global_transform.origin + Vector3(0, 1, 0)
	# Добавляем небольшой случайный разброс
	drop_position += Vector3(randf_range(-0.5, 0.5), 0, randf_range(-0.5, 0.5))
	
	item_dropped.emit(item, drop_position)
	
	# Здесь должна быть логика создания физического объекта предмета в мире

func _use_item(item: Item, slot_index: int) -> bool:
	if not item:
		return false
	
	# Логика использования предмета в зависимости от типа
	match item.item_type:
		Item.ItemType.CONSUMABLE:
			return _use_consumable(item)
		Item.ItemType.TOOL:
			return _use_tool(item)
		Item.ItemType.WEAPON:
			return _equip_weapon(item)
		_:
			return false

func _use_consumable(item: Item) -> bool:
	# Пример: лечение, восстановление энергии и т.д.
	match item.use_action:
		"heal":
			# _player.health_system.heal(item.value)
			return true
		"mana":
			# _player.mana_system.restore(item.value)
			return true
		_:
			return false

func _use_tool(item: Item) -> bool:
	# Логика использования инструментов
	return true

func _equip_weapon(item: Item) -> bool:
	# Логика экипировки оружия
	return true

# === УПРАВЛЕНИЕ ИНТЕРФЕЙСОМ ===
func toggle_inventory() -> void:
	_is_inventory_open = not _is_inventory_open
	# Здесь должна быть логика показа/скрытия UI инвентаря

func is_inventory_open() -> bool:
	return _is_inventory_open

# === СЕРИАЛИЗАЦИЯ ===
func save_inventory_data() -> Dictionary:
	var data = {}
	data["slots"] = []
	
	for i in range(_inventory_slots.size()):
		var slot = _inventory_slots[i]
		if not slot.is_empty():
			data["slots"].append({
				"index": i,
				"item_id": slot.item.id,
				"quantity": slot.quantity
			})
	
	data["selected_hotbar"] = _selected_hotbar_index
	return data

func load_inventory_data(data: Dictionary) -> void:
	if not data.has("slots"):
		return
	
	# Очищаем инвентарь
	for slot in _inventory_slots:
		slot.item = null
		slot.quantity = 0
	
	# Загружаем предметы
	for slot_data in data["slots"]:
		var slot_index = slot_data.get("index", -1)
		var item_id = slot_data.get("item_id", "")
		var quantity = slot_data.get("quantity", 0)
		
		if slot_index >= 0 and slot_index < _inventory_slots.size():
			# Здесь должна быть загрузка предмета по ID из базы данных предметов
			var item = _create_item_by_id(item_id)
			if item:
				_inventory_slots[slot_index].add_item(item, quantity, item.max_stack_size)
	
	_selected_hotbar_index = data.get("selected_hotbar", 0)
	inventory_changed.emit()

func _create_item_by_id(item_id: String) -> Item:
	# Здесь должна быть логика создания предмета по ID
	# Например, загрузка из ItemDatabase
	return null

# === ГЕТТЕРЫ ===
func get_inventory_slots() -> Array[InventorySlot]:
	return _inventory_slots

func get_hotbar_slots() -> Array[InventorySlot]:
	return _hotbar_slots_array

func get_selected_hotbar_index() -> int:
	return _selected_hotbar_index

func get_free_slots_count() -> int:
	var count = 0
	for slot in _inventory_slots:
		if slot.is_empty():
			count += 1
	return count

func is_full() -> bool:
	return get_free_slots_count() == 0
