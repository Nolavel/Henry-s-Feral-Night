# BackpackUI.gd - Control с анимацией появления рюкзака
extends Control

@export var backpack_image: Sprite2D  # Перетащи сюда изображение рюкзака в инспекторе
@export var animation_duration: float = 0.8
@export var scale_overshoot: float = 0.12  # Эффект "bounce"
@export var fade_in_delay: float = 0.1

# Переменные для анимации
var backpack_tween: Tween
var has_backpack: bool = false

func _ready():
	# Добавляем в группу для легкого поиска
	add_to_group("backpack_ui")
	print("BackpackUI: 🎒 Добавлен в группу 'backpack_ui'")
	
	# ОТЛАДКА: Показываем путь к узлу
	print("BackpackUI: 📍 Путь к узлу: %s" % get_path())
	print("BackpackUI: 👨‍👩‍👧‍👦 Родитель: %s" % get_parent().name)
	
	# Убедимся что изображение скрыто изначально
	if is_instance_valid(backpack_image):
		backpack_image.visible = false
		backpack_image.modulate = Color.TRANSPARENT
		backpack_image.scale = Vector2.ZERO
		print("BackpackUI: ✅ Инициализирован (изображение скрыто)")
	else:
		printerr("BackpackUI: ❌ backpack_image не назначен в инспекторе!")
		print("BackpackUI: 🔍 Ищем TextureRect детей...")
		for child in get_children():
			print("  - Ребенок: %s (%s)" % [child.name, child.get_class()])
			if child is TextureRect:
				print("    ^ Это TextureRect! Можно использовать как backpack_image")
func _on_backpack_picked_up(backpack_type: String):
	"""ГЛАВНАЯ ФУНКЦИЯ: Вызывается когда BackpackPickup отправляет сигнал"""
	print("BackpackUI: 🎒 Получен сигнал подбора рюкзака: %s" % backpack_type)
	
	if has_backpack:
		print("BackpackUI: ⚠️ Рюкзак уже показан, игнорируем")
		return
	
	if not is_instance_valid(backpack_image):
		printerr("BackpackUI: ❌ backpack_image не назначен! Анимация невозможна.")
		return
	
	# Запускаем анимацию появления
	show_backpack_with_animation(backpack_type)

func show_backpack_with_animation(backpack_type: String):
	"""Показывает рюкзак с красивой анимацией"""
	
	# Останавливаем предыдущую анимацию если есть
	if backpack_tween:
		backpack_tween.kill()
	
	# ТВОИ РАЗМЕРЫ: 0.092 нормальный, 0.12 bounce
	var normal_scale = Vector2(0.092, 0.092)  # Твой нормальный размер
	var overshoot_scale = Vector2(0.12, 0.12)  # 0.092 * 1.3 для bounce
	
	# Устанавливаем начальные значения
	backpack_image.visible = true
	backpack_image.modulate = Color.TRANSPARENT
	backpack_image.scale = Vector2.ZERO
	
	# Создаем новый Tween
	backpack_tween = create_tween()
	backpack_tween.set_parallel(true)  # Позволяет несколько анимаций одновременно
	
	# ФАЗА 1: Появление с масштабированием (bounce эффект)
	# Сначала быстро увеличиваем до overshoot размера (0.12)
	backpack_tween.tween_property(backpack_image, "scale", overshoot_scale, animation_duration * 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	
	# Потом плавно уменьшаем до нормального размера (0.092)
	backpack_tween.tween_property(backpack_image, "scale", normal_scale, animation_duration * 0.4).set_delay(animation_duration * 0.6).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	
	# ФАЗА 2: Fade in (появление прозрачности)
	backpack_tween.tween_property(backpack_image, "modulate", Color.WHITE, animation_duration * 0.7).set_delay(fade_in_delay)
	
	# ФАЗА 3: Легкое покачивание в конце для привлечения внимания
	backpack_tween.tween_callback(add_subtle_bounce_effect).set_delay(animation_duration)
	
	# Обновляем состояние
	has_backpack = true
	
	print("BackpackUI: ✨ Анимация появления рюкзака '%s' запущена! (0.0 → 0.12 → 0.092)" % backpack_type)

func add_subtle_bounce_effect():
	"""Добавляет тонкий bounce эффект в конце анимации"""
	if not is_instance_valid(backpack_image):
		return
	
	var bounce_tween = create_tween()
	bounce_tween.set_loops(2)  # 2 раза подпрыгнет
	
	# Легкое увеличение и уменьшение (0.092 ↔ 0.099)
	bounce_tween.tween_property(backpack_image, "scale", Vector2(0.099, 0.099), 0.15)
	bounce_tween.tween_property(backpack_image, "scale", Vector2(0.092, 0.092), 0.15)
	
	print("BackpackUI: 🎈 Bounce эффект завершен! (0.092 ↔ 0.099)")

func hide_backpack_with_animation():
	"""Скрывает рюкзак с анимацией (если нужно будет)"""
	if not has_backpack or not is_instance_valid(backpack_image):
		return
	
	# Останавливаем предыдущую анимацию
	if backpack_tween:
		backpack_tween.kill()
	
	# Создаем анимацию исчезновения
	backpack_tween = create_tween()
	backpack_tween.set_parallel(true)
	
	# Fade out + уменьшение
	backpack_tween.tween_property(backpack_image, "modulate", Color.TRANSPARENT, 0.4)
	backpack_tween.tween_property(backpack_image, "scale", Vector2.ZERO, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	
	# Скрываем в конце
	backpack_tween.tween_callback(func(): backpack_image.visible = false).set_delay(0.4)
	
	has_backpack = false
	print("BackpackUI: 👻 Анимация скрытия рюкзака запущена!")

# === PUBLIC API ===

func is_backpack_visible() -> bool:
	"""Проверяет, виден ли рюкзак в UI"""
	return has_backpack

func set_backpack_image_texture(texture: Texture2D):
	"""Устанавливает текстуру рюкзака"""
	if is_instance_valid(backpack_image):
		backpack_image.texture = texture
		print("BackpackUI: 🖼️ Текстура рюкзака обновлена")

func get_backpack_visibility() -> bool:
	"""Возвращает видимость рюкзака"""
	return has_backpack and is_instance_valid(backpack_image) and backpack_image.visible
