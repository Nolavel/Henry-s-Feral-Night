extends Node3D

# ============================================================================
# НАСТРОЙКИ ФОНАРИКА
# ============================================================================
@export var flashlight_enabled: bool = false
@export var flashlight_power: float = 5.0 # Регулировка яркости (0.5 - 10.0)
@export var flashlight_range: float = 50.0 # Дальность

# ============================================================================
# ЗВУКОВЫЕ НАСТРОЙКИ
# ============================================================================
@export var flashlight_on_sound: AudioStream   # Звук включения
@export var flashlight_off_sound: AudioStream  # Звук выключения
@export var sound_volume: float = 0.7          # Громкость звуков (0.0 - 1.0)
@export var sound_enabled: bool = true         # Включены ли звуки фонарика

# ============================================================================
# КОМПОНЕНТЫ
# ============================================================================
@onready var flashlight_spot: SpotLight3D = $FlashlightSpot
@onready var flashlight_area: OmniLight3D = $FlashlightArea
@onready var Switcher_label = $"../../../UI/FlashlightUI/switcher_flashlight_label"
@onready var FlashlightUI = $"../../../UI/FlashlightUI" #Control

# ОТДЕЛЬНЫЕ ЗВУКОВЫЕ КОМПОНЕНТЫ
@onready var audio_on: AudioStreamPlayer = $FlashlightAudioOn   # Звук включения
@onready var audio_off: AudioStreamPlayer = $FlashlightAudioOff # Звук выключения

# ============================================================================
# ИНИЦИАЛИЗАЦИЯ
# ============================================================================
func _ready():
	print("🔦 SimpleFlashlight ready!")
	
	# Добавляем фонарик в звуковую группу для настроек
	add_to_group("flashlight_sounds")
	add_to_group("ui_sounds")
	print("🔊 Flashlight добавлен в звуковые группы: flashlight_sounds, ui_sounds")
	
	# Проверяем компоненты
	if not flashlight_spot:
		print("WARNING: FlashlightSpot not found!")
	if not flashlight_area:
		print("WARNING: FlashlightArea not found!")
	
	# Проверяем аудио компоненты
	setup_audio_players()
	
	# Начинаем с выключенным фонариком
	set_flashlight_state(false)
	
	# Инициализируем UI лейбл
	init_status_label()
	
	# UI настройки
	if Switcher_label:
		Switcher_label.z_index = 1000
		print("🔦 [DEBUG] Switcher_label Z-Index установлен на 1000.")
		
		var parent_canvas_layer = Switcher_label.get_parent()
		while parent_canvas_layer and not (parent_canvas_layer is CanvasLayer):
			parent_canvas_layer = parent_canvas_layer.get_parent()
		
		if parent_canvas_layer:
			parent_canvas_layer.layer = 5
			print("🔦 [DEBUG] Родительский CanvasLayer установлен на слой 5.")
	
	# Подключаемся к системе день/ночь
	if is_instance_valid(DayNightManager):
		if not DayNightManager.night_started.is_connected(_on_night_started):
			DayNightManager.night_started.connect(_on_night_started)
	else:
		printerr("SimpleFlashlight.gd: DayNightManager не найден.")

func setup_audio_players():
	"""Настройка аудио плееров"""
	# Настройка плеера включения
	if audio_on:
		audio_on.volume_db = linear_to_db(sound_volume)
		# ПРОСТАЯ ШИНА - SFX или Master
		if AudioServer.get_bus_index("SFX") >= 0:
			audio_on.bus = "SFX"
		else:
			audio_on.bus = "Master"
		
		if flashlight_on_sound:
			audio_on.stream = flashlight_on_sound
		print("🔊 Audio ON configured! Bus: %s" % audio_on.bus)
	else:
		print("WARNING: FlashlightAudioOn not found!")
	
	# Настройка плеера выключения
	if audio_off:
		audio_off.volume_db = linear_to_db(sound_volume)
		# ПРОСТАЯ ШИНА - SFX или Master
		if AudioServer.get_bus_index("SFX") >= 0:
			audio_off.bus = "SFX"
		else:
			audio_off.bus = "Master"
		
		if flashlight_off_sound:
			audio_off.stream = flashlight_off_sound
		print("🔊 Audio OFF configured! Bus: %s" % audio_off.bus)
	else:
		print("WARNING: FlashlightAudioOff not found!")

func init_status_label():
	"""Инициализирует лейбл статуса"""
	if Switcher_label:
		Switcher_label.visible = false
		Switcher_label.modulate.a = 0.0
		print("🔦 Status label инициализирован (скрыт).")
	else:
		printerr("SimpleFlashlight.gd: Switcher_label не найден!")

# ============================================================================
# INPUT HANDLING
# ============================================================================
func _input(event):
	"""Переключение фонарика"""
	if event.is_action_pressed("toggle_flashlight"):
		print("🔦 Flashlight input received!")
		toggle_flashlight()
	
	# ТЕСТ ЗВУКОВ НА КЛАВИШУ T
	if event.is_action_pressed("ui_select"):
		test_flashlight_sounds()

func _process(delta):
	"""Регулировка яркости в реальном времени"""
	if flashlight_enabled:
		var power_changed = false
		
		if Input.is_key_pressed(KEY_EQUAL) or Input.is_key_pressed(KEY_KP_ADD):
			var old_power = flashlight_power
			flashlight_power = min(flashlight_power + delta * 3.0, 10.0)
			if flashlight_power != old_power:
				power_changed = true
				
		elif Input.is_key_pressed(KEY_MINUS) or Input.is_key_pressed(KEY_KP_SUBTRACT):
			var old_power = flashlight_power
			flashlight_power = max(flashlight_power - delta * 3.0, 0.5)
			if flashlight_power != old_power:
				power_changed = true
		
		if power_changed:
			update_flashlight_brightness()
			if fmod(flashlight_power * 10, 5) < 0.01:
				print("🔦 Яркость: ", snappedf(flashlight_power, 0.1))

# ============================================================================
# УПРАВЛЕНИЕ ФОНАРИКОМ
# ============================================================================
func toggle_flashlight():
	"""Включить/выключить фонарик со звуком"""
	flashlight_enabled = not flashlight_enabled
	set_flashlight_state(flashlight_enabled)
	
	# Воспроизводим звук
	play_flashlight_sound(flashlight_enabled)
	
	# Показываем анимированный статус
	show_flashlight_status_animated()

func set_flashlight_state(enabled: bool):
	"""Установка состояния фонарика"""
	flashlight_enabled = enabled
	
	if flashlight_spot:
		flashlight_spot.visible = enabled
		if enabled:
			flashlight_spot.light_energy = flashlight_power
			print("🔦 Фонарик ВКЛЮЧЕН (мощность: ", snappedf(flashlight_power, 0.1), ")")
		else:
			print("🔦 Фонарик ВЫКЛЮЧЕН")
			
	if flashlight_area:
		flashlight_area.visible = enabled
		if enabled:
			flashlight_area.light_energy = flashlight_power * 0.3

func update_flashlight_brightness():
	"""Обновление яркости без перезапуска"""
	if flashlight_enabled and flashlight_spot:
		flashlight_spot.light_energy = flashlight_power
	if flashlight_enabled and flashlight_area:
		flashlight_area.light_energy = flashlight_power * 0.3

# ============================================================================
# ЗВУКОВАЯ СИСТЕМА
# ============================================================================
func play_flashlight_sound(turning_on: bool):
	"""Воспроизводит звук включения или выключения фонарика"""
	if not sound_enabled:
		print("🔊 Звуки фонарика отключены")
		return
	
	if turning_on:
		if audio_on:
			audio_on.play()
			print("🔊 Играем звук ВКЛЮЧЕНИЯ")
		else:
			print("🔊 Audio ON player не найден!")
	else:
		if audio_off:
			audio_off.play()
			print("🔊 Играем звук ВЫКЛЮЧЕНИЯ")
		else:
			print("🔊 Audio OFF player не найден!")

func set_sound_volume(volume: float):
	"""Устанавливает громкость звуков фонарика"""
	sound_volume = clamp(volume, 0.0, 1.0)
	var volume_db = linear_to_db(sound_volume)
	
	if audio_on:
		audio_on.volume_db = volume_db
	if audio_off:
		audio_off.volume_db = volume_db
	
	print("🔊 Громкость фонарика установлена на: %.1f" % sound_volume)

func set_sound_enabled(enabled: bool):
	"""Включает/выключает звуки фонарика"""
	sound_enabled = enabled
	print("🔊 Звуки фонарика ", "ВКЛЮЧЕНЫ" if enabled else "ВЫКЛЮЧЕНЫ")

func get_sound_volume() -> float:
	"""Возвращает текущую громкость"""
	return sound_volume

func is_sound_enabled() -> bool:
	"""Проверяет, включены ли звуки"""
	return sound_enabled

func test_flashlight_sounds():
	"""Тестовая функция для проверки звуков"""
	if not sound_enabled:
		print("🔊 Звуки отключены, тест невозможен")
		return
		
	print("🔊 Тестируем звуки фонарика...")
	
	# Тест звука включения
	if audio_on:
		audio_on.play()
		print("🔊 Тест звука ВКЛЮЧЕНИЯ")
	else:
		print("🔊 Audio ON не найден")
	
	# Через 1 секунду тест звука выключения
	await get_tree().create_timer(1.0).timeout
	
	if audio_off:
		audio_off.play()
		print("🔊 Тест звука ВЫКЛЮЧЕНИЯ")
	else:
		print("🔊 Audio OFF не найден")

# ============================================================================
# ГЛОБАЛЬНЫЕ ЗВУКОВЫЕ ФУНКЦИИ ДЛЯ МЕНЮ
# ============================================================================
func apply_global_sound_settings(volume: float, enabled: bool):
	"""Применяет глобальные настройки звука"""
	set_sound_volume(volume)
	set_sound_enabled(enabled)
	print("🔊 Применены глобальные настройки: громкость=%.1f, включено=%s" % [volume, enabled])

# ============================================================================
# АНИМАЦИЯ СТАТУСА
# ============================================================================
func show_flashlight_status_animated():
	"""Показывает анимированный статус ON/OFF"""
	if not Switcher_label:
		printerr("🔦 Switcher_label не найден!")
		return
	
	var status_text: String
	var status_color: Color
	
	if flashlight_enabled:
		status_text = "🔦 ON"
		status_color = Color(0.3, 1.0, 0.3) # Зеленый
	else:
		status_text = "🔦 OFF"
		status_color = Color(1.0, 0.4, 0.4) # Красный
	
	print("🔦 Показываем статус: %s" % status_text)
	
	stop_current_status_animation()
	
	Switcher_label.text = status_text
	Switcher_label.modulate = status_color
	Switcher_label.visible = true
	Switcher_label.modulate.a = 0.0
	Switcher_label.scale = Vector2(0.5, 0.5)

	var status_tween = create_tween()
	Switcher_label.set_meta("status_tween", status_tween)
	
	# Анимация появления с подпрыгиванием
	status_tween.parallel() \
		.tween_property(Switcher_label, "modulate:a", 1.0, 0.2) \
		.set_ease(Tween.EASE_OUT) \
		.set_trans(Tween.TRANS_QUAD)
	status_tween.parallel() \
		.tween_property(Switcher_label, "scale", Vector2(1.2, 1.2), 0.2) \
		.set_ease(Tween.EASE_OUT) \
		.set_trans(Tween.TRANS_QUAD)
	
	# Оседание масштаба
	status_tween.tween_property(Switcher_label, "scale", Vector2(1.0, 1.0), 0.2) \
		.set_ease(Tween.EASE_IN) \
		.set_trans(Tween.TRANS_QUAD)
	
	# Пауза показа
	status_tween.tween_interval(5.0)
	
	# Исчезновение
	status_tween.tween_property(Switcher_label, "modulate:a", 0.0, 0.5) \
		.set_ease(Tween.EASE_IN) \
		.set_trans(Tween.TRANS_LINEAR)
	
	# Скрытие
	status_tween.tween_callback(func():
		Switcher_label.visible = false
		Switcher_label.scale = Vector2(1.0, 1.0)
	)

func stop_current_status_animation():
	"""Останавливает текущую анимацию статуса"""
	if not Switcher_label:
		return
	
	if Switcher_label.has_meta("status_tween"):
		var existing_tween = Switcher_label.get_meta("status_tween")
		if existing_tween and existing_tween.is_valid():
			existing_tween.kill()
			print("🔦 Предыдущая анимация статуса остановлена")
		Switcher_label.remove_meta("status_tween")

func quick_show_status(text: String, color: Color = Color.WHITE, duration: float = 2.0):
	"""Быстрый показ статуса без сложных эффектов"""
	if not Switcher_label:
		printerr("🔦 Switcher_label не найден!")
		return
	
	Switcher_label.text = text
	Switcher_label.modulate = color
	Switcher_label.visible = true
	
	stop_current_status_animation()
	
	var quick_tween = create_tween()
	
	Switcher_label.modulate.a = 0.0
	quick_tween.tween_property(Switcher_label, "modulate:a", 1.0, 0.2)
	quick_tween.tween_interval(duration)
	quick_tween.tween_property(Switcher_label, "modulate:a", 0.0, 0.3)
	quick_tween.tween_callback(func(): Switcher_label.visible = false)
	
	Switcher_label.set_meta("status_tween", quick_tween)



# ============================================================================
# EVENT HANDLERS
# ============================================================================
func _on_night_started(night_number: int):
	"""Сообщение о наступлении ночи"""
	print("🌙 Ночь ", night_number, " началась! Время доставать фонарик (F)")
	quick_show_status("🌙 Ночь началась! Нажми F", Color.CYAN, 3.0)

# ============================================================================
# API ДЛЯ ДРУГИХ СИСТЕМ
# ============================================================================
func get_flashlight_status() -> String:
	"""Статус для UI"""
	if flashlight_enabled:
		return "Включен (" + str(int(flashlight_power)) + "/10)"
	else:
		return "Выключен"

func is_flashlight_on() -> bool:
	return flashlight_enabled

func get_flashlight_power() -> float:
	return flashlight_power

func set_flashlight_power(power: float):
	"""Установить мощность программно"""
	flashlight_power = clamp(power, 0.5, 10.0)
	if flashlight_enabled:
		update_flashlight_brightness()

func is_audio_playing() -> bool:
	"""Проверяет, играет ли звук фонарика"""
	var on_playing = audio_on.playing if audio_on else false
	var off_playing = audio_off.playing if audio_off else false
	return on_playing or off_playing

func stop_flashlight_audio():
	"""Останавливает все звуки фонарика"""
	if audio_on and audio_on.playing:
		audio_on.stop()
	if audio_off and audio_off.playing:
		audio_off.stop()
	print("🔊 Все звуки фонарика остановлены")

func _exit_tree():
	"""Очистка при удалении узла"""
	stop_flashlight_audio()
	print("🔦 SimpleFlashlight removed from tree")
