extends Node3D
# 🌍 WorldStreamManager
# 📦🔄 Этот менеджер-нода отвечает за подгрузку и выгрузку локаций-сцен и чанков игрового мира.
# 📦🔄 This manager node is responsible for loading and unloading location scenes and world chunks.

@onready var player = $"../Player"
@onready var debug_label_loc: RichTextLabel = $"../Perfomance&Debugging/debug_label_loc_pos_player"
@onready var debug_label_loc_info: RichTextLabel = $"../Perfomance&Debugging/debug_label_loc_info"
@onready var debug_label_chunk_info: RichTextLabel = $"../Perfomance&Debugging/debug_label_chunk_info"

@export_group("debug")
@export var debug_info: bool = true
@export var recalculate_locations: bool = false  # true = пересчитать, false = загрузить из JSON

@onready var debug_node = $"../Perfomance&Debugging"

# --- Ссылки на ноды локаций ---
@onready var Node_Silvan_Heights: Node3D = $"Silvan Heights"
@onready var Node_Palawan_Cove: Node3D = $"Palawan Cove"
@onready var Node_Fort_Meridian: Node3D = $"Fort Meridian"
@onready var Node_Verdant_Ruins: Node3D = $"Verdant Ruins"
@onready var Node_Harborlight_District: Node3D = $"Harborlight District"

# --- Ссылки на зоны Area3D ---
@onready var loc_Silvan_Heights: Area3D = $"Silvan Heights/Loc_SilvanHeights"
@onready var loc_Palawan_Cove: Area3D = $"Palawan Cove/Loc_PalawanCove"
@onready var loc_Fort_Meridian: Area3D = $"Fort Meridian/Loc_FortMeridian"
@onready var loc_Verdant_Ruins: Area3D = $"Verdant Ruins/Loc_VerdantRuins"
@onready var loc_Harborlight_District: Area3D = $"Harborlight District/Loc_HarborlightDistrict"

# --- Ссылки на чанки Area3D ---
@onready var chunk_EastPointRedoubt: Area3D = $"Fort Meridian/FM_Сhunks/Сhunk_EastPointRedoubt"
@onready var chunk_AlataBattery: Area3D = $"Fort Meridian/FM_Сhunks/Сhunk_AlataBattery"
@onready var chunk_GuardsBeach: Area3D = $"Fort Meridian/FM_Сhunks/Сhunk_GuardsBeach"
@onready var chunk_GatewayCove: Area3D = $"Fort Meridian/FM_Сhunks/Сhunk_GatewayCove"
@onready var chunk_EchoGlade: Area3D = $"Fort Meridian/FM_Сhunks/Сhunk_EchoGlade"
@onready var chunk_TheWaitingHill: Area3D = $"Fort Meridian/FM_Сhunks/Сhunk_TheWaitingHill"
@onready var chunk_ThePatrolTrail: Area3D = $"Fort Meridian/FM_Сhunks/Сhunk_ThePatrolTrail"
@onready var chunk_RadioShadow: Area3D = $"Fort Meridian/FM_Сhunks/Сhunk_RadioShadow"
@onready var chunk_ThePitDescent: Area3D = $"Fort Meridian/FM_Сhunks/Сhunk_ThePitDescent"

var debug_lines := []
var debug_lines_chunks := []
var locations_data := {}  # Словарь для хранения информации о локациях
var active_locations := []  # Массив активных локаций где находится игрок
var active_chunks := []  # Массив активных чанков где находится игрок

var chunk_scene_paths = {
"East Point Redoubt": "res://scenes/game/Сhunks/chunk_east_point_redoubt.tscn",
"Alata Battery": "res://scenes/game/Сhunks/chunk_alata_battery.tscn",
"Guards Beach": "res://scenes/game/Сhunks/chunk_guards_beach.tscn",
"Gateway Cove": "res://scenes/game/Сhunks/chunk_gateway_cove.tscn",
"Echo Glade": "res://scenes/game/Сhunks/chunk_echo_glade.tscn",
"The Waiting Hill": "res://scenes/game/Сhunks/chunk_the_waiting_hill.tscn",
"The Patrol Trail": "res://scenes/game/Сhunks/chunk_the_patrol_trail.tscn",
"Radio Shadow": "res://scenes/game/Сhunks/chunk_radio_shadow.tscn",
"The Pit Descent": "res://scenes/game/Сhunks/chunk_the_pit_descent.tscn",
}

var loaded_chunk_nodes := {} # Словарь для хранения загруженных нод: {"Chunk Name": Node3D instance}

func _ready() -> void:
	_update_debugging_node(debug_info)
	
	if recalculate_locations:
		collect_and_save_location_data()
	else:
		load_location_data_from_json()

func _update_debugging_node(_enabled: bool) -> void:
	debug_node.visible = _enabled
	debug_node.set_process(_enabled)
	debug_node.set_physics_process(_enabled)
	debug_node.set_process_input(_enabled)
	debug_node.propagate_call("set_process", [_enabled])
	debug_node.propagate_call("set_physics_process", [_enabled])
	debug_node.propagate_call("set_process_input", [_enabled])
	
	for child in get_children():
		var label_path = "lbl_" + child.name.replace(" ", "_")
		if child.has_node(label_path):
			child.get_node(label_path).visible = _enabled

# --- Загрузка данных из JSON ---
func load_location_data_from_json() -> void:
	var file = FileAccess.open("res://locations_data.json", FileAccess.READ)
	if file:
		var json_string = file.get_as_text()
		var json = JSON.new()
		var parse_result = json.parse(json_string)
		if parse_result == OK:
			locations_data = json.data
			if debug_info:
				print("Location data loaded from locations_data.json")
		else:
			print("Error parsing JSON file")
	else:
		print("Warning: locations_data.json not found, recalculating...")
		collect_and_save_location_data()

# --- Сбор и сохранение данных о локациях ---
func collect_and_save_location_data() -> void:
	var areas = {
		"Silvan Heights": loc_Silvan_Heights,
		"Palawan Cove": loc_Palawan_Cove,
		"Fort Meridian": loc_Fort_Meridian,
		"Verdant Ruins": loc_Verdant_Ruins,
		"Harborlight District": loc_Harborlight_District
	}
	
	for loc_name in areas:
		var area: Area3D = areas[loc_name]
		if not is_instance_valid(area):
			print("Error: Area3D for '", loc_name, "' is not valid.")
			continue
		
		var collision_polygon = find_collision_polygon(area)
		if not collision_polygon:
			print("Warning: No CollisionPolygon3D found for '", loc_name, "'")
			continue
		
		var aabb = calculate_aabb_from_polygon(collision_polygon)
		var size = aabb.size
		var loc_position = area.global_position 
		var area_sq_meters = size.x * size.z
		var hectares = area_sq_meters / 10000.0  # 1 гектар = 10,000 кв. метров
		
				# Получаем вершины полигона
		var polygon_vertices = collision_polygon.polygon
		var vertices_array = []
		for vertex in polygon_vertices:
			vertices_array.append({"x": vertex.x, "y": vertex.y})
		# Получаем цвет дебага из полигона (если есть debug_color)
		var debug_color = Color.WHITE
		if collision_polygon.has_meta("debug_color"):
			debug_color = collision_polygon.get_meta("debug_color")
		elif collision_polygon.get_parent() and collision_polygon.get_parent().has_meta("debug_color"):
			debug_color = collision_polygon.get_parent().get_meta("debug_color")
		
		locations_data[loc_name] = {
			"position": {
				"x": loc_position.x,
				"y": loc_position.y,
				"z": loc_position.z
			},
			"polygon_vertices": vertices_array,
			"polygon_depth": collision_polygon.depth,
			"aabb_size": {
				"x": size.x,
				"y": size.y,
				"z": size.z
			},
			"area_sq_m": area_sq_meters,
			"hectares": hectares,
			"debug_color": {
				"r": debug_color.r,
				"g": debug_color.g,
				"b": debug_color.b,
				"a": debug_color.a
			}
		}
	
	var file = FileAccess.open("res://locations_data.json", FileAccess.WRITE)
	if file:
		var json_string = JSON.stringify(locations_data, "\t")
		file.store_string(json_string)
		print("Location data saved to locations_data.json")

func calculate_aabb_from_polygon(polygon_node: CollisionPolygon3D) -> AABB:
	var vertices_2d: PackedVector2Array = polygon_node.polygon
	if vertices_2d.is_empty():
		return AABB()
	
	var min_point_2d = vertices_2d[0]
	var max_point_2d = vertices_2d[0]
	
	for i in range(1, vertices_2d.size()):
		var vertex = vertices_2d[i]
		min_point_2d.x = min(min_point_2d.x, vertex.x)
		min_point_2d.y = min(min_point_2d.y, vertex.y)
		max_point_2d.x = max(max_point_2d.x, vertex.x)
		max_point_2d.y = max(max_point_2d.y, vertex.y)
	
	var depth = polygon_node.depth
	var half_depth = depth / 2.0
	
	# Создаем 3D-точки для AABB
	var min_point_3d = Vector3(min_point_2d.x, min_point_2d.y, -half_depth)
	var max_point_3d = Vector3(max_point_2d.x, max_point_2d.y, half_depth)
	
	# Создаем и возвращаем AABB из найденных крайних точек
	return AABB(min_point_3d, max_point_3d - min_point_3d)

# Вспомогательная функция для поиска CollisionPolygon3D
func find_collision_polygon(node: Node) -> CollisionPolygon3D:
	for child in node.get_children():
		if child is CollisionPolygon3D:
			return child
	return null

func add_debug_line(new_line: String) -> void:
	debug_lines.append(new_line)
	if debug_lines.size() > 2:
		debug_lines.remove_at(0)
	debug_label_loc.text = "\n".join(debug_lines)
	
func add_debug_line_chunks(new_line: String) -> void:
	debug_lines_chunks.append(new_line)
	if debug_lines_chunks.size() > 2:
		debug_lines_chunks.remove_at(0)
	debug_label_chunk_info.text = "\n".join(debug_lines_chunks)

func update_location_info_panel(location_name: String) -> void:
	if not locations_data.has(location_name):
		debug_label_loc_info.text = "[color=yellow]Информация о локации не найдена.[/color]"
		return
	
	var data = locations_data[location_name]
	var pos = data.position
	var size = data.aabb_size
	
	# Округление до 1 знака после запятой
	var line1 = "[color=yellow]Позиция: (%.1f, %.1f, %.1f), Размер: (%.1f, %.1f, %.1f)[/color]" % [pos.x, pos.y, pos.z, size.x, size.y, size.z]
	var line2 = "[color=yellow]Площадь: %.1f м², %.1f га[/color]" % [data.area_sq_m, data.hectares]
	
	debug_label_loc_info.text = line1 + "\n" + line2

func clear_location_info_panel() -> void:
	debug_label_loc_info.text = ""

func load_chunk(chunk_name: String) -> void:
	# Проверяем, есть ли путь к сцене
	if not chunk_scene_paths.has(chunk_name):
		print("Error: Scene path not defined for chunk: " + chunk_name)
		return
	
	# Уже загружено?
	if loaded_chunk_nodes.has(chunk_name):
		print("Chunk already loaded: " + chunk_name)
		return
	
	var path = chunk_scene_paths[chunk_name]
	
	# Запускаем потоковую загрузку
	var error = ResourceLoader.load_threaded_request(path, "PackedScene", true)
	
	if error != OK:
		print("Error initializing threaded load for chunk: " + chunk_name + ". Error code: " + str(error))
		return
	
	# Ждём завершения загрузки (можно вызывать в _process для неблокирующей загрузки)
	_poll_chunk_loading(chunk_name, path)
	
func _poll_chunk_loading(chunk_name: String, path: String) -> void:
	var status = ResourceLoader.load_threaded_get_status(path)
	
	match status:
		ResourceLoader.THREAD_LOAD_LOADED:
			# Загрузка завершена успешно
			var scene_resource = ResourceLoader.load_threaded_get(path)
			if scene_resource is PackedScene:
				_instantiate_chunk(chunk_name, scene_resource)
			else:
				print("Error: Loaded resource is not a PackedScene for chunk: " + chunk_name)
		
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			# Продолжаем ожидание в следующем кадре
			await get_tree().process_frame
			_poll_chunk_loading(chunk_name, path)
		
		ResourceLoader.THREAD_LOAD_FAILED:
			print("Error: Failed to load chunk scene: " + chunk_name)
		
		ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			print("Error: Invalid resource for chunk: " + chunk_name)

func _instantiate_chunk(chunk_name: String, scene: PackedScene) -> void:
	var chunk_instance = scene.instantiate()
	
	# ВАЖНО: Определяем родительскую ноду для чанка
	# Получаем соответствующую Area3D чанка для определения позиции
	var chunk_area: Area3D = null
	match chunk_name:
		"East Point Redoubt":
			chunk_area = chunk_EastPointRedoubt
		"Alata Battery":
			chunk_area = chunk_AlataBattery
		"Guards Beach":
			chunk_area = chunk_GuardsBeach
		"Gateway Cove":
			chunk_area = chunk_GatewayCove
		"Echo Glade":
			chunk_area = chunk_EchoGlade
		"The Waiting Hill":
			chunk_area = chunk_TheWaitingHill
		"The Patrol Trail":
			chunk_area = chunk_ThePatrolTrail
		"Radio Shadow":
			chunk_area = chunk_RadioShadow
		"The Pit Descent":
			chunk_area = chunk_ThePitDescent
	
	if chunk_area:
		# Добавляем инстанс как дочернюю ноду к родителю Area3D (например, к "Fort Meridian")
		var parent_location = chunk_area.get_parent().get_parent() # FM_Chunks -> Fort Meridian
		parent_location.add_child(chunk_instance)
		
		# Позиционируем чанк в центре Area3D
		chunk_instance.global_position = chunk_area.global_position
		
		# Сохраняем ссылку
		loaded_chunk_nodes[chunk_name] = chunk_instance
		
		if debug_info:
			print("✓ Chunk loaded and instantiated: " + chunk_name + " at position: " + str(chunk_instance.global_position))
	else:
		print("Error: Could not find Area3D for chunk: " + chunk_name)
		chunk_instance.queue_free()
		
func unload_chunk(chunk_name: String) -> void:
	if not loaded_chunk_nodes.has(chunk_name):
		return # Чанк не загружен
	
	var chunk_node = loaded_chunk_nodes[chunk_name]
	
	if is_instance_valid(chunk_node):
		chunk_node.queue_free() # Безопасное удаление в конце кадра
		
	loaded_chunk_nodes.erase(chunk_name)
	
	if debug_info:
		print("✓ Chunk unloaded: " + chunk_name)

# --- Обработка сигналов входа/выхода из локаций ---
func _on_loc_fort_meridian_body_entered(body: Node3D) -> void:
	if body == player:
		active_locations.append("Fort Meridian")
		if debug_info:
			add_debug_line("[color=green]➡ Игрок в локации Форт-Меридиан[/color]")
			update_location_info_panel("Fort Meridian")

func _on_loc_fort_meridian_body_exited(body: Node3D) -> void:
	if body == player:
		active_locations.erase("Fort Meridian")
		if debug_info:
			add_debug_line("[color=red]⬅ Игрок покинул локацию Форт-Меридиан[/color]")
			if active_locations.size() > 0:
				update_location_info_panel(active_locations[-1])
			else:
				clear_location_info_panel()

func _on_loc_verdant_ruins_body_entered(body: Node3D) -> void:
	if body == player:
		active_locations.append("Verdant Ruins")
		if debug_info:
			add_debug_line("[color=green]➡ Игрок в локации Вердан-Руинс[/color]")
			update_location_info_panel("Verdant Ruins")

func _on_loc_verdant_ruins_body_exited(body: Node3D) -> void:
	if body == player:
		active_locations.erase("Verdant Ruins")
		if debug_info:
			add_debug_line("[color=red]⬅ Игрок покинул локацию Вердан-Руинс[/color]")
			if active_locations.size() > 0:
				update_location_info_panel(active_locations[-1])
			else:
				clear_location_info_panel()

func _on_loc_harborlight_district_body_entered(body: Node3D) -> void:
	if body == player:
		active_locations.append("Harborlight District")
		if debug_info:
			add_debug_line("[color=green]➡ Игрок в локации Харборлайт-Дистрикт[/color]")
			update_location_info_panel("Harborlight District")

func _on_loc_harborlight_district_body_exited(body: Node3D) -> void:
	if body == player:
		active_locations.erase("Harborlight District")
		if debug_info:
			add_debug_line("[color=red]⬅ Игрок покинул локацию Харборлайт-Дистрикт[/color]")
			if active_locations.size() > 0:
				update_location_info_panel(active_locations[-1])
			else:
				clear_location_info_panel()

func _on_loc_silvan_heights_body_entered(body: Node3D) -> void:
	if body == player:
		active_locations.append("Silvan Heights")
		if debug_info:
			add_debug_line("[color=green]➡ Игрок в локации Сильван-Хайтс[/color]")
			update_location_info_panel("Silvan Heights")

func _on_loc_silvan_heights_body_exited(body: Node3D) -> void:
	if body == player:
		active_locations.erase("Silvan Heights")
		if debug_info:
			add_debug_line("[color=red]⬅ Игрок покинул локацию Сильван-Хайтс[/color]")
			if active_locations.size() > 0:
				update_location_info_panel(active_locations[-1])
			else:
				clear_location_info_panel()

func _on_loc_palawan_cove_body_entered(body: Node3D) -> void:
	if body == player:
		active_locations.append("Palawan Cove")
		if debug_info:
			add_debug_line("[color=green]➡ Игрок в локации Палаван-Коу[/color]")
			update_location_info_panel("Palawan Cove")

func _on_loc_palawan_cove_body_exited(body: Node3D) -> void:
	if body == player:
		active_locations.erase("Palawan Cove")
		if debug_info:
			add_debug_line("[color=red]⬅ Игрок покинул локацию Палаван-Коу[/color]")
			if active_locations.size() > 0:
				update_location_info_panel(active_locations[-1])
			else:
				clear_location_info_panel()


func _on_chunk_east_point_redoubt_body_entered(body: Node3D) -> void:
	if body == player:
		active_chunks.append("East Point Redoubt")
		load_chunk("East Point Redoubt")
		if debug_info:
			add_debug_line_chunks("[color=green]➡ Игрок в чанке East Point Redoubt[/color]")


func _on_chunk_east_point_redoubt_body_exited(body: Node3D) -> void:
	if body == player:
		active_chunks.erase("East Point Redoubt")
		unload_chunk("East Point Redoubt")
		if debug_info:
			add_debug_line_chunks("[color=red]⬅ Игрок покинул локацию East Point Redoubt[/color]")


func _on_chunk_alata_battery_body_entered(body: Node3D) -> void:
	if body == player:
		active_chunks.append("Alata Battery")
		load_chunk("Alata Battery")
		if debug_info:
			add_debug_line_chunks("[color=green]➡ Игрок в чанке Alata Battery[/color]")


func _on_chunk_alata_battery_body_exited(body: Node3D) -> void:
	if body == player:
		active_chunks.erase("Alata Battery")
		unload_chunk("Alata Battery")
		if debug_info:
			add_debug_line_chunks("[color=red]⬅ Игрок покинул локацию Alata Battery[/color]")


func _on_chunk_guards_beach_body_entered(body: Node3D) -> void:
	if body == player:
		active_chunks.append("Guards Beach")
		load_chunk("Guards Beach")
		if debug_info:
			add_debug_line_chunks("[color=green]➡ Игрок в чанке Guards Beach[/color]")


func _on_chunk_guards_beach_body_exited(body: Node3D) -> void:
	if body == player:
		active_chunks.erase("Guards Beach")
		unload_chunk("Guards Beach")
		if debug_info:
			add_debug_line_chunks("[color=red]⬅ Игрок покинул локацию Guards Beach[/color]")


func _on_chunk_gateway_cove_body_entered(body: Node3D) -> void:
	if body == player:
		active_chunks.append("Gateway Cove")
		load_chunk("Gateway Cove")
		if debug_info:
			add_debug_line_chunks("[color=green]➡ Игрок в чанке Gateway Cove[/color]")


func _on_chunk_gateway_cove_body_exited(body: Node3D) -> void:
	if body == player:
		active_chunks.erase("Gateway Cove")
		unload_chunk("Gateway Cove")
		if debug_info:
			add_debug_line_chunks("[color=red]⬅ Игрок покинул локацию Gateway Cove[/color]")


func _on_chunk_echo_glade_body_entered(body: Node3D) -> void:
	if body == player:
		active_chunks.append("Echo Glade")
		load_chunk("Echo Glade")
		if debug_info:
			add_debug_line_chunks("[color=green]➡ Игрок в чанке Echo Glade[/color]")


func _on_chunk_echo_glade_body_exited(body: Node3D) -> void:
	if body == player:
		active_chunks.erase("Echo Glade")
		unload_chunk("Echo Glade")
		if debug_info:
			add_debug_line_chunks("[color=red]⬅ Игрок покинул локацию Echo Glade[/color]")

func _on_chunk_the_waiting_hill_body_entered(body: Node3D) -> void:
	if body == player:
		active_chunks.append("The Waiting Hill")
		load_chunk("The Waiting Hill")
		if debug_info:
			add_debug_line_chunks("[color=green]➡ Игрок в чанке The Waiting Hill[/color]")


func _on_chunk_the_waiting_hill_body_exited(body: Node3D) -> void:
	if body == player:
		active_chunks.erase("The Waiting Hill")
		unload_chunk("The Waiting Hill")
		if debug_info:
			add_debug_line_chunks("[color=red]⬅ Игрок покинул локацию The Waiting Hill[/color]")


func _on_chunk_the_patrol_trail_body_entered(body: Node3D) -> void:
	if body == player:
		active_chunks.append("The Patrol Trail")
		load_chunk("The Patrol Trail")
		if debug_info:
			add_debug_line_chunks("[color=green]➡ Игрок в чанке The Patrol Trail[/color]")


func _on_chunk_the_patrol_trail_body_exited(body: Node3D) -> void:
	if body == player:
		active_chunks.erase("The Patrol Trail")
		unload_chunk("The Patrol Trail")
		if debug_info:
			add_debug_line_chunks("[color=red]⬅ Игрок покинул локацию The Patrol Trail[/color]")


func _on_chunk_radio_shadow_body_entered(body: Node3D) -> void:
	if body == player:
		active_chunks.append("Radio Shadow")
		load_chunk("Radio Shadow")
		if debug_info:
			add_debug_line_chunks("[color=green]➡ Игрок в чанке Radio Shadow[/color]")


func _on_chunk_radio_shadow_body_exited(body: Node3D) -> void:
	if body == player:
		active_chunks.erase("Radio Shadow")
		unload_chunk("Radio Shadow")
		if debug_info:
			add_debug_line_chunks("[color=red]⬅ Игрок покинул локацию Radio Shadow[/color]")


func _on_chunk_the_pit_descent_body_entered(body: Node3D) -> void:
	if body == player:
		active_chunks.append("The Pit Descent")
		load_chunk("The Pit Descent")
		if debug_info:
			add_debug_line_chunks("[color=green]➡ Игрок в чанке The Pit Descent[/color]")


func _on_chunk_the_pit_descent_body_exited(body: Node3D) -> void:
	if body == player:
		active_chunks.erase("The Pit Descent")
		unload_chunk("The Pit Descent")
		if debug_info:
			add_debug_line_chunks("[color=red]⬅ Игрок покинул локацию The Pit Descent[/color]")
