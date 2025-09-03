# TransitionManager.gd
extends Node2D

@onready var fade_rect: ColorRect = $CanvasLayer/FadeRect
@onready var animator: AnimationPlayer = $CanvasLayer/TransitionAnimator

var target_scene_path = ""

func _ready():
	print("TransitionManager _ready() called.")

	# Проверка, найден ли CanvasLayer
	var canvas_layer_node = get_node_or_null("CanvasLayer")
	if canvas_layer_node == null:
		printerr("ERROR: CanvasLayer node not found at path 'CanvasLayer'. Check name and hierarchy.")
		return # Прекращаем выполнение, так как дальше будет ошибка

	# Проверка, найден ли FadeRect
	if fade_rect == null:
		printerr("ERROR: fade_rect is null. Check path $CanvasLayer/FadeRect or name 'FadeRect' under CanvasLayer.")
		return # Прекращаем выполнение

	# Проверка, найден ли Animator
	if animator == null:
		printerr("ERROR: animator is null. Check path $CanvasLayer/TransitionAnimator or name 'TransitionAnimator' under CanvasLayer.")
		return # Прекращаем выполнение

	print("All nodes found: FadeRect and TransitionAnimator.")

	fade_rect.modulate.a = 1.0 # Убедитесь, что экран полностью черный в начале
	animator.play("fade_in") # Запускаем анимацию осветления

func change_scene_to(path: String):
	target_scene_path = path
	# Убедитесь, что fade_rect не null перед использованием
	if fade_rect != null:
		fade_rect.modulate.a = 0.0 # Убедимся, что начинаем с прозрачного для fade_out
	else:
		printerr("ERROR: fade_rect is null in change_scene_to. Cannot start fade_out.")
		get_tree().change_scene_to_file(target_scene_path) # Смена сцены без эффекта
		return

	if animator != null:
		animator.play("fade_out")
		animator.animation_finished.connect(_on_fade_out_finished, CONNECT_ONE_SHOT)
	else:
		printerr("ERROR: animator is null in change_scene_to. Cannot start fade_out animation.")
		get_tree().change_scene_to_file(target_scene_path) # Смена сцены без эффекта

func _on_fade_out_finished(anim_name: String):
	if anim_name == "fade_out":
		get_tree().change_scene_to_file(target_scene_path)
