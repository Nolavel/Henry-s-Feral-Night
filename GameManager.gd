
# GameManager.gd (УПРОЩЕННЫЙ)
extends Node

@export var pause_menu_scene: PackedScene # Загружается через инспектор

var is_game_paused: bool = false:
	set(value):
		if is_game_paused == value:
			return # Состояние не изменилось, ничего не делаем
		is_game_paused = value
		
		# --- Управление паузой ---
		get_tree().paused = is_game_paused # Устанавливаем глобальное состояние паузы
		
		if is_game_paused:
			print("Игра на паузе.")
			_show_pause_menu()
		else:
			print("Игра продолжена.")
			_hide_pause_menu()

func _ready():
	# GameManager как Autoload имеет PROCESS_MODE_ALWAYS по умолчанию
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	# Загружаем сцену программно, если не загружена через инспектор
	if not pause_menu_scene:
		var scene_path = "res://pause_menu.tscn"
		print("GameManager: Попытка загрузки pause_menu из: ", scene_path)
		if ResourceLoader.exists(scene_path):
			pause_menu_scene = load(scene_path)
			if pause_menu_scene:
				print("✅ Сцена меню паузы загружена программно")
			else:
				print("❌ Ошибка загрузки сцены меню паузы")
		else:
			print("❌ Файл pause_menu.tscn не найден в res://")
			print("GameManager: Доступные .tscn файлы в res://:")
			var dir = DirAccess.open("res://")
			if dir:
				dir.list_dir_begin()
				var file_name = dir.get_next()
				while file_name != "":
					if file_name.ends_with(".tscn"):
						print("  - ", file_name)
					file_name = dir.get_next()
	else:
		print("✅ pause_menu_scene уже назначена в инспекторе")
	
	Input.set_custom_mouse_cursor(null) # Сбрасываем курсор на стандартный

# НЕ ОБРАБАТЫВАЕМ toggle_pause здесь - только SystemCamera это делает!
# func _unhandled_input(event: InputEvent): # УБРАНО

func toggle_pause():
	"""Переключает состояние паузы"""
	print("GameManager: toggle_pause() called. Current paused state: ", is_game_paused)
	
	# Если снимаем с паузы, сначала уведомляем SystemCamera
	if is_game_paused:
		var system_camera = get_tree().get_first_node_in_group("system_camera")
		if system_camera and system_camera.has_method("return_to_game"):
			print("GamweManager: Calling return_to_game() on SystemCamera")
			system_camera.return_to_game()
			# НЕ меняем is_game_paused здесь - это сделает SystemCamera
			return
	
	# Если ставим на паузу, меняем состояние сразу
	is_game_paused = not is_game_paused

func _show_pause_menu():
	# Проверяем что меню еще не показано
	if get_tree().current_scene.get_node_or_null("PauseMenu"):
		return
		
	if pause_menu_scene:
		var pause_menu_instance = pause_menu_scene.instantiate()
		get_tree().current_scene.add_child(pause_menu_instance)
		pause_menu_instance.name = "PauseMenu"
		print("✅ Pause menu показано")
	else:
		print("❌ Сцена меню паузы не загружена!")

func _hide_pause_menu():
	var pause_menu = get_tree().current_scene.get_node_or_null("PauseMenu")
	if pause_menu:
		pause_menu.queue_free()
		print("✅ Pause menu скрыто")

# Публичные методы для UI систем
func request_inventory():
	"""Запрос показа инвентаря из UI или других систем"""
	# Найти SystemCamera и вызвать transition_to_inventory()
	var system_camera = get_tree().get_first_node_in_group("system_camera")
	if system_camera and system_camera.has_method("transition_to_inventory"):
		system_camera.transition_to_inventory()

func request_health():
	"""Запрос показа health UI из Tab или других систем"""  
	# Найти SystemCamera и вызвать transition_to_health()
	var system_camera = get_tree().get_first_node_in_group("system_camera")
	if system_camera and system_camera.has_method("transition_to_health"):
		system_camera.transition_to_health()
		
func request_crafting():
	"""Запрос показа crafting UI из  или других систем"""  
	# Найти SystemCamera и выз	вать transition_to_health()
	var system_camera = get_tree().get_first_node_in_group("system_camera")
	if system_camera and system_camera.has_method("transition_to_crafting"):
		system_camera.transition_to_crafting()
		
func request_tactical_hub():
	"""Запрос показа crafting UI из tactical_hub или других систем"""  
	# Найти SystemCamera и выз	вать transition_to_health()
	var system_camera = get_tree().get_first_node_in_group("system_camera")
	if system_camera and system_camera.has_method("transition_to_tactical_hub"):
		system_camera.transition_to_tactical_hub()
