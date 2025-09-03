extends Node3D
class_name OptimizedHoverUI

@export var camera: Camera3D
@export var label: Label
@export var player_mesh: MeshInstance3D
@export var max_hover_distance: float = 5.0
@export var collision_mask: int = 0b11111111
@export var raycast_frequency: int = 10  # Увеличили частоту
@export var mouse_threshold: float = 5.0  # Увеличили порог движения мыши
@export var fade_duration: float = 0.15

# Кэшированные ссылки (КЛЮЧЕВАЯ ОПТИМИЗАЦИЯ)
var cached_viewport: Viewport = null
var cached_space_state: PhysicsDirectSpaceState3D = null
var cached_inventory_items: Array[Node] = []
var cache_update_timer: float = 0.0
const CACHE_UPDATE_INTERVAL: float = 1.0  # Обновляем кеш раз в секунду

@onready var effect_screen: TextureRect = $UI_Inventory/Background_effect
var effect_tween: Tween = null

var dragging_object: Node = null
var drag_start_transform: Transform3D
var drag_distance: float = 0.0
var drag_button: String = "shoot"

var last_item: Node = null
var system_camera: Node = null
var frame_counter: int = 0
var last_mouse_pos: Vector2 = Vector2.ZERO
var tween_pool: Array[Tween] = []  # Pool для tween'ов
var current_tween_index: int = 0

var hovered_object: Node = null
var selected_object: Node = null

# Материалы (кэшируются один раз)
var outline_hover: ShaderMaterial = null
var outline_selected: ShaderMaterial = null

# Кэш для поиска mesh родителей
var parent_mesh_cache: Dictionary = {}

# Система прозрачности
var original_positions: Dictionary = {}
var original_player_material: Material = null
var transparent_player_material: StandardMaterial3D = null

# Флаги состояния для оптимизации
var is_inventory_mode: bool = false
var was_inventory_mode: bool = false
var mouse_moved_recently: bool = false



func _ready():
	# Кэшируем viewport один раз
	cached_viewport = get_viewport()
	set_process(false)
	
	system_camera = get_tree().get_first_node_in_group("system_camera")
	if not system_camera:
		push_error("RaycastUI: не найден узел SystemCamera в группе 'system_camera'")

	# Создание outline материалов ОДИН РАЗ
	_create_outline_materials()
	
	# Инициализация tween pool
	_init_tween_pool()

	# Настройка прозрачности игрока
	_setup_player_transparency()
	
	# Кэшируем inventory items при старте
	_update_inventory_cache()
	_save_original_positions()
	
	_hide_label()
	
	# Кэшируем space_state один раз
	cached_space_state = get_world_3d().direct_space_state

func _create_outline_materials():
	"""Создает outline материалы один раз (КЭШИРОВАНИЕ)"""
	if outline_hover != null:  # Уже созданы
		return
		
	var shader_code = """
		shader_type spatial;
		render_mode cull_front, unshaded, depth_draw_always;

		uniform vec4 outline_color : source_color = vec4(1.0,1.0,0.0,1.0);
		uniform float outline_size : hint_range(0.01,0.3) = 0.05;
		uniform float edge_fade : hint_range(0.0,1.0) = 0.5;

		void vertex() {
			VERTEX += NORMAL * outline_size;
		}

		void fragment() {
			float intensity = clamp(dot(NORMAL, vec3(0,0,1)), 0.0, 1.0);
			float alpha = outline_color.a * pow(intensity, 1.0/edge_fade);
			ALBEDO = outline_color.rgb;
			ALPHA = alpha;
		}
	"""
	var shader = Shader.new()
	shader.code = shader_code

	outline_hover = ShaderMaterial.new()
	outline_hover.shader = shader
	outline_hover.set_shader_parameter("outline_color", Color(1,1,0,1))

	outline_selected = ShaderMaterial.new()
	outline_selected.shader = shader
	outline_selected.set_shader_parameter("outline_color", Color(0,0.6,1,1))

func _init_tween_pool():
	"""Создает pool tween'ов для переиспользования"""
	for i in range(5):  # Создаем 5 tween'ов в pool
		var tween = create_tween()
		tween.kill()  # Останавливаем сразу
		tween_pool.append(tween)

func _get_pooled_tween() -> Tween:
	"""Возвращает tween из pool или создает новый"""
	for tween in tween_pool:
		if not tween.is_valid():
			return create_tween()
	
	# Если все заняты, используем round-robin
	var tween = tween_pool[current_tween_index]
	if tween.is_valid():
		tween.kill()
	current_tween_index = (current_tween_index + 1) % tween_pool.size()
	return create_tween()

func _update_inventory_cache():
	"""Обновляет кэш inventory items (ПЕРИОДИЧЕСКИ, НЕ КАЖДЫЙ КАДР)"""
	cached_inventory_items = get_tree().get_nodes_in_group("inventory_items")
	print("OptimizedHoverUI: Кэш inventory обновлен, найдено %d объектов" % cached_inventory_items.size())

func _setup_player_transparency():
	"""Настраивает материалы для прозрачности игрока"""
	if not player_mesh:
		print("OptimizedHoverUI: player_mesh не назначен!")
		return
	original_player_material = player_mesh.get_active_material(0)
	if original_player_material:
		transparent_player_material = original_player_material.duplicate() as StandardMaterial3D
		if transparent_player_material:
			transparent_player_material.flags_transparent = true
			transparent_player_material.albedo_color.a = 0.3

func _save_original_positions():
	"""Сохраняет оригинальные позиции из кэша (НЕ из поиска)"""
	original_positions.clear()  # Очищаем старые данные
	
	for item in cached_inventory_items:
		if is_instance_valid(item) and item is Node3D:
			original_positions[item] = item.transform.origin
			print("OptimizedHoverUI: Сохранена позиция для %s: %s" % [item.name, item.transform.origin])

func _process(delta):
	# ОПТИМИЗАЦИЯ 1: Обновляем кэш периодически, не каждый кадр
	cache_update_timer += delta
	if cache_update_timer >= CACHE_UPDATE_INTERVAL:
		cache_update_timer = 0.0
		_update_inventory_cache()
		_save_original_positions()

	# ОПТИМИЗАЦИЯ 2: Ранний выход если system_camera не готов
	if not system_camera or not system_camera.has_method("get"):
		_clear_hover()
		_clear_selection()
		_hide_label()
		return

	# ОПТИМИЗАЦИЯ 3: Проверяем режим камеры только при изменении
	is_inventory_mode = (system_camera.current_state == system_camera.CameraState.INVENTORY)
	
	if not is_inventory_mode:
		_cleanup_and_exit()
		return
		if was_inventory_mode:  # Только при выходе из режима
			_clear_hover()
			_clear_selection()
			_hide_label()
		was_inventory_mode = false
		return
	was_inventory_mode = true

	# ОПТИМИЗАЦИЯ 4: Ранний выход если камера не готова
	if not camera:
		return

	frame_counter += 1
	
	# ОПТИМИЗАЦИЯ 5: Получаем mouse position реже
	var mouse_pos: Vector2
	if frame_counter % 2 == 0:  # Каждый второй кадр
		mouse_pos = cached_viewport.get_mouse_position()
		mouse_moved_recently = last_mouse_pos.distance_squared_to(mouse_pos) >= (mouse_threshold * mouse_threshold)
		last_mouse_pos = mouse_pos
	else:
		mouse_pos = last_mouse_pos

	# ОПТИМИЗАЦИЯ 6: Raycast только если мышь двигалась или через интервал
	var should_raycast = false
	if mouse_moved_recently:
		should_raycast = true
		mouse_moved_recently = false
	elif frame_counter % raycast_frequency == 0:
		should_raycast = true
	
	if should_raycast:
		_do_raycast_optimized(mouse_pos)

	# Обработка input'а
	_handle_input_optimized()

func _cleanup_and_exit():
	"""Очищает все состояния при выходе из inventory режима"""
	_clear_hover()
	_clear_selection()
	_hide_label()
	
	# Останавливаем drag если был активен
	if dragging_object:
		_force_end_drag()
	
	print("OptimizedHoverUI: Выход из inventory режима - состояние очищено")

func _force_end_drag():
	"""Принудительно завершает drag при выходе из inventory"""
	if dragging_object:
		_set_player_transparency(false)
		_set_screen_effect_end()
		dragging_object = null
		print("OptimizedHoverUI: Drag принудительно завершен")
	_clear_selection()
	_clear_hover()

func _process_inventory_mode():
	"""🎯 ВСЯ ЛОГИКА INVENTORY РЕЖИМА - raycast работает ТОЛЬКО здесь"""
	frame_counter += 1
	
	# Получаем mouse position с оптимизацией
	var mouse_pos: Vector2
	if frame_counter % 2 == 0:  # Каждый второй кадр
		mouse_pos = cached_viewport.get_mouse_position()
		mouse_moved_recently = last_mouse_pos.distance_squared_to(mouse_pos) >= (mouse_threshold * mouse_threshold)
		last_mouse_pos = mouse_pos
	else:
		mouse_pos = last_mouse_pos

	# 🔥 RAYCAST ТОЛЬКО В INVENTORY РЕЖИМЕ
	var should_raycast = false
	if mouse_moved_recently:
		should_raycast = true
		mouse_moved_recently = false
	elif frame_counter % raycast_frequency == 0:
		should_raycast = true
	
	if should_raycast:
		_do_raycast_optimized(mouse_pos)

	# Обработка input'а ТОЛЬКО в inventory режиме
	_handle_input_optimized()

func _handle_input_optimized():
	"""Оптимизированная обработка input'а"""
	# Проверяем input только когда нужно
	if Input.is_action_just_pressed("shoot"):
		if hovered_object:
			_select_object(hovered_object)
		else:
			_clear_selection()
			
	# Drag & drop с прозрачностью игрока
	if Input.is_action_just_pressed(drag_button) and hovered_object:
		_start_drag(hovered_object)
	elif Input.is_action_pressed(drag_button) and dragging_object:
		_update_drag_optimized()
	elif Input.is_action_just_released(drag_button) and dragging_object:
		_end_drag()

func _do_raycast_optimized(mouse_pos: Vector2):
	"""Оптимизированный raycast с кэшированными объектами"""
	var from = camera.project_ray_origin(mouse_pos)
	var to = from + camera.project_ray_normal(mouse_pos) * max_hover_distance
	
	# Используем кэшированный space_state
	var query = PhysicsRayQueryParameters3D.create(from, to, collision_mask)
	var result = cached_space_state.intersect_ray(query)
	_process_hit_optimized(result)

func _process_hit_optimized(result: Dictionary):
	"""Оптимизированная обработка hit'а с кэшированием"""
	if result.is_empty():
		_clear_hover()
		_hide_label()
		return

	var hit_object = result.collider
	
	# ОПТИМИЗАЦИЯ: Проверяем кэш inventory items вместо группы
	var is_inventory_item = hit_object in cached_inventory_items
	
	if is_inventory_item:
		var parent_mesh = _find_parent_mesh_cached(hit_object)
		if parent_mesh:
			_set_hover(parent_mesh)
			if last_item != parent_mesh:
				last_item = parent_mesh
				# Проверяем наличие метода один раз
				if hit_object.has_method("get_full_item_info") and label:
					label.text = hit_object.get_full_item_info()
					_show_label_optimized()
	else:
		_clear_hover()
		_hide_label()

func _find_parent_mesh_cached(node: Node) -> MeshInstance3D:
	"""Кэшированный поиск parent mesh"""
	# Проверяем кэш
	if node in parent_mesh_cache:
		var cached_result = parent_mesh_cache[node]
		if is_instance_valid(cached_result):
			return cached_result
	
	# Если не в кэше, ищем и кэшируем результат
	var current = node
	var depth = 0
	const MAX_SEARCH_DEPTH = 5  # Ограничиваем глубину поиска
	
	while current and depth < MAX_SEARCH_DEPTH:
		if current is MeshInstance3D:
			parent_mesh_cache[node] = current
			return current
		current = current.get_parent()
		depth += 1
	
	# Кэшируем null результат, чтобы не искать снова
	parent_mesh_cache[node] = null
	return null

# ===== ОПТИМИЗИРОВАННЫЕ UI функции =====
func _show_label_optimized():
	"""Оптимизированный показ label'а"""
	if not label or label.visible:
		return
	label.visible = true
	
	# Используем pooled tween
	var tween = _get_pooled_tween()
	tween.tween_property(label, "modulate:a", 1.0, fade_duration)

func _hide_label():
	"""Скрытие label'а"""
	last_item = null
	if not label or not label.visible:
		return
		
	var tween = _get_pooled_tween()
	tween.tween_property(label, "modulate:a", 0.0, fade_duration)
	tween.finished.connect(_on_fade_finished, CONNECT_ONE_SHOT)

func _on_fade_finished():
	if label:
		label.visible = false

# ===== Outline система (БЕЗ ИЗМЕНЕНИЙ) =====
func _set_hover(obj: Node):
	if hovered_object == obj: return
	_clear_hover()
	hovered_object = obj
	_apply_outline(hovered_object, outline_hover)

func _clear_hover():
	if hovered_object and hovered_object != selected_object:
		_remove_outline(hovered_object)
	hovered_object = null

func _select_object(obj: Node):
	if selected_object:
		_remove_outline(selected_object)
	selected_object = obj
	_apply_outline(selected_object, outline_selected)

func _clear_selection():
	if selected_object:
		_remove_outline(selected_object)
	selected_object = null

func _apply_outline(obj: Node, material: ShaderMaterial):
	if obj is MeshInstance3D:
		obj.material_overlay = material

func _remove_outline(obj: Node):
	if obj is MeshInstance3D:
		obj.material_overlay = null

# ===== ОПТИМИЗИРОВАННЫЙ Drag & drop =====
func _start_drag(obj: Node):
	dragging_object = obj
	drag_start_transform = obj.transform
	drag_distance = camera.global_transform.origin.distance_to(obj.global_transform.origin)
	
	_set_player_transparency(true)
	_set_screen_effect_start()
	
	print("Drag начат для: %s" % obj.name)

func _update_drag_optimized():
	"""Оптимизированное обновление drag'а с ограничением мыши"""
	if not dragging_object:
		return

	# Получаем позицию мыши
	var mouse_pos = cached_viewport.get_mouse_position()

	# Размеры Viewport
	var vp_size = cached_viewport.get_visible_rect().size
	var margin = 100  # Отступ от края

	# Ограничиваем мышь в пределах Viewport с отступом
	mouse_pos.x = clamp(mouse_pos.x, margin, vp_size.x - margin)
	mouse_pos.y = clamp(mouse_pos.y, margin, vp_size.y - margin)

	# Проецируем ray из камеры
	var from = camera.project_ray_origin(mouse_pos)
	var to = from + camera.project_ray_normal(mouse_pos) * drag_distance
	dragging_object.global_transform.origin = to


func _end_drag():
	if dragging_object:
		_set_player_transparency(false)
		_set_screen_effect_end()
		
		var drag_obj = dragging_object
		var original_pos = original_positions.get(drag_obj, drag_start_transform.origin)
		
		# Используем pooled tween для возврата
		if original_pos != drag_obj.transform.origin:
			var return_tween = _get_pooled_tween()
			return_tween.tween_method(
				func(pos: Vector3): _set_item_position_safe(drag_obj, pos),
				drag_obj.transform.origin,
				original_pos,
				0.3
			)
			return_tween.finished.connect(
				func(): print("Возврат объекта %s завершен" % drag_obj.name), 
				CONNECT_ONE_SHOT
			)
		
		dragging_object = null
		_clear_selection()
		_clear_hover()
		_force_end_drag()

func _set_item_position_safe(item: Node3D, pos: Vector3):
	"""Безопасно устанавливает позицию объекта с проверками"""
	if is_instance_valid(item):
		item.transform.origin = pos

func _set_player_transparency(transparent: bool):
	"""Управляет прозрачностью игрока"""
	if not player_mesh:
		return
	if transparent:
		player_mesh.set_surface_override_material(0, transparent_player_material)
	else:
		player_mesh.set_surface_override_material(0, original_player_material)
		
func _set_effect_progress(value: float):
	"""Устанавливает progress параметр шейдера эффекта экрана"""
	if is_instance_valid(effect_screen) and effect_screen.material:
		effect_screen.material.set_shader_parameter("progress", value)

func _set_screen_effect_start():
	"""Запускает эффект экрана при начале drag"""
	if not is_instance_valid(effect_screen):
		return
	
	if effect_tween and effect_tween.is_valid():
		effect_tween.kill()
	
	effect_tween = _get_pooled_tween()
	effect_tween.set_ease(Tween.EASE_OUT)
	effect_tween.set_trans(Tween.TRANS_QUART)
	
	var current_progress = 0.0
	if effect_screen.material:
		var shader_progress = effect_screen.material.get_shader_parameter("progress")
		if shader_progress != null:
			current_progress = shader_progress
	
	effect_tween.tween_method(
		func(value: float): _set_effect_progress(value),
		current_progress,
		0.3,
		0.4
	)

func _set_screen_effect_end():
	"""Завершает эффект экрана при окончании drag"""
	if not is_instance_valid(effect_screen):
		return
	
	if effect_tween and effect_tween.is_valid():
		effect_tween.kill()
	
	effect_tween = _get_pooled_tween()
	effect_tween.set_ease(Tween.EASE_IN)
	effect_tween.set_trans(Tween.TRANS_QUART)
	
	var current_progress = 0.3
	if effect_screen.material:
		var shader_progress = effect_screen.material.get_shader_parameter("progress")
		if shader_progress != null:
			current_progress = shader_progress
	
	effect_tween.tween_method(
		func(value: float): _set_effect_progress(value),
		current_progress,
		0.0,
		0.3
	)

# ===== Cleanup функции =====
func _exit_tree():
	"""Очистка ресурсов при выходе"""
	parent_mesh_cache.clear()
	original_positions.clear()
	
	# Очищаем tween pool
	for tween in tween_pool:
		if tween.is_valid():
			tween.kill()
	tween_pool.clear()
