# ✅ Script: RoofController.gd
# (Eng) Makes roof fade away when player gets under it, handles collision bullshit too
# (Rus) Делает крышу прозрачной когда игрок залезает под неё, разруливает коллизии тоже
# 🧩 Playable — usable in-game, feels okay / играбельный кусок, можно юзать

extends Node3D 

@onready var roof_mesh: MeshInstance3D = $"../../church roof/world/geometry_0"
@onready var trigger_area_roof: Area3D = $TriggerArea_Roof
@export var player_body: CharacterBody3D
@export var fade_duration: float = 0.45   # (Eng) How long it takes to fade / (Rus) Сколько времени займёт исчезновение

# (Eng) Occlusion control variables - decides what counts as "walls"
# (Rus) Переменные контроля окклюзии - решает что считается "стенами"
@export var occlusion_layer_mask: int = 1   # битовая маска слоя(ов) которые считаются "стенами" (совместимо с PlayerVisibilityController.wall_collision_layer)
var _occluder_colliders_info: Array = []   # [{"node": CollisionObject3D, "layer": int}, ...]

# (Eng) Current state tracking - keeps tabs on what the fuck is happening
# (Rus) Отслеживание текущего состояния - следит за тем что происходит
var original_material: Material = null
var fade_material: StandardMaterial3D = null
var is_roof_hidden: bool = false
var player_inside_area: bool = false
var roof_tween = null   # без аннотации типа — избегаем ошибки

func _ready() -> void:
	# (Eng) Safety checks - make sure we got our shit together
	# (Rus) Проверки безопасности - убеждаемся что всё на месте
	if not roof_mesh:
		push_error("Roof mesh not found!")
		return
	if not trigger_area_roof:
		push_error("Trigger area not found!")
		return

	# (Eng) Grab original material - steal it before we fuck with it
	# (Rus) Берём оригинальный материал - крадём его до того как начнём с ним возиться
	original_material = roof_mesh.get_surface_override_material(0)
	if original_material == null and roof_mesh.mesh:
		if roof_mesh.mesh.get_surface_count() > 0:
			original_material = roof_mesh.mesh.surface_get_material(0)

	# (Eng) Get base color from original material if it's StandardMaterial3D
	# (Rus) Получаем базовый цвет из оригинального материала если он StandardMaterial3D
	var base_color: Color = Color(1, 1, 1, 1)
	if original_material and original_material is StandardMaterial3D:
		base_color = (original_material as StandardMaterial3D).albedo_color

	# (Eng) Create fade material but don't assign it yet - prepare for transparency magic
	# (Rus) Создаём материал для исчезновения но пока не назначаем - готовим магию прозрачности
	fade_material = StandardMaterial3D.new()
	fade_material.albedo_color = base_color
	fade_material.flags_transparent = true
	fade_material.albedo_color.a = 1.0

	# (Eng) Roof visible by default and opaque
	# (Rus) Крыша видна по-умолчанию и непрозрачна
	roof_mesh.visible = true

	# (Eng) Collect all collision objects near mesh - prepare for layer manipulation fuckery
	# (Rus) Собираем все объекты коллизии рядом с мешем - готовим манипуляции со слоями
	_collect_occluder_colliders(roof_mesh.get_parent())

	print("Roof controller ready. Original material:", original_material)


# (Eng) Signal handlers - react when player enters/exits like a proper bouncer
# (Rus) Обработчики сигналов - реагируем когда игрок входит/выходит как нормальный вышибала
func _on_trigger_area_roof_body_entered(body: Node) -> void:
	if not (body == player_body or (body is Node and body.is_in_group("player"))):
		return
	if player_inside_area:
		return
	player_inside_area = true
	_hide_roof_smooth()

func _on_trigger_area_roof_body_exited(body: Node) -> void:
	if not (body == player_body or (body is Node and body.is_in_group("player"))):
		return
	if not player_inside_area:
		return
	player_inside_area = false
	_show_roof_smooth()


# (Eng) Fade out - make roof disappear smoothly like a magic trick
# (Rus) Исчезновение - заставляем крышу исчезнуть плавно как фокус
func _hide_roof_smooth() -> void:
	if is_roof_hidden:
		return
	is_roof_hidden = true

	# (Eng) Kill previous tween - stop any ongoing animation bullshit
	# (Rus) Убиваем предыдущий твин - останавливаем любую текущую анимацию
	if roof_tween:
		roof_tween.kill()
		roof_tween = null

	# (Eng) Apply transparent material right before animation
	# (Rus) Назначаем прозрачный материал прямо перед анимацией
	roof_mesh.set_surface_override_material(0, fade_material)
	var c = fade_material.albedo_color
	c.a = 1.0
	fade_material.albedo_color = c

	# (Eng) Create tween and animate alpha to 0 - fade that bastard out
	# (Rus) Создаём твин и анимируем альфу до 0 - убираем эту штуку
	roof_tween = create_tween()
	roof_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	roof_tween.tween_property(fade_material, "albedo_color:a", 0.0, fade_duration)
	roof_tween.tween_callback(Callable(self, "_on_fade_out_complete"))

func _on_fade_out_complete() -> void:
	# (Eng) Hide mesh and restore original material - clean up after ourselves
	# (Rus) Скрываем меш и восстанавливаем оригинал - убираем за собой
	roof_mesh.visible = false
	roof_mesh.set_surface_override_material(0, original_material)

	# (Eng) After complete hiding disable occluder layers on all found colliders
	# (Rus) После полного скрытия отключаем occluder-слои у всех найденных коллайдеров
	_disable_occluder_collisions()

	roof_tween = null


# (Eng) Fade in - bring that roof back like resurrection
# (Rus) Появление - возвращаем крышу как воскрешение
func _show_roof_smooth() -> void:
	if not is_roof_hidden:
		return
	is_roof_hidden = false

	if roof_tween:
		roof_tween.kill()
		roof_tween = null

	# (Eng) Restore collisions immediately - roof becomes obstacle again during appearance
	# (Rus) Восстанавливаем коллизии сразу - во время появления крыша снова препятствие
	_restore_occluder_collisions()

	# (Eng) Make mesh visible and set fade material with alpha 0
	# (Rus) Делаем меш видимым и ставим fade_material с альфой 0
	roof_mesh.visible = true
	roof_mesh.set_surface_override_material(0, fade_material)
	var c = fade_material.albedo_color
	c.a = 0.0
	fade_material.albedo_color = c

	roof_tween = create_tween()
	roof_tween.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	roof_tween.tween_property(fade_material, "albedo_color:a", 1.0, fade_duration)
	roof_tween.tween_callback(Callable(self, "_on_fade_in_complete"))

func _on_fade_in_complete() -> void:
	# (Eng) Return original material - back to normal state
	# (Rus) Возвращаем оригинальный материал - обратно к нормальному состоянию
	roof_mesh.set_surface_override_material(0, original_material)
	roof_tween = null


# =====================
# (Eng) Collision management - collect/disable/restore collision layers like a pro
# (Rus) Управление коллизией - собираем/отключаем/восстанавливаем слои коллизии как профи
# =====================
func _collect_occluder_colliders(node: Node) -> void:
	# (Eng) Recursively collect all CollisionObject3D - find every collision bastard
	# (Rus) Рекурсивно собираем все CollisionObject3D - находим каждый коллизионный объект
	if node is CollisionObject3D:
		# (Eng) Save original layer to restore later
		# (Rus) Сохраняем оригинальный слой чтобы потом восстановить
		_occluder_colliders_info.append({"node": node, "layer": node.collision_layer})
	for child in node.get_children():
		_collect_occluder_colliders(child)

func _disable_occluder_collisions() -> void:
	# (Eng) Disable collision layers on all collected objects - make them non-blocking
	# (Rus) Отключаем слои коллизии у всех собранных объектов - делаем их непрепятствующими
	for info in _occluder_colliders_info:
		var node: Node = info["node"]
		if not is_instance_valid(node):
			continue
		var orig_layer: int = info["layer"]
		var new_layer: int = orig_layer & ~occlusion_layer_mask
		# (Eng) Deferred to not break physics in current step
		# (Rus) Отложенно, чтобы не ломать физику в текущем шаге
		node.set_deferred("collision_layer", new_layer)

func _restore_occluder_collisions() -> void:
	# (Eng) Restore original collision layers - put everything back where it was
	# (Rus) Восстанавливаем оригинальные слои коллизии - ставим всё обратно как было
	for info in _occluder_colliders_info:
		var node: Node = info["node"]
		if not is_instance_valid(node):
			continue
		var orig_layer: int = info["layer"]
		node.set_deferred("collision_layer", orig_layer)
