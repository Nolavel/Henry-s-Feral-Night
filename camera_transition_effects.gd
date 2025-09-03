extends Node
class_name CameraTransitionEffects

@export var transition_duration: float = 0.4

# === ССЫЛКИ ===
var system_camera: Camera3D
var player_node: Node3D
var overlay_container: Control
var world_environment: WorldEnvironment

# === СОСТОЯНИЕ ===
var current_tween: Tween
var overlay_nodes: Array[Control] = []

func _ready():
	name = "CameraTransitionEffects"
	setup_overlay_container()
	
	
func setup(camera: Camera3D, player: Node3D, env: WorldEnvironment):
	system_camera = camera
	player_node = player
	world_environment = env
	
	if system_camera and not overlay_container.get_parent():
		system_camera.add_child(overlay_container)
	
func setup_overlay_container():
	overlay_container = Control.new()
	overlay_container.name = "TransitionOverlay"
	overlay_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay_container.visible = false

# === ЭФФЕКТЫ ===

func play_enter_transition():
	overlay_container.visible = true
	var rect := ColorRect.new()
	rect.color = Color(0, 0, 0, 1)
	overlay_container.add_child(rect)
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var tween = create_tween()
	tween.tween_property(rect, "modulate:a", 0.0, transition_duration * 1.25) # плавнее
	tween.tween_callback(rect.queue_free)
	tween.tween_callback(func(): overlay_container.visible = false)

func play_exit_transition():
	overlay_container.visible = true
	var rect := ColorRect.new()
	rect.color = Color(1, 1, 1, 0)
	overlay_container.add_child(rect)
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var tween = create_tween()
	tween.tween_property(rect, "modulate:a", 1.0, transition_duration * 0.25) # короче
	tween.tween_callback(rect.queue_free)
	tween.tween_callback(func(): overlay_container.visible = false)

func play_state_transition():
	overlay_container.visible = true
	var rect := ColorRect.new()
	rect.color = Color(0.05, 0.05, 0.05, 0.8)
	overlay_container.add_child(rect)
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var tween = create_tween()
	tween.tween_property(rect, "modulate:a", 0.0, transition_duration) # стандартно
	tween.tween_callback(rect.queue_free)
	tween.tween_callback(func(): overlay_container.visible = false)

	# тряска камеры
	if system_camera:
		var shake = create_tween()
		shake.tween_property(system_camera, "rotation_degrees:z", 2.0, transition_duration * 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		shake.tween_property(system_camera, "rotation_degrees:z", -2.0, transition_duration * 0.25)
		shake.tween_property(system_camera, "rotation_degrees:z", 0.0, transition_duration * 0.25)
