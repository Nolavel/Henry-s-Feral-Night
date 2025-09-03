extends ColorRect

func _ready():
	print("Начинаем затухание")
	# Создаем анимацию затухания
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 2.0)
	# После анимации удаляем элемент
	tween.tween_callback(queue_free)
