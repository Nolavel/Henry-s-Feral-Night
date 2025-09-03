# ✅ Script: AimDot.gd
# (Eng) Combat aiming dot with visibility toggles, distance control and all that lerping performance-killing bullshit
# (Rus) Боевая точка прицеливания с переключением видимости, контролем расстояния и всем этим убивающим производительность лерпом
# 🔧 WIP ⚡ Prototype — raw, unfinished crap, demo mechanics / сырая, незавершённая фигня, демо-механика

extends Node3D

# (Eng) Distance configuration - bunch of exported floats because having reasonable hardcoded values is apparently forbidden
# (Rus) Конфигурация расстояния - куча экспортируемых флоатов потому что иметь разумные хардкод значения видимо запрещено
@export var min_distance = 2.0
@export var max_distance = 10.0  
@export var distance_sensitivity = 0.1

# (Eng) Visual settings explosion - more exported variables because every tiny detail needs to be tweakable apparently
# (Rus) Взрыв визуальных настроек - больше экспортируемых переменных потому что каждая мелочь видимо должна быть настраиваемой
@export var dot_vertical_offset = 3.0
@export var idle_dot_size = 0.7
@export var active_dot_size = 0.2
@export var size_lerp_speed = 8.0
@export var distance_lerp_speed = 5.0
@export var visibility_lerp_speed = 12.0  # Speed of fade in/out

# (Eng) Mouse motion detection settings - complex mouse tracking for simple size changes
# (Rus) Настройки обнаружения движения мыши - сложное отслеживание мыши для простых изменений размера
@export var mouse_motion_threshold = 2.0
@export var mouse_motion_detection_time = 0.15

# (Eng) State tracking hell - dozens of variables because proper state management is too complicated apparently
# (Rus) Ад отслеживания состояния - дюжины переменных потому что нормальное управление состоянием видимо слишком сложно
var current_distance = 5.0
var target_distance = 5.0
var current_dot_scale = 0.7
var target_dot_scale = 0.7
var current_alpha = 0.0  # Current transparency
var target_alpha = 0.0   # Target transparency

# (Eng) Commented-out auto-calculation feature - dead code because removing unused shit is too much work
# (Rus) Закомментированная функция автовычисления - мёртвый код потому что удаление неиспользуемой фигни слишком много работы
# @export var auto_calculate_max_distance = true  
# @export var camera_view_margin = 0.8

# (Eng) Mouse tracking state - complex motion detection for barely noticeable visual effect
# (Rus) Состояние отслеживания мыши - сложное обнаружение движения для едва заметного визуального эффекта
var mouse_moved_recently = false
var mouse_motion_timer = 0.0
var last_mouse_position = Vector2.ZERO

var is_aiming = false  # Is right mouse button held?

@onready var mesh_instance = $MeshInstance3D

func _ready():
	print("AimDot _ready() called. Parent is: ", get_parent().name)
	
	# (Eng) Dynamic mesh creation because setting up the scene properly is apparently too hard
	# (Rus) Динамическое создание меша потому что правильная настройка сцены видимо слишком сложна
	if not has_node("MeshInstance3D"):
		create_aim_dot_mesh()
	
	# (Eng) Manual initialization with hardcoded calculations - because parametric initialization is rocket science
	# (Rus) Ручная инициализация с хардкод вычислениями - потому что параметрическая инициализация это ракетостроение
	current_distance = (min_distance + max_distance) / 2.0  # Start at 4.25
	target_distance = current_distance
	current_dot_scale = idle_dot_size
	target_dot_scale = idle_dot_size
	
	# (Eng) Start invisible - because visible by default would make too much sense
	# (Rus) Начинаем невидимым - потому что видимый по умолчанию имел бы слишком много смысла
	current_alpha = 0.0
	target_alpha = 0.0
	visible = false
	
	update_position()
	scale = Vector3(current_dot_scale, current_dot_scale, current_dot_scale)
	
	last_mouse_position = get_viewport().get_mouse_position()
	print("AimDot initialized - Distance range: ", min_distance, " to ", max_distance)

func create_aim_dot_mesh():
	# (Eng) Runtime mesh creation clusterfuck - build entire 3D object with materials from scratch because scene setup is too easy
	# (Rus) Пиздец создания меша во время выполнения - строим целый 3D объект с материалами с нуля потому что настройка сцены слишком лёгкая
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "MeshInstance3D"
	add_child(mesh_instance)
	
	# (Eng) Sphere mesh creation with hardcoded dimensions because parametric geometry is too advanced
	# (Rus) Создание сферического меша с хардкод размерами потому что параметрическая геометрия слишком продвинута
	var sphere_mesh = SphereMesh.new()
	sphere_mesh.radius = 0.1
	sphere_mesh.height = 0.2
	mesh_instance.mesh = sphere_mesh
	
	# (Eng) Material creation nightmare - build entire material from scratch with emission and transparency
	# (Rus) Кошмар создания материала - строим целый материал с нуля с эмиссией и прозрачностью
	var material = StandardMaterial3D.new()
	material.albedo_color = Color.LIME_GREEN
	material.emission_enabled = true
	material.emission = Color.LIME_GREEN * 0.5
	material.no_depth_test = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA  # Enable transparency
	mesh_instance.material_override = material
	
	print("AimDot: Created mesh with transparency support")

func _physics_process(delta):
	# (Eng) Main performance destroyer - runs every physics frame with multiple lerp operations and material property changes
	# (Rus) Основной убийца производительности - работает каждый физический кадр с множественными lerp операциями и изменениями свойств материала
	
	# (Eng) Input polling every frame - check right mouse button state because proper input events are too complex
	# (Rus) Опрос ввода каждый кадр - проверяем состояние правой кнопки мыши потому что нормальные события ввода слишком сложны
	is_aiming = Input.is_action_pressed("aim")  # You need to add "aim" action in Input Map
	
	# (Eng) Target alpha calculation - because simple boolean-to-float conversion needs a dedicated line apparently
	# (Rus) Расчёт целевой альфы - потому что простое преобразование булев-флоат видимо нуждается в отдельной строке
	target_alpha = 1.0 if is_aiming else 0.0
	
	# (Eng) Mouse motion timer decay - manual timer management because using built-in timers would be too convenient
	# (Rus) Затухание таймера движения мыши - ручное управление таймером потому что использование встроенных таймеров было бы слишком удобно
	if mouse_moved_recently:
		mouse_motion_timer -= delta
		if mouse_motion_timer <= 0:
			mouse_moved_recently = false
	
	# (Eng) Target size calculation with conditional logic - complex size selection for simple visual state
	# (Rus) Расчёт целевого размера с условной логикой - сложный выбор размера для простого визуального состояния
	if is_aiming:
		target_dot_scale = active_dot_size if mouse_moved_recently else idle_dot_size
	else:
		target_dot_scale = idle_dot_size
	
	# (Eng) Triple lerp hell - smooth interpolation for three different properties every physics frame
	# (Rus) Тройной ад lerp - плавная интерполяция для трёх разных свойств каждый физический кадр
	current_distance = lerp(current_distance, target_distance, distance_lerp_speed * delta)
	current_dot_scale = lerp(current_dot_scale, target_dot_scale, size_lerp_speed * delta)
	current_alpha = lerp(current_alpha, target_alpha, visibility_lerp_speed * delta)
	
	# (Eng) Visibility management clusterfuck - manual visibility toggle with alpha threshold checking
	# (Rus) Пиздец управления видимостью - ручное переключение видимости с проверкой порога альфы
	if current_alpha < 0.01:
		visible = false
	else:
		visible = true
		# (Eng) Material property modification every frame - change material colors constantly because batch updates are too efficient
		# (Rus) Модификация свойств материала каждый кадр - постоянно меняем цвета материала потому что пакетные обновления слишком эффективны
		if has_node("MeshInstance3D"):
			var material = $MeshInstance3D.material_override
			if material:
				material.albedo_color.a = current_alpha
				material.emission = Color.LIME_GREEN * (0.5 * current_alpha)
	
	# (Eng) Position and scale updates every frame - because transform caching would be too advanced
	# (Rus) Обновления позиции и масштаба каждый кадр - потому что кеширование трансформаций было бы слишком продвинуто
	update_position()
	scale = Vector3(current_dot_scale, current_dot_scale, current_dot_scale)

func update_position():
	# (Eng) Position calculation - hardcoded Y offset and Z distance because flexible positioning is too complex
	# (Rus) Расчёт позиции - хардкод смещения Y и расстояния Z потому что гибкое позиционирование слишком сложно
	position = Vector3(0, dot_vertical_offset, -current_distance)

func _unhandled_input(event):
	# (Eng) Mouse wheel handling with input consumption - zoom control only during aiming with event blocking
	# (Rus) Обработка колеса мыши с поглощением ввода - контроль зума только во время прицеливания с блокированием событий
	if is_aiming and (event.is_action_pressed("zoom_in") or event.is_action_pressed("zoom_out")):
		if event.is_action_pressed("zoom_in"):
			target_distance -= 0.5  # Closer
		elif event.is_action_pressed("zoom_out"):
			target_distance += 0.5  # Further
		
		target_distance = clamp(target_distance, min_distance, max_distance)
		
		# (Eng) Event consumption to prevent camera zoom - manual input blocking because proper input priority is too hard
		# (Rus) Поглощение события чтобы предотвратить зум камеры - ручная блокировка ввода потому что нормальный приоритет ввода слишком сложен
		get_viewport().set_input_as_handled()

func notify_mouse_motion(event_position: Vector2, event_relative: Vector2):
	# (Eng) Mouse motion notification system - complex motion detection for simple visual feedback
	# (Rus) Система уведомления о движении мыши - сложное обнаружение движения для простой визуальной обратной связи
	
	# (Eng) Aiming mode gate - only respond to mouse when in specific state
	# (Rus) Ворота режима прицеливания - отвечаем на мышь только в определённом состоянии
	if not is_aiming:
		return
		
	# (Eng) Motion threshold detection - distance calculation to determine if mouse moved enough
	# (Rus) Обнаружение порога движения - расчёт расстояния чтобы определить достаточно ли сдвинулась мышь
	if (event_position - last_mouse_position).length() > mouse_motion_threshold:
		mouse_moved_recently = true
		mouse_motion_timer = mouse_motion_detection_time
	
	# (Eng) Commented-out vertical mouse control - dead code for distance control that was replaced by wheel input
	# (Rus) Закомментированный вертикальный контроль мыши - мёртвый код для контроля расстояния который заменили вводом колеса
	# var distance_change = -event_relative.y * distance_sensitivity
	# target_distance += distance_change
	# target_distance = clamp(target_distance, min_distance, max_distance)
	
	last_mouse_position = event_position
