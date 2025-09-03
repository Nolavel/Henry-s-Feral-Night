# ✅ Script: CameraFollow.gd  
# (Eng) Improved camera system with dead zone clusterfuck, mode switching nightmare and all that performance-destroying optimization bullshit
# (Rus) Улучшенная система камеры с пиздецом мёртвых зон, кошмаром переключения режимов и всей этой производительность-убивающей оптимизационной хуйнёй
# 🔧 WIP ⚡ Prototype 🐛 Not Optimized — raw, unfinished crap, demo mechanics, eats resources / сырая, незавершённая хуйня, демо-механика, жрёт ресурсы

extends Camera3D

# (Eng) Basic camera settings - hardcoded dependencies because proper reference system is too advanced
# (Rus) Базовые настройки камеры - хардкод зависимостей потому что нормальная система ссылок слишком продвинута
@export var target_path: NodePath
@export var follow_speed = 5.0
@export var start_camera_point: NodePath

# (Eng) Camera mode explosion - boolean flags and transition speeds because proper state machine is rocket science
# (Rus) Взрыв режимов камеры - булевые флаги и скорости перехода потому что нормальная машина состояний это ракетостроение
@export var is_isometric: bool = true
@export var transition_speed: float = 3.0  # Скорость переключения между режимами

# (Eng) Isometric camera settings hell - dozens of exported variables because data-driven design is apparently illegal
# (Rus) Ад настроек изометрической камеры - дюжины экспортируемых переменных потому что дата-дривен дизайн видимо незаконен
@export var isometric_rotation_x_degrees = -30.0 
@export var isometric_rotation_y_degrees = 45.0 
@export var isometric_offset_from_target = Vector3(0, 0, 0) 
@export var base_isometric_size = 15.0 
@export var zoom_speed_isometric = 1.0
@export var min_isometric_size = 5.0 
@export var max_isometric_size = 25.0 

# (Eng) Top-Down camera settings clusterfuck - duplicate configuration hell because consistency is dead
# (Rus) Пиздец настроек top-down камеры - ад дублирования конфигурации потому что последовательность мертва
@export var topdown_rotation_x_degrees = -90.0  # Смотрим строго вниз
@export var topdown_rotation_y_degrees = 0.0    # Без поворота по Y
@export var topdown_offset = Vector3(0, 20, 0)  # Высота над игроком
@export var base_topdown_size = 18.0            # Базовый размер для top-down
@export var zoom_speed_topdown = 2.0
@export var min_topdown_size = 10.0
@export var max_topdown_size = 28.0

# (Eng) Dead Zone configuration nightmare - overcomplicated cursor following system for what should be simple camera movement
# (Rus) Кошмар конфигурации мёртвой зоны - перекомплексная система следования за курсором для того что должно быть простым движением камеры
@export_group("Dead Zone")
@export var enable_dead_zone: bool = false:
	set(value):
		enable_dead_zone = value
		if not value:
			_dead_zone_offset = Vector3.ZERO

@export_range(0.0, 1.0) var dead_zone_width: float = 0.3
@export_range(0.0, 1.0) var dead_zone_height: float = 0.3
@export var show_dead_zone_debug: bool = false

# (Eng) Auto-centering settings hell - automatic camera movement because manual control is apparently too hard for players
# (Rus) Ад настроек автоцентрирования - автоматическое движение камеры потому что ручное управление видимо слишком сложно для игроков
@export_subgroup("Auto-Centering")
@export var enable_auto_centering: bool = true
@export_range(0.5, 10.0) var auto_center_delay: float = 2.0
@export_range(0.1, 2.0) var auto_center_speed: float = 0.3

# (Eng) Dead Zone smoothing overkill - complex interpolation for simple camera movement because direct control would be too responsive
# (Rus) Оверкилл сглаживания мёртвой зоны - сложная интерполяция для простого движения камеры потому что прямое управление было бы слишком отзывчивым
@export_subgroup("Dead Zone Smoothing")
@export_range(0.1, 2.0) var dead_zone_smoothing: float = 0.8
@export_range(0.01, 0.1) var dead_zone_threshold: float = 0.02

# (Eng) Node references - target hunting because proper dependency injection is too professional
# (Rus) Ссылки на узлы - охота за целью потому что нормальное внедрение зависимостей слишком профессионально
var target: Node3D = null

# (Eng) Transition state hell - multiple variables to track mode switching because proper state management is apparently impossible
# (Rus) Ад переходного состояния - множественные переменные для отслеживания переключения режимов потому что нормальное управление состоянием видимо невозможно
var target_is_isometric: bool = true  # Целевой режим
var current_rotation_x: float
var current_rotation_y: float
var current_size: float
var current_offset: Vector3

# (Eng) Shake variables - screen shake because visual feedback is more important than player vision
# (Rus) Переменные тряски - тряска экрана потому что визуальная обратная связь важнее зрения игрока
var shake_duration = 0.0
var shake_intensity = 0.0
var shake_timer = 0.0
var current_shake_offset = Vector3.ZERO

# (Eng) Dead Zone state tracking explosion - dozens of variables because proper data structures are too advanced
# (Rus) Взрыв отслеживания состояния мёртвой зоны - дюжины переменных потому что нормальные структуры данных слишком продвинуты
var _dead_zone_offset = Vector3.ZERO
var _dead_zone_camera_position = Vector3.ZERO
var _last_input_time_msec: int = 0
var _is_auto_centering: bool = false
var _player_last_position: Vector3 = Vector3.ZERO
var _debug_dead_zone_overlay: Control = null

# (Eng) Dynamic camera settings - more zoom bullshit because simple camera control is too boring
# (Rus) Настройки динамической камеры - больше зум херни потому что простое управление камерой слишком скучно
@export_group("Dynamic Camera")
@export var dynamic_size_enabled: bool = true
@export var sprint_zoom_out: float = 2.0
@export var aim_zoom_in: float = -3.0
@export var size_transition_speed: float = 4.0

var base_camera_size: float
var target_size_modifier: float = 0.0

# (Eng) UI and sound references - hardcoded paths because proper asset management is too complex
# (Rus) Ссылки UI и звуков - хардкод путей потому что нормальное управление ассетами слишком сложно
@onready var camera_mode_label = $"../UI/camera_mode_label"
@onready var transition_camera_sound = $TransitionCameraSound
@onready var zoom_camera_sound = $ZoomCameraSound
@onready var LimitReachedSound = $LimitReachedSound

# (Eng) "Performance optimization" hell - caching that gets invalidated constantly and counters that count nothing useful
# (Rus) Ад "оптимизации производительности" - кеширование которое постоянно инвалидируется и счётчики которые считают ничего полезного
var _cached_viewport_size: Vector2
var _viewport_size_dirty: bool = true
var _cached_transform: Transform3D
var _transform_dirty: bool = true

# (Eng) Update frequency control nightmare - frame counting because running logic every frame is apparently too expensive
# (Rus) Кошмар контроля частоты обновлений - подсчёт кадров потому что запуск логики каждый кадр видимо слишком дорог
var _dead_zone_update_counter: int = 0
const DEAD_ZONE_UPDATE_FREQUENCY: int = 2
var _movement_check_timer: float = 0.0
const MOVEMENT_CHECK_INTERVAL: float = 0.1

# (Eng) Sound batching hell - queue system to prevent audio spam but still process audio every frame like idiots
# (Rus) Ад батчинга звуков - система очередей чтобы предотвратить спам аудио но всё равно процессить аудио каждый кадр как дебилы
var _sound_queue: Array[AudioStreamPlayer] = []
var _sound_process_timer: float = 0.0
const SOUND_PROCESS_INTERVAL: float = 0.05

# (Eng) Tween pooling clusterfuck - object pooling for animations because garbage collection is apparently the end of the world
# (Rus) Пиздец пулинга твинов - пулинг объектов для анимаций потому что сборка мусора видимо конец света
var _tween_pool: Array[Tween] = []
var _active_tweens: Array[Tween] = []
var _is_tweening = false

func _ready():
	# (Eng) Initialization clusterfuck - setup everything in one giant function because modular initialization is too hard
	# (Rus) Пиздец инициализации - настраиваем всё в одной гигантской функции потому что модульная инициализация слишком сложна
	base_camera_size = current_size
	
	# (Eng) Target hunting expedition - search for player in multiple ways because proper references are rocket science
	# (Rus) Экспедиция поиска цели - ищем игрока несколькими способами потому что нормальные ссылки это ракетостроение
	if target_path:
		target = get_node(target_path)
	else:
		target = get_tree().get_first_node_in_group("player") 
	
	if target == null:
		printerr("CameraFollow: Target node not found! Set 'target_path' in inspector.")
	
	# (Eng) Setup cascade hell - call multiple setup functions because single initialization would be too simple
	# (Rus) Ад каскада настройки - вызываем множественные функции настройки потому что единая инициализация была бы слишком простой
	target_is_isometric = is_isometric
	setup_camera_mode()
	create_camera_mode_ui()
	
	# (Eng) Dead Zone initialization nightmare - complex setup for overcomplicated camera system
	# (Rus) Кошмар инициализации мёртвой зоны - сложная настройка для перекомплексной системы камеры
	if enable_dead_zone and target:
		_dead_zone_camera_position = global_position
		_player_last_position = target.global_position
		_last_input_time_msec = Time.get_ticks_msec()
	
	_create_debug_overlay()
	
	# (Eng) Event subscription hell - connect to viewport changes because cache invalidation is performance critical apparently
	# (Rus) Ад подписки на события - подключаемся к изменениям viewport потому что инвалидация кеша видимо критична для производительности
	get_viewport().size_changed.connect(_on_viewport_resized)
	
	add_to_group("game_camera_group") 

func setup_camera_mode():
	# (Eng) Camera mode setup - hardcode projection settings because flexible camera system is too advanced
	# (Rus) Настройка режима камеры - хардкод настроек проекции потому что гибкая система камеры слишком продвинута
	projection = PROJECTION_ORTHOGONAL  # Оба режима используют ортогональную проекцию
	
	# (Eng) Mode-specific configuration hell - duplicate logic for each mode because polymorphism is scary
	# (Rus) Ад конфигурации специфичной для режима - дублируем логику для каждого режима потому что полиморфизм страшен
	if is_isometric:
		current_rotation_x = isometric_rotation_x_degrees
		current_rotation_y = isometric_rotation_y_degrees
		current_size = base_isometric_size
		current_offset = isometric_offset_from_target
	else:
		current_rotation_x = topdown_rotation_x_degrees
		current_rotation_y = topdown_rotation_y_degrees
		current_size = base_topdown_size
		current_offset = topdown_offset
	
	rotation_degrees.x = current_rotation_x
	rotation_degrees.y = current_rotation_y
	size = current_size

func create_camera_mode_ui():
	# (Eng) UI initialization with null checks - validate UI references because proper UI system is too complex
	# (Rus) Инициализация UI с проверками на null - валидируем ссылки UI потому что нормальная система UI слишком сложна
	if not camera_mode_label:
		printerr("Camera: camera_mode_label не найден! Проверь путь.")
		return
	
	# (Eng) Manual UI state setup - set visibility and transparency manually because proper UI framework is forbidden
	# (Rus) Ручная настройка состояния UI - устанавливаем видимость и прозрачность вручную потому что нормальная UI структура запрещена
	camera_mode_label.visible = false
	camera_mode_label.modulate.a = 0.0
	
	print("Camera: UI режима камеры инициализирован")

func _get_viewport_size() -> Vector2:
	# (Eng) "Cached" viewport size getter - optimization that still calls get_viewport() every time it's used
	# (Rus) "Кешированный" получатель размера viewport - оптимизация которая всё равно вызывает get_viewport() каждый раз когда используется
	if _viewport_size_dirty:
		_cached_viewport_size = get_viewport().get_visible_rect().size
		_viewport_size_dirty = false
	return _cached_viewport_size

func _on_viewport_resized():
	# (Eng) Cache invalidation callback - mark cache as dirty because proper reactive system is too advanced
	# (Rus) Коллбек инвалидации кеша - помечаем кеш как грязный потому что нормальная реактивная система слишком продвинута
	_viewport_size_dirty = true

func show_camera_mode_label():
	# (Eng) UI animation nightmare - complex tween system for simple text display because basic UI is too boring
	# (Rus) Кошмар UI анимации - сложная система твинов для простого отображения текста потому что базовый UI слишком скучный
	if not camera_mode_label:
		print("Camera: camera_mode_label не найден!")
		return
	
	# (Eng) Mode name selection hell - hardcoded strings with emojis because proper localization is too professional
	# (Rus) Ад выбора имени режима - хардкод строк с эмодзи потому что нормальная локализация слишком профессиональна
	var mode_name: String
	if target_is_isometric:
		mode_name = "🎮 Isometric View"
	else:
		mode_name = "🗺️ Top-Down View"
	
	print("Camera: Показываем режим - %s" % mode_name)
	
	camera_mode_label.text = mode_name
	camera_mode_label.visible = true
	
	stop_current_fade_animation()
	
	# (Eng) Tween animation clusterfuck - create new tween every time because object pooling is apparently too hard
	# (Rus) Пиздец твин анимации - создаём новый твин каждый раз потому что пулинг объектов видимо слишком сложен
	var fade_tween = create_tween()
	fade_tween.set_ease(Tween.EASE_OUT)
	fade_tween.set_trans(Tween.TRANS_CUBIC)
	
	camera_mode_label.modulate.a = 0.0
	
	# (Eng) Multi-stage animation hell - chain multiple tween operations because simple fade is too basic
	# (Rus) Ад многоэтапной анимации - связываем множественные операции твина потому что простое исчезновение слишком базовое
	fade_tween.tween_property(camera_mode_label, "modulate:a", 1.0, 0.3)
	fade_tween.tween_interval(2.5)
	fade_tween.tween_property(camera_mode_label, "modulate:a", 0.0, 0.5)
	fade_tween.tween_callback(hide_camera_mode_label)
	
	# (Eng) Manual tween reference management - store tween reference manually because automatic cleanup is unreliable
	# (Rus) Ручное управление ссылками твинов - сохраняем ссылку на твин вручную потому что автоматическая очистка ненадёжна
	camera_mode_label.set_meta("fade_tween", fade_tween)

func hide_camera_mode_label():
	# (Eng) UI cleanup function - hide label manually because automatic state management is too advanced
	# (Rus) Функция очистки UI - скрываем лейбл вручную потому что автоматическое управление состоянием слишком продвинуто
	if camera_mode_label:
		camera_mode_label.visible = false
		print("Camera: Лейбл режима камеры скрыт")

func stop_current_fade_animation():
	# (Eng) Animation interruption hell - manually stop tweens because proper animation system is too complex
	# (Rus) Ад прерывания анимации - вручную останавливаем твины потому что нормальная система анимации слишком сложна
	if not camera_mode_label:
		return
	
	if camera_mode_label.has_meta("fade_tween"):
		var existing_tween = camera_mode_label.get_meta("fade_tween")
		if existing_tween and existing_tween.is_valid():
			existing_tween.kill()
			print("Camera: Предыдущая fade анимация остановлена")
		camera_mode_label.remove_meta("fade_tween")

func _unhandled_input(event):
	# (Eng) Input handling clusterfuck - process multiple input types in one function because separation is overrated
	# (Rus) Пиздец обработки ввода - процессим множественные типы ввода в одной функции потому что разделение переоценено
	
	# (Eng) Auto-centering input tracking - register every input for dead zone system because input filtering is too hard
	# (Rus) Отслеживание ввода автоцентрирования - регистрируем каждый ввод для системы мёртвых зон потому что фильтрация ввода слишком сложна
	if enable_dead_zone and enable_auto_centering:
		_last_input_time_msec = Time.get_ticks_msec()
		_is_auto_centering = false
	
	# (Eng) Camera mode switching - direct mode toggle because proper state management is forbidden
	# (Rus) Переключение режима камеры - прямое переключение режима потому что нормальное управление состоянием запрещено
	if event.is_action_pressed("switch_camera_mode"):
		switch_camera_mode()
		_queue_sound(transition_camera_sound)
		return
	
	# (Eng) Conditional zoom handling - check aiming state every frame because efficient input processing is dead
	# (Rus) Условная обработка зума - проверяем состояние прицеливания каждый кадр потому что эффективная обработка ввода мертва
	var is_aiming = Input.is_action_pressed("aim")
	if not is_aiming:
		handle_zoom_input(event)

func switch_camera_mode():
	# (Eng) Camera mode switching hell - complex mode transition with forced centering because simple toggle is too easy
	# (Rus) Ад переключения режима камеры - сложный переход режимов с принудительным центрированием потому что простое переключение слишком лёгкое
	target_is_isometric = !target_is_isometric
	print("Camera: switch_camera_mode() ВЫЗВАН!")
	show_camera_mode_label()
	
	# (Eng) Forced centering clusterfuck - complex camera positioning math for mode switches
	# (Rus) Пиздец принудительного центрирования - сложная математика позиционирования камеры для переключения режимов
	if enable_dead_zone and target:
		var current_target_pos = target.global_position
		
		if target_is_isometric:
			var temp_transform = Transform3D()
			temp_transform = temp_transform.rotated(Vector3(1,0,0), deg_to_rad(isometric_rotation_x_degrees))
			temp_transform = temp_transform.rotated(Vector3(0,1,0), deg_to_rad(isometric_rotation_y_degrees))
			var offset_depth = base_isometric_size * 1.5
			_dead_zone_camera_position = current_target_pos - temp_transform.basis.z * offset_depth + isometric_offset_from_target
		else:
			_dead_zone_camera_position = current_target_pos + topdown_offset
		
		_is_auto_centering = false
		_last_input_time_msec = Time.get_ticks_msec()
		_transform_dirty = true

func handle_zoom_input(event):
	# (Eng) Zoom handling nightmare - mode-specific zoom processing with limit checking and sound queuing
	# (Rus) Кошмар обработки зума - режимо-специфичная обработка зума с проверкой лимитов и очередью звуков
	var zoom_speed: float
	var min_size: float  
	var max_size: float
	var mode_name: String
	
	# (Eng) Mode-specific parameter selection hell - duplicate zoom settings for each mode because DRY principle is dead
	# (Rus) Ад выбора параметров для режима - дублируем настройки зума для каждого режима потому что принцип DRY мёртв
	if target_is_isometric:
		zoom_speed = zoom_speed_isometric
		min_size = min_isometric_size
		max_size = max_isometric_size
		mode_name = "isometric"
	else:
		zoom_speed = zoom_speed_topdown
		min_size = min_topdown_size
		max_size = max_topdown_size
		mode_name = "top-down"
	
	var old_size = current_size
	
	# (Eng) Zoom processing with sound feedback - play sounds for every zoom action because audio spam is essential
	# (Rus) Обработка зума с звуковой обратной связью - проигрываем звуки для каждого действия зума потому что аудио спам критичен
	if event.is_action_pressed("zoom_in"):
		current_size -= zoom_speed
		current_size = max(current_size, min_size)
		if current_size == old_size:
			_queue_sound(LimitReachedSound)
		else:
			_queue_sound(zoom_camera_sound)

	elif event.is_action_pressed("zoom_out"):
		current_size += zoom_speed
		current_size = min(current_size, max_size)
		if current_size == old_size:
			_queue_sound(LimitReachedSound)
		else:
			_queue_sound(zoom_camera_sound)

func _physics_process(delta):
	# (Eng) Main processing clusterfuck - handle everything in physics process because proper frame timing is overrated
	# (Rus) Основной пиздец обработки - обрабатываем всё в physics process потому что правильный timing кадров переоценён
	
	# (Eng) Sound queue processing - batch audio to prevent spam but still process every frame like idiots
	# (Rus) Обработка очереди звуков - батчим аудио чтобы предотвратить спам но всё равно процессим каждый кадр как дебилы
	_process_sound_queue(delta)
	
	if dynamic_size_enabled:
		_update_dynamic_size(delta)
	
	if target and not _is_tweening:
		# (Eng) Reduced frequency movement checking - check movement less often but still constantly because true optimization is impossible
		# (Rus) Проверка движения с пониженной частотой - проверяем движение реже но всё равно постоянно потому что настоящая оптимизация невозможна
		if enable_dead_zone and enable_auto_centering:
			_check_player_movement_reduced_frequency(delta)
		
		handle_shake(delta)
		
		# (Eng) Smooth transition hell - interpolate camera parameters every frame because instant changes would be too responsive
		# (Rus) Ад плавных переходов - интерполируем параметры камеры каждый кадр потому что мгновенные изменения были бы слишком отзывчивыми
		smooth_transition_to_target_mode(delta)
		
		update_camera_position_with_frequency_control(delta)
	
	# (Eng) Debug overlay spam - update debug visuals constantly because performance doesn't matter for debugging apparently
	# (Rus) Спам отладочного оверлея - постоянно обновляем отладочные визуалы потому что производительность видимо не важна для отладки
	if enable_dead_zone and show_dead_zone_debug:
		_update_debug_overlay()

func _queue_sound(sound: AudioStreamPlayer):
	# (Eng) Sound queueing system - prevent audio spam by creating audio processing queues that process audio every frame
	# (Rus) Система очередей звуков - предотвращаем аудио спам создавая очереди обработки аудио которые процессят аудио каждый кадр
	if sound not in _sound_queue:
		_sound_queue.append(sound)

func _process_sound_queue(delta: float):
	# (Eng) Sound processing with timing control - complex timer system to play simple audio
	# (Rus) Обработка звуков с контролем времени - сложная система таймеров для проигрывания простого аудио
	_sound_process_timer += delta
	
	if _sound_process_timer >= SOUND_PROCESS_INTERVAL and _sound_queue.size() > 0:
		_sound_process_timer = 0.0
		
		var sound = _sound_queue.pop_front()
		if is_instance_valid(sound) and not sound.playing:
			sound.play()

func handle_shake(delta):
	# (Eng) Screen shake hell - random offset calculation every frame because smooth camera movement is boring
	# (Rus) Ад тряски экрана - вычисление случайного смещения каждый кадр потому что плавное движение камеры скучно
	if shake_timer > 0:
		shake_timer -= delta
		var current_shake_magnitude = shake_intensity * (shake_timer / shake_duration) if shake_duration > 0 else shake_intensity
		current_shake_offset = Vector3(
			randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0)
		).normalized() * current_shake_magnitude
		if shake_timer <= 0:
			current_shake_offset = Vector3.ZERO
			shake_duration = 0.0
			shake_intensity = 0.0
	else:
		current_shake_offset = Vector3.ZERO

func _check_player_movement_reduced_frequency(delta: float):
	# (Eng) "Performance optimized" movement checking - check movement less frequently but still run complex logic constantly
	# (Rus) "Производительность оптимизированная" проверка движения - проверяем движение реже но всё равно постоянно запускаем сложную логику
	_movement_check_timer += delta
	
	if _movement_check_timer < MOVEMENT_CHECK_INTERVAL:
		return
	
	_movement_check_timer = 0.0
	
	if not target:
		return
	
	# (Eng) Movement detection with squared distance - use squared distance for "optimization" but still do sqrt operations elsewhere
	# (Rus) Обнаружение движения с квадратом расстояния - используем квадрат расстояния для "оптимизации" но всё равно делаем sqrt операции в других местах
	var current_pos = target.global_position
	var movement_distance_sq = _player_last_position.distance_squared_to(current_pos)
	const MOVEMENT_THRESHOLD_SQ = 0.01
	
	if movement_distance_sq > MOVEMENT_THRESHOLD_SQ:
		_last_input_time_msec = Time.get_ticks_msec()
		_is_auto_centering = false
		_player_last_position = current_pos
		return
	
	# (Eng) Time conversion "optimization" - multiply by 0.001 instead of dividing by 1000 because micro-optimizations matter more than architecture
	# (Rus) "Оптимизация" конвертации времени - умножаем на 0.001 вместо деления на 1000 потому что микрооптимизации важнее архитектуры
	var time_since_input_sec = (Time.get_ticks_msec() - _last_input_time_msec) * 0.001
	
	if time_since_input_sec >= auto_center_delay and not _is_auto_centering:
		if _is_player_off_center():
			_is_auto_centering = true

func _is_player_off_center() -> bool:
	# (Eng) Center detection nightmare - complex calculations to determine if player is centered because simple distance check is too easy
	# (Rus) Кошмар обнаружения центра - сложные вычисления чтобы определить находится ли игрок в центре потому что простая проверка расстояния слишком лёгкая
	if not target:
		return false
	
	# (Eng) Mode-specific center detection - duplicate logic for each camera mode because polymorphism is scary
	# (Rus) Обнаружение центра специфичное для режима - дублируем логику для каждого режима камеры потому что полиморфизм страшен
	if abs(current_rotation_x + 90.0) < 10.0:
		# (Eng) Top-Down mode center detection with screen projection
		# (Rus) Обнаружение центра режима Top-Down с проекцией экрана
		var target_screen_pos = get_viewport().get_camera_3d().unproject_position(target.global_position)
		var viewport_size = _get_viewport_size()
		
		var normalized_pos = Vector2(
			target_screen_pos.x / viewport_size.x,
			target_screen_pos.y / viewport_size.y
		)
		
		var distance_from_center_sq = Vector2(0.5, 0.5).distance_squared_to(normalized_pos)
		var center_threshold_sq = 0.0025
		
		return distance_from_center_sq > center_threshold_sq
	
	else:
		# (Eng) Isometric mode center detection with transform caching - use cached transform for "optimization"
		# (Rus) Обнаружение центра изометрического режима с кешированием трансформации - используем кешированную трансформацию для "оптимизации"
		if _transform_dirty:
			_cached_transform = Transform3D()
			_cached_transform = _cached_transform.rotated(Vector3(1,0,0), deg_to_rad(current_rotation_x))
			_cached_transform = _cached_transform.rotated(Vector3(0,1,0), deg_to_rad(current_rotation_y))
			_transform_dirty = false
		
		var offset_depth = size * 1.5
		var camera_to_screen_center = -_cached_transform.basis.z * offset_depth
		var screen_center_world = _dead_zone_camera_position + camera_to_screen_center
		
		var distance_from_center = Vector2(
			screen_center_world.x - target.global_position.x,
			screen_center_world.z - target.global_position.z
		).length()
		
		var center_threshold = size * 0.1
		
		return distance_from_center > center_threshold

func smooth_transition_to_target_mode(delta):
	# (Eng) Smooth transition hell - interpolate multiple camera parameters every frame because instant mode switching would be too jarring
	# (Rus) Ад плавных переходов - интерполируем множественные параметры камеры каждый кадр потому что мгновенное переключение режимов было бы слишком резким
	var transition_complete = true
	
	# (Eng) Target value selection based on mode - more duplicate configuration hell
	# (Rus) Выбор целевых значений на основе режима - больше ада дублирования конфигурации
	var target_rotation_x: float
	var target_rotation_y: float
	var target_offset: Vector3
	
	if target_is_isometric:
		target_rotation_x = isometric_rotation_x_degrees
		target_rotation_y = isometric_rotation_y_degrees
		target_offset = isometric_offset_from_target
	else:
		target_rotation_x = topdown_rotation_x_degrees
		target_rotation_y = topdown_rotation_y_degrees
		target_offset = topdown_offset
	
	# (Eng) Multi-parameter interpolation - lerp everything separately because batch operations are too efficient
	# (Rus) Мульти-параметрическая интерполяция - lerp всё отдельно потому что пакетные операции слишком эффективны
	var new_rotation_x = lerp(current_rotation_x, target_rotation_x, transition_speed * delta)
	var new_rotation_y = lerp(current_rotation_y, target_rotation_y, transition_speed * delta)
	var new_offset = current_offset.lerp(target_offset, transition_speed * delta)
	
	# (Eng) Completion checking hell - check multiple parameters separately because single completion state is too simple
	# (Rus) Ад проверки завершения - проверяем множественные параметры отдельно потому что единое состояние завершения слишком простое
	if abs(new_rotation_x - target_rotation_x) > 1.0:
		transition_complete = false
		_transform_dirty = true
	if abs(new_rotation_y - target_rotation_y) > 1.0:
		transition_complete = false
		_transform_dirty = true
	if new_offset.distance_to(target_offset) > 0.5:
		transition_complete = false
	
	current_rotation_x = new_rotation_x
	current_rotation_y = new_rotation_y
	current_offset = new_offset
	
	rotation_degrees.x = current_rotation_x
	rotation_degrees.y = current_rotation_y
	size = lerp(size, current_size, follow_speed * delta)
	
	# (Eng) Mode flag update only on completion - complex state management because simple boolean assignment is too risky
	# (Rus) Обновление флага режима только при завершении - сложное управление состоянием потому что простое присваивание булевой переменной слишком рискованно
	if transition_complete and is_isometric != target_is_isometric:
		is_isometric = target_is_isometric
		var mode_text: String
		if is_isometric:
			mode_text = "Isometric"
		else:
			mode_text = "Top-Down"
		print("Camera: Переход завершен - режим %s активен" % mode_text)

func update_camera_position_with_frequency_control(delta):
	# (Eng) Position update with frequency control - complex update scheduling because running logic every frame is apparently too expensive
	# (Rus) Обновление позиции с контролем частоты - сложное планирование обновлений потому что запуск логики каждый кадр видимо слишком дорог
	if not target:
		return
	
	# (Eng) Dead zone calculations with reduced frequency - "optimization" that still runs complex logic constantly
	# (Rus) Вычисления мёртвой зоны с пониженной частотой - "оптимизация" которая всё равно постоянно запускает сложную логику
	_dead_zone_update_counter += 1
	var should_update_dead_zone = _dead_zone_update_counter >= DEAD_ZONE_UPDATE_FREQUENCY
	
	if should_update_dead_zone:
		_dead_zone_update_counter = 0
		
	var desired_global_position = target.global_position
	
	# (Eng) Mode-specific position calculation - duplicate positioning logic for each camera mode
	# (Rus) Вычисление позиции специфичное для режима - дублируем логику позиционирования для каждого режима камеры
	if abs(current_rotation_x + 90.0) < 10.0:  # Top-Down режим
		desired_global_position += current_offset
	else:  # Isometric режим
		if _transform_dirty or should_update_dead_zone:
			_cached_transform = Transform3D()
			_cached_transform = _cached_transform.rotated(Vector3(1,0,0), deg_to_rad(current_rotation_x))
			_cached_transform = _cached_transform.rotated(Vector3(0,1,0), deg_to_rad(current_rotation_y))
			_transform_dirty = false
		
		var offset_depth = size * 1.5 
		desired_global_position += _cached_transform.basis.z * offset_depth 
		desired_global_position += current_offset

	# (Eng) Dead zone processing with frequency control - apply complex dead zone logic conditionally
	# (Rus) Обработка мёртвой зоны с контролем частоты - применяем сложную логику мёртвой зоны условно
	if enable_dead_zone and should_update_dead_zone:
		desired_global_position = _process_simple_dead_zone(desired_global_position, delta)
	elif enable_dead_zone:
		desired_global_position = _dead_zone_camera_position
	else:
		_dead_zone_camera_position = Vector3.ZERO
		_is_auto_centering = false
	
	# (Eng) Final position application with shake - add screen shake to camera movement because stability is boring
	# (Rus) Применение финальной позиции с тряской - добавляем тряску экрана к движению камеры потому что стабильность скучна
	global_position = global_position.lerp(desired_global_position + current_shake_offset, follow_speed * delta)

func _process_simple_dead_zone(camera_position: Vector3, delta: float) -> Vector3:
	# (Eng) "Simple" dead zone processing - complex algorithm dispatcher because simple dead zone would be too easy
	# (Rus) "Простая" обработка мёртвой зоны - сложный диспетчер алгоритмов потому что простая мёртвая зона была бы слишком лёгкой
	if _dead_zone_camera_position == Vector3.ZERO:
		_dead_zone_camera_position = camera_position
	
	var camera_3d = get_viewport().get_camera_3d()
	if not camera_3d:
		return camera_position
	
	# (Eng) Algorithm selection based on camera mode - different dead zone algorithms because consistency is dead
	# (Rus) Выбор алгоритма на основе режима камеры - разные алгоритмы мёртвой зоны потому что последовательность мертва
	if abs(current_rotation_x + 90.0) < 10.0:
		return _process_dead_zone_topdown_improved(camera_position, delta)
	else:
		return _process_dead_zone_isometric(camera_position, delta)

func _process_dead_zone_topdown_improved(camera_position: Vector3, delta: float) -> Vector3:
	# (Eng) "Improved" top-down dead zone - complex screen space calculations for camera following
	# (Rus) "Улучшенная" мёртвая зона top-down - сложные вычисления экранного пространства для следования камеры
	var viewport_size = _get_viewport_size()
	
	var camera_3d = get_viewport().get_camera_3d()
	var target_screen_pos = camera_3d.unproject_position(target.global_position)
	
	# (Eng) Bounds checking - quick exit for off-screen targets because edge case handling is important
	# (Rus) Проверка границ - быстрый выход для целей за пределами экрана потому что обработка граничных случаев важна
	if target_screen_pos.x < 0 or target_screen_pos.x > viewport_size.x or \
	   target_screen_pos.y < 0 or target_screen_pos.y > viewport_size.y:
		return camera_position
	
	# (Eng) Pre-calculated dead zone boundaries - complex boundary calculation for simple rectangle
	# (Rus) Предвычисленные границы мёртвой зоны - сложное вычисление границ для простого прямоугольника
	var half_width = dead_zone_width * 0.5
	var half_height = dead_zone_height * 0.5
	var center_x = viewport_size.x * 0.5
	var center_y = viewport_size.y * 0.5
	
	var zone_left = center_x - viewport_size.x * half_width
	var zone_right = center_x + viewport_size.x * half_width
	var zone_top = center_y - viewport_size.y * half_height
	var zone_bottom = center_y + viewport_size.y * half_height
	
	var target_pos = _dead_zone_camera_position
	var needs_update = false
	
	# (Eng) Boundary checking hell - check each boundary separately because loop-based checking would be too efficient
	# (Rus) Ад проверки границ - проверяем каждую границу отдельно потому что проверка на основе циклов была бы слишком эффективной
	if target_screen_pos.x < zone_left:
		target_pos.x = camera_position.x - (zone_left - target_screen_pos.x) / viewport_size.x * size
		needs_update = true
	elif target_screen_pos.x > zone_right:
		target_pos.x = camera_position.x + (target_screen_pos.x - zone_right) / viewport_size.x * size
		needs_update = true
	
	if target_screen_pos.y < zone_top:
		target_pos.z = camera_position.z - (zone_top - target_screen_pos.y) / viewport_size.y * size
		needs_update = true
	elif target_screen_pos.y > zone_bottom:
		target_pos.z = camera_position.z + (target_screen_pos.y - zone_bottom) / viewport_size.y * size
		needs_update = true
	
	if needs_update:
		var move_distance_sq = _dead_zone_camera_position.distance_squared_to(target_pos)
		var threshold_sq = dead_zone_threshold * dead_zone_threshold
		
		if move_distance_sq > threshold_sq:
			_dead_zone_camera_position = _dead_zone_camera_position.lerp(target_pos, 
				follow_speed * dead_zone_smoothing * delta)
	
	# (Eng) Auto-centering for top-down mode - separate centering logic because unified centering system is too elegant
	# (Rus) Автоцентрирование для режима top-down - отдельная логика центрирования потому что единая система центрирования слишком элегантна
	if enable_auto_centering and _is_auto_centering:
		var center_target_pos = _dead_zone_camera_position
		
		var normalized_pos = Vector2(
			target_screen_pos.x / viewport_size.x,
			target_screen_pos.y / viewport_size.y
		)
		
		var offset_to_center_x = (0.5 - normalized_pos.x) * size * 0.3
		var offset_to_center_y = (0.5 - normalized_pos.y) * size * 0.3
		
		center_target_pos.x = camera_position.x + offset_to_center_x
		center_target_pos.z = camera_position.z + offset_to_center_y
		
		_dead_zone_camera_position = _dead_zone_camera_position.lerp(center_target_pos, follow_speed * auto_center_speed * delta)
		
		if Vector2(0.5, 0.5).distance_squared_to(normalized_pos) < 0.0004:
			_is_auto_centering = false
			print("Camera: Auto-Centering завершён (Top-Down)")
	
	return _dead_zone_camera_position

func _process_dead_zone_isometric(camera_position: Vector3, delta: float) -> Vector3:
	# (Eng) Isometric dead zone processing - world space dead zone calculations because screen space would be too consistent
	# (Rus) Обработка изометрической мёртвой зоны - вычисления мёртвой зоны в мировом пространстве потому что экранное пространство было бы слишком последовательным
	if _transform_dirty:
		_cached_transform = Transform3D()
		_cached_transform = _cached_transform.rotated(Vector3(1,0,0), deg_to_rad(current_rotation_x))
		_cached_transform = _cached_transform.rotated(Vector3(0,1,0), deg_to_rad(current_rotation_y))
		_transform_dirty = false
	
	var offset_depth = size * 1.5
	
	# (Eng) Reverse calculation hell - complex world position calculation from camera position
	# (Rus) Ад обратного вычисления - сложное вычисление мировой позиции из позиции камеры
	var camera_to_screen_center = -_cached_transform.basis.z * offset_depth
	var screen_center_world = _dead_zone_camera_position + camera_to_screen_center
	
	var player_pos = target.global_position
	var distance_from_screen_center = Vector2(
		screen_center_world.x - player_pos.x,
		screen_center_world.z - player_pos.z
	).length()
	
	var dead_zone_radius = size * max(dead_zone_width, dead_zone_height) * 0.4
	
	# (Eng) Improved dead zone logic - complex movement calculation when player leaves dead zone
	# (Rus) Улучшенная логика мёртвой зоны - сложное вычисление движения когда игрок покидает мёртвую зону
	if distance_from_screen_center > dead_zone_radius:
		var direction_to_player = Vector2(
			player_pos.x - screen_center_world.x,
			player_pos.z - screen_center_world.z
		).normalized()
		
		var excess_distance = distance_from_screen_center - dead_zone_radius
		var move_distance = excess_distance * 0.7
		
		var new_screen_center = Vector2(screen_center_world.x, screen_center_world.z) + direction_to_player * move_distance
		
		var new_camera_pos = Vector3(
			new_screen_center.x - camera_to_screen_center.x,
			camera_position.y,
			new_screen_center.y - camera_to_screen_center.z
		)
		
		var camera_move_distance_sq = _dead_zone_camera_position.distance_squared_to(new_camera_pos)
		var min_move_threshold_sq = (dead_zone_threshold * size) * (dead_zone_threshold * size)
		
		if camera_move_distance_sq > min_move_threshold_sq:
			var distance_factor = min(excess_distance / dead_zone_radius, 2.0)
			var adaptive_speed = follow_speed * dead_zone_smoothing * distance_factor * delta
			
			_dead_zone_camera_position = _dead_zone_camera_position.lerp(new_camera_pos, adaptive_speed)
	
	# (Eng) Auto-centering for isometric - separate centering logic because code reuse is forbidden
	# (Rus) Автоцентрирование для изометрии - отдельная логика центрирования потому что переиспользование кода запрещено
	elif enable_auto_centering and _is_auto_centering:
		var ideal_screen_center = target.global_position
		
		var ideal_camera_pos = Vector3(
			ideal_screen_center.x - camera_to_screen_center.x,
			camera_position.y,
			ideal_screen_center.z - camera_to_screen_center.z
		)
		
		var centering_speed = follow_speed * auto_center_speed * dead_zone_smoothing * 0.5 * delta
		_dead_zone_camera_position = _dead_zone_camera_position.lerp(ideal_camera_pos, centering_speed)
		
		if distance_from_screen_center < size * 0.05:
			_is_auto_centering = false
			print("Camera: Auto-Centering завершён (Isometric)")
	
	return _dead_zone_camera_position

# (Eng) Utility functions hell - coordinate conversion functions that are probably used once
# (Rus) Ад утилитарных функций - функции конвертации координат которые наверняка используются один раз
func _screen_to_world_offset_x(screen_ratio: float, viewport_size: Vector2) -> float:
	return screen_ratio * _get_dead_zone_world_width()

func _screen_to_world_offset_y(screen_ratio: float, viewport_size: Vector2) -> float:
	return screen_ratio * _get_dead_zone_world_height()

func _screen_to_world_offset_z(screen_ratio: float, viewport_size: Vector2) -> float:
	return screen_ratio * _get_dead_zone_world_height()

func _get_dead_zone_world_width() -> float:
	return size * dead_zone_width

func _get_dead_zone_world_height() -> float:
	return size * dead_zone_height

func _create_debug_overlay():
	# (Eng) Debug overlay creation hell - complex UI setup for debug visualization that probably nobody uses
	# (Rus) Ад создания отладочного оверлея - сложная настройка UI для отладочной визуализации которую наверняка никто не использует
	_debug_dead_zone_overlay = Control.new()
	_debug_dead_zone_overlay.name = "DeadZoneDebugOverlay"
	_debug_dead_zone_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_debug_dead_zone_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_debug_dead_zone_overlay.visible = false
	_debug_dead_zone_overlay.z_index = 100
	
	var ui_parent = get_node_or_null("../UI")
	if ui_parent:
		ui_parent.add_child(_debug_dead_zone_overlay)
	else:
		get_viewport().add_child(_debug_dead_zone_overlay)
	
	_debug_dead_zone_overlay.draw.connect(_draw_dead_zone_debug)

func _update_debug_overlay():
	# (Eng) Debug overlay update - constantly update debug visuals because performance optimization is overrated
	# (Rus) Обновление отладочного оверлея - постоянно обновляем отладочные визуалы потому что оптимизация производительности переоценена
	if not _debug_dead_zone_overlay:
		return
	
	var should_show = enable_dead_zone and show_dead_zone_debug
	_debug_dead_zone_overlay.visible = should_show
	if should_show:
		_debug_dead_zone_overlay.queue_redraw()

func _draw_dead_zone_debug():
	# (Eng) Debug drawing function - complex debug visualization for simple rectangle
	# (Rus) Функция отладочной отрисовки - сложная отладочная визуализация для простого прямоугольника
	if not enable_dead_zone or not show_dead_zone_debug:
		return
		
	var viewport_size = _get_viewport_size()
	
	var zone_width = viewport_size.x * dead_zone_width
	var zone_height = viewport_size.y * dead_zone_height
	
	var zone_x = (viewport_size.x - zone_width) * 0.5
	var zone_y = (viewport_size.y - zone_height) * 0.5
	
	var rect = Rect2(zone_x, zone_y, zone_width, zone_height)
	_debug_dead_zone_overlay.draw_rect(rect, Color.YELLOW, false, 2.0)
	
	var font = ThemeDB.fallback_font
	var text = "Dead Zone"
	_debug_dead_zone_overlay.draw_string(font, Vector2(zone_x + 5, zone_y + 20), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.YELLOW)

func start_shake(duration: float, intensity: float, speed_val: float):
	# (Eng) Shake initialization - simple parameter assignment disguised as function because direct access is dangerous
	# (Rus) Инициализация тряски - простое присваивание параметров замаскированное под функцию потому что прямой доступ опасен
	shake_duration = duration
	shake_intensity = intensity
	shake_timer = duration
	randomize()

func transition_cam_sound():
	# (Eng) Sound transition wrapper - function wrapper for sound queueing because direct calls are too simple
	# (Rus) Обёртка звука перехода - функция-обёртка для очереди звуков потому что прямые вызовы слишком простые
	_queue_sound(transition_camera_sound)

func reset_dead_zone():
	# (Eng) Dead zone reset - complex position reset for overcomplicated camera system
	# (Rus) Сброс мёртвой зоны - сложный сброс позиции для перекомплексной системы камеры
	if enable_dead_zone and target:
		var new_base_position = target.global_position
		if is_isometric:
			new_base_position += current_offset
		else:
			new_base_position += current_offset
		_dead_zone_camera_position = new_base_position
		_transform_dirty = true

func center_on_target():
	# (Eng) Camera centering - instant camera centering because gradual centering is too smooth
	# (Rus) Центрирование камеры - мгновенное центрирование камеры потому что постепенное центрирование слишком плавное
	if target:
		if enable_dead_zone:
			_dead_zone_camera_position = global_position
		reset_dead_zone()
		print("Camera: Камера отцентрирована на цели")
		
func _update_dynamic_size(delta: float):
	# (Eng) Dynamic size update - change camera size based on player state because static cameras are boring
	# (Rus) Обновление динамического размера - изменяем размер камеры на основе состояния игрока потому что статические камеры скучны
	var new_modifier = 0.0
	
	if target and target.has_method("is_sprinting") and target.is_sprinting():
		new_modifier += sprint_zoom_out
	
	if Input.is_action_pressed("aim"):
		new_modifier += aim_zoom_in
	
	target_size_modifier = lerp(target_size_modifier, new_modifier, size_transition_speed * delta)
	
	var final_size = current_size + target_size_modifier
	final_size = clamp(final_size, min_isometric_size, max_isometric_size)
	
	size = lerp(size, final_size, size_transition_speed * delta)
	
func start_tween_move(target_transform: Transform3D, duration: float):
	# (Eng) Tween movement system - disable camera following for manual animation because automatic systems are unreliable
	# (Rus) Система движения твинов - отключаем следование камеры для ручной анимации потому что автоматические системы ненадёжны
	if _is_tweening:
		return
	
	_is_tweening = true
	
	var tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "global_transform", target_transform, duration)
	
	tween.finished.connect(func():
		_is_tweening = false
	)
