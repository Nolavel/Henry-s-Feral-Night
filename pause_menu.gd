extends Control # Или CanvasLayer, в зависимости от корневого узла. Control - более универсальный выбор, если не нужен CanvasLayer для конкретных целей.

@onready var continue_button = $UI_PauseMenu/Background/Continue
@onready var quit_button = $UI_PauseMenu/Background/Quit

func _ready():
	# Убедитесь, что меню паузы обрабатывает ввод, даже если игра на паузе.
	# Это позволит вам нажимать кнопки в меню.
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	# Подключаем сигналы кнопок
	if continue_button:
		continue_button.pressed.connect(on_continue_button_pressed)
	else:
		print("❌ Continue button не найдена! Проверьте путь: %s" % continue_button.get_path())
	
	if quit_button:
		quit_button.pressed.connect(on_quit_button_pressed) # Используем простую функцию выхода
		# quit_button.pressed.connect(on_quit_button_pressed_with_countdown) # Или эту
		# quit_button.pressed.connect(on_quit_button_pressed_with_confirmation) # Или эту, если нужна более сложная логика
	else:
		print("❌ Quit button не найдена! Проверьте путь: %s" % quit_button.get_path())
	
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE) # Показать курсор мыши
	
	fade_in() # Вызываем плавное появление меню при его создании

func on_continue_button_pressed():
	await fade_out()
	
	if is_instance_valid(GameManager):
		GameManager.toggle_pause()
	else:
		print("Ошибка: GameManager не найден. Проверьте настройки Autoload.")
	
	# УБИРАЕМ эту строку - курсором управляет только SystemCamera
	# Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN) # УДАЛИТЬ

func on_quit_button_pressed():
	print("Выход из игры через 1 секунду...")
	
	# Отключаем кнопки, чтобы нельзя было нажать повторно
	if continue_button:
		continue_button.disabled = true
	if quit_button:
		quit_button.disabled = true
		quit_button.text = "Выход..." # Меняем текст кнопки
	
	# Сначала плавно исчезаем меню
	await fade_out()
	
	# Создаем таймер на 1 секунду
	await get_tree().create_timer(1.0).timeout
	
	# Выходим из игры
	print("Выход из игры!")
	get_tree().quit()

# Альтернативный метод с обратным отсчетом
func on_quit_button_pressed_with_countdown():
	print("Выход из игры через 3 секунды...")
	
	# Отключаем кнопки
	if continue_button:
		continue_button.disabled = true
	if quit_button:
		quit_button.disabled = true
	
	# Сначала плавно исчезаем меню
	await fade_out() # Добавляем плавное исчезновение здесь тоже
	
	# Обратный отсчет
	for i in range(3, 0, -1):
		if quit_button:
			quit_button.text = "Выход через " + str(i) + "..."
		await get_tree().create_timer(1.0).timeout
	
	# Выходим из игры
	print("Выход из игры!")
	get_tree().quit()

# Функция для отмены выхода (если нужно)
func cancel_quit():
	# Включаем кнопки обратно
	if continue_button:
		continue_button.disabled = false
	if quit_button:
		quit_button.disabled = false
		quit_button.text = "Quit" # Возвращаем оригинальный текст
		
# Добавьте эту функцию в PauseMenu.gd
func on_quit_button_pressed_with_confirmation():
	print("Подтверждение выхода...")
	
	# Создаем диалог подтверждения
	var confirmation_dialog = AcceptDialog.new()
	confirmation_dialog.dialog_text = "Вы действительно хотите выйти из игры?"
	confirmation_dialog.title = "Подтверждение"
	confirmation_dialog.add_cancel_button("Отмена")
	
	# Добавляем диалог в сцену
	add_child(confirmation_dialog)
	confirmation_dialog.popup_centered()
	
	# Ждем ответа пользователя
	var result = await confirmation_dialog.confirmed # confirmation_dialog.confirmed будет true, если нажата OK
	
	# Важно: if confirmation_dialog.confirmed: не работает так, как ожидается.
	# Вместо этого, подтверждение должно быть получено через await signal.
	# Если пользователь нажал OK, signal confirmed будет испущен.
	# Если пользователь нажал Cancel, signal cancelled будет испущен.
	# Лучше использовать AcceptDialog.canceled или AcceptDialog.custom_action
	# для обработки отмены. Но для простоты:

	if result: # Если сигнал confirmed был получен
		print("Выход подтвержден. Выход через 1 секунду...")
		if quit_button: # Проверка на null
			quit_button.text = "Выход..."
		
		# Сначала плавно исчезаем меню
		await fade_out()
		
		await get_tree().create_timer(1.0).timeout
		get_tree().quit()
	else: # Если диалог был закрыт без подтверждения (например, Cancel или ESC)
		print("Выход отменен.")
	
	# Удаляем диалог
	confirmation_dialog.queue_free()

# 5. Функция для плавного появления меню
func fade_in():
	modulate.a = 0.0 # Начинаем с полностью прозрачного
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT) # Для более приятной анимации
	tween.set_trans(Tween.TRANS_QUAD) # Тип перехода
	tween.tween_property(self, "modulate:a", 1.0, 0.3) # Анимируем прозрачность до 1.0 за 0.3 секунды
	await tween.finished # Ждем завершения анимации

# 6. Функция для плавного исчезновения меню
func fade_out():
	var tween = create_tween()
	tween.set_ease(Tween.EASE_IN) # Для более приятной анимации
	tween.set_trans(Tween.TRANS_QUAD) # Тип перехода
	tween.tween_property(self, "modulate:a", 0.0, 0.3) # Анимируем прозрачность до 0.0 за 0.3 секунды
	await tween.finished # Ждем завершения анимации
