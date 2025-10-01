# Flashlight Node - вся логика фонаря
extends Node3D

@onready var projector: SpotLight3D = $Projector

@export var follow_speed: float = 5.0

@export var flashlight_color: Color = Color(0.6, 0.8, 1.0)
@export var flashlight_energy_on: float = 16.0
@export var flashlight_energy_off: float = 0.0
@export var flashlight_range: float = 1005.0
@export var flashlight_angle: float = 20.0

# ramp controls
@export var ramp_time: float = 0.35
@export var ramp_profile: int = 2 # 0=snappy, 1=cinematic, 2=soft

# flicker controls
@export var flicker_intensity: float = 0.22
@export var flicker_speed: float = 12.0

# secondary mode
@export var wide_angle: float = 55.0
@export var wide_range: float = 600.0
@export var narrow_angle: float = 20.0
@export var narrow_range: float = 1005.0

var flashlight_toggle := false
var smooth_dir: Vector3

var range_tween: Tween
var energy_tween: Tween
var shadow_tween: Tween

var wide_mode := false
var flicker_time := 0.0

func _ready() -> void:
	projector.light_color = flashlight_color
	projector.spot_range = 0.0
	projector.spot_angle = flashlight_angle
	projector.spot_attenuation = 1.5
	projector.light_energy = flashlight_energy_off
	projector.shadow_enabled = false
	
	smooth_dir = -projector.global_transform.basis.z

# === Публичный API ===
func toggle() -> void:
	if flashlight_toggle:
		flashlight_off()
	else:
		flashlight_on()

func is_on() -> bool:
	return flashlight_toggle

func toggle_mode() -> void:
	wide_mode = !wide_mode

	var target_angle: float
	var target_range: float

	if wide_mode:
		target_angle = wide_angle
		target_range = wide_range
	else:
		target_angle = narrow_angle
		target_range = narrow_range

	var t := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(projector, "spot_angle", target_angle, 0.3)
	t.tween_property(projector, "spot_range", target_range, 0.3)

# === Включение фонаря ===
func flashlight_on() -> void:
	_kill_tweens()
	flashlight_toggle = true

	projector.shadow_enabled = false
	projector.spot_range = 0.0
	projector.light_energy = 0.0

	var trans := _profile_trans()
	var ease := _profile_ease_out()

	range_tween = create_tween().set_trans(trans).set_ease(ease)
	range_tween.tween_property(projector, "spot_range", flashlight_range, ramp_time)

	energy_tween = create_tween().set_trans(trans).set_ease(ease)
	energy_tween.tween_property(projector, "light_energy", flashlight_energy_on, ramp_time * 0.8)

	shadow_tween = create_tween()
	shadow_tween.tween_interval(ramp_time * 0.6)
	shadow_tween.finished.connect(func(): projector.shadow_enabled = true)

# === Выключение фонаря ===
func flashlight_off() -> void:
	_kill_tweens()
	flashlight_toggle = false

	var trans := _profile_trans()
	var ease := _profile_ease_in()

	energy_tween = create_tween().set_trans(trans).set_ease(ease)
	energy_tween.tween_property(projector, "light_energy", flashlight_energy_off, ramp_time * 0.5)

	range_tween = create_tween().set_trans(trans).set_ease(ease)
	range_tween.tween_property(projector, "spot_range", 0.0, ramp_time * 0.6)

	var end_tween := create_tween()
	end_tween.tween_interval(ramp_time * 0.6)
	end_tween.finished.connect(func(): projector.shadow_enabled = false)

func _kill_tweens() -> void:
	if range_tween and range_tween.is_valid(): range_tween.kill()
	if energy_tween and energy_tween.is_valid(): energy_tween.kill()
	if shadow_tween and shadow_tween.is_valid(): shadow_tween.kill()

func _process(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera:
		var mouse_pos := get_viewport().get_mouse_position()
		var ray_origin := camera.project_ray_origin(mouse_pos)
		var ray_dir := camera.project_ray_normal(mouse_pos)

		var target := ray_origin + ray_dir * 20.0
		var target_dir := (target - projector.global_position).normalized()

		smooth_dir = smooth_dir.slerp(target_dir, follow_speed * delta)

		# ограничение угла ±60° относительно родителя
		var parent_forward: Vector3 = -get_parent().global_transform.basis.z
		var angle: float = acos(clamp(parent_forward.dot(smooth_dir), -1.0, 1.0))
		var max_angle: float = deg_to_rad(60.0)
		if angle > max_angle:
			var axis: Vector3 = parent_forward.cross(smooth_dir).normalized()
			var limited_dir: Vector3 = parent_forward.rotated(axis, max_angle)
			smooth_dir = limited_dir.normalized()

		var clamped_basis := Basis.looking_at(smooth_dir, Vector3.UP)
		projector.global_transform.basis = clamped_basis

	# === Flicker эффект ===
	if flashlight_toggle:
		flicker_time += delta * flicker_speed
		var noise := sin(flicker_time) * 0.5 + 0.5
		var flicker := 1.0 - flicker_intensity + noise * flicker_intensity
		projector.light_energy = lerp(flashlight_energy_off, flashlight_energy_on, flicker)

# --- ramp profiles ---
func _profile_trans() -> int:
	match ramp_profile:
		0: return Tween.TRANS_QUAD
		1: return Tween.TRANS_BACK
		2: return Tween.TRANS_SINE
		_: return Tween.TRANS_BACK

func _profile_ease_out() -> int:
	return Tween.EASE_OUT

func _profile_ease_in() -> int:
	return Tween.EASE_IN
