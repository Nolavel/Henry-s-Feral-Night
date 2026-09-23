extends Node3D
class_name InteractionManager

signal interaction_performed(area: InteractiveArea)

## Autoload that arbitrates the interact key; looked up rather than preloaded
## so a scene opened without autoloads still runs.
const INPUT_SYSTEMS_PATH: NodePath = ^"/root/InputSystems"

var detected_areas: Array[InteractiveArea] = []

@export var player: CharacterBody3D
@export var shape_cast: ShapeCast3D

func _ready() -> void:
	if not shape_cast:
		shape_cast = $ShapeCast3D

func _physics_process(_delta: float) -> void:
	if not shape_cast:
		return
	
	shape_cast.force_shapecast_update()
	var new_areas: Array[InteractiveArea] = []
	
	# Проверяем все коллизии ShapeCast с группой "interactables"
	for i in range(shape_cast.get_collision_count()):
		var collider = shape_cast.get_collider(i)
		if collider.is_in_group("interactables"):
			var area = _find_parent_interactive_area(collider)
			if area and area not in new_areas:
				new_areas.append(area)
				
	# Обновляем состояния областей
	for area in detected_areas:
		if area not in new_areas:
			area.set_shape_cast_detected(false)
	
	for area in new_areas:
		if area not in detected_areas:
			area.set_shape_cast_detected(true)
	
	detected_areas = new_areas

func _find_parent_interactive_area(node: Node) -> InteractiveArea:
	var current = node
	var max_depth = 10  # Ограничиваем глубину поиска для производительности
	var depth = 0
	
	while current and depth < max_depth:
		if current is InteractiveArea:
			return current
		current = current.get_parent()
		depth += 1
	
	return null


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and not _is_interact_claimed():
		_try_interact()


## True while something else owns the interact key — the sleep dialog, say.
## Confirming sleep with E must not also trigger the nearest object.
func _is_interact_claimed() -> bool:
	var input_systems: Node = get_node_or_null(INPUT_SYSTEMS_PATH)
	if input_systems == null:
		return false
	return input_systems.is_interact_claimed()

func _try_interact() -> void:
	for area in detected_areas:
		if area.can_interact():
			area.interact()
			interaction_performed.emit(area)
			return

func get_interactable_areas() -> Array[InteractiveArea]:
	var interactable: Array[InteractiveArea] = []
	for area in detected_areas:
		if area.can_interact():
			interactable.append(area)
	return interactable

func has_available_interactions() -> bool:
	return get_interactable_areas().size() > 0

func get_areas_by_type(interaction_type: InteractiveArea.InteractionType) -> Array[InteractiveArea]:
	var filtered_areas: Array[InteractiveArea] = []
	for area in detected_areas:
		if area.interaction_type == interaction_type and area.can_interact():
			filtered_areas.append(area)
	return filtered_areas

func get_pickup_areas_by_subtype(pickup_subtype: InteractiveArea.PickupSubtype) -> Array[InteractiveArea]:
	var filtered_areas: Array[InteractiveArea] = []
	for area in detected_areas:
		if area.interaction_type == InteractiveArea.InteractionType.PICKUP and \
		   area.pickup_subtype == pickup_subtype and area.can_interact():
			filtered_areas.append(area)
	return filtered_areas

func interact_with_closest() -> void:
	var closest = get_closest_interactable()
	if closest:
		closest.interact()
		interaction_performed.emit(closest)

func get_closest_interactable() -> InteractiveArea:
	var interactable_areas = get_interactable_areas()
	if interactable_areas.is_empty():
		return null
	
	if not player:
		return interactable_areas[0]
	
	# Находим ближайшую область
	var closest_area: InteractiveArea = null
	var closest_distance: float = INF
	
	for area in interactable_areas:
		var distance = player.global_position.distance_to(area.global_position)
		if distance < closest_distance:
			closest_distance = distance
			closest_area = area
	
	return closest_area
	
func interact_with_type(interaction_type: InteractiveArea.InteractionType) -> void:
	var areas = get_areas_by_type(interaction_type)
	if not areas.is_empty():
		areas[0].interact()
		interaction_performed.emit(areas[0])

func interact_with_pickup_subtype(pickup_subtype: InteractiveArea.PickupSubtype) -> void:
	var areas = get_pickup_areas_by_subtype(pickup_subtype)
	if not areas.is_empty():
		areas[0].interact()
		interaction_performed.emit(areas[0])

# Утилитарные методы для получения статистики
func get_interaction_stats() -> Dictionary:
	var stats = {
		"total_areas": detected_areas.size(),
		"interactable_areas": get_interactable_areas().size(),
		"by_type": {},
		"pickup_by_subtype": {}
	}
	
	# Статистика по типам взаимодействия
	for type in InteractiveArea.InteractionType.values():
		var count = get_areas_by_type(type).size()
		stats.by_type[InteractiveArea.InteractionType.keys()[type]] = count
	
	# Статистика по подтипам пикапов
	for subtype in InteractiveArea.PickupSubtype.values():
		var count = get_pickup_areas_by_subtype(subtype).size()
		stats.pickup_by_subtype[InteractiveArea.PickupSubtype.keys()[subtype]] = count
	
	return stats
