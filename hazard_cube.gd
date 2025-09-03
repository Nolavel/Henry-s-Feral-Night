extends StaticBody3D

@export var camera_shake_magnitude = 0.2
@export var camera_shake_speed = 0.5
@export var camera_shake_duration = 0.1

func _ready():
	# Добавляем этот узел в группу "HazardCubes", чтобы Player мог проверять её.
	# Также это используется для удобства в самом скрипте камеры, если нужно.
	add_to_group("HazardCubes")
	
	# Подключаем сигнал, который сработает, когда что-то войдет в эту область.
	# Если HazardCube - Area3D, используем body_entered.
	# Если HazardCube - StaticBody3D, используем body_shape_entered (или body_entered, если это Godot 4).
	# Для простоты и гибкости, особенно если это триггер, Area3D + body_entered - предпочтительнее.
	print("HazardCube loaded and ready. Listening for body_entered.")

func _on_body_entered(body: Node3D):
	# Проверяем, что вошедшее тело - это наш игрок.
	# Для этого мы используем группу "player_group", которую добавили игроку.
	if body.is_in_group("player_group"):
		print("Player entered HazardCube! Initiating camera shake.")
		
		# Вызываем метод shake_camera у игрока (или напрямую у камеры)
		# Поскольку камера у нас теперь отдельный узел в сцене и игрок знает, как её найти,
		# мы можем вызвать shake_camera через игрока, который, в свою очередь, передаст это камере.
		if body.has_method("trigger_camera_shake"):
			body.trigger_camera_shake(camera_shake_magnitude, camera_shake_speed, camera_shake_duration)
		else:
			printerr("Player does not have 'trigger_camera_shake' method.")
