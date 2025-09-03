extends Camera3D

func _ready():
	pass

func _physics_process(delta): # Используем _physics_process для синхронизации с движением игрока
	pass
		# Можно добавить look_at(player.global_position, Vector3.UP) если нужно, чтобы камера всегда смотрела на игрока.
