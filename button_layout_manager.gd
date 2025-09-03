# ButtonLayoutManager.gd - Управление позиционированием и анимацией кнопок
extends Control
class_name ButtonLayoutManager

# === СИГНАЛЫ ===
signal button_animation_completed()

# === EXPORT НАСТРОЙКИ ===
@export_group("Animation Settings")
@export var button_spread_distance: float = 150.0
@export var button_animation_duration: float = 0.6
@export var fade_duration: float = 0.4

@export_group("Layout Settings")
@export var tactical_hub_vertical_offset: float = -50.0
@export var standard_top_offset: float = 50.0
@export var button_separation: float = 20.0

@export_group("Advanced Positioning")
@export var player_circle_radius: float = 40.0
@export var button_connection_offset: float = 25.0

@export_group("Global Offset")
@export var global_offset: Vector2 = Vector2(0, 0)

# === ССЫЛКИ НА УЗЛЫ ===
@export var system_camera: Camera3D
@export var player_node: Node3D

# Кнопки (назначаются извне)
var btn_inventory: Control
var btn_health: Control
var btn_character_overview: Control
var btn_crafting: Control
var btn_tactical_hub: Control
var btn_menu_pause: Control

# === КОНТЕЙНЕРЫ ===
var left_button_container: HBoxContainer
var right_button_container: HBoxContainer
var top_button_container: HBoxContainer
var bottom_button_container: VBoxContainer
var line_container: Control

@export_group("Btn CharacterOverview Column")
@export var character_overview_contrainer: VBoxContainer
@export var po_contrainer_info_1: HBoxContainer
@export var po_contrainer_info_2: HBoxContainer

@export_group("Btn Health Column")
@export var health_contrainer: VBoxContainer
@export var health_contrainer_info_1: HBoxContainer
@export var health_contrainer_info_2: HBoxContainer

@export_group("Btn Inventory Column")
@export var inventory_contrainer: VBoxContainer
@export var inventory_contrainer_info_1: HBoxContainer
@export var inventory_contrainer_info_2: HBoxContainer

@export_group("Btn Crafting Column")
@export var crafting_contrainer: VBoxContainer
@export var crafting_contrainer_info_1: HBoxContainer
@export var crafting_contrainer_info_2: HBoxContainer


# === СОСТОЯНИЕ ===
enum LayoutMode { STANDARD, TACTICAL_HUB }
var current_mode: LayoutMode = LayoutMode.STANDARD
var is_animating: bool = false
var player_screen_center: Vector2

# === АНИМАЦИЯ ===
var button_tween: Tween


func _ready():
	name = "ButtonLayoutManager"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	setup_containers()

func _process(_delta):
	if current_mode == LayoutMode.TACTICAL_HUB:
		update_player_screen_position()

func setup_containers():
	"""Создает контейнеры для разных групп кнопок"""
	
	# Левый контейнер
	left_button_container = HBoxContainer.new()
	left_button_container.name = "LeftButtonContainer"
	left_button_container.add_theme_constant_override("separation", button_separation)
	left_button_container.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	left_button_container.visible = false
	add_child(left_button_container)
	
	# Правый контейнер
	right_button_container = HBoxContainer.new()
	right_button_container.name = "RightButtonContainer" 
	right_button_container.add_theme_constant_override("separation", button_separation)
	right_button_container.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	right_button_container.visible = false
	add_child(right_button_container)
	
	# Верхний контейнер - ИСПРАВЛЕНО: используем TOP_LEFT для ручного контроля позиции
	top_button_container = HBoxContainer.new()
	top_button_container.name = "TopButtonContainer"
	top_button_container.add_theme_constant_override("separation", 15)
	top_button_container.set_anchors_and_offsets_preset(Control.PRESET_CENTER)  # Изменено!
	top_button_container.visible = false
	add_child(top_button_container)
	
	# ДОБАВЛЯЕМ: Нижний контейнер для menu_pause в tactical hub
	bottom_button_container = VBoxContainer.new()
	bottom_button_container.name = "BottomButtonContainer"
	bottom_button_container.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	bottom_button_container.visible = false
	add_child(bottom_button_container)
	
# === ПУБЛИЧНОЕ API ===

func set_button_references(buttons_dict: Dictionary):
	"""Устанавливает ссылки на кнопки"""
	btn_inventory = buttons_dict.get("inventory")
	btn_health = buttons_dict.get("health")
	btn_character_overview = buttons_dict.get("character_overview")
	btn_crafting = buttons_dict.get("crafting")
	btn_tactical_hub = buttons_dict.get("tactical_hub")
	btn_menu_pause = buttons_dict.get("menu_pause")

func switch_to_tactical_hub_layout(visible_buttons: Array[String]):
	"""Переключается в режим Tactical Hub с анимацией"""
	if is_animating or current_mode == LayoutMode.TACTICAL_HUB:
		return
	
	current_mode = LayoutMode.TACTICAL_HUB
	is_animating = true
	
	# Получаем центр экрана
	var viewport_size = get_viewport().get_visible_rect().size
	player_screen_center = viewport_size * 0.5
	
	clear_all_containers()
	distribute_buttons_tactical_hub(visible_buttons)
	
	# Ждём кадр для размера контейнеров
	call_deferred("_start_tactical_hub_animation")

func _start_tactical_hub_animation():
	"""Запускает анимацию tactical hub после frame delay"""
	animate_tactical_hub_appearance()

func switch_to_standard_layout(visible_buttons: Array[String]):
	"""Переключается в стандартный режим"""
	if current_mode == LayoutMode.STANDARD:
		return
	
	current_mode = LayoutMode.STANDARD
	
	_force_hide_all_info_containers()
	stop_current_animations()
	clear_all_containers() 
	distribute_buttons_standard(visible_buttons)
	
	call_deferred("_start_standard_animation")

func _start_standard_animation():
	"""Запускает стандартную анимацию после frame delay"""
	animate_standard_appearance()

func hide_all_buttons():
	"""Скрывает все кнопки"""
	stop_current_animations()
	
	left_button_container.visible = false
	right_button_container.visible = false
	top_button_container.visible = false
	bottom_button_container.visible = false  # ДОБАВЛЯЕМ
	
	if po_contrainer_info_1:
		po_contrainer_info_1.visible = false
	if po_contrainer_info_2:
		po_contrainer_info_2.visible = false
		
	if health_contrainer_info_1:
		health_contrainer_info_1.visible = false
	if health_contrainer_info_2:
		health_contrainer_info_2.visible = false
	
	if inventory_contrainer_info_1:
		inventory_contrainer_info_1.visible = false
	if inventory_contrainer_info_2:
		inventory_contrainer_info_2.visible = false
	
	if crafting_contrainer_info_1:
		crafting_contrainer_info_1.visible = false
	if crafting_contrainer_info_2:
		crafting_contrainer_info_2.visible = false
	
	clear_all_containers()
	
	current_mode = LayoutMode.STANDARD
	is_animating = false

func _on_layout_mode_requested(mode: String, visible_buttons: Array[String]):
	"""Обработчик сигнала смены режима layout"""
	match mode:
		"tactical_hub":
			switch_to_tactical_hub_layout(visible_buttons)
		"standard":
			switch_to_standard_layout(visible_buttons)

# === РАСПРЕДЕЛЕНИЕ КНОПОК ===

func distribute_buttons_tactical_hub(visible_buttons: Array[String]):
	"""Распределяет кнопки для Tactical Hub режима"""
	
	# Левые кнопки
	if "character_overview" in visible_buttons and btn_character_overview:
		reparent_button(btn_character_overview, left_button_container)
	if "health" in visible_buttons and btn_health:
		reparent_button(btn_health, left_button_container)
	
	# Правые кнопки  
	if "inventory" in visible_buttons and btn_inventory:
		reparent_button(btn_inventory, right_button_container)
	if "crafting" in visible_buttons and btn_crafting:
		reparent_button(btn_crafting, right_button_container)
	
	# ДОБАВЛЯЕМ: Нижняя кнопка menu_pause
	if "menu_pause" in visible_buttons and btn_menu_pause:
		reparent_button(btn_menu_pause, bottom_button_container)

func distribute_buttons_standard(visible_buttons: Array[String]):
	"""Распределяет кнопки для стандартного режима"""
	
	var buttons_map = {
		"tactical_hub": btn_tactical_hub,
		"character_overview": btn_character_overview,
		"inventory": btn_inventory, 
		"health": btn_health,
		"crafting": btn_crafting,
		"menu_pause": btn_menu_pause
	}
	
	for button_name in visible_buttons:
		var button = buttons_map.get(button_name)
		if button:
			reparent_button(button, top_button_container)

func reparent_button(button: Control, new_parent: Control):
	"""Безопасно перемещает кнопку в новый контейнер"""
	if not button or not new_parent:
		return
		
	if button.get_parent():
		button.get_parent().remove_child(button)
	new_parent.add_child(button)

func clear_all_containers():
	"""Очищает все контейнеры от кнопок"""
	for container in [left_button_container, right_button_container, top_button_container, bottom_button_container]:
		if is_instance_valid(container):
			for child in container.get_children():
				container.remove_child(child)

# === АНИМАЦИИ ===

func animate_tactical_hub_appearance():
	"""Анимирует появление кнопок в Tactical Hub режиме"""
	stop_current_animations()
	
	# Создаём отдельные tween'ы для каждого контейнера
	animate_left_container()
	animate_right_container()
	animate_bottom_container()  # ДОБАВЛЯЕМ
	
	
	
	# Таймер для завершения
	var completion_timer = get_tree().create_timer(button_animation_duration)
	completion_timer.timeout.connect(_on_tactical_hub_animation_complete)

func animate_left_container():
	"""Анимирует левый контейнер"""
	if left_button_container.get_child_count() == 0:
		return
	
	var container_size = left_button_container.get_rect().size
	
	var start_pos = Vector2(
		player_screen_center.x - 150 + global_offset.x, # Добавлено смещение
		player_screen_center.y + tactical_hub_vertical_offset + global_offset.y # Добавлено смещение
	)
	var end_pos = Vector2(
		player_screen_center.x - button_spread_distance + global_offset.x, # Добавлено смещение
		player_screen_center.y + tactical_hub_vertical_offset + global_offset.y # Добавлено смещение
	)
	
	
	left_button_container.position = start_pos
	left_button_container.modulate.a = 0.0
	left_button_container.visible = true
	
	var left_tween = create_tween()
	left_tween.set_parallel(true)
	left_tween.set_trans(Tween.TRANS_BACK)
	left_tween.set_ease(Tween.EASE_OUT)
	
	left_tween.tween_property(left_button_container, "position", end_pos, button_animation_duration)
	left_tween.tween_property(left_button_container, "modulate:a", 1.0, fade_duration)

func animate_right_container():
	"""Анимирует правый контейнер"""
	if right_button_container.get_child_count() == 0:
		return
	
	var container_size = right_button_container.get_rect().size
	
	var start_pos = Vector2(
		player_screen_center.x + 150 + global_offset.x, # Добавлено смещение
		player_screen_center.y + tactical_hub_vertical_offset + global_offset.y # Добавлено смещение
	)
	var end_pos = Vector2(
		player_screen_center.x + button_spread_distance + global_offset.x, # Добавлено смещение
		player_screen_center.y + tactical_hub_vertical_offset + global_offset.y # Добавлено смещение
	)
	
	right_button_container.position = start_pos
	right_button_container.modulate.a = 0.0
	right_button_container.visible = true
	
	var right_tween = create_tween()
	right_tween.set_parallel(true)
	right_tween.set_trans(Tween.TRANS_BACK)
	right_tween.set_ease(Tween.EASE_OUT)
	
	right_tween.tween_property(right_button_container, "position", end_pos, button_animation_duration)
	right_tween.tween_property(right_button_container, "modulate:a", 1.0, fade_duration)

# ДОБАВЛЯЕМ: Анимация нижнего контейнера
func animate_bottom_container():
	"""Анимирует нижний контейнер (menu_pause)"""
	if bottom_button_container.get_child_count() == 0:
		return
	
	var viewport_size = get_viewport().get_visible_rect().size
	var container_size = bottom_button_container.get_rect().size
	
	var start_pos = Vector2(
		player_screen_center.x + global_offset.x + 55, # Добавлено смещение
		player_screen_center.y + 50 + global_offset.y # Добавлено смещение
	)
	var end_pos = Vector2(
		player_screen_center.x + global_offset.x + 55, # Добавлено смещение
		player_screen_center.y + 220 + global_offset.y # Добавлено смещение
	)
	
	
	bottom_button_container.position = start_pos
	bottom_button_container.modulate.a = 0.0
	bottom_button_container.visible = true
	
	var bottom_tween = create_tween()
	bottom_tween.set_parallel(true)
	bottom_tween.set_trans(Tween.TRANS_BACK)
	bottom_tween.set_ease(Tween.EASE_OUT)
	
	bottom_tween.tween_property(bottom_button_container, "position", end_pos, button_animation_duration)
	bottom_tween.tween_property(bottom_button_container, "modulate:a", 1.0, fade_duration)

func animate_standard_appearance():
	"""Анимирует появление кнопок в стандартном режиме"""
	if top_button_container.get_child_count() == 0:
		return
	
	stop_current_animations()
	
	top_button_container.visible = true
	
	# ИСПРАВЛЕНИЕ: Центрируем относительно экрана
	var viewport_size = get_viewport().get_visible_rect().size
	var container_width = top_button_container.get_rect().size.x
	var final_pos = Vector2(
		(viewport_size.x - container_width) / 2.0,  # Центр по X
		standard_top_offset  # Отступ сверху
	)
	
	# Начальная позиция для анимации (сверху за экраном)
	var start_pos = Vector2(final_pos.x, -100)
	
	top_button_container.position = start_pos
	top_button_container.modulate.a = 0.0
	
	var standard_tween = create_tween()
	standard_tween.set_parallel(true)
	standard_tween.set_trans(Tween.TRANS_BACK)
	standard_tween.set_ease(Tween.EASE_OUT)
	
	standard_tween.tween_property(top_button_container, "position", final_pos, 0.5)
	standard_tween.tween_property(top_button_container, "modulate:a", 1.0, fade_duration)
	
	var completion_timer = get_tree().create_timer(0.5)
	completion_timer.timeout.connect(_on_standard_animation_complete)

func stop_current_animations():
	"""Останавливает текущие анимации"""
	if button_tween and button_tween.is_valid():
		button_tween.kill()
	
	is_animating = false

func _on_tactical_hub_animation_complete():
	"""Вызывается по завершении анимации Tactical Hub"""
	pass
	
	is_animating = false
	button_animation_completed.emit()
	animate_player_overview_info_containers()
	animate_health_info_containers()         # ДОБАВИТЬ
	animate_inventory_info_containers()      # ДОБАВИТЬ
	animate_crafting_info_containers() 

func _on_standard_animation_complete():
	"""Вызывается по завершении стандартной анимации"""
	is_animating = false
	button_animation_completed.emit()

func update_player_screen_position():
	"""Обновляет позицию игрока на экране"""
	if not system_camera or not player_node:
		return
	
	var new_center = system_camera.unproject_position(player_node.global_position)
	if new_center != player_screen_center:
		player_screen_center = new_center

# === УТИЛИТЫ ===

func is_layout_animating() -> bool:
	return is_animating

func get_current_mode() -> LayoutMode:
	return current_mode

func set_animation_settings(spread: float, duration: float, line_duration: float):
	button_spread_distance = spread
	button_animation_duration = duration
	
func animate_player_overview_info_containers():
	"""Анимирует появление info контейнеров под кнопкой player overview"""
	if current_mode != LayoutMode.TACTICAL_HUB:
		return
	
	if not po_contrainer_info_1 or not po_contrainer_info_2:
		return
	
	if not btn_character_overview or not btn_character_overview.visible:
		return
	
		# В начале функции animate_player_overview_info_containers():
	if po_contrainer_info_1.get_parent() != btn_character_overview:
		if po_contrainer_info_1.get_parent():
			po_contrainer_info_1.get_parent().remove_child(po_contrainer_info_1)
		btn_character_overview.add_child(po_contrainer_info_1)

	if po_contrainer_info_2.get_parent() != btn_character_overview:
		if po_contrainer_info_2.get_parent():
			po_contrainer_info_2.get_parent().remove_child(po_contrainer_info_2)
		btn_character_overview.add_child(po_contrainer_info_2)

		# Замени расчет позиций на это:
	var container_x = 0   # Поскольку теперь относительно кнопки
	var start_y = btn_character_overview.size.y + 30

	# ДИНАМИЧЕСКИЙ расчет позиций с учетом размеров контейнеров
	var spacing = 10  # Отступ между контейнерами

	# Устанавливаем начальные состояния
	po_contrainer_info_1.position = Vector2(container_x, start_y)
	po_contrainer_info_1.modulate.a = 0.0
	po_contrainer_info_1.visible = true

	# Ждем frame чтобы получить правильный размер первого контейнера
	await get_tree().process_frame

	# Теперь позиционируем второй контейнер с учетом высоты первого
	var info_1_height = po_contrainer_info_1.get_rect().size.y
	po_contrainer_info_2.position = Vector2(container_x, start_y + info_1_height + spacing)
	po_contrainer_info_2.modulate.a = 0.0
	po_contrainer_info_2.visible = true

	# В анимации также используем динамические размеры:
	var info_tween = create_tween()

	# Этап 1: Появление первого контейнера
	info_tween.tween_property(po_contrainer_info_1, "modulate:a", 1.0, 0.4)
	info_tween.tween_property(po_contrainer_info_1, "scale", Vector2(1.1, 1.1), 0.2)
	info_tween.tween_property(po_contrainer_info_1, "scale", Vector2(1.0, 1.0), 0.2)

	# Этап 2: Появление второго контейнера
	info_tween.tween_property(po_contrainer_info_2, "modulate:a", 1.0, 0.4)
	info_tween.tween_property(po_contrainer_info_2, "scale", Vector2(1.1, 1.1), 0.2)
	info_tween.tween_property(po_contrainer_info_2, "scale", Vector2(1.0, 1.0), 0.2)

	# Этап 3: Скольжение с учетом РЕАЛЬНЫХ размеров
	info_tween.set_parallel(true)
	var final_y_1 = start_y + 15.0
	var final_y_2 = final_y_1 + info_1_height + spacing + 15.0  # Динамический расчет

	info_tween.tween_property(po_contrainer_info_1, "position:y", final_y_1, 0.5)
	info_tween.tween_property(po_contrainer_info_2, "position:y", final_y_2, 0.5)

func animate_health_info_containers():
	"""Анимирует появление info контейнеров под кнопкой health"""
	if current_mode != LayoutMode.TACTICAL_HUB:
		return
	
	if not health_contrainer_info_1 or not health_contrainer_info_2:
		return
	
	if not btn_health or not btn_health.visible:
		return
	
	# Перемещаем контейнеры под кнопку health
	if health_contrainer_info_1.get_parent() != btn_health:
		if health_contrainer_info_1.get_parent():
			health_contrainer_info_1.get_parent().remove_child(health_contrainer_info_1)
		btn_health.add_child(health_contrainer_info_1)

	if health_contrainer_info_2.get_parent() != btn_health:
		if health_contrainer_info_2.get_parent():
			health_contrainer_info_2.get_parent().remove_child(health_contrainer_info_2)
		btn_health.add_child(health_contrainer_info_2)

	var container_x = 0   # Поскольку теперь относительно кнопки
	var start_y = btn_health.size.y + 30

	# ДИНАМИЧЕСКИЙ расчет позиций с учетом размеров контейнеров
	var spacing = 10  # Отступ между контейнерами

	# Устанавливаем начальные состояния
	health_contrainer_info_1.position = Vector2(container_x, start_y)
	health_contrainer_info_1.modulate.a = 0.0
	health_contrainer_info_1.visible = true

	# Ждем frame чтобы получить правильный размер первого контейнера
	await get_tree().process_frame

	# Теперь позиционируем второй контейнер с учетом высоты первого
	var info_1_height = health_contrainer_info_1.get_rect().size.y
	health_contrainer_info_2.position = Vector2(container_x, start_y + info_1_height + spacing)
	health_contrainer_info_2.modulate.a = 0.0
	health_contrainer_info_2.visible = true

	# В анимации также используем динамические размеры:
	var info_tween = create_tween()

	# Этап 1: Появление первого контейнера
	info_tween.tween_property(health_contrainer_info_1, "modulate:a", 1.0, 0.4)
	info_tween.tween_property(health_contrainer_info_1, "scale", Vector2(1.1, 1.1), 0.2)
	info_tween.tween_property(health_contrainer_info_1, "scale", Vector2(1.0, 1.0), 0.2)

	# Этап 2: Появление второго контейнера
	info_tween.tween_property(health_contrainer_info_2, "modulate:a", 1.0, 0.4)
	info_tween.tween_property(health_contrainer_info_2, "scale", Vector2(1.1, 1.1), 0.2)
	info_tween.tween_property(health_contrainer_info_2, "scale", Vector2(1.0, 1.0), 0.2)

	# Этап 3: Скольжение с учетом РЕАЛЬНЫХ размеров
	info_tween.set_parallel(true)
	var final_y_1 = start_y + 15.0
	var final_y_2 = final_y_1 + info_1_height + spacing + 15.0  # Динамический расчет

	info_tween.tween_property(health_contrainer_info_1, "position:y", final_y_1, 0.5)
	info_tween.tween_property(health_contrainer_info_2, "position:y", final_y_2, 0.5)

func animate_inventory_info_containers():
	"""Анимирует появление info контейнеров под кнопкой inventory"""
	if current_mode != LayoutMode.TACTICAL_HUB:
		return
	
	if not inventory_contrainer_info_1 or not inventory_contrainer_info_2:
		return
	
	if not btn_inventory or not btn_inventory.visible:
		return
	
	# Перемещаем контейнеры под кнопку inventory
	if inventory_contrainer_info_1.get_parent() != btn_inventory:
		if inventory_contrainer_info_1.get_parent():
			inventory_contrainer_info_1.get_parent().remove_child(inventory_contrainer_info_1)
		btn_inventory.add_child(inventory_contrainer_info_1)

	if inventory_contrainer_info_2.get_parent() != btn_inventory:
		if inventory_contrainer_info_2.get_parent():
			inventory_contrainer_info_2.get_parent().remove_child(inventory_contrainer_info_2)
		btn_inventory.add_child(inventory_contrainer_info_2)

	var container_x = 0   # Поскольку теперь относительно кнопки
	var start_y = btn_inventory.size.y + 30

	# ДИНАМИЧЕСКИЙ расчет позиций с учетом размеров контейнеров
	var spacing = 10  # Отступ между контейнерами

	# Устанавливаем начальные состояния
	inventory_contrainer_info_1.position = Vector2(container_x, start_y)
	inventory_contrainer_info_1.modulate.a = 0.0
	inventory_contrainer_info_1.visible = true

	# Ждем frame чтобы получить правильный размер первого контейнера
	await get_tree().process_frame

	# Теперь позиционируем второй контейнер с учетом высоты первого
	var info_1_height = inventory_contrainer_info_1.get_rect().size.y
	inventory_contrainer_info_2.position = Vector2(container_x, start_y + info_1_height + spacing)
	inventory_contrainer_info_2.modulate.a = 0.0
	inventory_contrainer_info_2.visible = true

	# В анимации также используем динамические размеры:
	var info_tween = create_tween()

	# Этап 1: Появление первого контейнера
	info_tween.tween_property(inventory_contrainer_info_1, "modulate:a", 1.0, 0.4)
	info_tween.tween_property(inventory_contrainer_info_1, "scale", Vector2(1.1, 1.1), 0.2)
	info_tween.tween_property(inventory_contrainer_info_1, "scale", Vector2(1.0, 1.0), 0.2)

	# Этап 2: Появление второго контейнера
	info_tween.tween_property(inventory_contrainer_info_2, "modulate:a", 1.0, 0.4)
	info_tween.tween_property(inventory_contrainer_info_2, "scale", Vector2(1.1, 1.1), 0.2)
	info_tween.tween_property(inventory_contrainer_info_2, "scale", Vector2(1.0, 1.0), 0.2)

	# Этап 3: Скольжение с учетом РЕАЛЬНЫХ размеров
	info_tween.set_parallel(true)
	var final_y_1 = start_y + 15.0
	var final_y_2 = final_y_1 + info_1_height + spacing + 15.0  # Динамический расчет

	info_tween.tween_property(inventory_contrainer_info_1, "position:y", final_y_1, 0.5)
	info_tween.tween_property(inventory_contrainer_info_2, "position:y", final_y_2, 0.5)

func animate_crafting_info_containers():
	"""Анимирует появление info контейнеров под кнопкой crafting"""
	if current_mode != LayoutMode.TACTICAL_HUB:
		return
	
	if not crafting_contrainer_info_1 or not crafting_contrainer_info_2:
		return
	
	if not btn_crafting or not btn_crafting.visible:
		return
	
	# Перемещаем контейнеры под кнопку crafting
	if crafting_contrainer_info_1.get_parent() != btn_crafting:
		if crafting_contrainer_info_1.get_parent():
			crafting_contrainer_info_1.get_parent().remove_child(crafting_contrainer_info_1)
		btn_crafting.add_child(crafting_contrainer_info_1)

	if crafting_contrainer_info_2.get_parent() != btn_crafting:
		if crafting_contrainer_info_2.get_parent():
			crafting_contrainer_info_2.get_parent().remove_child(crafting_contrainer_info_2)
		btn_crafting.add_child(crafting_contrainer_info_2)

	var container_x = 0   # Поскольку теперь относительно кнопки
	var start_y = btn_crafting.size.y + 30

	# ДИНАМИЧЕСКИЙ расчет позиций с учетом размеров контейнеров
	var spacing = 10  # Отступ между контейнерами

	# Устанавливаем начальные состояния
	crafting_contrainer_info_1.position = Vector2(container_x, start_y)
	crafting_contrainer_info_1.modulate.a = 0.0
	crafting_contrainer_info_1.visible = true

	# Ждем frame чтобы получить правильный размер первого контейнера
	await get_tree().process_frame

	# Теперь позиционируем второй контейнер с учетом высоты первого
	var info_1_height = crafting_contrainer_info_1.get_rect().size.y
	crafting_contrainer_info_2.position = Vector2(container_x, start_y + info_1_height + spacing)
	crafting_contrainer_info_2.modulate.a = 0.0
	crafting_contrainer_info_2.visible = true

	# В анимации также используем динамические размеры:
	var info_tween = create_tween()

	# Этап 1: Появление первого контейнера
	info_tween.tween_property(crafting_contrainer_info_1, "modulate:a", 1.0, 0.4)
	info_tween.tween_property(crafting_contrainer_info_1, "scale", Vector2(1.1, 1.1), 0.2)
	info_tween.tween_property(crafting_contrainer_info_1, "scale", Vector2(1.0, 1.0), 0.2)

	# Этап 2: Появление второго контейнера
	info_tween.tween_property(crafting_contrainer_info_2, "modulate:a", 1.0, 0.4)
	info_tween.tween_property(crafting_contrainer_info_2, "scale", Vector2(1.1, 1.1), 0.2)
	info_tween.tween_property(crafting_contrainer_info_2, "scale", Vector2(1.0, 1.0), 0.2)

	# Этап 3: Скольжение с учетом РЕАЛЬНЫХ размеров
	info_tween.set_parallel(true)
	var final_y_1 = start_y + 15.0
	var final_y_2 = final_y_1 + info_1_height + spacing + 15.0  # Динамический расчет

	info_tween.tween_property(crafting_contrainer_info_1, "position:y", final_y_1, 0.5)
	info_tween.tween_property(crafting_contrainer_info_2, "position:y", final_y_2, 0.5)

func _force_hide_all_info_containers():
	"""Принудительно скрывает все info контейнеры"""
	if po_contrainer_info_1: po_contrainer_info_1.visible = false
	if po_contrainer_info_2: po_contrainer_info_2.visible = false
	if health_contrainer_info_1: health_contrainer_info_1.visible = false
	if health_contrainer_info_2: health_contrainer_info_2.visible = false
	if inventory_contrainer_info_1: inventory_contrainer_info_1.visible = false
	if inventory_contrainer_info_2: inventory_contrainer_info_2.visible = false
	if crafting_contrainer_info_1: crafting_contrainer_info_1.visible = false
	if crafting_contrainer_info_2: crafting_contrainer_info_2.visible = false
