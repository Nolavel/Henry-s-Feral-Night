extends Node3D

@onready var texture_rect_node: TextureRect = $HenryFeedbackHUD/TextureCFH
@onready var sub_viewport_node: SubViewport = $SubViewport
@onready var camera_face: Camera3D = $SubViewport/CameraFaceHenry
@onready var player: CharacterBody3D = get_parent()
@onready var shader_mat: ShaderMaterial = texture_rect_node.material

# === Экспорт: камера ===
@export var distance: float = 0.35
@export var height: float = 0.8

# === Экспорт: шейдерные параметры ===
@export var sh_diamond_softness: float = 0.02
@export var sh_aspect: float = 1.0
@export var sh_modulate_color: Color = Color(1, 1, 1, 1)

@export var sh_border_thickness: float = 0.05
@export var sh_border_softness: float = 0.02
@export var sh_border_color: Color = Color(1.0, 0.8, 0.2, 1.0)

@export var sh_fade_amount: float = 0.0
@export var sh_fade_softness: float = 0.05

# === Экспорт: паузы ===
@export var use_pause_softness: bool = true
@export var sh_border_softness_pause: float = 0.2
@export var sh_border_softness_normal: float = 0.02

# === Экспорт: запуск анимации ===
@export var run_only_when_debug_pressed: bool = true

# === Сегменты анимации ===
var segments = [
	{ "s": 0.0, "e": 1.0, "d": 0.25 }, # проявление
	{ "s": 1.0, "e": 0.5, "d": 0.15 }, # откат
	{ "s": 0.5, "e": 0.5, "d": 0.10 }, # пауза
	{ "s": 0.5, "e": 1.0, "d": 0.15 }, # снова полностью
	{ "s": 1.0, "e": 1.0, "d": 0.25 }, # пауза
	{ "s": 1.0, "e": 0.0, "d": 0.25 }, # исчезновение
	{ "s": 0.0, "e": 0.0, "d": 0.50 }, # пауза
]

var i := 0
var t := 0.0

func _ready():
	#await get_tree().process_frame
	#await get_tree().process_frame
	texture_rect_node.texture = sub_viewport_node.get_texture()
	_apply_shader_params_initial()

func _process(delta: float):
	# камера
	if player and camera_face:
		var player_pos = player.global_transform.origin
		var forward = -player.global_transform.basis.z.normalized()
		var cam_pos = player_pos + forward * distance + Vector3(0, height, 0)
		camera_face.global_transform.origin = cam_pos
		camera_face.look_at(player_pos + Vector3(0, height, 0), Vector3.UP)

	# обновляем статические параметры
	_apply_shader_params_static()

	# анимация
	var allow_run = true
	if run_only_when_debug_pressed:
		allow_run = Input.is_action_pressed("DEBUG")

	if allow_run:
		var seg = segments[i]
		t += delta
		var dur: float = seg["d"]
		var start_val: float = seg["s"]
		var end_val: float = seg["e"]

		var progress = clamp(t / dur, 0.0, 1.0) if dur > 0.0 else 1.0
		sh_fade_amount = lerp(start_val, end_val, progress)
		shader_mat.set_shader_parameter("fade_amount", sh_fade_amount)

		# пауза → мягкая рамка
		if use_pause_softness and start_val == end_val:
			shader_mat.set_shader_parameter("border_softness", sh_border_softness_pause)
		else:
			shader_mat.set_shader_parameter("border_softness", sh_border_softness_normal)

		if progress >= 1.0:
			i = (i + 1) % segments.size()
			t = 0.0
	else:
		if run_only_when_debug_pressed:
			sh_fade_amount = 0.0
			shader_mat.set_shader_parameter("fade_amount", sh_fade_amount)
			shader_mat.set_shader_parameter("border_softness", sh_border_softness_normal)
			i = 0
			t = 0.0

func _apply_shader_params_initial():
	if shader_mat == null: return
	shader_mat.set_shader_parameter("diamond_softness", sh_diamond_softness)
	shader_mat.set_shader_parameter("aspect", sh_aspect)
	shader_mat.set_shader_parameter("modulate_color", sh_modulate_color)
	shader_mat.set_shader_parameter("border_thickness", sh_border_thickness)
	shader_mat.set_shader_parameter("border_softness", sh_border_softness)
	shader_mat.set_shader_parameter("border_color", sh_border_color)
	shader_mat.set_shader_parameter("fade_amount", sh_fade_amount)
	shader_mat.set_shader_parameter("fade_softness", sh_fade_softness)

func _apply_shader_params_static():
	if shader_mat == null: return
	shader_mat.set_shader_parameter("aspect", sh_aspect)
	shader_mat.set_shader_parameter("modulate_color", sh_modulate_color)
	shader_mat.set_shader_parameter("border_thickness", sh_border_thickness)
	shader_mat.set_shader_parameter("border_color", sh_border_color)
	shader_mat.set_shader_parameter("fade_softness", sh_fade_softness)
