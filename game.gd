extends Node3D


#@export var camera_path: NodePath
#@export var start_camera_point: NodePath
#
#var camera: Node3D
#var start_point: Node3D
#
#signal intro_finished
#
#func _ready():
	##$Intro_for_inspiration.play()
	##Engine.max_fps = 30
	#camera = get_node(camera_path)
	#start_point = get_node(start_camera_point)
#
	## Ставим камеру в стартовую позицию
	#camera.set_instant_position(start_point.global_position, start_point.rotation_degrees)
#
	## Запускаем плавный переход
	#_play_intro_transition()
	#
#func _play_intro_transition():
	#var tween = create_tween()
	#tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
#
	## Камера едет к игроку
	#var player = get_tree().get_first_node_in_group("player")
	#var target_pos = player.global_position + camera.current_offset
#
	#tween.tween_property(camera, "global_position", target_pos, 2.0)
	#tween.tween_property(camera, "rotation_degrees:x", camera.isometric_rotation_x_degrees, 2.0)
	#tween.tween_property(camera, "rotation_degrees:y", camera.isometric_rotation_y_degrees, 2.0)
#
	#tween.tween_callback(func ():
		#emit_signal("intro_finished")
		#print("GameManager: intro finished -> enabling gameplay")
	#)

	



	
