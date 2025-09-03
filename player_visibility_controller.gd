# ✅ Script: PlayerVisibilityController.gd
# (Eng) Player outline system when occluded behind walls, raycast bullshit and shader magic clusterfuck
# (Rus) Система контура игрока когда он скрыт за стенами, raycast херня и магический пиздец шейдеров
# 🔧 WIP ⚡ Prototype 🐛 Not Optimized — raw, unfinished crap, demo mechanics, eats resources / сырая, незавершённая хуйня, демо-механика, жрёт ресурсы

extends Node3D

# (Eng) Node references - hardcoded dependencies because proper architecture is too advanced
# (Rus) Ссылки на узлы - хардкод зависимостей потому что нормальная архитектура слишком продвинута
@export var player_body: CharacterBody3D
@export var camera_node: Camera3D
@export var player_mesh_override: MeshInstance3D  # Прямое назначение меша игрока
@export var head: MeshInstance3D 
@export var additional_groups: Array[String] = ["Weapons", "Backpacks"]  # Группы для поиска мешей

# (Eng) Outline visual settings - because glowing players are apparently essential for gameplay
# (Rus) Настройки визуала контура - потому что светящиеся игроки видимо критически важны для геймплея
@export var outline_color: Color = Color.CYAN
@export var outline_width: float = 0.02
@export var outline_alpha: float = 0.7

# (Eng) Occlusion detection settings - raycast frequency nightmare because performance is overrated
# (Rus) Настройки обнаружения окклюзии - кошмар частоты raycast потому что производительность переоценена
@export var raycast_frequency: float = 0.05  # Более частые проверки (было 0.1)
@export var wall_collision_layer: int = 1   # Слой стен (2^0 = 1)
@export var use_multiple_rays: bool = true  # Несколько лучей для точности

# (Eng) Internal state hell - arrays and variables because proper data structures are too complex
# (Rus) Ад внутреннего состояния - массивы и переменные потому что нормальные структуры данных слишком сложны
var outline_mesh_instances: Array[MeshInstance3D] = []  # Массив outline мешей
var outline_material: ShaderMaterial
var raycast_timer: float = 0.0
var is_player_occluded: bool = false
var player_mesh_instances: Array[MeshInstance3D] = []  # Массив всех мешей игрока

# (Eng) "Performance optimization" - position caching that still gets recalculated constantly
# (Rus) "Оптимизация производительности" - кеширование позиций которые всё равно постоянно пересчитываются
var last_camera_position: Vector3
var last_player_position: Vector3
var position_change_threshold: float = 0.5

func _ready():
	# (Eng) Node hunting expedition - search entire scene tree because proper references are too hard
	# (Rus) Экспедиция поиска узлов - обыскиваем всё дерево сцены потому что нормальные ссылки слишком сложны
	if not player_body:
		player_body = get_tree().get_first_node_in_group("player")
	
	if not camera_node:
		camera_node = get_tree().get_first_node_in_group("game_camera_group")
	
	# (Eng) Panic mode validation - disable everything if we can't find basic components
	# (Rus) Валидация в панике - отключаем всё если не можем найти базовые компоненты
	if not player_body:
		printerr("PlayerVisibilityController: Player not found!")
		set_process(false)
		return
	
	if not camera_node:
		printerr("PlayerVisibilityController: Camera not found!")
		set_process(false)
		return
	
	# (Eng) Initialization clusterfuck - find meshes and create outline bullshit
	# (Rus) Пиздец инициализации - находим меши и создаём контурную херню
	find_player_mesh()
	create_outline_mesh()
	
	print("PlayerVisibilityController: Initialized successfully")

func find_player_mesh():
	# (Eng) Mesh hunting nightmare - try to find all visual parts of player because automatic detection is broken
	# (Rus) Кошмар поиска мешей - пытаемся найти все визуальные части игрока потому что автоматическое обнаружение сломано
	player_mesh_instances.clear()
	
	# (Eng) Manual mesh assignment - hardcode references because dynamic discovery is too unreliable
	# (Rus) Ручное назначение мешей - хардкод ссылок потому что динамическое обнаружение слишком ненадёжно
	if player_mesh_override:
		player_mesh_instances.append(player_mesh_override)
		print("PlayerVisibilityController: Using manually assigned body mesh: %s" % player_mesh_override.name)
	
	if head:
		player_mesh_instances.append(head)
		print("PlayerVisibilityController: Using manually assigned head mesh: %s" % head.name)
	
	if player_mesh_override or head:
		print("PlayerVisibilityController: Using manually assigned meshes (%d total)" % player_mesh_instances.size())
	
	# (Eng) Group-based mesh discovery - scan additional groups because finding meshes is apparently rocket science
	# (Rus) Обнаружение мешей по группам - сканируем дополнительные группы потому что поиск мешей видимо ракетостроение
	for group_name in additional_groups:
		find_meshes_in_group(group_name)

func create_outline_mesh():
	# (Eng) Outline mesh creation hell - duplicate every mesh for glow effect because efficient rendering is dead
	# (Rus) Ад создания контурных мешей - дублируем каждый меш для эффекта свечения потому что эффективный рендеринг мёртв
	if player_mesh_instances.is_empty():
		return
	
	clear_outline_meshes()
	create_outline_material()
	
	# (Eng) Mesh duplication nightmare - create outline copy for every single mesh because vertex shaders are too advanced
	# (Rus) Кошмар дублирования мешей - создаём контурную копию каждого меша потому что вершинные шейдеры слишком продвинуты
	for i in range(player_mesh_instances.size()):
		var original_mesh = player_mesh_instances[i]
		var outline_mesh = MeshInstance3D.new()
		outline_mesh.name = "PlayerOutline_%d_%s" % [i, original_mesh.name]
		outline_mesh.mesh = original_mesh.mesh
		outline_mesh.material_override = outline_material
		outline_mesh.layers = 2
		outline_mesh.visible = false
		
		# (Eng) Parent hierarchy clusterfuck - add outline to same parent because proper scene management is too hard
		# (Rus) Пиздец родительской иерархии - добавляем контур к тому же родителю потому что нормальное управление сценой слишком сложно
		var original_parent = original_mesh.get_parent()
		if is_instance_valid(original_parent):
			original_parent.call_deferred("add_child", outline_mesh)
			outline_mesh.transform = original_mesh.transform
		else:
			# (Eng) Fallback hell - add to player when proper parent is missing
			# (Rus) Запасной ад - добавляем к игроку когда нормального родителя нет
			player_body.call_deferred("add_child", outline_mesh)
			outline_mesh.global_transform = original_mesh.global_transform
		
		outline_mesh_instances.append(outline_mesh)
		print("PlayerVisibilityController: Created outline for: %s (parent: %s)" % [original_mesh.name, original_parent.name if original_parent else "player_body"])
	
	print("PlayerVisibilityController: Created %d outline meshes" % outline_mesh_instances.size())

func clear_outline_meshes():
	# (Eng) Cleanup hell - manually delete all outline meshes because proper resource management is too advanced
	# (Rus) Ад очистки - вручную удаляем все контурные меши потому что нормальное управление ресурсами слишком продвинуто
	for outline_mesh in outline_mesh_instances:
		if is_instance_valid(outline_mesh):
			outline_mesh.queue_free()
	outline_mesh_instances.clear()

func create_outline_material():
	# (Eng) Shader material creation - hardcode outline shader because proper material system is too complex
	# (Rus) Создание шейдерного материала - хардкод контурного шейдера потому что нормальная система материалов слишком сложна
	outline_material = ShaderMaterial.new()
	
	# (Eng) Inline shader hell - embed shader code in script because external files are apparently forbidden
	# (Rus) Ад встроенного шейдера - встраиваем код шейдера в скрипт потому что внешние файлы видимо запрещены
	var outline_shader = Shader.new()
	outline_shader.code = get_outline_shader_code()
	outline_material.shader = outline_shader
	
	# (Eng) Parameter setting spam - set every shader parameter manually because automation is dead
	# (Rus) Спам установки параметров - устанавливаем каждый параметр шейдера вручную потому что автоматизация мертва
	outline_material.set_shader_parameter("outline_color", outline_color)
	outline_material.set_shader_parameter("outline_width", outline_width)
	outline_material.set_shader_parameter("outline_alpha", outline_alpha)

func get_outline_shader_code() -> String:
	# (Eng) Inline shader code - embed GLSL in GDScript because proper asset management is too advanced
	# (Rus) Встроенный код шейдера - встраиваем GLSL в GDScript потому что нормальное управление ассетами слишком продвинуто
	return """
shader_type spatial;
render_mode unshaded, depth_test_disabled, cull_front, depth_draw_opaque, alpha_to_coverage;

uniform vec4 outline_color : source_color = vec4(0.0, 1.0, 1.0, 0.7);
uniform float outline_width : hint_range(0.0, 0.1) = 0.02;
uniform float outline_alpha : hint_range(0.0, 1.0) = 0.7;

void vertex() {
	// Expand vertices along normals for outline effect
	vec4 world_normal = MODEL_MATRIX * vec4(NORMAL, 0.0);
	vec3 world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_position += normalize(world_normal.xyz) * outline_width;
	
	VERTEX = (inverse(MODEL_MATRIX) * vec4(world_position, 1.0)).xyz;
}

void fragment() {
	ALBEDO = outline_color.rgb;
	ALPHA = outline_color.a * outline_alpha;
}
"""

func _process(delta):
	# (Eng) Main processing clusterfuck - run occlusion detection every frame because performance optimization is overrated
	# (Rus) Основной пиздец обработки - запускаем обнаружение окклюзии каждый кадр потому что оптимизация производительности переоценена
	raycast_timer += delta
	
	# (Eng) Frequency-based raycast - check visibility less often but still constantly because true optimization is impossible
	# (Rus) Raycast на основе частоты - проверяем видимость реже но всё равно постоянно потому что настоящая оптимизация невозможна
	if raycast_timer >= raycast_frequency:
		raycast_timer = 0.0
		
		# (Eng) "Performance check" - additional computation to avoid computation because logic is dead
		# (Rus) "Проверка производительности" - дополнительные вычисления чтобы избежать вычислений потому что логика мертва
		if should_perform_occlusion_check():
			check_player_occlusion()
			update_last_positions()

func should_perform_occlusion_check() -> bool:
	# (Eng) "Optimization" function that does extra work to avoid work - performance logic at its finest
	# (Rus) "Оптимизационная" функция которая делает дополнительную работу чтобы избежать работы - логика производительности во всей красе
	if not camera_node or not player_body:
		return false
	
	var camera_pos = camera_node.global_position
	var player_pos = player_body.global_position
	
	# (Eng) Distance checking optimization - calculate distances to avoid calculating distances
	# (Rus) Оптимизация проверки расстояния - вычисляем расстояния чтобы избежать вычисления расстояний
	var camera_moved = camera_pos.distance_to(last_camera_position) > position_change_threshold
	var player_moved = player_pos.distance_to(last_player_position) > position_change_threshold
	
	return camera_moved or player_moved

func update_last_positions():
	# (Eng) Position caching - store positions that will be immediately overwritten next frame
	# (Rus) Кеширование позиций - сохраняем позиции которые будут немедленно перезаписаны в следующем кадре
	if camera_node:
		last_camera_position = camera_node.global_position
	if player_body:
		last_player_position = player_body.global_position

func check_player_occlusion():
	# (Eng) Occlusion detection nightmare - multiple raycasts every frame because simple visibility check is too easy
	# (Rus) Кошмар обнаружения окклюзии - множественные raycast каждый кадр потому что простая проверка видимости слишком лёгкая
	if not camera_node or not player_body:
		return
	
	var space_state = get_world_3d().direct_space_state
	var camera_pos = camera_node.global_position
	var player_pos = player_body.global_position
	
	var rays_blocked = 0
	var total_rays = 1
	
	# (Eng) Multiple raycast hell - cast several rays because one wasn't expensive enough
	# (Rus) Ад множественных raycast - кастим несколько лучей потому что одного было недостаточно дорого
	if use_multiple_rays:
		total_rays = 3
		# (Eng) Hardcoded test points - because dynamic point generation would be too flexible
		# (Rus) Хардкод тестовых точек - потому что динамическая генерация точек была бы слишком гибкой
		var test_points = [
			player_pos,  # Центр игрока
			player_pos + Vector3(0, 1.0, 0),  # Голова игрока  
			player_pos + Vector3(0, 0.5, 0)   # Торс игрока
		]
		
		# (Eng) Raycast spam loop - physics queries for every test point because performance is overrated
		# (Rus) Цикл спама raycast - физические запросы для каждой тестовой точки потому что производительность переоценена
		for point in test_points:
			var query = PhysicsRayQueryParameters3D.create(camera_pos, point)
			query.collision_mask = wall_collision_layer
			query.exclude = [player_body]
			
			var result = space_state.intersect_ray(query)
			
			if result.size() > 0:
				rays_blocked += 1
	else:
		# (Eng) Single raycast fallback - simple version for when multiple raycasts aren't expensive enough
		# (Rus) Запасной одиночный raycast - простая версия когда множественные raycast недостаточно дорогие
		var query = PhysicsRayQueryParameters3D.create(camera_pos, player_pos)
		query.collision_mask = wall_collision_layer
		query.exclude = [player_body]
		
		var result = space_state.intersect_ray(query)
		if result.size() > 0:
			rays_blocked = 1
	
	# (Eng) Occlusion threshold logic - complex math for simple boolean result
	# (Rus) Логика порога окклюзии - сложная математика для простого булевого результата
	var occlusion_threshold = total_rays if not use_multiple_rays else max(2, total_rays - 1)
	var new_occluded_state = rays_blocked >= occlusion_threshold
	
	# (Eng) State change detection - compare booleans every frame because state machines are too advanced
	# (Rus) Обнаружение изменения состояния - сравниваем булевы переменные каждый кадр потому что машины состояний слишком продвинуты
	if new_occluded_state != is_player_occluded:
		is_player_occluded = new_occluded_state
		update_outline_visibility()
		
		# (Eng) Debug spam - print every state change because proper logging is for professionals
		# (Rus) Спам отладки - печатаем каждое изменение состояния потому что нормальное логирование для профессионалов
		if is_player_occluded:
			print("PlayerVisibilityController: Player occluded (%d/%d rays blocked) - showing outline" % [rays_blocked, total_rays])
		else:
			print("PlayerVisibilityController: Player visible (%d/%d rays blocked) - hiding outline" % [rays_blocked, total_rays])

func update_outline_visibility():
	# (Eng) Visibility update hell - iterate through all outline meshes every state change because batch operations are forbidden
	# (Rus) Ад обновления видимости - итерируемся по всем контурным мешам при каждом изменении состояния потому что пакетные операции запрещены
	for outline_mesh in outline_mesh_instances:
		if is_instance_valid(outline_mesh):
			outline_mesh.visible = is_player_occluded

# (Eng) Public API functions - wrapper methods because direct property access would be chaos
# (Rus) Функции публичного API - методы-обёртки потому что прямой доступ к свойствам был бы хаосом
func set_outline_color(color: Color):
	# (Eng) Color setter with shader parameter update - because property binding is too advanced
	# (Rus) Установщик цвета с обновлением параметра шейдера - потому что привязка свойств слишком продвинута
	outline_color = color
	if outline_material:
		outline_material.set_shader_parameter("outline_color", color)

func set_outline_width(width: float):
	# (Eng) Width setter with manual shader sync - because automatic synchronization is impossible
	# (Rus) Установщик ширины с ручной синхронизацией шейдера - потому что автоматическая синхронизация невозможна
	outline_width = width
	if outline_material:
		outline_material.set_shader_parameter("outline_width", width)

func set_outline_alpha(alpha: float):
	# (Eng) Alpha setter with parameter propagation - another wrapper for simple property assignment
	# (Rus) Установщик альфы с распространением параметра - ещё одна обёртка для простого присваивания свойства
	outline_alpha = alpha
	if outline_material:
		outline_material.set_shader_parameter("outline_alpha", alpha)

func force_outline_visibility(visible: bool):
	# (Eng) Force visibility override - manually control all outlines because automatic management is broken
	# (Rus) Принудительное переопределение видимости - вручную контролируем все контуры потому что автоматическое управление сломано
	for outline_mesh in outline_mesh_instances:
		if is_instance_valid(outline_mesh):
			outline_mesh.visible = visible

func refresh_player_mesh():
	# (Eng) Mesh refresh hell - recreate everything because incremental updates are too complex
	# (Rus) Ад обновления мешей - пересоздаём всё потому что инкрементальные обновления слишком сложны
	find_player_mesh()
	create_outline_mesh()
	print("PlayerVisibilityController: Refreshed %d player meshes" % player_mesh_instances.size())

func get_player_mesh_count() -> int:
	# (Eng) Mesh count getter - wrapper function for array size because direct access is forbidden
	# (Rus) Получатель количества мешей - функция-обёртка для размера массива потому что прямой доступ запрещён
	return player_mesh_instances.size()

func get_outline_mesh_count() -> int:
	# (Eng) Outline count getter - another size wrapper because consistency demands redundancy
	# (Rus) Получатель количества контуров - ещё одна обёртка размера потому что последовательность требует избыточности
	return outline_mesh_instances.size()

func _exit_tree():
	# (Eng) Cleanup on exit - manual resource cleanup because automatic garbage collection is unreliable
	# (Rus) Очистка при выходе - ручная очистка ресурсов потому что автоматическая сборка мусора ненадёжна
	clear_outline_meshes()

func find_meshes_in_group(group_name: String):
	# (Eng) Group-based mesh discovery - scan scene tree by group membership because proper component system is too advanced
	# (Rus) Обнаружение мешей по группам - сканируем дерево сцены по принадлежности к группе потому что нормальная система компонентов слишком продвинута
	var nodes_in_group = get_tree().get_nodes_in_group(group_name)
	
	# (Eng) Node type checking hell - validate every node type because duck typing is dangerous
	# (Rus) Ад проверки типов узлов - валидируем каждый тип узла потому что утиная типизация опасна
	for node in nodes_in_group:
		if node is MeshInstance3D:
			var mesh = node as MeshInstance3D
			if mesh.mesh and mesh.visible:
				player_mesh_instances.append(mesh)
				print("PlayerVisibilityController: Found %s mesh: %s" % [group_name.to_upper(), mesh.name])
		else:
			# (Eng) Recursive search fallback - search children because proper node structure is apparently optional
			# (Rus) Запасной рекурсивный поиск - ищем в детях потому что нормальная структура узлов видимо опциональна
			find_meshes_in_children(node, group_name.to_upper())

func find_meshes_in_children(node: Node, group_prefix: String):
	# (Eng) Recursive child search - traverse entire subtree because proper node organization is dead
	# (Rus) Рекурсивный поиск в детях - обходим всё поддерево потому что нормальная организация узлов мертва
	for child in node.get_children():
		if child is MeshInstance3D:
			var mesh = child as MeshInstance3D
			if mesh.mesh and mesh.visible:
				player_mesh_instances.append(mesh)
				print("PlayerVisibilityController: Found %s mesh: %s" % [group_prefix, mesh.name])
		
		# (Eng) Infinite recursion risk - keep searching deeper because proper depth limiting is too safe
		# (Rus) Риск бесконечной рекурсии - продолжаем искать глубже потому что нормальное ограничение глубины слишком безопасно
		find_meshes_in_children(child, group_prefix)
