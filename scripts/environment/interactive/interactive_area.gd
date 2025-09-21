extends Area3D
class_name InteractiveArea

enum InteractionType {
	PUSHABLE,
	PICKUP,
	BUTTON,
	DOOR,
	OTHER
}

enum PickupSubtype {
	WEAPON,      # Оружие
	FOOD,        # Еда
	WATER,       # Вода
	CLOTHING,    # Одежда
	TOOLS,       # Инструменты
	SPECIAL,     # Особые предметы
	JUNK         # Хлам
}

# === ОСНОВНЫЕ ПАРАМЕТРЫ ===
@export_group("Настройки взаимодействия")
@export var interaction_type: InteractionType = InteractionType.OTHER
@export var pickup_subtype: PickupSubtype = PickupSubtype.JUNK
@export var item_name: String = "Неизвестный объект"
@export var description: String = "Описание отсутствует"

# === ЗАГРУЖАЕМЫЕ РЕСУРСЫ ===
@export_group("Загружаемые ресурсы")
@export var interactable_scene: PackedScene  # Сцена с мешом и коллизией

# === ВИЗУАЛЬНЫЕ ЭЛЕМЕНТЫ ===
@export_group("Визуальные элементы")
@export var icon_sprite: Sprite3D
@export var info_label: Label3D
@export var interactive_mesh: MeshInstance3D  # Меш под которым создаем круг

# === НАСТРОЙКИ ОТОБРАЖЕНИЯ ===
@export_group("Настройки отображения")
@export var icon_height_offset: float = 1.5
@export var info_height_offset: float = 2.0
@export var fade_duration: float = 0.3
@export var billboard_mode: bool = true

# === АВТОМАТИЧЕСКОЕ ОПРЕДЕЛЕНИЕ ЗЕМЛИ ===
@export_group("Автоопределение земли")
@export var auto_detect_ground: bool = true  # Включить автоопределение
@export var ground_check_distance: float = 0.1  # Дистанция проверки вниз
@export var object_on_ground: bool = true 
var ground_raycast: RayCast3D

# === НАСТРОЙКИ ПОДСВЕТКИ КРУГА ===
@export_group("Подсветка круга")
@export var highlight_color: Color = Color(1.0, 1.0, 0.0, 0.45)  # Цвет круга
@export var circle_radius: float = 1.0  # Размер круга
@export var circle_animation_duration: float = 0.5  # Длительность анимации

# === ВНУТРЕННИЕ ПЕРЕМЕННЫЕ ===
var player_in_area := false
var shape_cast_detected := false
var player_reference: CharacterBody3D = null
var tween_icon: Tween
var tween_info: Tween
var highlight_circle: MeshInstance3D = null  # Круг подсветки
var tween_circle: Tween
var loaded_interactable_node: Node3D = null  # Загруженная сцена

# Кэш для избежания пересоздания строки
var _cached_interaction_text: String = ""
var _text_cache_dirty: bool = true

# === ТАЙМЕР ШЕЙКА ===
var shake_timer: Timer = null
var is_shaking: bool = false
var original_icon_position: Vector3
const WAIT_TIME: float = 5.0  # Время ожидания до шейка
const SHAKE_TIME: float = 2.0  # Длительность шейка
const SHAKE_STRENGTH: float = 0.1  # Сила тряски

func _ready() -> void:
	_load_interactable_scene()
	_setup_initial_state()
	_setup_ground_detection()
	_setup_visual_elements()
	_create_highlight_circle()
	_setup_shake_timer()

func _setup_initial_state() -> void:
	if icon_sprite:
		icon_sprite.visible = false
		icon_sprite.modulate.a = 0.0
	
	if info_label:
		info_label.visible = false
		info_label.modulate.a = 0.0

func _setup_visual_elements() -> void:
	if icon_sprite:
		if billboard_mode:
			icon_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		icon_sprite.position.y = icon_height_offset
	
	if info_label:
		if billboard_mode:
			info_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		info_label.position.y = info_height_offset
		info_label.font_size = 64
		info_label.outline_size = 8

func _create_highlight_circle() -> void:
	if not interactive_mesh:
		push_warning("InteractiveArea: interactive_mesh не назначен!")
		return
	
	highlight_circle = MeshInstance3D.new()
	add_child(highlight_circle)
	
	var circle_mesh = CylinderMesh.new()
	circle_mesh.height = 0.01
	circle_mesh.top_radius = circle_radius
	circle_mesh.bottom_radius = circle_radius
	circle_mesh.cap_top = true
	circle_mesh.cap_bottom = false
	highlight_circle.mesh = circle_mesh
	
	var circle_material = StandardMaterial3D.new()
	# ВАЖНО: создаем с альфой 0 изначально
	var transparent_color = Color(highlight_color.r, highlight_color.g, highlight_color.b, 0.0)
	circle_material.albedo_color = transparent_color
	circle_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	circle_material.flags_transparent = true
	circle_material.flags_unshaded = true
	# Добавляем no_depth_test чтобы круг не скрывался землей
	circle_material.no_depth_test = true
	highlight_circle.material_override = circle_material
	
	var mesh_bounds = interactive_mesh.get_aabb()
	highlight_circle.position = Vector3(0, mesh_bounds.position.y - 0.05, 0) # ближе к поверхности
	highlight_circle.rotation.x = 0
	highlight_circle.visible = true  # оставляем видимым, но прозрачным
	highlight_circle.scale = Vector3.ONE
	
	highlight_circle.set_meta("mat", circle_material)

func _setup_shake_timer() -> void:
	shake_timer = Timer.new()
	shake_timer.wait_time = WAIT_TIME
	shake_timer.one_shot = true
	shake_timer.timeout.connect(_start_shake)
	add_child(shake_timer)

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		player_in_area = true
		player_reference = body
		_show_icon_sprite()
		_start_shake_cycle()

func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		player_in_area = false
		shape_cast_detected = false
		player_reference = null
		_hide_icon_sprite_with_lift()
		_hide_info_label()
		_stop_shake_cycle()

func set_shape_cast_detected(detected: bool) -> void:
	# Небольшая оптимизация - избегаем лишних вызовов
	if shape_cast_detected == detected:
		return
		
	shape_cast_detected = detected
	if player_in_area:
		if shape_cast_detected:
			_stop_shake_cycle()  # Останавливаем тряску
			_hide_icon_sprite_with_lift_then_show_info()  # Сначала скрываем спрайт, потом показываем инфо
			if object_on_ground:
				_show_highlight_circle()
		else:
			_show_icon_sprite()
			_hide_info_label()
			if object_on_ground:
				_hide_highlight_circle()
			_start_shake_cycle()  # Перезапускаем цикл тряски

func _show_icon_sprite() -> void:
	if not icon_sprite:
		return
	
	# Сохраняем оригинальную позицию для шейка
	if not is_shaking:
		original_icon_position = icon_sprite.position
	
	icon_sprite.visible = true
	
	if tween_icon:
		tween_icon.kill()
	tween_icon = create_tween()
	
	# Спрайт появляется сверху и опускается в свое положение
	icon_sprite.position.y = original_icon_position.y + 0.5  # Начинаем выше
	icon_sprite.modulate.a = 0.0  # Начинаем прозрачным
	
	# Параллельные анимации: опускание вниз И появление
	tween_icon.parallel().tween_property(icon_sprite, "position:y", original_icon_position.y, fade_duration)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BOUNCE)
	tween_icon.parallel().tween_property(icon_sprite, "modulate:a", 1.0, fade_duration)

func _hide_icon_sprite() -> void:
	if not icon_sprite:
		return
	
	if tween_icon:
		tween_icon.kill()
	tween_icon = create_tween()
	tween_icon.tween_property(icon_sprite, "modulate:a", 0.0, fade_duration)
	tween_icon.tween_callback(func(): icon_sprite.visible = false)

func _hide_icon_sprite_with_lift() -> void:
	if not icon_sprite:
		return
	
	if tween_icon:
		tween_icon.kill()
	tween_icon = create_tween()
	
	# Параллельные анимации: поднятие вверх И исчезновение
	tween_icon.parallel().tween_property(icon_sprite, "position:y", original_icon_position.y + 0.5, 0.2)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUART)
	tween_icon.parallel().tween_property(icon_sprite, "modulate:a", 0.0, 0.2)
	
	tween_icon.tween_callback(func(): 
		icon_sprite.visible = false
		# Возвращаем в исходную позицию для следующего появления
		icon_sprite.position.y = original_icon_position.y
	)

func _hide_icon_sprite_with_lift_then_show_info() -> void:
	if not icon_sprite:
		_show_info_label()
		return
	
	if tween_icon:
		tween_icon.kill()
	tween_icon = create_tween()
	
	# Параллельные анимации: поднятие вверх И исчезновение
	tween_icon.parallel().tween_property(icon_sprite, "position:y", original_icon_position.y + 0.5, 0.2)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUART)
	tween_icon.parallel().tween_property(icon_sprite, "modulate:a", 0.0, 0.2)
	
	tween_icon.tween_callback(func(): 
		icon_sprite.visible = false
		# Возвращаем в исходную позицию для следующего появления
		icon_sprite.position.y = original_icon_position.y
		# ТОЛЬКО ТЕПЕРЬ показываем инфо-лейбл
		_show_info_label()
	)

func _show_info_label() -> void:
	if not info_label:
		return
	
	info_label.text = _get_interaction_text()
	info_label.visible = true
	
	if tween_info:
		tween_info.kill()
	tween_info = create_tween()
	tween_info.tween_property(info_label, "modulate:a", 1.0, fade_duration)

func _hide_info_label() -> void:
	if not info_label:
		return
	
	if tween_info:
		tween_info.kill()
	tween_info = create_tween()
	tween_info.tween_property(info_label, "modulate:a", 0.0, fade_duration)
	tween_info.tween_callback(func(): info_label.visible = false)

func _get_interaction_text() -> String:
	# Кэшируем текст чтобы не пересоздавать каждый раз
	if _text_cache_dirty:
		var action_text: String
		
		match interaction_type:
			InteractionType.PUSHABLE:
				action_text = "[E] Толкнуть"
			InteractionType.PICKUP:
				action_text = "[E] Подобрать " + _get_pickup_subtype_text()
			InteractionType.BUTTON:
				action_text = "[E] Нажать"
			InteractionType.DOOR:
				action_text = "[E] Открыть"
			_:
				action_text = "[E] Взаимодействовать"
		
		_cached_interaction_text = action_text + "\n" + item_name + "\n" + description
		_text_cache_dirty = false
	
	return _cached_interaction_text

func _get_pickup_subtype_text() -> String:
	match pickup_subtype:
		PickupSubtype.WEAPON:
			return "(Оружие)"
		PickupSubtype.FOOD:
			return "(Еда)"
		PickupSubtype.WATER:
			return "(Вода)"
		PickupSubtype.CLOTHING:
			return "(Одежда)"
		PickupSubtype.TOOLS:
			return "(Инструменты)"
		PickupSubtype.SPECIAL:
			return "(Особый предмет)"
		PickupSubtype.JUNK:
			return "(Хлам)"
		_:
			return ""
			
func _show_highlight_circle() -> void:
	if not highlight_circle: 
		return
	
	# Сначала делаем видимым с нулевым scale
	highlight_circle.scale = Vector3.ZERO
	
	if tween_circle:
		tween_circle.kill()
	tween_circle = create_tween()
	
	# Параллельные анимации: альфа И scale
	tween_circle.parallel().tween_method(
		_set_circle_alpha,
		0.0, highlight_color.a, circle_animation_duration
	)
	tween_circle.parallel().tween_property(highlight_circle, "scale", Vector3.ONE, circle_animation_duration)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

func _hide_highlight_circle() -> void:
	if not highlight_circle: 
		return
	
	if tween_circle:
		tween_circle.kill()
	tween_circle = create_tween()
	
	# Параллельные анимации: альфа И scale
	var current_alpha = 0.0
	var mat: StandardMaterial3D = highlight_circle.get_meta("mat")
	if mat:
		current_alpha = mat.albedo_color.a
	
	tween_circle.parallel().tween_method(
		_set_circle_alpha,
		current_alpha, 0.0, circle_animation_duration
	)
	tween_circle.parallel().tween_property(highlight_circle, "scale", Vector3.ZERO, circle_animation_duration)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)

# Вынесли в отдельный метод для чистоты
func _set_circle_alpha(value: float) -> void:
	var mat: StandardMaterial3D = highlight_circle.get_meta("mat")
	if mat:
		var c = highlight_color
		c.a = value
		mat.albedo_color = c

func _fade_circle_alpha(to_alpha: float) -> void:
	if not highlight_circle: 
		return
	var mat: StandardMaterial3D = highlight_circle.get_meta("mat")
	if not mat: 
		return
	
	if tween_circle:
		tween_circle.kill()
	tween_circle = create_tween()
	tween_circle.tween_method(
		_set_circle_alpha,
		mat.albedo_color.a, to_alpha, 0.3
	)

func is_player_in_area() -> bool:
	return player_in_area

func can_interact() -> bool:
	return player_in_area and shape_cast_detected

func interact() -> void:
	if can_interact():
		print("Взаимодействие с: ", item_name)
		_stop_shake_cycle()  # Останавливаем тряску при взаимодействии
		_on_interaction_performed()

func _on_interaction_performed() -> void:
	pass

# === СИСТЕМА ТРЯСКИ СПРАЙТА ===
func _start_shake_cycle() -> void:
	if shake_timer and player_in_area and not shape_cast_detected:
		shake_timer.start()

func _stop_shake_cycle() -> void:
	if shake_timer:
		shake_timer.stop()
	_stop_shake()

func _start_shake() -> void:
	# Проверяем что игрок все еще в области и нет взаимодействия
	if not player_in_area or shape_cast_detected:
		return
	
	if not icon_sprite or not icon_sprite.visible:
		_restart_shake_cycle()
		return
	
	is_shaking = true
	
	# Создаем тряску на 2 секунды
	if tween_icon:
		tween_icon.kill()
	tween_icon = create_tween()
	tween_icon.set_loops()  # Бесконечный цикл
	
	# Тряска вверх-вниз
	tween_icon.tween_property(icon_sprite, "position:y", original_icon_position.y + SHAKE_STRENGTH, 0.1)
	tween_icon.tween_property(icon_sprite, "position:y", original_icon_position.y - SHAKE_STRENGTH, 0.1)
	tween_icon.tween_property(icon_sprite, "position:y", original_icon_position.y, 0.1)
	
	# Останавливаем тряску через 2 секунды
	await get_tree().create_timer(SHAKE_TIME).timeout
	_stop_shake()
	_restart_shake_cycle()

func _stop_shake() -> void:
	if not is_shaking:
		return
		
	is_shaking = false
	
	if tween_icon:
		tween_icon.kill()
	
	# Возвращаем спрайт в исходную позицию
	if icon_sprite:
		icon_sprite.position = original_icon_position

func _restart_shake_cycle() -> void:
	# Перезапускаем цикл если игрок все еще в области
	if player_in_area and not shape_cast_detected:
		_start_shake_cycle()

# Методы для обновления кэша при изменении параметров
func set_item_name(new_name: String) -> void:
	item_name = new_name
	_text_cache_dirty = true

func set_description(new_description: String) -> void:
	description = new_description
	_text_cache_dirty = true

func set_interaction_type(new_type: InteractionType) -> void:
	interaction_type = new_type
	_text_cache_dirty = true

func _load_interactable_scene() -> void:
	if interactable_scene:
		loaded_interactable_node = interactable_scene.instantiate()
		add_child(loaded_interactable_node)
		
		# Получаем данные от загруженного объекта
		if loaded_interactable_node.has_method("get_interaction_data"):
			var data = loaded_interactable_node.get_interaction_data()
			item_name = data.get("name", item_name)
			description = data.get("description", description)
			highlight_color = data.get("highlight_color", highlight_color)
			circle_radius = data.get("circle_radius", circle_radius)
			_text_cache_dirty = true
		
		if not interactive_mesh:
			interactive_mesh = _find_main_mesh_recursive(loaded_interactable_node)
	
	# Если нет загружаемой сцены, то просто используем уже назначенный interactive_mesh
	# (он должен быть установлен в редакторе)
		
func set_pickup_subtype(new_subtype: PickupSubtype) -> void:
	pickup_subtype = new_subtype
	_text_cache_dirty = true

# Утилитарные методы для получения информации о загруженном объекте
func get_loaded_interactable() -> Node3D:
	return loaded_interactable_node

func has_loaded_scene() -> bool:
	return loaded_interactable_node != null

func _find_main_mesh_recursive(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	
	for child in node.get_children():
		var result = _find_main_mesh_recursive(child)
		if result:
			return result
	
	return null

func _setup_ground_detection() -> void:
	if not auto_detect_ground:
		return
		
	ground_raycast = RayCast3D.new()
	add_child(ground_raycast)
	ground_raycast.target_position = Vector3(0, -ground_check_distance, 0)
	ground_raycast.enabled = true
	
	# Проверяем после загрузки сцены
	call_deferred("_check_ground")

func _check_ground() -> void:
	if not ground_raycast:
		return
		
	ground_raycast.force_raycast_update()
	object_on_ground = ground_raycast.is_colliding()
