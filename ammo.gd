extends Control

class_name AmmoUI

@onready var weapon_texture_display = null

# Ссылки на лейблы
@onready var weapon_name_label: Label = $WeaponNameLabel
@onready var current_ammo_label: Label = $CurrentAmmoLabel
@onready var total_ammo_label: Label = $TotalAmmoLabel
@onready var visual_ammo_container: Control = $"../visual_ammo_container"
@onready var fire_mode_label: Label = $FireModeLabel # НОВЫЙ: Лейбл для режима огня

# Переменные для отслеживания состояния
var current_weapon_name: String = ""
var is_animating: bool = false # Для внутренних анимаций смены оружия и т.п.
var current_fire_mode: String = "" # Для отслеживания текущего режима огня

# Настройки анимации
@export var animation_duration: float = 0.2
@export var enable_weapon_change_animation: bool = true
@export var enable_fire_mode_animation: bool = true

var last_ammo_count: int = 0

# Enum для типов анимации
enum AnimationType { COMBINED, FADE, SCALE, SLIDE, DRAMATIC }
@export var animation_type: AnimationType = AnimationType.COMBINED

# Цвета для разных типов оружия
var weapon_colors = {
	"Wasteland Eagle": Color(0.6, 0.5, 0.4),      # Выцветший коричневый
	"Enforcer 12-Gauge": Color(0.4, 0.5, 0.3),       # Болотно-зеленый  
	"Trail Boss Shotgun": Color(0.7, 0.4, 0.2),     # Ржавый оранжевый
	"Assault Auto-Rifle": Color(0.5, 0.3, 0.3),   # Темно-бордовый
	"default": Color(0.6, 0.6, 0.5)      # Грязно-серый
}

# --- ЦЕНТРАЛИЗОВАННОЕ УПРАВЛЕНИЕ ВИДИМОСТЬЮ UI ---
var _visibility_tween: Tween = null
# visual_ammo_container УДАЛЁН из этого списка, его видимость управляется отдельно
# fire_mode_label ДОБАВЛЕН сюда, чтобы он затухал вместе с остальными лейблами
var _ui_elements_to_manage: Array = [] # Список лейблов, которыми мы будем управлять (для 5-секундного отображения)

func _ready():
	_find_weapon_texture_display()
	
	# Проверяем, что все лейблы найдены
	if not weapon_name_label:
		printerr("AmmoUI: WeaponNameLabel не найден!")
	if not current_ammo_label:
		printerr("AmmoUI: CurrentAmmoLabel не найден!")
	if not total_ammo_label:
		printerr("AmmoUI: TotalAmmoLabel не найден!")
	if not visual_ammo_container:
		printerr("AmmoUI: Visual Ammo Container не найден!")
	if not fire_mode_label: # НОВОЕ: Проверка нового лейбла
		printerr("AmmoUI: FireModeLabel не найден!")
		
	# Инициализируем лейблы и контейнер как невидимые/прозрачные
	# Добавляем все лейблы, которыми управляет _show_ui_temporarily, в массив
	_ui_elements_to_manage = [weapon_name_label, current_ammo_label, total_ammo_label, fire_mode_label]
	
	for element in _ui_elements_to_manage:
		if is_instance_valid(element):
			element.modulate = Color(0.3, 0.3, 0.3, 0.6)  # ПРИГЛУШЕННЫЙ, НО ВИДИМЫЙ
			element.visible = true  # ВСЕГДА ВИДИМЫЕ!
			element.scale = Vector2(1.0, 1.0) # Сбросить масштаб на всякий случай

	
	if is_instance_valid(visual_ammo_container):
		visual_ammo_container.modulate = Color(0.3, 0.3, 0.3, 0.6)
		visual_ammo_container.visible = true
	
	# Устанавливаем начальные значения "X"
	weapon_name_label.text = "X"
	current_ammo_label.text = "X"
	total_ammo_label.text = "X"
	fire_mode_label.text = "" # По умолчанию пустая строка для fire_mode_label

	animate_startup_slide()

## Централизованная функция управления видимостью
func _show_ui_temporarily():
	# Если предыдущий твин существует и активен, прерываем его
	if _visibility_tween and _visibility_tween.is_valid():
		_visibility_tween.kill()
		_visibility_tween = null

	_visibility_tween = create_tween()
	_visibility_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)

	# Фаза 1: Сделать все управляемые лейблы яркими и полностью непрозрачными
	for element in _ui_elements_to_manage:
		if is_instance_valid(element):
			element.visible = true
			if element.modulate.a < 1.0:
				_visibility_tween.parallel().tween_property(element, "modulate", Color.WHITE, 0.2)
			else:
				element.modulate = Color.WHITE

	# Фаза 2: Задержка в 22 секунды
	_visibility_tween.tween_interval(22.0)

	# Фаза 3: Затухание до ПРИГЛУШЕННОГО состояния (НЕ до нуля!)
	for element in _ui_elements_to_manage:
		if is_instance_valid(element):
			_visibility_tween.parallel().tween_property(element, "modulate", Color(0.3, 0.3, 0.3, 0.6), 5.0)
	
	# Фаза 4: НЕ СКРЫВАЕМ ПОЛНОСТЬЮ! Оставляем приглушенными
	_visibility_tween.tween_callback(func():
		for element in _ui_elements_to_manage:
			if is_instance_valid(element):
				element.modulate = Color(0.3, 0.3, 0.3, 0.6) # Оставляем приглушенными
	)

func animate_startup_slide():
	# Все лейблы, включая новый fire_mode_label, участвуют в стартовой анимации
	var labels = [weapon_name_label, current_ammo_label, total_ammo_label, fire_mode_label]
	
	for label in labels:
		if is_instance_valid(label):
			label.visible = true 
			label.modulate.a = 0.0
			label.scale = Vector2(0.3, 0.3)
	
	var tween = create_tween()
	
	for i in range(labels.size()):
		var label = labels[i]
		if is_instance_valid(label):
			tween.parallel().tween_property(label, "modulate:a", 1.0, 0.4)
			tween.parallel().tween_property(label, "scale", Vector2(1.1, 1.1), 0.4)
			
			tween.parallel().tween_property(label, "scale", Vector2(1.0, 1.0), 0.2)
			
			if i < labels.size() - 1:
				tween.tween_interval(0.2)
	
	tween.tween_callback(func(): _show_ui_temporarily())


## Основные Функции Обновления


func update_weapon_display(weapon_name: String, animate: bool = true):
	"""ИСПРАВЛЕННАЯ версия - правильная логика burn"""
	if not is_instance_valid(weapon_name_label):
		return
	
	stop_reloading_animation()
	
	_show_ui_temporarily() # Запускаем таймер видимости для лейблов
	
	# Убеждаемся, что visual_ammo_container виден, когда оружие есть
	if is_instance_valid(visual_ammo_container):
		visual_ammo_container.visible = true
		visual_ammo_container.modulate.a = 1.0
	
	if weapon_name != current_weapon_name and animate and enable_weapon_change_animation and current_weapon_name != "":
		animate_weapon_change(weapon_name)
	else:
		weapon_name_label.text = weapon_name
		current_weapon_name = weapon_name
		weapon_name_label.scale = Vector2(1.0, 1.0) # Сбросить масштаб на всякий случай
	
	# ОБНОВЛЕННАЯ логика для изображения оружия
	if weapon_texture_display != null:
		# Если переключаемся на "No Weapon" И есть текущее оружие - используем burn
		if weapon_name.to_lower() == "no weapon" and weapon_texture_display.current_weapon_name != "":

			weapon_texture_display.hide_weapon_with_burn()
		else:
			print("AmmoUI: Обычное показ оружия: %s" % weapon_name)
			weapon_texture_display.show_weapon(weapon_name)
	else:
		print("AmmoUI: weapon_texture_display равен null!")
	

func update_ammo_display(current_ammo: int, weapon_type: String = "", fire_mode: String = ""):
	"""Обновляет отображение патронов (текст + визуальное)"""
	if not is_instance_valid(current_ammo_label):
		return
	
	_show_ui_temporarily() # Запускаем таймер видимости для лейблов
	
	# Убеждаемся, что visual_ammo_container виден, когда патроны есть
	if is_instance_valid(visual_ammo_container):
		visual_ammo_container.visible = true
		visual_ammo_container.modulate.a = 1.0

	# Обновляем текстовое отображение current_ammo_label БЕЗ fire_mode
	current_ammo_label.text = str(current_ammo)
	
	update_visual_ammo(current_ammo, weapon_type)

	# ОБНОВЛЕНИЕ РЕЖИМА ОГНЯ: только для автоматов
	if weapon_type.to_lower() == "Assault Auto-Rifle":
		update_fire_mode_display(fire_mode)
	else:
		# Если не автомат, скрываем fire_mode_label (или очищаем текст)
		if is_instance_valid(fire_mode_label):
			fire_mode_label.text = "" # Очищаем текст, так как не применимо
			# fire_mode_label будет скрыт _show_ui_temporarily по таймауту, если не будет других обновлений
			
## НОВАЯ ФУНКЦИЯ: Обновление отображения режима огня
func update_fire_mode_display(active_mode: String):
	if not is_instance_valid(fire_mode_label):
		return

	_show_ui_temporarily() # Убеждаемся, что fire_mode_label виден и будет управляться таймером

	current_fire_mode = active_mode.to_lower()
	var modes = ["single", "burst", "auto"]
	var display_text = ""

	for mode in modes:
		var mode_display = mode
		if mode == current_fire_mode:
			mode_display = mode.to_upper() # Активный режим - заглавными буквами
		display_text += mode_display + " "
	
	fire_mode_label.text = display_text.strip_edges()
	
	if enable_fire_mode_animation:
		animate_fire_mode_change_effect() # Отдельная анимация для всего лейбла

func update_total_ammo_display(total_ammo: int):
	"""Обновляет отображение общих патронов"""
	if not is_instance_valid(total_ammo_label):
		return
	
	_show_ui_temporarily() # Запускаем таймер видимости для лейблов
	
	total_ammo_label.text = str(total_ammo)

func show_reloading():
	"""Показывает состояние перезарядки с анимацией"""
	_show_ui_temporarily() # Запускаем таймер видимости для лейблов
	
	# Скрываем visual_ammo_container и fire_mode_label при перезарядке
	if is_instance_valid(visual_ammo_container):
		visual_ammo_container.visible = false
		visual_ammo_container.modulate.a = 0.0
	if is_instance_valid(fire_mode_label):
		fire_mode_label.text = "" # Очищаем текст режима огня
		
	if is_instance_valid(weapon_name_label):
		weapon_name_label.text = "Reloading..."
		animate_reloading_text()
	if is_instance_valid(current_ammo_label):
		current_ammo_label.text = ""
	if is_instance_valid(total_ammo_label):
		total_ammo_label.text = ""

func animate_reloading_text():
	"""Анимация пульсации для текста перезарядки"""
	if not is_instance_valid(weapon_name_label):
		return
	
	if weapon_name_label.has_meta("reload_tween"):
		var existing_tween = weapon_name_label.get_meta("reload_tween")
		if existing_tween and existing_tween.is_valid():
			existing_tween.kill()
	
	var tween = create_tween()
	tween.set_loops()
	
	tween.tween_property(weapon_name_label, "scale", Vector2(1.1, 1.1), 0.4)
	tween.tween_property(weapon_name_label, "scale", Vector2(0.9, 0.9), 0.4)
	tween.tween_property(weapon_name_label, "scale", Vector2(1.0, 1.0), 0.2)
	tween.tween_interval(0.3)
	
	weapon_name_label.set_meta("reload_tween", tween)

func stop_reloading_animation():
	"""Останавливает анимацию перезарядки"""
	if not is_instance_valid(weapon_name_label):
		return
	
	if weapon_name_label.has_meta("reload_tween"):
		var existing_tween = weapon_name_label.get_meta("reload_tween")
		if existing_tween and existing_tween.is_valid():
			existing_tween.kill()
		weapon_name_label.remove_meta("reload_tween")
	
	var reset_tween = create_tween()
	reset_tween.tween_property(weapon_name_label, "scale", Vector2(1.0, 1.0), 0.1)

func show_no_weapon():
	"""ИСПРАВЛЕННАЯ функция - НЕ скрывает лейблы полностью"""
	stop_reloading_animation()
	
	_show_ui_temporarily() # Запускаем таймер видимости для лейблов
	
	# Делаем visual_ammo_container приглушенным
	if is_instance_valid(visual_ammo_container):
		visual_ammo_container.visible = true
		visual_ammo_container.modulate = Color(0.3, 0.3, 0.3, 0.6)
	if is_instance_valid(fire_mode_label):
		fire_mode_label.text = "" # Очищаем текст режима огня
		
	# Burn эффект для изображения оружия
	var texture_node = get_node_or_null("../TextureWeapon")
	if texture_node != null:
		print("AmmoUI: Вызываю hide_weapon_with_burn для скрытия оружия")
		texture_node.hide_weapon_with_burn()
	else:
		print("AmmoUI: TextureWeapon НЕ НАЙДЕН в данный момент!")
	
	# Устанавливаем "X", но НЕ скрываем лейблы
	update_weapon_display("No Weapon", false)
	if is_instance_valid(current_ammo_label):
		current_ammo_label.text = "X"
	if is_instance_valid(total_ammo_label):
		total_ammo_label.text = "X"
	

## Анимации


func animate_weapon_change(new_weapon_name: String):
	"""Главная анимация смены оружия"""
	if is_animating:
		return
	
	is_animating = true
	current_weapon_name = new_weapon_name
	
	match animation_type:
		AnimationType.COMBINED:
			_combined_weapon_effect(new_weapon_name)
		AnimationType.FADE:
			_fade_weapon_effect(new_weapon_name)
		AnimationType.SCALE:
			_scale_weapon_effect(new_weapon_name)
		AnimationType.SLIDE:
			_slide_weapon_effect(new_weapon_name)
		AnimationType.DRAMATIC:
			_dramatic_weapon_effect(new_weapon_name)

func _combined_weapon_effect(new_weapon_name: String):
	"""Комбинированный эффект: масштаб + цвет + сдвиг"""
	var tween = create_tween()
	var original_color = weapon_name_label.modulate
	var original_position = weapon_name_label.position
	
	var weapon_color = weapon_colors.get(new_weapon_name.to_lower(), weapon_colors["default"])
	
	tween.parallel().tween_property(weapon_name_label, "position:x", original_position.x - 25, animation_duration * 0.3)
	tween.parallel().tween_property(weapon_name_label, "scale", Vector2(0.7, 0.7), animation_duration * 0.3)
	tween.parallel().tween_property(weapon_name_label, "modulate:a", 0.2, animation_duration * 0.3)
	
	tween.tween_callback(func(): 
		weapon_name_label.text = new_weapon_name
		weapon_name_label.position.x = original_position.x + 30
	)
	
	tween.parallel().tween_property(weapon_name_label, "position:x", original_position.x, animation_duration * 0.4)
	tween.parallel().tween_property(weapon_name_label, "scale", Vector2(1.15, 1.15), animation_duration * 0.4)
	tween.parallel().tween_property(weapon_name_label, "modulate", weapon_color, animation_duration * 0.4)
	tween.parallel().tween_property(weapon_name_label, "modulate:a", 1.0, animation_duration * 0.4)
	
	tween.parallel().tween_property(weapon_name_label, "scale", Vector2(1.0, 1.0), animation_duration * 0.3)
	tween.tween_property(weapon_name_label, "modulate", original_color, animation_duration * 1.5)
	
	tween.tween_callback(func(): is_animating = false)

func animate_fire_mode_change(): 
	# Эта функция теперь не используется напрямую для визуального эффекта
	# Она была переименована в animate_fire_mode_change_effect и вызывается в update_fire_mode_display.
	# Оставляю на случай, если вы где-то её ещё вызываете, но она может быть удалена.
	"""Анимация смены режима стрельбы (старая версия, может быть удалена)"""
	if not enable_fire_mode_animation or not is_instance_valid(current_ammo_label):
		return
	
	_show_ui_temporarily()

	var tween = create_tween()
	tween.tween_property(current_ammo_label, "modulate", Color.YELLOW, 0.05)
	tween.tween_property(current_ammo_label, "modulate", Color.WHITE, 0.1)

## НОВАЯ ФУНКЦИЯ: Анимация для всего лейбла режима огня
func animate_fire_mode_change_effect():
	"""Анимация для всего лейбла режима огня при его обновлении"""
	if not is_instance_valid(fire_mode_label):
		return
	
	var tween = create_tween()
	var original_scale = fire_mode_label.scale
	var original_modulate = fire_mode_label.modulate
	
	# Быстрое увеличение и подсветка
	tween.parallel().tween_property(fire_mode_label, "scale", Vector2(1.1, 1.1), 0.1)
	tween.parallel().tween_property(fire_mode_label, "modulate", Color.YELLOW, 0.1)
	
	# Возврат к норме
	tween.parallel().tween_property(fire_mode_label, "scale", original_scale, 0.1)
	tween.parallel().tween_property(fire_mode_label, "modulate", original_modulate, 0.1)

func animate_ammo_pickup(ammo_type: String, amount: int):
	"""Анимация подбора патронов - слайд эффект"""
	if not is_instance_valid(total_ammo_label):
		print("DEBUG: AmmoUI: total_ammo_label недействителен.") # Отладочное сообщение
		return
	
	_show_ui_temporarily() # Запускаем таймер видимости для лейблов

	var tween = create_tween()
	var original_position = total_ammo_label.position 
	var original_global_position = total_ammo_label.global_position
	var original_color = total_ammo_label.modulate
	
	var pickup_color = weapon_colors.get(ammo_type.to_lower(), weapon_colors["default"]) # Убедимся, что ammo_type в нижнем регистре
	
	var pickup_label = Label.new()
	pickup_label.text = "+" + str(amount)
	pickup_label.add_theme_font_size_override("font_size", 16)
	
	# --- ПЕРВОЕ ИСПРАВЛЕНИЕ / ОТЛАДКА ---
	# Установим начальную модуляцию (прозрачность) так, чтобы она была видимой,
	# и убедимся, что цвет имеет полный альфа-канал, если его нет в weapon_colors.
	var initial_modulate_color = pickup_color
	initial_modulate_color.a = 1.0 # Убедимся, что альфа-канал полный
	pickup_label.modulate = initial_modulate_color 
	
	# Установите начальную глобальную позицию для pickup_label
	pickup_label.global_position = original_global_position + Vector2(-20, -10) 
	
	pickup_label.scale = Vector2(1.0, 1.0) # Для отладки: делаем его сразу видимым
	
	get_tree().get_root().add_child(pickup_label) 
	

	# Анимация для total_ammo_label
	tween.parallel().tween_property(total_ammo_label, "position:x", original_position.x - 15, 0.2)
	tween.parallel().tween_property(total_ammo_label, "modulate", pickup_color, 0.2)
	tween.parallel().tween_property(total_ammo_label, "scale", Vector2(1.2, 1.2), 0.2)

	
	tween.parallel().tween_property(pickup_label, "global_position:y", pickup_label.global_position.y - 40, 0.8)
	
	# Возвращение total_ammo_label в исходное состояние
	tween.parallel().tween_property(total_ammo_label, "position:x", original_position.x, 0.3)
	tween.parallel().tween_property(total_ammo_label, "scale", Vector2(1.0, 1.0), 0.3)
	
	# Затухание pickup_label (добавим задержку перед затуханием, чтобы он был виден)
	tween.tween_interval(0.5) # Добавлена небольшая задержка перед затуханием
	tween.parallel().tween_property(pickup_label, "modulate:a", 0.0, 0.6)
	
	# Восстановление цвета total_ammo_label
	tween.tween_property(total_ammo_label, "modulate", original_color, 0.4)
	
	# Удаление pickup_label из дерева сцены после завершения анимации
	tween.tween_callback(func(): 
		if is_instance_valid(pickup_label): # Добавим проверку на валидность
			pickup_label.queue_free()
	)

func animate_ammo_change():
	"""Небольшая анимация при изменении патронов"""
	if not is_instance_valid(current_ammo_label):
		return
	
	_show_ui_temporarily() # Запускаем таймер видимости для лейблов

	var tween = create_tween()
	tween.tween_property(current_ammo_label, "scale", Vector2(1.1, 1.1), 0.05)
	tween.tween_property(current_ammo_label, "scale", Vector2(1.0, 1.0), 0.05)


## Альтернативные Эффекты


func _fade_weapon_effect(new_weapon_name: String):
	"""Простое затухание/появление"""
	var tween = create_tween()
	
	tween.tween_property(weapon_name_label, "modulate:a", 0.0, animation_duration * 0.5)
	tween.tween_callback(func(): weapon_name_label.text = new_weapon_name)
	tween.tween_property(weapon_name_label, "modulate:a", 1.0, animation_duration * 0.5)
	tween.tween_callback(func(): is_animating = false)

func _scale_weapon_effect(new_weapon_name: String):
	"""Уменьшение/увеличение с подпрыгиванием"""
	var tween = create_tween()
	
	tween.tween_property(weapon_name_label, "scale", Vector2(0.8, 0.8), animation_duration * 0.4)
	tween.tween_callback(func(): weapon_name_label.text = new_weapon_name)
	tween.tween_property(weapon_name_label, "scale", Vector2(1.1, 1.1), animation_duration * 0.3)
	tween.tween_property(weapon_name_label, "scale", Vector2(1.0, 1.0), animation_duration * 0.3)
	tween.tween_callback(func(): is_animating = false)

func _slide_weapon_effect(new_weapon_name: String):
	"""Только сдвиг влево/справа"""
	var tween = create_tween()
	var original_position = weapon_name_label.position
	
	tween.parallel().tween_property(weapon_name_label, "position:x", original_position.x - 30, animation_duration * 0.4)
	tween.parallel().tween_property(weapon_name_label, "modulate:a", 0.2, animation_duration * 0.4)
	
	tween.tween_callback(func(): 
		weapon_name_label.text = new_weapon_name
		weapon_name_label.position.x = original_position.x + 30
	)
	
	tween.parallel().tween_property(weapon_name_label, "position:x", original_position.x, animation_duration * 0.6)
	tween.parallel().tween_property(weapon_name_label, "modulate:a", 1.0, animation_duration * 0.6)
	tween.tween_callback(func(): is_animating = false)

func _dramatic_weapon_effect(new_weapon_name: String):
	"""Самый драматичный эффект с большим сдвигом"""
	var tween = create_tween()
	var original_color = weapon_name_label.modulate
	var original_position = weapon_name_label.position
	var weapon_color = weapon_colors.get(new_weapon_name.to_lower(), weapon_colors["default"])
	
	tween.parallel().tween_property(weapon_name_label, "position:x", original_position.x - 50, animation_duration * 0.25)
	tween.parallel().tween_property(weapon_name_label, "rotation_degrees", -15.0, animation_duration * 0.25)
	tween.parallel().tween_property(weapon_name_label, "scale", Vector2(0.5, 0.5), animation_duration * 0.25)
	tween.parallel().tween_property(weapon_name_label, "modulate:a", 0.0, animation_duration * 0.25)
	
	tween.tween_callback(func(): 
		weapon_name_label.text = new_weapon_name
		weapon_name_label.position.x = original_position.x + 60
		weapon_name_label.rotation_degrees = 15.0
	)
	
	tween.parallel().tween_property(weapon_name_label, "position:x", original_position.x, animation_duration * 0.5)
	tween.parallel().tween_property(weapon_name_label, "rotation_degrees", 0.0, animation_duration * 0.5)
	tween.parallel().tween_property(weapon_name_label, "scale", Vector2(1.2, 1.2), animation_duration * 0.3)
	tween.parallel().tween_property(weapon_name_label, "modulate", weapon_color, animation_duration * 0.3)
	tween.parallel().tween_property(weapon_name_label, "modulate:a", 1.0, animation_duration * 0.3)
	
	tween.parallel().tween_property(weapon_name_label, "scale", Vector2(1.0, 1.0), animation_duration * 0.25)
	tween.tween_property(weapon_name_label, "modulate", original_color, animation_duration)
	tween.tween_callback(func(): is_animating = false)


## Утилиты


func set_animation_enabled(weapon_change: bool, fire_mode: bool):
	"""Включает/выключает анимации"""
	enable_weapon_change_animation = weapon_change
	enable_fire_mode_animation = fire_mode

func set_animation_speed(speed_multiplier: float):
	"""Изменяет скорость анимации"""
	animation_duration = 0.2 / speed_multiplier

func set_animation_type(type: AnimationType):
	"""Изменяет тип анимации"""
	animation_type = type
	print("AmmoUI: Тип анимации изменен на: %s" % AnimationType.keys()[type])


## Публичный API для Player.gd (и других скриптов)


func update_full_display(weapon_name: String, current_ammo: int, total_ammo: int, weapon_type: String = "", fire_mode: String = ""):
	"""Обновляет весь дисплей сразу"""
	_show_ui_temporarily() # Запускаем таймер видимости для лейблов
	
	# Убеждаемся, что visual_ammo_container виден, когда оружие есть
	if is_instance_valid(visual_ammo_container):
		visual_ammo_container.visible = true
		visual_ammo_container.modulate.a = 1.0
	
	update_weapon_display(weapon_name)
	update_ammo_display(current_ammo, weapon_type, fire_mode) # Передаем fire_mode сюда
	update_total_ammo_display(total_ammo)

func on_fire_mode_changed(weapon_type: String, new_fire_mode: String): # ИСПРАВЛЕНИЕ: ВОЗВРАЩЕНЫ ОБА АРГУМЕНТА
	"""Вызывается при смене режима стрельбы"""
	# Теперь эта функция принимает оба аргумента, как вы испускаете сигнал.
	# Используем переданный weapon_type для проверки, является ли оружие "automatic".
	if weapon_type.to_lower() == "Assault Auto-Rifle":
		update_fire_mode_display(new_fire_mode)

func on_reload_started():
	"""Вызывается когда начинается перезарядка"""
	show_reloading()

func on_reload_finished():
	"""Вызывается когда перезарядка завершается"""
	stop_reloading_animation()

func on_ammo_pickup(ammo_type: String, amount: int):
	"""Вызывается при подборе патронов"""
	animate_ammo_pickup(ammo_type, amount)

func on_ammo_changed():
	"""Вызывается при изменении патронов"""
	animate_ammo_change()
	
func animate_active_weapon_confirmation(): #shake
	"""Альтернативная анимация - тряска"""
	if not is_instance_valid(weapon_name_label) or is_animating:
		return
	
	_show_ui_temporarily() # Запускаем таймер видимости для лейблов

	var original_position = weapon_name_label.position
	var current_weapon_type = current_weapon_name.to_lower()
	var highlight_color = weapon_colors.get(current_weapon_type, weapon_colors["default"])
	var original_color = weapon_name_label.modulate
	
	var tween = create_tween()
	
	tween.parallel().tween_property(weapon_name_label, "modulate", highlight_color, 0.05)
	
	for i in range(4):
		var offset = 3 if i % 2 == 0 else -3
		tween.parallel().tween_property(weapon_name_label, "position:x", original_position.x + offset, 0.03)
	
	tween.parallel().tween_property(weapon_name_label, "position", original_position, 0.05)
	tween.tween_property(weapon_name_label, "modulate", original_color, 0.2)
	

func show_weapon_not_available(weapon_type: String): # ВОЗВРАЩЕНА АНИМАЦИЯ И ФУНКЦИОНАЛ
	"""Показывает, что оружие недоступно (для случая когда его нет в инвентаре)"""
	
	_show_ui_temporarily() # Запустит таймер для основного UI.

	var unavailable_label = Label.new()
	unavailable_label.text = weapon_type.capitalize() + " - Not Available"
	unavailable_label.add_theme_font_size_override("font_size", 14)
	unavailable_label.modulate = Color(1.0, 0.3, 0.3, 0.0) # Красноватый, прозрачный
	unavailable_label.position = Vector2(weapon_name_label.position.x, weapon_name_label.position.y - 25)
	get_tree().get_root().add_child(unavailable_label) # Важно: добавляем к корневому узлу, чтобы он был поверх всего
	
	var tween = create_tween()
	
	# Появление сверху
	tween.parallel().tween_property(unavailable_label, "modulate:a", 0.8, 0.2)
	tween.parallel().tween_property(unavailable_label, "position:y", unavailable_label.position.y + 10, 0.2)
	
	# Держим на экране
	tween.tween_interval(1.82)
	
	# Исчезновение
	tween.parallel().tween_property(unavailable_label, "modulate:a", 0.0, 0.3)
	tween.parallel().tween_property(unavailable_label, "position:y", unavailable_label.position.y - 15, 0.3)
	
	# Удаляем лейбл после завершения анимации
	tween.tween_callback(func(): unavailable_label.queue_free())
	
func animate_active_weapon_confirmation_pulse():
	"""Альтернативная анимация - пульсация с цветом"""
	if not is_instance_valid(weapon_name_label) or is_animating:
		return
	
	_show_ui_temporarily() # Запускаем таймер видимости для лейблов
	
	var current_weapon_type = current_weapon_name.to_lower()
	var highlight_color = weapon_colors.get(current_weapon_type, weapon_colors["default"])
	var original_color = weapon_name_label.modulate
	
	var tween = create_tween()
	
	for i in range(2):
		tween.parallel().tween_property(weapon_name_label, "scale", Vector2(1.15, 1.15), 0.08)
		tween.parallel().tween_property(weapon_name_label, "modulate", highlight_color, 0.08)
		
		tween.parallel().tween_property(weapon_name_label, "scale", Vector2(1.0, 1.0), 0.08)
		tween.parallel().tween_property(weapon_name_label, "modulate", original_color, 0.08)
		
		if i == 0:
			tween.tween_interval(0.1)

func update_visual_ammo(current_ammo: int, weapon_type: String):
	"""Обновляет визуальное отображение патронов"""
	if not is_instance_valid(visual_ammo_container):
		return
	
	visual_ammo_container.visible = true
	visual_ammo_container.modulate.a = 1.0

	var max_ammo = get_max_ammo_for_weapon(weapon_type)
	
	if current_ammo != last_ammo_count:
		create_visual_ammo_for_weapon(current_ammo, max_ammo) # ИСПРАВЛЕНИЕ: Убрали weapon_type отсюда
		last_ammo_count = current_ammo

func get_max_ammo_for_weapon(weapon_type: String) -> int:
	"""Возвращает максимальный размер обоймы для типа оружия"""
	match weapon_type:
		"Wasteland Eagle": return 12
		"Enforcer 12-Gauge": return 5
		"Trail Boss Shotgun": return 8
		"Assault Auto-Rifle": return 30
		_: return 10

func create_visual_ammo_for_weapon(current_ammo: int, max_ammo: int):
	"""Создает визуальное отображение в зависимости от типа оружия"""
	for child in visual_ammo_container.get_children():
		child.queue_free()
	
	if current_ammo <= 0:
		return
		
	# Используем current_weapon_name для определения типа визуализации, так как weapon_type может быть пустым
	match current_weapon_name.to_lower(): 
		"Wasteland Eagle":
			create_simple_dots(current_ammo, max_ammo)
		"Enforcer 12-Gauge":
			create_bullet_icons(current_ammo, max_ammo)
		"Trail Boss Shotgun":
			create_shotgun_shells(current_ammo, max_ammo)
		"Assault Auto-Rifle":
			create_magazine_display(current_ammo, max_ammo)
		_:
			create_simple_dots(current_ammo, max_ammo)


## Реализации Визуальных Стилей


func create_bullet_icons(current_ammo: int, max_ammo: int):
	"""Иконки патронов для винтовки - постапокалиптический стиль"""
	if not is_instance_valid(visual_ammo_container):
		return
		
	var bullet_size = Vector2(8, 24)  # Чуть уже и выше - более реалистично
	var spacing = 2
	
	for i in range(max_ammo):
		var bullet_container = Control.new()
		bullet_container.size = bullet_size
		bullet_container.position = Vector2(0, i * (bullet_size.y + spacing))
		
		if i < current_ammo:
			# Живая пуля - медный/латунный цвет с градиентом
			var bullet_case = ColorRect.new()
			bullet_case.size = Vector2(bullet_size.x, bullet_size.y * 0.7)  # Гильза
			bullet_case.position = Vector2(0, bullet_size.y * 0.3)
			bullet_case.color = Color(0.8, 0.6, 0.3, 0.9)  # Медный цвет гильзы
			
			var bullet_head = ColorRect.new()  # Пуля
			bullet_head.size = Vector2(bullet_size.x * 0.8, bullet_size.y * 0.3)
			bullet_head.position = Vector2(bullet_size.x * 0.1, 0)
			bullet_head.color = Color(0.4, 0.4, 0.4, 1.0)  # Свинцовый цвет пули
			
			bullet_container.add_child(bullet_case)
			bullet_container.add_child(bullet_head)
			
		else:
			# Пустая гильза или отсутствие пули
			var empty_outline = ColorRect.new()
			empty_outline.size = bullet_size
			empty_outline.color = Color(0.2, 0.15, 0.1, 0.4)  # Темно-коричневый, почти невидимый
			
			# Добавляем тонкую рамку для показа пустого места
			var border = ColorRect.new()
			border.size = Vector2(bullet_size.x, 2)
			border.position = Vector2(0, bullet_size.y - 2)
			border.color = Color(0.3, 0.2, 0.1, 0.6)  # Грязно-коричневая рамка
			
			bullet_container.add_child(empty_outline)
			bullet_container.add_child(border)
		
		visual_ammo_container.add_child(bullet_container)
		
func create_magazine_display(current_ammo: int, max_ammo: int):
	"""Постапокалиптический магазин для автомата"""
	if not is_instance_valid(visual_ammo_container):
		return
		
	# Основа магазина - ржавый металл
	var magazine_bg = ColorRect.new()
	magazine_bg.size = Vector2(18, 65)
	magazine_bg.color = Color(0.25, 0.2, 0.15, 0.9)  # Темный ржавый металл
	visual_ammo_container.add_child(magazine_bg)
	
	# Рамка магазина - более светлый металл
	var magazine_frame = ColorRect.new()
	magazine_frame.size = Vector2(20, 67)
	magazine_frame.position = Vector2(-1, -1)
	magazine_frame.color = Color(0.35, 0.3, 0.25, 0.7)  # Чуть светлее для контура
	visual_ammo_container.add_child(magazine_frame)
	visual_ammo_container.move_child(magazine_bg, -1)  # Перемещаем bg поверх frame
	
	var bullet_height = 60.0 / max_ammo if max_ammo > 0 else 0
	
	for i in range(max_ammo):
		var bullet = ColorRect.new()
		bullet.size = Vector2(14, max(bullet_height - 1, 2))
		bullet.position = Vector2(2, 62 - (i + 1) * bullet_height)
		
		if i < current_ammo:
			# Градиент для живых патронов - от медного снизу к свинцовому сверху
			var ammo_ratio = float(i) / float(max_ammo)
			var copper = Color(0.72, 0.45, 0.2, 1.0)  # Медный
			var lead = Color(0.4, 0.4, 0.45, 1.0)     # Свинцовый
			bullet.color = copper.lerp(lead, ammo_ratio * 0.3)
			
			# Добавляем немного "грязи" для реализма
			if i % 3 == 0:  # Каждый третий патрон чуть темнее
				bullet.color = bullet.color.darkened(0.1)
		else:
			# Пустые места - очень темные
			bullet.color = Color(0.15, 0.12, 0.08, 0.3)
		
		magazine_bg.add_child(bullet)

func create_simple_dots(current_ammo: int, max_ammo: int):
	"""Постапокалиптические точки для патронов"""
	if not is_instance_valid(visual_ammo_container):
		return
		
	var dot_size = Vector2(8, 8)  # Чуть больше для лучшей видимости
	var spacing = 3
	
	var total_height = max_ammo * dot_size.y + (max_ammo - 1) * spacing
	if max_ammo == 0: total_height = 0
	
	for i in range(max_ammo):
		var dot_container = Control.new()
		dot_container.size = dot_size
		dot_container.position = Vector2(0, total_height - (i + 1) * (dot_size.y + spacing))
		
		if i < current_ammo:
			# Живые патроны - медные точки с темным центром
			var outer_dot = ColorRect.new()
			outer_dot.size = dot_size
			outer_dot.color = Color(0.7, 0.5, 0.3, 0.8)  # Медная оболочка
			
			var inner_dot = ColorRect.new()
			inner_dot.size = Vector2(dot_size.x * 0.6, dot_size.y * 0.6)
			inner_dot.position = Vector2(dot_size.x * 0.2, dot_size.y * 0.2)
			inner_dot.color = Color(0.3, 0.3, 0.3, 1.0)  # Темный центр
			
			dot_container.add_child(outer_dot)
			dot_container.add_child(inner_dot)
		else:
			# Пустые места - едва видимые темные кружки
			var empty_dot = ColorRect.new()
			empty_dot.size = dot_size
			empty_dot.color = Color(0.2, 0.15, 0.1, 0.4)
			
			# Тонкая рамка для обозначения пустого места
			var border_dot = ColorRect.new()
			border_dot.size = Vector2(dot_size.x, 2)
			border_dot.position = Vector2(0, dot_size.y - 2)
			border_dot.color = Color(0.3, 0.2, 0.1, 0.6)
			
			dot_container.add_child(empty_dot)
			dot_container.add_child(border_dot)
		
		visual_ammo_container.add_child(dot_container)
		
# Функция для создания "грязного" эффекта на UI
func add_postapoc_dirt_effect(element: Control):
	"""Добавляет эффект грязи/ржавчины на UI элемент"""
	if not is_instance_valid(element):
		return
		
	# Создаем несколько маленьких темных пятен для эффекта грязи
	for i in range(3):
		var dirt_spot = ColorRect.new()
		dirt_spot.size = Vector2(randf_range(2, 4), randf_range(2, 4))
		dirt_spot.position = Vector2(
			randf_range(0, element.size.x - dirt_spot.size.x),
			randf_range(0, element.size.y - dirt_spot.size.y)
		)
		dirt_spot.color = Color(0.1, 0.08, 0.05, randf_range(0.2, 0.4))
		element.add_child(dirt_spot)

func create_shotgun_shells(current_ammo: int, max_ammo: int):
	"""Компактный дисплей для дробовика - два ряда по 4 патрона"""
	if not is_instance_valid(visual_ammo_container):
		return
		
	var shell_size = Vector2(6, 18)  # Компактные гильзы
	var spacing_x = 2  # Расстояние между колонками
	var spacing_y = 2  # Расстояние между рядами
	var shells_per_row = 4  # 4 патрона в ряду
	
	for i in range(max_ammo):
		var shell_container = Control.new()
		shell_container.size = shell_size
		
		# Вычисляем позицию: левый ряд (0-3), правый ряд (4-7)
		var row = i / shells_per_row  # 0 или 1 (левый/правый ряд)
		var col = i % shells_per_row  # 0-3 (позиция в ряду)
		
		shell_container.position = Vector2(
			row * (shell_size.x + spacing_x),  # X: 0 для левого ряда, (shell_size.x + spacing) для правого
			col * (shell_size.y + spacing_y)   # Y: сверху вниз по 4 патрона
		)
		
		if i < current_ammo:
			# Пластиковая часть гильзы (цветная)
			var shell_plastic = ColorRect.new()
			shell_plastic.size = Vector2(shell_size.x, shell_size.y * 0.65)
			shell_plastic.position = Vector2(0, shell_size.y * 0.35)
			
			# Цвета патронов дробовика
			var shell_colors = [
				Color(0.7, 0.2, 0.2, 0.9),  # Красный
				Color(0.2, 0.6, 0.2, 0.9),  # Зеленый  
				Color(0.2, 0.2, 0.7, 0.9),  # Синий
				Color(0.8, 0.8, 0.2, 0.9),  # Желтый
			]
			shell_plastic.color = shell_colors[col % shell_colors.size()]  # Цвет зависит от позиции в ряду
			
			# Металлическая основа (латунь)
			var shell_base = ColorRect.new()
			shell_base.size = Vector2(shell_size.x, shell_size.y * 0.35)
			shell_base.position = Vector2(0, shell_size.y * 0.65)
			shell_base.color = Color(0.75, 0.6, 0.35, 1.0)  # Латунная основа
			
			# Небольшая точка сверху для реализма (обжим)
			var shell_crimp = ColorRect.new()
			shell_crimp.size = Vector2(shell_size.x * 0.8, 2)
			shell_crimp.position = Vector2(shell_size.x * 0.1, 0)
			shell_crimp.color = Color(0.4, 0.3, 0.2, 0.8)  # Темный обжим
			
			shell_container.add_child(shell_plastic)
			shell_container.add_child(shell_base)
			shell_container.add_child(shell_crimp)
			
			# Добавляем небольшую грязь
			add_postapoc_dirt_effect_small(shell_container)
		else:
			# Пустое место - едва видимый контур
			var empty_shell = ColorRect.new()
			empty_shell.size = shell_size
			empty_shell.color = Color(0.15, 0.12, 0.08, 0.25)
			
			# Тонкая рамка для обозначения пустого места
			var empty_outline = ColorRect.new()
			empty_outline.size = Vector2(shell_size.x, 1)
			empty_outline.position = Vector2(0, shell_size.y - 1)
			empty_outline.color = Color(0.25, 0.2, 0.15, 0.4)
			
			shell_container.add_child(empty_shell)
			shell_container.add_child(empty_outline)
		
		visual_ammo_container.add_child(shell_container)

func add_postapoc_dirt_effect_small(element: Control):
	"""Добавляет маленькие пятна грязи на патроны"""
	if not is_instance_valid(element):
		return
		
	# Только 1-2 маленьких пятна чтобы не засорять мелкие патроны
	for i in range(randi_range(1, 2)):
		var dirt_spot = ColorRect.new()
		dirt_spot.size = Vector2(1, 1)  # Совсем маленькие пятна
		dirt_spot.position = Vector2(
			randf_range(0, element.size.x - 1),
			randf_range(0, element.size.y - 1)
		)
		dirt_spot.color = Color(0.08, 0.06, 0.04, randf_range(0.3, 0.5))
		element.add_child(dirt_spot)
		
func _find_weapon_texture_display():
	
	# Попробуем разные пути
	var paths_to_try = [
		"../TextureWeapon",
		"TextureWeapon", 
		"../../TextureWeapon",
		"../UI/TextureWeapon"
	]
	
	for path in paths_to_try:
		var node = get_node_or_null(path)
		if node:
			weapon_texture_display = node
			return
	
	weapon_texture_display = null
