extends CanvasLayer

@export var texture_rect_fov: TextureRect
@export var texture_rect_scan_line: TextureRect

@export var hover_fov: float = 35.0
@export var default_fov: float = 90.0
@export var transition_duration: float = 1.0
@export var progress_scan_line_hover: float = 0.1
@export var progress_scan_line_default: float = 0.05

var tween_fov: Tween
var tween_scan: Tween
var shader_material_fov: ShaderMaterial
var shader_material_scan_line: ShaderMaterial

func _ready():
	if not texture_rect_fov:
		printerr("TextureRect FOV не назначен!")
		return
	if not texture_rect_scan_line:
		printerr("TextureRect ScanLine не назначен!")
		return
	
	# Получаем материалы
	shader_material_fov = texture_rect_fov.material as ShaderMaterial
	if not shader_material_fov:
		printerr("У FOV TextureRect нет ShaderMaterial!")
		return
	
	shader_material_scan_line = texture_rect_scan_line.material as ShaderMaterial
	if not shader_material_scan_line:
		printerr("У ScanLine TextureRect нет ShaderMaterial!")
		return
	
	# Устанавливаем начальные значения
	shader_material_fov.set_shader_parameter("fov", default_fov)
	shader_material_scan_line.set_shader_parameter("progress", progress_scan_line_default)
	
	# Подключаем сигналы
	texture_rect_fov.mouse_entered.connect(_on_mouse_entered)
	texture_rect_fov.mouse_exited.connect(_on_mouse_exited)
	
	print("Интерактивный FOV + ScanLine эффект готов")
	

# === Наведение мыши ===
func _on_mouse_entered():
	animate_fov_to(hover_fov)
	animate_scan_line_to(progress_scan_line_hover)
	print("Мышь наведена - FOV -> %.1f | ScanLine -> %.2f" % [hover_fov, progress_scan_line_hover])

func _on_mouse_exited():
	animate_fov_to(default_fov)
	animate_scan_line_to(progress_scan_line_default)
	print("Мышь убрана - FOV -> %.1f | ScanLine -> %.2f" % [default_fov, progress_scan_line_default])

# === Анимация FOV ===
func animate_fov_to(target_fov: float):
	if not shader_material_fov:
		return
	
	if tween_fov and tween_fov.is_valid():
		tween_fov.kill()
	
	var current_fov = shader_material_fov.get_shader_parameter("fov")
	
	tween_fov = create_tween()
	tween_fov.set_ease(Tween.EASE_OUT)
	tween_fov.set_trans(Tween.TRANS_CUBIC)
	tween_fov.tween_method(set_fov_value, current_fov, target_fov, transition_duration)

func set_fov_value(value: float):
	if shader_material_fov:
		shader_material_fov.set_shader_parameter("fov", value)

# === Анимация ScanLine ===
func animate_scan_line_to(target_progress: float):
	if not shader_material_scan_line:
		return
	
	if tween_scan and tween_scan.is_valid():
		tween_scan.kill()
	
	var current_progress = shader_material_scan_line.get_shader_parameter("progress")
	
	tween_scan = create_tween()
	tween_scan.set_ease(Tween.EASE_OUT)
	tween_scan.set_trans(Tween.TRANS_CUBIC)
	tween_scan.tween_method(set_progress_scan_value, current_progress, target_progress, transition_duration)

func set_progress_scan_value(value: float):
	if shader_material_scan_line:
		shader_material_scan_line.set_shader_parameter("progress", value)
