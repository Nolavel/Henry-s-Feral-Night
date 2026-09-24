class_name InteractComponent
extends Node3D

## ADT's InteractComponent on InteractiveArea targets: a focus cast, then an
## intent cone, pick the target; F acts at arm's length or walks over first.

## What is targeted and whether it is already within arm's reach.
signal interact_target_changed(target: InteractiveArea, in_reach: bool)
## Emitted after F acted on a target.
signal interaction_performed(target: InteractiveArea)

@export_group("Focus")
## Length of the focus cast straight ahead, metres.
@export var focus_length: float = 1.8
@export var focus_radius: float = 0.4

@export_group("Intent")
## Second tier, used when the focus cast finds nothing: what Henry plausibly reaches for.
@export var intent_radius: float = 2.5
## Full width of the intent cone around facing, degrees; excludes only a rear arc.
@export var intent_angle_deg: float = 240.0

@export_group("Approach")
## F acts on the spot inside this flat distance, otherwise Henry walks over.
@export var pickup_distance: float = 0.9
## Inside this distance the object shows its F prompt instead of a marker.
@export var prompt_distance: float = 2.0
## Gives up a walk that stops making progress, seconds.
@export var approach_timeout: float = 4.0

var current_target: InteractiveArea = null

var _player: CharacterBody3D
var _focus_cast: ShapeCast3D
var _last_in_reach: bool = false
var _last_in_prompt: bool = false
var _pending: InteractiveArea = null
var _approach_elapsed: float = 0.0
var _approach_stopped: bool = false


func _ready() -> void:
	_player = get_parent() as CharacterBody3D
	_focus_cast = _build_focus_cast()
	add_child(_focus_cast)
	var input_systems: Node = get_node_or_null(^"/root/InputSystems")
	if input_systems != null:
		input_systems.connect(&"interact_pressed", try_interact)
	if _player != null and _player.has_signal(&"movement_stopped"):
		_player.connect(&"movement_stopped", _on_player_movement_stopped)


func _physics_process(delta: float) -> void:
	if _player == null:
		return
	detect_target()
	_update_approach(delta)


## Re-picks the target now; normally run every physics frame.
func detect_target() -> void:
	if not is_instance_valid(current_target):
		current_target = null
	var found: InteractiveArea = _find_focus_target()
	if found == null:
		found = _find_intent_target()
	var distance: float = _flat_distance_to(found) if found != null else INF
	var in_reach: bool = distance <= pickup_distance
	var in_prompt: bool = distance <= prompt_distance
	var changed: bool = found != current_target
	if changed:
		if current_target != null:
			current_target.set_target_state(false, false)
		current_target = found
		if found != null:
			found.set_target_state(true, in_prompt)
	elif found != null and in_prompt != _last_in_prompt:
		found.set_target_state(true, in_prompt)
	if changed or in_reach != _last_in_reach or in_prompt != _last_in_prompt:
		interact_target_changed.emit(current_target, in_reach)
	_last_in_reach = in_reach
	_last_in_prompt = in_prompt


func is_target_in_reach() -> bool:
	return _last_in_reach


## F states an intent: act now at arm's length, or walk over and act on arrival.
func try_interact() -> void:
	if _is_blocked() or current_target == null:
		return
	if _flat_distance_to(current_target) <= pickup_distance:
		_cancel_approach()
		_perform(current_target)
		return
	_begin_approach(current_target)


func _perform(target: InteractiveArea) -> void:
	if not is_instance_valid(target):
		return
	if _player != null and _player.has_method(&"play_action_animation"):
		var action: StringName = target.player_animation_action
		if action == &"":
			if target is ItemPickup:
				action = &"pickup"
			elif target is BreachBoardUp:
				action = &"fix"
			else:
				action = &"interact"
		_player.call(&"play_action_animation", action)
	target.interact()
	interaction_performed.emit(target)


func _find_focus_target() -> InteractiveArea:
	_focus_cast.force_shapecast_update()
	var best: InteractiveArea = null
	var best_distance: float = INF
	for i: int in range(_focus_cast.get_collision_count()):
		var area := _area_from(_focus_cast.get_collider(i))
		if area == null or not _is_ahead(area):
			continue
		var distance: float = _flat_distance_to(area)
		if distance < best_distance:
			best = area
			best_distance = distance
	return best


## Nearest available area inside intent_radius and the forward cone.
func _find_intent_target() -> InteractiveArea:
	if intent_radius <= 0.0:
		return null
	var shape := SphereShape3D.new()
	shape.radius = intent_radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, _player.global_position)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var facing: Vector3 = get_facing_direction()
	var half_angle: float = deg_to_rad(intent_angle_deg) * 0.5
	var best: InteractiveArea = null
	var best_distance: float = INF
	for hit: Dictionary in get_world_3d().direct_space_state.intersect_shape(query, 32):
		var area := _area_from(hit.get("collider"))
		if area == null:
			continue
		var to_area: Vector3 = area.global_position - _player.global_position
		to_area.y = 0.0
		var distance: float = to_area.length()
		if distance > intent_radius or distance >= best_distance:
			continue
		if distance > 0.01 and facing.angle_to(to_area / distance) > half_angle:
			continue
		best = area
		best_distance = distance
	return best


## Henry's flat forward; the body faces -Z.
func get_facing_direction() -> Vector3:
	var forward: Vector3 = -_player.global_transform.basis.z
	forward.y = 0.0
	return forward.normalized() if forward.length() > 0.001 else Vector3.FORWARD


## A cast starting inside a big area reports it even when it lies behind.
func _is_ahead(area: Node3D) -> bool:
	var to_area: Vector3 = area.global_position - _player.global_position
	to_area.y = 0.0
	return to_area.length() < 0.01 or get_facing_direction().dot(to_area) > 0.0


func _area_from(collider: Variant) -> InteractiveArea:
	if not is_instance_valid(collider):
		return null
	var node := collider as Node
	for i: int in range(4):
		if node == null:
			return null
		if node is InteractiveArea:
			var area := node as InteractiveArea
			return area if area.can_interact() else null
		node = node.get_parent()
	return null


func _flat_distance_to(target: Node3D) -> float:
	var offset: Vector3 = target.global_position - _player.global_position
	offset.y = 0.0
	return offset.length()


## Walks to a point on the line from the target toward Henry, inside reach.
func _begin_approach(target: InteractiveArea) -> void:
	if not _player.has_method(&"move_to_position"):
		return
	var from_target: Vector3 = _player.global_position - target.global_position
	from_target.y = 0.0
	if from_target.length() < 0.01:
		return
	var stop_point: Vector3 = target.global_position + from_target.normalized() * pickup_distance * 0.75
	stop_point.y = _player.global_position.y
	_pending = target
	_approach_elapsed = 0.0
	_approach_stopped = false
	_player.call(&"move_to_position", stop_point)


## Arrival is distance to the target, never "the walk ended".
func _update_approach(delta: float) -> void:
	if _pending == null:
		return
	if not is_instance_valid(_pending) or not _pending.can_interact():
		_stop_approach()
		return
	if _flat_distance_to(_pending) <= pickup_distance + 0.05:
		var target: InteractiveArea = _pending
		_stop_approach()
		_perform(target)
		return
	_approach_elapsed += delta
	if _approach_stopped or _approach_elapsed >= approach_timeout:
		_stop_approach()


func _stop_approach() -> void:
	var was_walking: bool = _pending != null
	_cancel_approach()
	if was_walking and _player.has_method(&"stop_moving"):
		_player.call(&"stop_moving")


func _cancel_approach() -> void:
	_pending = null
	_approach_elapsed = 0.0
	_approach_stopped = false


func _on_player_movement_stopped() -> void:
	if _pending != null:
		_approach_stopped = true


func _is_blocked() -> bool:
	var state: Node = get_node_or_null(^"/root/PlayerState")
	return state != null and bool(state.call(&"is_movement_blocked"))


func _build_focus_cast() -> ShapeCast3D:
	var cast := ShapeCast3D.new()
	cast.name = "FocusCast"
	var sphere := SphereShape3D.new()
	sphere.radius = focus_radius
	cast.shape = sphere
	cast.target_position = Vector3(0.0, 0.0, -focus_length)
	cast.collide_with_areas = true
	cast.collide_with_bodies = false
	cast.max_results = 8
	return cast
