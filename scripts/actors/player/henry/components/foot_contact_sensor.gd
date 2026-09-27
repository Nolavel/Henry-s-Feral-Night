class_name FootContactSensor
extends Node

## Watches Henry's animated feet and reports each moment a foot is planted on
## the ground. The honest source for footprints, footstep audio and ice load.

## Emitted when a foot lands. Position is on the ground under the sole; normal
## is the ground's; forward runs heel to toe along that ground.
signal foot_planted(
	side: Side, position: Vector3, normal: Vector3, forward: Vector3, speed_mps: float
)

enum Side { LEFT, RIGHT }

## Bones on the UAL rig: ankle, ball of the foot, and the toe tip.
const BONES: Dictionary = {
	Side.LEFT: {"heel": &"foot_l", "ball": &"ball_l", "toe": &"ball_leaf_l"},
	Side.RIGHT: {"heel": &"foot_r", "ball": &"ball_r", "toe": &"ball_leaf_r"},
}

@export_group("Wiring")
## The body whose floor contact and speed gate the prints.
@export var body: CharacterBody3D
## Henry's animated visual; its skeleton is read, never written.
@export var visual: HenryUALAnimation

@export_group("Contact")
## Ball of the foot this close to the ground counts as planted, in metres.
@export var contact_height_m: float = 0.06
## Absolute ground clearance that definitely rearms a foot. This remains a
## conservative fallback for tests and unusual poses.
@export var lift_height_m: float = 0.09
## A blended UAL step may never reach 9 cm of world-space clearance. Rearm from
## the animated ball bone rising relative to its own last planted pose instead.
## This observation is independent of the ground ray, so a one-frame probe miss
## at a terrain seam cannot silently lose the next step.
@export var animated_rearm_rise_m: float = 0.045
## Slower than this and Henry is standing, not stepping.
@export var min_speed_mps: float = 0.35
## How far below the ball of the foot the ground is searched for.
@export var probe_depth_m: float = 1.2

var _lifted: Dictionary = {Side.LEFT: true, Side.RIGHT: true}
var _bone_index: Dictionary = {}
## Latest animated ball height in Player-local space, and the height at the
## previous accepted plant. Local space removes terrain/body elevation changes.
var _sampled_local_y: Dictionary = {}
var _last_planted_local_y: Dictionary = {}


func _physics_process(_delta: float) -> void:
	var skeleton: Skeleton3D = _skeleton()
	if skeleton == null or body == null:
		return
	var speed: float = Vector2(body.velocity.x, body.velocity.z).length()
	for side: int in Side.values():
		var feet: Dictionary = _sample(skeleton, side)
		if feet.is_empty():
			continue
		var ball: Vector3 = feet["ball"]
		## Observe the animation before the ground ray. A raycast can briefly
		## miss at a terrain/collider seam; foot phase must survive that miss.
		observe_foot_motion(side, body.to_local(ball).y)

		var hit: Dictionary = _ground_below(ball)
		if hit.is_empty():
			continue

		var normal: Vector3 = hit["normal"]
		if normal.length_squared() <= 0.0001:
			normal = Vector3.UP
		else:
			normal = normal.normalized()

		var height: float = surface_clearance(ball, hit["position"], normal)
		var centre: Vector3 = (feet["heel"] + feet["toe"]) * 0.5
		## Put the heel/toe centre on the local surface plane rather than only
		## copying world Y; this keeps slope contacts and decals coherent.
		centre -= normal * (centre - hit["position"]).dot(normal)
		var forward: Vector3 = feet["toe"] - feet["heel"]
		update_foot(side, height, centre, forward, body.is_on_floor(), speed, normal)


## Records animated foot phase even when there is no valid ground hit this tick.
## Relative Player-local rise is deliberately separate from absolute clearance:
## blend transitions can compress the gait while still producing a real step.
func observe_foot_motion(side: int, animated_local_y: float) -> void:
	_sampled_local_y[side] = animated_local_y
	if _lifted[side] or not _last_planted_local_y.has(side):
		return
	if animated_local_y - float(_last_planted_local_y[side]) >= animated_rearm_rise_m:
		_lifted[side] = true


## Distance from the animated ball to the sampled surface measured along that
## surface's normal, not world Y. This is the contact quantity used on slopes.
func surface_clearance(point: Vector3, ground_point: Vector3, ground_normal: Vector3) -> float:
	var normal: Vector3 = (
		ground_normal.normalized()
		if ground_normal.length_squared() > 0.0001
		else Vector3.UP
	)
	return maxf((point - ground_point).dot(normal), 0.0)


## The contact rule, kept free of scene access so it can be tested directly.
## Returns true on the frame the foot is planted.
func update_foot(
	side: int, height_m: float, ground_point: Vector3, forward: Vector3,
	on_floor: bool, speed_mps: float, ground_normal: Vector3 = Vector3.UP
) -> bool:
	if height_m > lift_height_m:
		_lifted[side] = true
		return false
	if height_m > contact_height_m or not _lifted[side]:
		return false
	if not on_floor or speed_mps < min_speed_mps:
		return false
	_lifted[side] = false
	if _sampled_local_y.has(side):
		_last_planted_local_y[side] = float(_sampled_local_y[side])
	var normal: Vector3 = ground_normal.normalized() if ground_normal.length_squared() > 0.0001 else Vector3.UP
	## Heel to toe, laid along the ground rather than the horizontal.
	var along: Vector3 = forward - normal * forward.dot(normal)
	if along.length_squared() < 0.0001:
		along = Vector3.FORWARD - normal * Vector3.FORWARD.dot(normal)
	foot_planted.emit(side, ground_point, normal, along.normalized(), speed_mps)
	return true


func _skeleton() -> Skeleton3D:
	if visual == null:
		return null
	return visual.skeleton


## World positions of heel, ball and toe for one foot, or empty on a rig
## that lacks the bones.
func _sample(skeleton: Skeleton3D, side: int) -> Dictionary:
	var names: Dictionary = BONES[side]
	var out: Dictionary = {}
	for key: String in names:
		var index: int = _index_of(skeleton, names[key])
		if index < 0:
			return {}
		out[key] = skeleton.global_transform * skeleton.get_bone_global_pose(index).origin
	return out


func _index_of(skeleton: Skeleton3D, bone: StringName) -> int:
	if not _bone_index.has(bone):
		_bone_index[bone] = skeleton.find_bone(bone)
	return _bone_index[bone]


## The ground under a point, found by a short ray that ignores Henry himself.
func _ground_below(point: Vector3) -> Dictionary:
	var space: PhysicsDirectSpaceState3D = body.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		point + Vector3.UP * 0.3, point + Vector3.DOWN * probe_depth_m
	)
	query.exclude = [body.get_rid()]
	return space.intersect_ray(query)
