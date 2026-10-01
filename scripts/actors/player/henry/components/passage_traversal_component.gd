class_name PassageTraversalComponent
extends Node

## Narrow doorways are a short traversal, not free movement: while the player
## pushes along the passage, Henry is steered through its centre and out.

## Solid walls closer together than this form a doorway, metres.
@export var max_gap: float = 1.9
## A wall this close ahead of Henry is searched for a door he is walking toward.
@export var look_ahead: float = 1.6
@export var scan_reach: float = 1.2
## Height of the scan above the feet: over sills and low walls, under lintels.
@export var scan_height: float = 1.3
## The traversal ends this far past the door plane on either side, metres.
@export var exit_distance: float = 1.1
## How hard Henry is pulled onto the centre line, per metre off it.
@export var centering_gain: float = 2.5
## Input more sideways than this share of its length is left alone.
@export_range(0.0, 1.0, 0.05) var min_along_share: float = 0.25

var body: CharacterBody3D

var _active: bool = false
## Horizontal unit along the passage; its sign carries no meaning.
var _axis: Vector3 = Vector3.FORWARD
## Door centre at foot height.
var _center: Vector3 = Vector3.ZERO
var _probe := TpsBoomProbe.new()
var _capsule: CollisionShape3D


func _ready() -> void:
	if body == null:
		body = get_parent() as CharacterBody3D
	if body != null:
		for child: Node in body.get_children():
			var shape := child as CollisionShape3D
			if shape != null and shape.shape is CapsuleShape3D:
				_capsule = shape
				break


func _physics_process(_delta: float) -> void:
	if body == null or not body.is_inside_tree():
		return
	_probe.begin(body.get_world_3d().direct_space_state, [body.get_rid()])
	var feet: Vector3 = _feet()
	var forward := Vector3(body.velocity.x, 0.0, body.velocity.z)
	if forward.length() < 0.3:
		forward = -body.global_basis.z
		forward.y = 0.0
	forward = forward.normalized()
	var height: float = minf(scan_height, _top() - 0.1)
	var best: Array = _narrowest(feet + Vector3.UP * height)
	if best.is_empty():
		best = _door_ahead(feet, forward, height)
	var short: bool = not best.is_empty() and _is_short(best[1], best[2], height)
	if short:
		_active = true
		_axis = best[2]
		_center = Vector3(best[1].x, feet.y, best[1].z)
	elif not best.is_empty():
		## Narrow both ways along the axis: a corridor, never a traversal.
		_active = false
	elif _active:
		var offset: Vector3 = feet - _center
		offset.y = 0.0
		var past: float = offset.dot(_axis)
		if absf(past) > exit_distance or (offset - _axis * past).length() > max_gap:
			_active = false


func is_active() -> bool:
	return _active


func get_axis() -> Vector3:
	return _axis


func get_center() -> Vector3:
	return _center


## 0 away from a doorway, 1 in its middle; eases over the last metre either side.
func get_blend(at: Vector3) -> float:
	if not _active:
		return 0.0
	return 1.0 - smoothstep(0.35, exit_distance, absf(Vector3(at.x - _center.x, 0.0, at.z - _center.z).dot(_axis)))


## Bends a movement direction through the doorway: along its axis toward the
## side the input points, pulled onto the centre line. Unchanged elsewhere.
func steer(world_dir: Vector3) -> Vector3:
	var length: float = world_dir.length()
	if not _active or length < 0.01:
		return world_dir
	var along: float = world_dir.dot(_axis)
	if absf(along) < min_along_share * length:
		return world_dir
	var offset: Vector3 = _feet() - _center
	offset.y = 0.0
	var past: float = offset.dot(_axis)
	var lateral: Vector3 = offset - _axis * past
	var weight: float = 1.0 - smoothstep(0.4, exit_distance, absf(past))
	var through: Vector3 = (_axis * signf(along) - lateral * centering_gain).normalized()
	return (world_dir / length).slerp(through, weight) * length


## The narrowest pair of opposite rays at `point` that both meet solid walls
## within max_gap: [gap, midpoint, axis]. Empty if none does.
func _narrowest(point: Vector3) -> Array:
	var best: Array = []
	for step: int in range(6):
		var found: Array = _gap_at(point, deg_to_rad(30.0 * float(step)))
		if not found.is_empty() and (best.is_empty() or found[0] < best[0]):
			best = found
	if best.is_empty():
		return best
	## Refine the angle so the gap is the true width and the axis is square.
	var angle: float = best[3]
	for nudge: float in [-10.0, -5.0, 5.0, 10.0]:
		var found: Array = _gap_at(point, angle + deg_to_rad(nudge))
		if not found.is_empty() and found[0] < best[0]:
			best = found
	return best.slice(0, 3)


## Two jambs: opposite rays that both meet solid faces turned toward each other,
## so two hits on one wall through an opening never pass for a gap.
func _gap_at(point: Vector3, angle: float) -> Array:
	var dir := Vector3(sin(angle), 0.0, cos(angle))
	var hit_a: Dictionary = _solid_hit(point, point + dir * scan_reach)
	var hit_b: Dictionary = _solid_hit(point, point - dir * scan_reach)
	if hit_a.is_empty() or hit_b.is_empty():
		return []
	if (hit_a["normal"] as Vector3).dot(hit_b["normal"]) > -0.7:
		return []
	var a: float = point.distance_to(hit_a["position"])
	var b: float = point.distance_to(hit_b["position"])
	if a + b > max_gap:
		return []
	return [a + b, point + dir * (a - b) * 0.5, dir.cross(Vector3.UP).normalized(), angle]


## Henry walking at a wall: the nearest gap in it that reaches the floor and is
## door-wide, as [gap, midpoint, axis], refined from inside it. Empty if none.
func _door_ahead(feet: Vector3, forward: Vector3, height: float) -> Array:
	var origin: Vector3 = feet + Vector3.UP * height
	var hit: Dictionary = _solid_hit(origin, origin + forward * look_ahead)
	if hit.is_empty():
		return []
	var normal: Vector3 = hit["normal"]
	normal.y = 0.0
	if normal.length() < 0.5:
		return []
	normal = normal.normalized()
	var along: Vector3 = normal.cross(Vector3.UP).normalized()
	var face: Vector3 = hit["position"]
	var run_start: float = INF
	var runs: Array = []
	for step: int in range(-12, 13):
		var k: float = float(step) * 0.2
		var point: Vector3 = face + along * k + normal * 0.15
		var through: bool = _solid_hit(point, point - normal * 0.8).is_empty()
		if through and run_start == INF:
			run_start = k
		elif not through and run_start != INF:
			runs.append([run_start, k - 0.2])
			run_start = INF
	for run: Array in runs:
		var width: float = run[1] - run[0] + 0.2
		var middle: Vector3 = face + along * (run[0] + run[1]) * 0.5
		if width < 0.7 or width > max_gap:
			continue
		var low := Vector3(middle.x, feet.y + 0.4, middle.z) + normal * 0.15
		if not _solid_hit(low, low - normal * 0.8).is_empty():
			continue
		var inside: Array = _narrowest(Vector3(middle.x, origin.y, middle.z) - normal * 0.1)
		if not inside.is_empty():
			return inside
	return []


## The first collider that stops the boom between two points, as intersect_ray
## gives it; thin props are skipped. Empty if the line is clear.
func _solid_hit(from: Vector3, to: Vector3) -> Dictionary:
	var space: PhysicsDirectSpaceState3D = body.get_world_3d().direct_space_state
	var exclude: Array[RID] = [body.get_rid()]
	for attempt: int in range(TpsBoomProbe.MAX_PASSES + 1):
		var hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 0xFFFFFFFF, exclude))
		if hit.is_empty() or attempt == TpsBoomProbe.MAX_PASSES or not _probe.passes(hit["collider"], int(hit["shape"])):
			return hit
		exclude.append(hit["rid"])
	return {}


## A doorway opens up within a step on at least one side; a corridor does not.
func _is_short(center: Vector3, axis: Vector3, height: float) -> bool:
	var across: Vector3 = axis.cross(Vector3.UP).normalized()
	var reach: float = scan_reach * 1.5
	for side: float in [-1.0, 1.0]:
		var point := Vector3(center.x, _feet().y + height, center.z) + axis * side * 0.9
		var gap: float = _probe.ray(point, across * reach) + _probe.ray(point, -across * reach)
		if gap > max_gap * 1.3:
			return true
	return false


func _feet() -> Vector3:
	if _capsule == null:
		return body.global_position - Vector3.UP
	var capsule := _capsule.shape as CapsuleShape3D
	return body.global_position + Vector3.UP * (_capsule.position.y - capsule.height * 0.5)


func _top() -> float:
	if _capsule == null:
		return 2.0
	return (_capsule.shape as CapsuleShape3D).height
