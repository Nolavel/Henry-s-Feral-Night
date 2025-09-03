# ✅ Script: ComicEffects.gd 
# (Eng) Handles comic-style UI effects with object pooling, shows shit like hits and explosions
# (Rus) Управляет комиксными UI эффектами с пулом объектов, показывает всякую фигню типа попаданий и взрывов
# ⚡ Prototype — demo mechanics, just for test / прототип механики, на пробу

extends Node

# (Eng) Pool constants - limit this crap so it doesn't eat all memory
# (Rus) Константы пула - ограничиваем эту фигню чтобы не сжирала всю память
const POOL_SIZE = 6
const MAX_ACTIVE_EFFECTS = 4

# (Eng) Effect types - what kind of visual bullshit we can spawn
# (Rus) Типы эффектов - какую визуальную фигню можем заспавнить
enum EffectType {
	PLAYER_SHOOT,
	PLAYER_HIT,
	PLAYER_DEATH,
	ENEMY_HIT,
	ENEMY_DEATH,
	EXPLOSION,
	HEADSHOT,
	PICKUP,
	OBJECT_HIT
}

# (Eng) Cached references - keep this shit ready so we don't search every time
# (Rus) Кешированные ссылки - держим эту фигню готовой чтобы не искать каждый раз
var effect_scene: PackedScene
var effect_pool: Array = []
var active_effects: Array = []
var canvas_layer: CanvasLayer
var cached_camera: Camera3D

# (Eng) Reusable variables - avoid creating new shit every frame
# (Rus) Переиспользуемые переменные - избегаем создания новой фигни каждый кадр
var temp_world_pos: Vector3
var temp_screen_pos: Vector2
var temp_viewport_size: Vector2

func _ready():
	print("ComicEffects: Инициализация оптимизированной системы эффектов")
	
	# (Eng) Load effect scene - grab our visual effect template
	# (Rus) Загружаем сцену эффекта - берём шаблон визуального эффекта
	var scene_path = "res://Global_scripts/ComicEffectUI.tscn"
	if ResourceLoader.exists(scene_path):
		effect_scene = load(scene_path)
		print("ComicEffects: Сцена эффекта загружена")
	else:
		printerr("ComicEffects: ОШИБКА! Файл не найден: %s" % scene_path)
		return
	
	# (Eng) Deferred initialization - wait for scene tree to be ready
	# (Rus) Отложенная инициализация - ждём пока дерево сцены будет готово
	call_deferred("deferred_setup")

func deferred_setup():
	# (Eng) Deferred setup after _ready() completion - avoid initialization race conditions
	# (Rus) Отложенная настройка после завершения _ready() - избегаем гонок инициализации
	setup_canvas_layer()
	create_effect_pool()
	temp_viewport_size = get_viewport().size
	print("ComicEffects: Отложенная инициализация завершена")

func setup_canvas_layer():
	# (Eng) Create CanvasLayer once - UI container for all our visual spam
	# (Rus) Создаём CanvasLayer один раз - UI контейнер для всего нашего визуального спама
	canvas_layer = CanvasLayer.new()
	canvas_layer.name = "ComicEffectsLayer"
	canvas_layer.layer = 100
	get_tree().root.add_child(canvas_layer)
	print("ComicEffects: CanvasLayer создан")

func create_effect_pool():
	# (Eng) Create fixed pool of 6 effects - pre-made objects to avoid allocation hell
	# (Rus) Создаём фиксированный пул из 6 эффектов - заготовленные объекты чтобы избежать ада аллокаций
	if not effect_scene:
		printerr("ComicEffects: Не удалось создать пул - сцена не загружена")
		return
	
	for i in range(POOL_SIZE):
		var effect = effect_scene.instantiate()
		if effect:
			canvas_layer.add_child(effect)
			effect.visible = false
			effect_pool.append(effect)
		else:
			printerr("ComicEffects: Не удалось создать эффект #%d" % i)
	
	print("ComicEffects: Пул из %d эффектов создан" % effect_pool.size())

func show_effect_on_node(target_node: Node3D, effect_type: EffectType, custom_text: String = ""):
	# (Eng) Optimized effect display - show visual feedback without killing performance
	# (Rus) Оптимизированный показ эффекта - показываем визуальную отдачу не убивая производительность
	if not is_instance_valid(target_node):
		return
	
	# (Eng) Limit active effects - kick out oldest if we hit the limit
	# (Rus) Ограничиваем активные эффекты - выкидываем самый старый если достигли лимита
	if active_effects.size() >= MAX_ACTIVE_EFFECTS:
		var oldest_effect = active_effects[0]
		force_return_to_pool(oldest_effect)
	
	var effect = get_pooled_effect()
	if not effect:
		return
	
	# (Eng) Reuse temp variables - don't create new Vector3/Vector2 every call
	# (Rus) Переиспользуем временные переменные - не создаём новые Vector3/Vector2 каждый вызов
	temp_world_pos = target_node.global_position
	temp_world_pos.y += randf_range(1.0, 2.5)
	
	temp_screen_pos = get_screen_position_optimized(temp_world_pos)
	
	# (Eng) Random offset - make effects feel more alive and less robotic
	# (Rus) Случайное смещение - делаем эффекты более живыми и менее роботическими
	temp_screen_pos.x += randf_range(-80, 80)
	temp_screen_pos.y += randf_range(-60, 40)
	
	# (Eng) Clamp to screen bounds - keep effects visible on screen
	# (Rus) Ограничиваем границами экрана - держим эффекты видимыми на экране
	temp_screen_pos.x = clamp(temp_screen_pos.x, 50, temp_viewport_size.x - 100)
	temp_screen_pos.y = clamp(temp_screen_pos.y, 50, temp_viewport_size.y - 100)
	
	effect.setup_optimized(temp_screen_pos, effect_type, custom_text)
	effect.play_animation_optimized()

func show_effect_attached(target_node: Node3D, effect_type: EffectType, offset: Vector3 = Vector3(0, 1.5, 0), custom_text: String = ""):
	# (Eng) Alternative function with custom offset - more precise effect positioning
	# (Rus) Альтернативная функция с кастомным смещением - более точное позиционирование эффекта
	if not is_instance_valid(target_node):
		return
	
	if active_effects.size() >= MAX_ACTIVE_EFFECTS:
		var oldest_effect = active_effects[0]
		force_return_to_pool(oldest_effect)
	
	var effect = get_pooled_effect()
	if not effect:
		return
	
	temp_world_pos = target_node.global_position + offset
	temp_screen_pos = get_screen_position_optimized(temp_world_pos)
	
	temp_screen_pos.x += randf_range(-50, 50)
	temp_screen_pos.y += randf_range(-30, 30)
	
	effect.setup_optimized(temp_screen_pos, effect_type, custom_text)
	effect.play_animation_optimized()

func get_screen_position_optimized(world_pos: Vector3) -> Vector2:
	# (Eng) Optimized screen position calculation - cache camera to avoid repeated searches
	# (Rus) Оптимизированный расчёт экранной позиции - кешируем камеру чтобы избежать повторных поисков
	if not cached_camera:
		cached_camera = get_viewport().get_camera_3d()
		if not cached_camera:
			return Vector2(temp_viewport_size.x * 0.5, temp_viewport_size.y * 0.5)
	
	var screen_pos = cached_camera.unproject_position(world_pos)
	
	# (Eng) Check if position is within screen bounds - fallback to center if off-screen
	# (Rus) Проверяем что позиция в пределах экрана - откат к центру если за экраном
	if screen_pos.x < 0 or screen_pos.x > temp_viewport_size.x or screen_pos.y < 0 or screen_pos.y > temp_viewport_size.y:
		return Vector2(temp_viewport_size.x * 0.5, temp_viewport_size.y * 0.5)
	
	return screen_pos

func get_pooled_effect():
	# (Eng) Optimized pool management - grab free effect or recycle oldest one
	# (Rus) Оптимизированное управление пулом - берём свободный эффект или перерабатываем старый
	for effect in effect_pool:
		if not effect.visible:
			effect_pool.erase(effect)
			active_effects.append(effect)
			return effect
	
	# (Eng) All effects busy, recycle the oldest bastard
	# (Rus) Все эффекты заняты, перерабатываем самую старую фигню
	if active_effects.size() > 0:
		var oldest_effect = active_effects[0]
		force_return_to_pool(oldest_effect)
		return get_pooled_effect()  # Рекурсивный вызов
	
	printerr("ComicEffects: Критическая ошибка - нет доступных эффектов!")
	return null

func return_effect_to_pool(effect):
	# (Eng) Return effect to pool - clean up and make available for reuse
	# (Rus) Возвращаем эффект в пул - убираем и делаем доступным для переиспользования
	if effect in active_effects:
		active_effects.erase(effect)
	
	if effect not in effect_pool:
		effect_pool.append(effect)
		effect.visible = false

func force_return_to_pool(effect):
	# (Eng) Forcefully return effect to pool - stop whatever it's doing right now
	# (Rus) Принудительно возвращаем эффект в пул - останавливаем что бы он там ни делал
	if effect.has_method("force_stop"):
		effect.force_stop()
	else:
		effect.visible = false
	
	return_effect_to_pool(effect)

func show_effect_on_all_in_group(group_name: String, effect_type: EffectType, custom_text: String = ""):
	# (Eng) Group effects with limit - show effects on multiple objects without going nuts
	# (Rus) Групповые эффекты с лимитом - показываем эффекты на нескольких объектах не сходя с ума
	var nodes = get_tree().get_nodes_in_group(group_name)
	var count = 0
	
	for node in nodes:
		if node is Node3D and count < MAX_ACTIVE_EFFECTS:
			show_effect_on_node(node, effect_type, custom_text)
			count += 1

func _notification(what):
	# (Eng) Cleanup on focus loss - clear effects when window loses focus
	# (Rus) Очистка при потере фокуса - убираем эффекты когда окно теряет фокус
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		clear_all_effects()

func clear_all_effects():
	# (Eng) Clear all active effects - force reset everything to pool
	# (Rus) Очищаем все активные эффекты - принудительно сбрасываем всё в пул
	for effect in active_effects.duplicate():
		force_return_to_pool(effect)

func get_pool_status() -> String:
	# (Eng) Debug function - returns pool status for troubleshooting
	# (Rus) Отладочная функция - возвращает статус пула для траблшутинга
	return "Пул: %d свободных, %d активных" % [effect_pool.size(), active_effects.size()]
