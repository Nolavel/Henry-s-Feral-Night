extends Node3D

@export var player_body: CharacterBody3D
@onready var effect_mesh: MeshInstance3D = $ImageSpeedEffect   # QuadMesh с твоим шейдером

@export var offset_distance: float = 0.5   # насколько далеко сзади
@export var y_offset: float = 0.05         # чуть выше земли

var shader_mat: ShaderMaterial

func _ready() -> void:
	if not player_body:
		player_body = get_tree().get_first_node_in_group("player")
	if not player_body:
		printerr("Игрок не найден!")
		return

	# 1) если материал задан как material_override — берём его
	if effect_mesh.material_override != null:
		shader_mat = effect_mesh.material_override as ShaderMaterial

	# 2) иначе пробуем активный материал поверхности 0 (у QuadMesh одна поверхность)
	if shader_mat == null:
		shader_mat = effect_mesh.get_active_material(0) as ShaderMaterial

	# 3) иначе пробуем surface override (на всякий случай)
	if shader_mat == null:
		shader_mat = effect_mesh.get_surface_override_material(0) as ShaderMaterial

	if shader_mat == null:
		printerr("У MeshInstance3D нет ShaderMaterial. Повесь шейдер на material_override или на поверхность 0.")
	else:
		print("SpeedEffect: шейдер найден")
	effect_mesh.visible = false
	shader_mat.set_shader_parameter("particle_color", Color(0.6, 0.6, 0.6, 0.8))  # Почти черный
	print("SpeedEffect: готово")

func _physics_process(delta: float) -> void:
	if not player_body:
		return

	var speed := player_body.velocity.length()

	if speed > 2.0:
		effect_mesh.visible = true

		# Получаем нормализованное направление движения игрока
		var dir := Vector3.ZERO
		if speed > 0.001:
			dir = player_body.velocity.normalized()

		# Позиционируем объект-эффект позади игрока
		effect_mesh.global_position = player_body.global_position + Vector3(0, y_offset, 0) - dir * offset_distance

		# Вручную задаём вращение, основываясь на векторе направления
		# Мы используем направление, чтобы создать кватернион, который представляет правильное вращение
		effect_mesh.look_at(player_body.global_position + dir, Vector3.UP)

		# Остальная часть вашего кода для эффектов частиц...
		if shader_mat:
			if speed > 10.0:
				shader_mat.set_shader_parameter("particle_count", 20)
				shader_mat.set_shader_parameter("particle_speed", 1.0)
				shader_mat.set_shader_parameter("spread_angle", PI)
			elif speed > 5.0:
				shader_mat.set_shader_parameter("particle_count", 10)
				shader_mat.set_shader_parameter("particle_speed", 0.5)
				shader_mat.set_shader_parameter("spread_angle", PI * 0.5)
			else:
				shader_mat.set_shader_parameter("particle_count", 1)
				shader_mat.set_shader_parameter("particle_speed", 0.01)
				shader_mat.set_shader_parameter("spread_angle", PI / 6)
	else:
		effect_mesh.visible = false
