# CompassUI.gd
extends TextureRect # Или Control, если вы использовали Control вместо TextureRect

@export var player_node_path: NodePath # Путь к узлу вашего игрока (CharacterBody3D)
@export var player_head_node_path: NodePath # Путь к узлу Head игрока (для направления взгляда)

var player: Node3D = null
var player_head: Node3D = null

func _ready():
	# Поиск узлов игрока и его головы
	if player_node_path:
		player = get_node(player_node_path)
	if player == null:
		printerr("CompassUI: Player node not found via player_node_path!")
		# Попытка найти игрока по группе, если путь не указан или неверен
		player = get_tree().get_first_node_in_group("player_group")
		if player == null:
			printerr("CompassUI: Player node not found in 'player_group'!")
			set_process(false) # Отключаем _process, если игрок не найден
			return

	if player_head_node_path:
		player_head = get_node(player_head_node_path)
	if player_head == null:
		printerr("CompassUI: Player Head node not found via player_head_node_path! Falling back to player's global_transform for rotation.")
		# Если голова не найдена, будем использовать направление самого игрока.
		# Однако для Top-down камеры, где голова может вращаться отдельно, это не идеально.
		# Убедитесь, что player_head_node_path корректен, например, "../Player/Head"
		# или просто "Head" если CompassUI находится в той же сцене что и Player и Head.

	# Убедитесь, что индикатор расположен по центру TextureRect, к которому прикреплен скрипт
	# Это свойство должно быть настроено в редакторе, но для уверенности можно и тут
	self.pivot_offset = size / 2.0 # Устанавливаем точку вращения в центр индикатора

func _process(delta):
	if player == null:
		return

	var forward_direction = Vector3.ZERO

	# Используем направление Head для более точного компаса, если Head существует
	if player_head:
		# Направление "вперед" головы игрока (глобальное Z-направление головы)
		# Если голова смотрит вперед по Z, то transform.basis.z - это "назад"
		# transform.basis.x - вправо, transform.basis.y - вверх
		# Направление "вперед" обычно соответствует -transform.basis.z (для правой системы координат)
		forward_direction = -player_head.global_transform.basis.z
	else:
		# Если голова не найдена, используем направление игрока
		forward_direction = -player.global_transform.basis.z

	# Игнорируем вертикальную составляющую для горизонтального компаса
	forward_direction.y = 0
	forward_direction = forward_direction.normalized()

	# Север (N) обычно это Vector3(0, 0, -1) в Godot (вдоль отрицательной оси Z)
	var north_direction = Vector3(0, 0, -1)

	# Вычисляем угол между направлением игрока и Севером
	# Угол в радианах
	var angle = north_direction.signed_angle_to(forward_direction, Vector3.UP)

	# Устанавливаем вращение индикатора
	# Rotation degrees - это локальное вращение по Z для 2D UI элементов
	# Чтобы индикатор вращался так, будто он на компасе, нужно вращать его по Z
	# Индикатор должен вращаться НАПРАВЛЕНИЮ ИГРОКА.
	# Если 0 градусов - это Север (N), то при повороте игрока на Восток (+90 град)
	# индикатор должен показать на Восток.
	# Godot TextureRect rotation_degrees вращает против часовой стрелки,
	# так что angle_to уже должен давать правильный результат.
	rotation_degrees = rad_to_deg(angle)
