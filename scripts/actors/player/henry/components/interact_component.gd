class_name InteractComponent
extends Node3D

## Crosshair-authoritative interaction selection.
## Proximity only grants permission; the camera-centre ray decides which
## InteractiveArea Henry is actually addressing. F acts at arm's length or
## walks over first, but never on an unfocused nearby object.

## What is targeted and whether it is already within arm's reach.
signal interact_target_changed(target: InteractiveArea, in_reach: bool)
## Emitted after F acted on a target.
signal interaction_performed(target: InteractiveArea)

@export_group("Focus")
## Ray length through the exact screen centre. Selection is still capped by
## intent_radius, so distant scenery cannot become actionable.
@export var focus_length: float = 12.0
@export var focus_radius: float = 0.0
## Fallback only for cameras already inside an interaction Area: full cone width.
@export var focus_angle_deg: float = 16.0

@export_group("Intent")
## Maximum distance at which a crosshair-focused object can become current_target.
@export var intent_radius: float = 2.5
## Kept for scene compatibility; cone fallback is intentionally disabled.
@export var intent_angle_deg: float = 240.0

@export_group("Approach")
## F acts on the spot inside this flat distance, otherwise Henry walks over.
@export var pickup_distance: float = 0.9
## Inside this distance the object shows its F prompt instead of a marker.
@export var prompt_distance: float = 2.0
## Seated, Henry leans: this far, picked by where the camera looks (stove ring, table).
@export var seated_reach: float = 2.0
## Seated, a target must lie within this angle of the view direction.
@export var seated_aim_deg: float = 35.0
## Gives up a walk that stops making progress, seconds.
@export var approach_timeout: float = 4.0

var current_target: InteractiveArea = null

var _player: CharacterBody3D
var _last_in_reach: bool = false
var _last_in_prompt: bool = false
var _pending: InteractiveArea = null
var _approach_elapsed: float = 0.0
var _approach_stopped: bool = false


func _ready() -> void:
	_player = get_parent() as CharacterBody3D
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
	var seated: bool = _is_seated()
	var found: InteractiveArea = _find_seated_target() if seated else _find_crosshair_target()
	var distance: float = _flat_distance_to(found) if found != null else INF
	var in_reach: bool = distance <= _reach()
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
	if _flat_distance_to(current_target) <= _reach():
		_cancel_approach()
		_perform(current_target)
		return
	if not _is_seated():
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


func _find_crosshair_target() -> InteractiveArea:
	var viewport := get_viewport()
	var camera: Camera3D = viewport.get_camera_3d() if viewport != null else null
	if camera == null or _player == null:
		return null
	var center: Vector2 = viewport.get_visible_rect().size * 0.5
	var from: Vector3 = camera.project_ray_origin(center)
	var direction: Vector3 = camera.project_ray_normal(center).normalized()
	var to: Vector3 = from + direction * focus_length

	# The interaction volume owns selection. Query Areas first so a door leaf,
	# handle or frame cannot steal the centre ray from its InteractiveArea.
	# Physical bodies are checked separately below for honest occlusion.
	var area_hit := _first_interactive_area_on_ray(from, to)
	if not area_hit.is_empty():
		var direct := _area_from(area_hit.get("collider"))
		if direct != null and _flat_distance_to(direct) <= intent_radius:
			var hit_position: Vector3 = area_hit.get("position", direct.global_position)
			if _focus_hit_is_visible(from, hit_position, direct):
				return direct

	# Solid geometry still counts when it belongs to the InteractiveArea itself.
	# This keeps small/legacy Areas usable without allowing focus through walls.
	var body_ray := PhysicsRayQueryParameters3D.create(from, to)
	body_ray.collide_with_areas = false
	body_ray.collide_with_bodies = true
	body_ray.exclude = [_player.get_rid()]
	var body_hit: Dictionary = _player.get_world_3d().direct_space_state.intersect_ray(body_ray)
	if not body_hit.is_empty():
		var body_target := _area_from(body_hit.get("collider"))
		if body_target != null and _flat_distance_to(body_target) <= intent_radius:
			return body_target
		return null

	# Some legacy InteractiveAreas envelop the camera. Rays do not report a
	# shape containing their origin, so recover only candidates genuinely under
	# the crosshair and with clear line of sight.
	var shape := SphereShape3D.new()
	shape.radius = intent_radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, _player.global_position)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var best: InteractiveArea = null
	var best_angle := deg_to_rad(focus_angle_deg * 0.5)
	var best_distance := INF
	for result: Dictionary in get_world_3d().direct_space_state.intersect_shape(query, 32):
		var area := _area_from(result.get("collider"))
		if area == null:
			continue
		var flat_distance := _flat_distance_to(area)
		if flat_distance > intent_radius:
			continue
		# Legacy pickup Areas are intentionally much larger than the visible item,
		# so the camera can start inside them. Aim at the visible mesh instead of
		# Area3D.global_position: ground-level origins were being occluded by the
		# terrain itself, which made pickups impossible to focus.
		var focus_point: Vector3 = _focus_point(area)
		var toward: Vector3 = focus_point - from
		if toward.length() < 0.01:
			continue
		var angle := direction.angle_to(toward.normalized())
		if angle > best_angle:
			continue
		if not _has_focus_line(camera, area):
			continue
		if angle < best_angle or (is_equal_approx(angle, best_angle) and flat_distance < best_distance):
			best = area
			best_angle = angle
			best_distance = flat_distance
	return best


## Returns the first *interactive* Area on the centre ray, skipping unrelated
## trigger Areas (thermal zones, shelter volumes, etc.) instead of letting one
## of them hide the actual handle/door/pickup behind it.
func _first_interactive_area_on_ray(from: Vector3, to: Vector3) -> Dictionary:
	var excluded: Array[RID] = [_player.get_rid()]
	for _i: int in range(12):
		var ray := PhysicsRayQueryParameters3D.create(from, to)
		ray.collide_with_areas = true
		ray.collide_with_bodies = false
		ray.exclude = excluded
		var hit: Dictionary = _player.get_world_3d().direct_space_state.intersect_ray(ray)
		if hit.is_empty():
			return {}
		if _area_from(hit.get("collider")) != null:
			return hit
		var collider := hit.get("collider") as CollisionObject3D
		if collider == null:
			return {}
		excluded.append(collider.get_rid())
	return {}


## The Area hit grants focus only when no unrelated solid surface is closer.
## A body owned by the same InteractiveArea is allowed: that is the physical
## door/pickup itself, not an occluder.
func _focus_hit_is_visible(from: Vector3, hit_position: Vector3, target: InteractiveArea) -> bool:
	var offset := hit_position - from
	if offset.length() <= 0.01:
		return true
	var ray := PhysicsRayQueryParameters3D.create(from, hit_position)
	ray.collide_with_areas = false
	ray.collide_with_bodies = true
	ray.exclude = [_player.get_rid()]
	var hit: Dictionary = _player.get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty():
		return true
	return _area_from(hit.get("collider")) == target


func _has_focus_line(camera: Camera3D, area: InteractiveArea) -> bool:
	var from := camera.global_position
	var to := _focus_point(area)
	var ray := PhysicsRayQueryParameters3D.create(from, to)
	ray.collide_with_areas = false
	ray.collide_with_bodies = true
	ray.exclude = [_player.get_rid()]
	var hit := _player.get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty():
		return true
	return _area_from(hit.get("collider")) == area


## A focus anchor should represent what the player can actually see. Many old
## pickup Areas have their origin on the floor and a 6 m trigger sphere; using
## that origin for line-of-sight makes the terrain occlude the pickup itself.
func _focus_point(area: InteractiveArea) -> Vector3:
	if area == null:
		return Vector3.ZERO
	var mesh: MeshInstance3D = area.interactive_mesh
	if is_instance_valid(mesh) and mesh.mesh != null:
		var bounds: AABB = mesh.get_aabb()
		var point: Vector3 = mesh.to_global(bounds.get_center())
		# Keep tiny/rotated ground props (flare, cup, food) a few centimetres
		# above the authored root so their own supporting surface cannot win LOS.
		var safe_lift: float = clampf(bounds.size.y * 0.35, 0.08, 0.35)
		point.y = maxf(point.y, area.global_position.y + safe_lift)
		return point
	return area.global_position + Vector3.UP * 0.15


## Legacy cone helper retained for compatibility/reference only.
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


func _is_seated() -> bool:
	var rest := _player.get_node_or_null(^"RestComponent") as RestComponent if _player != null else null
	return rest != null and rest.is_sitting()


func _reach() -> float:
	return seated_reach if _is_seated() else pickup_distance


## Seated: the area within seated_reach closest to where the camera looks.
func _find_seated_target() -> InteractiveArea:
	var shape := SphereShape3D.new()
	shape.radius = seated_reach
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, _player.global_position)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var view: Vector3 = _player.call(&"get_view_direction") if _player.has_method(&"get_view_direction") else get_facing_direction()
	view.y = 0.0
	view = view.normalized() if view.length() > 0.001 else get_facing_direction()
	var best: InteractiveArea = null
	var best_angle: float = deg_to_rad(seated_aim_deg)
	for hit: Dictionary in get_world_3d().direct_space_state.intersect_shape(query, 32):
		var area := _area_from(hit.get("collider"))
		if area == null:
			continue
		var to_area: Vector3 = area.global_position - _player.global_position
		to_area.y = 0.0
		if to_area.length() > seated_reach or to_area.length() < 0.01:
			continue
		var angle: float = view.angle_to(to_area.normalized())
		if angle < best_angle:
			best = area
			best_angle = angle
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




func is_crosshair_focused() -> bool:
	return is_instance_valid(current_target)
