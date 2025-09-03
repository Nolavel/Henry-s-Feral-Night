extends Camera3D

# --- Экспортируемые переменные ---
@export var transform_tactical_hub_mode: Transform3D = Transform3D(
	Basis().rotated(Vector3.RIGHT, deg_to_rad(-75)), # Ось Y (UP) заменена на X (RIGHT)
	Vector3(0, 8, 1)
)
@export var transform_сharacter_overview_mode: Transform3D = Transform3D(Basis(), Vector3(0, 1, 1.7))
@export var transform_inventory_mode: Transform3D = Transform3D(Basis(), Vector3(0, 1.25, 1.0))
@export var transform_menu_pause_mode: Transform3D = Transform3D(
	Basis().rotated(Vector3.RIGHT, deg_to_rad(-75)), # Ось Y (UP) заменена на X (RIGHT)
	Vector3(0, 4, 1)
)
@export var transform_health_mode: Transform3D = Transform3D(Basis().rotated(Vector3.UP, deg_to_rad(180)), Vector3(0, 1, -1.7))
@export var transform_crafting_mode: Transform3D = Transform3D(
	Basis().rotated(Vector3.RIGHT, deg_to_rad(-75)), # Ось Y (UP) заменена на X (RIGHT)
	Vector3(0, 2, -0.3)
)

@export var player_node: Node3D
@export var player_node_collision: CollisionShape3D
@export var crosshair_controller: Control = null
@export var head_controller: Node3D = null

# --- ButtonLayoutManager ---
@onready var button_layout_manager: ButtonLayoutManager = $ButtonLayoutManager
@onready var transition_effects: CameraTransitionEffects = $CameraTransitionEffects
@onready var sound_trans_effect: AudioStreamPlayer = $CameraTransitionEffects/TransitionSoundEffect
@onready var scan_line_effect: TextureRect = $UI_SwitcherCamera/Mode_TacticalHub/UI_Effects_TacticalHub/CameraStateEffect

# --- Сигналы для UI (восстановлено) ---
signal show_inventory_ui
signal hide_inventory_ui
signal show_health_ui
signal hide_health_ui
signal show_crafting_ui
signal hide_crafting_ui
signal show_tactical_hub_ui
signal hide_tactical_hub_ui

signal camera_state_changed(new_state: CameraState, visible_buttons: Array[String])
signal buttons_should_hide()
signal layout_mode_requested(mode: String, visible_buttons: Array[String])

# --- Enum и ссылки ---
enum CameraState { GAME, TACTICAL_HUB, CHARACTER_OVERVIEW, INVENTORY, MENU, HEALTH, CRAFTING }

@onready var game_camera: Camera3D = $"../../../TopDownCamera"
@onready var btn_inventory = $UI_SwitcherCamera/Btn_CameraInventory
@onready var btn_health = $UI_SwitcherCamera/Btn_CameraHealth
@onready var btn_сharacter_overview = $UI_SwitcherCamera/Btn_CameraCharacterOverview
@onready var btn_menupause = $UI_SwitcherCamera/Btn_CameraMenuPause
@onready var btn_crafting = $UI_SwitcherCamera/Btn_CameraCrafting
@onready var btn_tactical_hub = $UI_SwitcherCamera/Btn_CameraTacticalHub

@onready var ui_overlay: CanvasLayer = $"../../../UI"


@onready var inventory_mode = $UI_SwitcherCamera/Mode_Inventory


@export var Weapon_Holder: Node3D
var original_weapon_holder_transform: Transform3D
# --- Переменные для Inventory режима ---
var original_player_collision_layer: int
var is_inventory_mode_active: bool = false

@export_group("Modes")
@export var mode_tactical_hub: Node3D
@export var mode_tactical_hub_ui: CanvasLayer
@export var mode_character_overview: Node3D
@export var mode_character_overview_ui: CanvasLayer
@export var mode_inventory: Node3D  
@export var mode_inventory_ui: CanvasLayer
@export var mode_health: Node3D
@export var mode_health_ui: CanvasLayer
@export var mode_crafting: Node3D
@export var mode_crafting_ui: CanvasLayer
@export var mode_menu: Node3D
@export var mode_menu_ui: CanvasLayer

var mode_nodes: Dictionary = {}
var mode_ui_nodes: Dictionary = {}

# --- Переменные состояния ---
var current_state: CameraState = CameraState.GAME
var using_pause_camera := false

# Флаги для показа UI после анимации (восстановлено)
var show_menu_next: bool = false
var show_inventory_next: bool = false
var show_health_next: bool = false
var show_crafting_next: bool = false
var show_tactical_hub_next: bool = false

# --- Переменные анимации ---
var is_animating: bool = false
var anim_time: float = 0.0
const DURATION: float = 0.4

var start_xform: Transform3D
var target_xform: Transform3D
var saved_game_camera_local_xform: Transform3D

var blur_tween: Tween = null
@onready var env: WorldEnvironment = $"../../../WorldEnvironment"

func _ready():
	if not player_node: player_node = get_parent() as Node3D
	if not player_node:
		push_error("SystemCamera: Player node is not assigned!")
		return
	
	add_to_group("system_camera")
	
	btn_inventory.pressed.connect(_on_inventory_button_pressed)
	btn_health.pressed.connect(_on_health_button_pressed)
	btn_сharacter_overview.pressed.connect(_on_сharacter_overview_button_pressed)
	btn_menupause.pressed.connect(_on_menupause_button_pressed)
	btn_crafting.pressed.connect(_on_crafting_button_pressed)
	btn_tactical_hub.pressed.connect(_on_tactical_hub_pressed)
	
	buttons_should_hide.connect(_on_buttons_should_hide)
	
	
	setup_mode_dictionaries()
	
	# Скрываем все режимы кроме игрового
	update_mode_visibility()

	
	_update_ui_buttons()
	# Настраиваем ButtonLayoutManager
	setup_button_layout_manager()
	
	# Обновляем состояние кнопок
	update_button_layout()
	setup_transition_effects()
	setup_inventory_original_values()
	
func setup_transition_effects():
	"""Настраивает систему эффектов переходов"""
	transition_effects = CameraTransitionEffects.new()
	add_child(transition_effects)
	transition_effects.setup(self, player_node, env)

func _unhandled_input(event):
	if is_animating: return
	
	if event.is_action_pressed("Meta"):
		_handle_tactical_hub_toggle()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_pause"):
		_handle_pause_toggle()
		get_viewport().set_input_as_handled()
		
func setup_inventory_original_values():
	"""Сохраняет оригинальные значения для восстановления после Inventory режима"""
	if is_instance_valid(Weapon_Holder):
		original_weapon_holder_transform = Weapon_Holder.transform
		
	
	if is_instance_valid(player_node):
		original_player_collision_layer = player_node.collision_layer
		print("SystemCamera: Сохранен оригинальный collision_layer игрока: %d" % original_player_collision_layer)

func _process(delta):
	if not is_animating: return
	
	anim_time += delta
	var t = clamp(anim_time / DURATION, 0.0, 1.0)
	transform = start_xform.interpolate_with(target_xform, t)
	
	if t >= 1.0:
		is_animating = false
		_on_animation_completed()

# --- Логика переключений ---

func _handle_tactical_hub_toggle():
	if not using_pause_camera:
		_enter_pause_mode(CameraState.TACTICAL_HUB, transform_tactical_hub_mode)
		if transition_effects:
			sound_trans_effect.play()
			sound_trans_effect.pitch_scale = 2.2
	else:
		_return_to_game_mode()
		remove_world_blur()
		if transition_effects:
			
			sound_trans_effect.play()
			sound_trans_effect.pitch_scale = 2.0
			transition_effects.play_exit_transition()

func _handle_pause_toggle():
	if not using_pause_camera:
		_enter_pause_mode(CameraState.MENU, transform_menu_pause_mode)
		apply_world_blur()
	else:
		_return_to_game_mode()
		remove_world_blur()

# --- Высокоуровневые функции состояний ---

func _enter_pause_mode(target_state: CameraState, target_local_xform: Transform3D):
	saved_game_camera_local_xform = player_node.global_transform.affine_inverse() * game_camera.global_transform
	# БЛОКИРУЕМ UI ЭЛЕМЕНТЫ
	set_ui_game_mode(false)
	
	# БЛОКИРУЕМ ДВИЖЕНИЕ ИГРОКА
	_set_player_movement_enabled(false)
	# Устанавливаем флаг для показа UI ПОСЛЕ анимации (восстановлено)
	if target_state == CameraState.MENU:
		show_menu_next = true
	
	_start_transition(CameraState.GAME, target_state, saved_game_camera_local_xform, target_local_xform)
	
	using_pause_camera = true
	current_state = target_state
	_set_player_movement_enabled(false)
	_set_cursor_visible(true)
	_update_ui_buttons()
	update_mode_visibility()

func _return_to_game_mode():
		
	if not using_pause_camera: return
	
	# МГНОВЕННОЕ ПЕРЕКЛЮЧЕНИЕ - без анимации
	using_pause_camera = false
	current_state = CameraState.GAME
	
	# Мгновенно переключаем камеры
	game_camera.current = true
	self.current = false
	
	# РАЗБЛОКИРУЕМ UI ЭЛЕМЕНТцЫ
	set_ui_game_mode(true)
	
	# РАЗБЛОКИРУЕМ ДВИЖЕНИЕ ИГРОКА  
	_set_player_movement_enabled(true)
	
	# Сбрасываем флаги анимации
	is_animating = false
	anim_time = 0.0
	
	# Обновляем состояние игры
	_set_player_movement_enabled(true)
	_set_cursor_visible(false)
	_hide_all_ui()
	restore_from_inventory_mode()
	_update_ui_buttons()
	remove_world_blur()
	update_mode_visibility()
	
	buttons_should_hide.emit()
	
	print("SystemCamera: Мгновенное возвращение к Game камере")

# Обновляем публичный метод для GameManager
func return_to_game():
	"""Публичный метод для GameManager - возвращает к игре"""
	_return_to_game_mode()
	
	# УБИРАЕМ задержку - переключение теперь мгновенное
	GameManager.is_game_paused = false
	remove_world_blur()
	restore_from_inventory_mode()
		
func _transition_to_state(new_state: CameraState, target_xform: Transform3D):
	if not using_pause_camera or is_animating or current_state == new_state: return
	
	_hide_all_ui()
	
	# Устанавливаем флаги для показа нужного UI (восстановлено)
	match new_state:
		CameraState.INVENTORY:
			show_inventory_next = true
		CameraState.HEALTH:
			show_health_next = true
		CameraState.MENU:
			show_menu_next = true
		CameraState.CRAFTING:
			show_crafting_next = true
		CameraState.TACTICAL_HUB:
			show_tactical_hub_next = true
	
	_start_transition(current_state, new_state, transform, target_xform)
	
	current_state = new_state
	_set_player_movement_enabled(false)
	set_ui_game_mode(false)
	_update_ui_buttons()
	update_button_layout()
	update_mode_visibility()
	
	if new_state != CameraState.TACTICAL_HUB:
		apply_world_blur()

# --- Низкоуровневые функции ---

func _start_transition(from_s: CameraState, to_s: CameraState, start_t: Transform3D, target_t: Transform3D):
	self.current = true
	game_camera.current = false
	start_xform = start_t
	target_xform = target_t
	anim_time = 0.0
	is_animating = true
	if transition_effects:
		sound_trans_effect.play()
		sound_trans_effect.pitch_scale = 1.7
		transition_effects.play_state_transition()
		

func _on_animation_completed():
	if current_state == CameraState.GAME:
		game_camera.current = true
		self.current = false
	
	# Логика показа UI после анимации (восстановлено из оригинала)
	if show_menu_next:
		show_menu_next = false
		GameManager.toggle_pause() # Показываем меню и ставим игру на паузу
	elif show_inventory_next:
		show_inventory_next = false
		emit_signal("show_inventory_ui")
	elif show_health_next:
		show_health_next = false
		emit_signal("show_health_ui")
	elif show_crafting_next:
		show_crafting_next = false
		emit_signal("show_crafting_ui")
	elif show_tactical_hub_next:
		show_tactical_hub_next = false
		emit_signal("show_tactical_hub_ui")

# --- Обработчики кнопок ---
func _on_inventory_button_pressed(): _transition_to_state(CameraState.INVENTORY, transform_inventory_mode)
func _on_health_button_pressed(): _transition_to_state(CameraState.HEALTH, transform_health_mode)
func _on_сharacter_overview_button_pressed(): _transition_to_state(CameraState.CHARACTER_OVERVIEW, transform_сharacter_overview_mode)
func _on_menupause_button_pressed(): _transition_to_state(CameraState.MENU, transform_menu_pause_mode)
func _on_crafting_button_pressed(): _transition_to_state(CameraState.CRAFTING, transform_crafting_mode)
func _on_tactical_hub_pressed(): _transition_to_state(CameraState.TACTICAL_HUB, transform_tactical_hub_mode)

# --- Управление UI и игроком ---
func _hide_all_ui():
	# Вызываем сигналы для скрытия UI (восстановлено)
	emit_signal("hide_inventory_ui")
	emit_signal("hide_health_ui")
	emit_signal("hide_crafting_ui")
	emit_signal("hide_tactical_hub_ui")

func _update_ui_buttons():
	var show = using_pause_camera
	btn_inventory.visible = show and (current_state == CameraState.CHARACTER_OVERVIEW or current_state == CameraState.HEALTH or current_state == CameraState.CRAFTING or current_state == CameraState.TACTICAL_HUB)
	btn_health.visible = show and (current_state == CameraState.CHARACTER_OVERVIEW or current_state == CameraState.INVENTORY or current_state == CameraState.CRAFTING or current_state == CameraState.TACTICAL_HUB)
	btn_menupause.visible = show and current_state == CameraState.TACTICAL_HUB
	btn_сharacter_overview.visible = show and (current_state == CameraState.INVENTORY or current_state == CameraState.HEALTH or current_state == CameraState.CRAFTING or current_state == CameraState.TACTICAL_HUB)
	btn_crafting.visible = show and (current_state == CameraState.CHARACTER_OVERVIEW or current_state == CameraState.HEALTH or current_state == CameraState.INVENTORY or current_state == CameraState.TACTICAL_HUB)
	btn_tactical_hub.visible = show and (current_state == CameraState.CHARACTER_OVERVIEW or current_state == CameraState.HEALTH or current_state == CameraState.INVENTORY or current_state == CameraState.CRAFTING)
	scan_line_effect.visible = show and (current_state == CameraState.TACTICAL_HUB)
	update_button_layout()
	# Управление режимом Inventory
	if current_state == CameraState.INVENTORY and using_pause_camera:
		apply_inventory_mode_changes()
	else:
		restore_from_inventory_mode()
	
func _set_player_movement_enabled(enabled: bool):
	if player_node and player_node.has_method("set_movement_enabled"):
		player_node.set_movement_enabled(enabled)
		print("SystemCamera: Вызван set_movement_enabled(%s) для игрока" % enabled)
	else:
		print("SystemCamera: ОШИБКА - Player не имеет метода set_movement_enabled()")
		# Fallback - попробуем найти movement_controller напрямую
		if player_node and player_node.has_method("force_stop_all"):
			if not enabled:
				player_node.force_stop_all()

func _set_cursor_visible(visible: bool):
	# Добавляем задержку и принудительную установку
	await get_tree().process_frame # Даем время другим системам
	
	if visible:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		print("SystemCamera: Курсор VISIBLE")
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN) 
		print("SystemCamera: Курсор CAPTURED")
	
	# Принудительно обновляем режим
	await get_tree().process_frame
	var current_mode = Input.get_mouse_mode()
	print("SystemCamera: Текущий режим мыши: ", current_mode)
	
func find_ui_controllers():
	"""Находит контроллеры UI для блокировки"""
	# Ищем CrosshairController
	crosshair_controller = get_tree().get_first_node_in_group("crosshair_ui") 
	if not crosshair_controller:
		# Альтернативные пути поиска
		crosshair_controller = player_node.get_node_or_null("CrosshairUI")
		if not crosshair_controller:
			crosshair_controller = get_node_or_null("../UI/CrosshairController")
	
	if crosshair_controller:
		print("SystemCamera: CrosshairController найден")
	else:
		print("SystemCamera: ⚠️ CrosshairController не найден")
	
	# Ищем Head контроллер
	if player_node:
		head_controller = player_node.get_node_or_null("Head")
		if head_controller:
			print("SystemCamera: Head контроллер найден")
		else:
			print("SystemCamera: ⚠️ Head контроллер не найден")

# Методы блокировки UI
func set_ui_game_mode(is_game_mode: bool):
	"""Блокирует UI элементы в неигровых режимах"""
	ui_overlay.visible = is_game_mode
	# Блокируем crosshair
	if crosshair_controller and crosshair_controller.has_method("set_game_mode"):
		crosshair_controller.set_game_mode(is_game_mode)
	elif crosshair_controller:
		# Fallback - просто скрываем/показываем
		crosshair_controller.visible = is_game_mode
	
	# Блокируем управление головой
	if head_controller and head_controller.has_method("set_head_control_enabled"):
		head_controller.set_head_control_enabled(is_game_mode)
	
	print("SystemCamera: UI Game Mode %s" % ("включен" if is_game_mode else "выключен"))

func apply_world_blur():
	if not env or not env.camera_attributes:
		return
	
	if blur_tween and blur_tween.is_valid():
		blur_tween.kill()
	
	var attr := env.camera_attributes as CameraAttributesPractical
	if not attr:
		push_error("CameraAttributesPractical not assigned to WorldEnvironment")
		return
	
	attr.dof_blur_far_enabled = true
	attr.dof_blur_far_distance = 5.0
	attr.dof_blur_far_transition = 5.0
	attr.dof_blur_amount = 0.15
	
	blur_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	blur_tween.tween_property(attr, "dof_blur_far_distance", 1.0, 2.0)

func remove_world_blur():
	if not env or not env.camera_attributes:
		return		
	
	var attr := env.camera_attributes as CameraAttributesPractical
	if not attr:
		return
	
	attr.dof_blur_far_enabled = false
	attr.dof_blur_far_distance = 0.0
	attr.dof_blur_far_transition = 0.0
	attr.dof_blur_amount = 0.0
	
func setup_button_layout_manager():
	"""Настраивает ButtonLayoutManager"""
	if not button_layout_manager:
		print("SystemCamera: ButtonLayoutManager не найден!")
		return
	
	# Передаем ссылки
	button_layout_manager.system_camera = self
	button_layout_manager.player_node = player_node
	
	# Передаем кнопки
	var buttons_dict = {
		"inventory": btn_inventory,
		"health": btn_health,
		"character_overview": btn_сharacter_overview,
		"crafting": btn_crafting,
		"tactical_hub": btn_tactical_hub,
		"menu_pause": btn_menupause
	}
	button_layout_manager.set_button_references(buttons_dict)
	
	button_layout_manager.button_animation_completed.connect(_on_button_animation_completed)
	
	# ДОБАВЛЯЕМ ПОДКЛЮЧЕНИЕ ГЛАВНОГО СИГНАЛА:
	layout_mode_requested.connect(button_layout_manager._on_layout_mode_requested)
	
	print("SystemCamera: ButtonLayoutManager настроен с подключенными сигналами")
	
func update_button_layout():
	"""Отправляет сигналы для обновления layout кнопок"""
	if not using_pause_camera:
		buttons_should_hide.emit()
		return
	
	var visible_buttons = get_visible_buttons_for_current_state()
	var layout_mode = "tactical_hub" if current_state == CameraState.TACTICAL_HUB else "standard"
	
	# Отправляем сигнал
	layout_mode_requested.emit(layout_mode, visible_buttons)
	
func _on_button_animation_completed():
	"""Вызывается когда ButtonLayoutManager завершил анимацию"""
	print("SystemCamera: Анимация кнопок завершена")
	
func get_visible_buttons_for_current_state() -> Array[String]:
	"""Возвращает список видимых кнопок для текущего состояния"""
	var visible_buttons: Array[String] = []
	
	
	# Проверяем btn_inventory
	if current_state == CameraState.CHARACTER_OVERVIEW or current_state == CameraState.HEALTH or current_state == CameraState.CRAFTING or current_state == CameraState.TACTICAL_HUB:
		visible_buttons.append("inventory")
	
	# Проверяем btn_health  
	if current_state == CameraState.CHARACTER_OVERVIEW or current_state == CameraState.INVENTORY or current_state == CameraState.CRAFTING or current_state == CameraState.TACTICAL_HUB:
		visible_buttons.append("health")
	
	# Проверяем btn_menupause
	if current_state == CameraState.TACTICAL_HUB:
		visible_buttons.append("menu_pause")
	
	# Проверяем btn_сharacter_overview
	if current_state == CameraState.INVENTORY or current_state == CameraState.HEALTH or current_state == CameraState.CRAFTING or current_state == CameraState.TACTICAL_HUB:
		visible_buttons.append("character_overview")
	
	# Проверяем btn_crafting
	if current_state == CameraState.CHARACTER_OVERVIEW or current_state == CameraState.HEALTH or current_state == CameraState.INVENTORY or current_state == CameraState.TACTICAL_HUB:
		visible_buttons.append("crafting")
	
	# Проверяем btn_tactical_hub
	if current_state == CameraState.CHARACTER_OVERVIEW or current_state == CameraState.HEALTH or current_state == CameraState.INVENTORY or current_state == CameraState.CRAFTING:
		visible_buttons.append("tactical_hub")
	
	return visible_buttons
	
func _on_buttons_should_hide():
	"""Обработчик для скрытия всех кнопок"""
	if button_layout_manager:
		button_layout_manager.hide_all_buttons()
		
func setup_mode_dictionaries():
	"""Настраивает словари для управления видимостью режимов"""
	mode_nodes = {
		CameraState.TACTICAL_HUB: mode_tactical_hub,
		CameraState.CHARACTER_OVERVIEW: mode_character_overview,
		CameraState.INVENTORY: mode_inventory,
		CameraState.HEALTH: mode_health,
		CameraState.CRAFTING: mode_crafting,
		CameraState.MENU: mode_menu
	}
	
	mode_ui_nodes = {
		CameraState.TACTICAL_HUB: mode_tactical_hub_ui,
		CameraState.CHARACTER_OVERVIEW: mode_character_overview_ui,
		CameraState.INVENTORY: mode_inventory_ui,
		CameraState.HEALTH: mode_health_ui,
		CameraState.CRAFTING: mode_crafting_ui,
		CameraState.MENU: mode_menu_ui
	}

func update_mode_visibility():
	"""Обновляет видимость узлов режимов в зависимости от текущего состояния"""
	
	# Скрываем все режимы
	for state in mode_nodes.keys():
		var mode_node = mode_nodes[state]
		var mode_ui_node = mode_ui_nodes[state]
		
		if is_instance_valid(mode_node):
			mode_node.visible = false
			
		if is_instance_valid(mode_ui_node):
			mode_ui_node.visible = false

	
	# Показываем узлы для текущего режима (только если не в игровом режиме)
	if current_state != CameraState.GAME and using_pause_camera:
		var current_mode_node = mode_nodes.get(current_state)
		var current_mode_ui_node = mode_ui_nodes.get(current_state)
		
		if is_instance_valid(current_mode_node):
			current_mode_node.visible = true
			print("SystemCamera: Показан режим узел для %s" % CameraState.keys()[current_state])
			
		if is_instance_valid(current_mode_ui_node):
			current_mode_ui_node.visible = true
			print("SystemCamera: Показан UI режима для %s" % CameraState.keys()[current_state])

func apply_inventory_mode_changes():
	"""Применяет изменения для режима Inventory"""
	if is_inventory_mode_active:
		return # Уже активен
	
	if is_instance_valid(Weapon_Holder):
		var new_transform = original_weapon_holder_transform

		# Сдвигаем позицию
		new_transform.origin += Vector3(0.0, -0.45, 0.25) # X, Y, Z
		# Добавляем вращение (например, 15 градусов по оси Y)
		Weapon_Holder.transform = new_transform
		print("SystemCamera: Weapon_Holder трансформ изменён на: %s" % Weapon_Holder.transform)
	
	if is_instance_valid(player_node):
		player_node.collision_layer = 0 # Отключаем коллизию
		player_node_collision.disabled = true
		print("SystemCamera: Коллизия игрока отключена")
		
	if is_instance_valid(inventory_mode):
		inventory_mode.set_process(true)
	
	is_inventory_mode_active = true
	print("SystemCamera: Inventory режим активирован")

func restore_from_inventory_mode():
	"""Восстанавливает изменения после режима Inventory"""
	if not is_inventory_mode_active:
		return # Уже отключен
	
	if is_instance_valid(Weapon_Holder):
		Weapon_Holder.transform = original_weapon_holder_transform
		player_node_collision.disabled = false
		print("SystemCamera: Weapon_Holder позиция восстановлена на: %s" % Weapon_Holder.position)
	
	if is_instance_valid(player_node):
		player_node.collision_layer = original_player_collision_layer
		print("SystemCamera: Коллизия игрока восстановлена")
		
	if is_instance_valid(inventory_mode) and current_state == CameraState.GAME:
		inventory_mode.set_process(false)
		inventory_mode._force_end_drag()
	
	is_inventory_mode_active = false
	print("SystemCamera: Inventory режим деактивирован")
	
