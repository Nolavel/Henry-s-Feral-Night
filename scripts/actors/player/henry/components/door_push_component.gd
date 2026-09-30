class_name DoorPushComponent
extends Node

## Henry meets doors with his hand. Walking into an unlatched leaf he reaches out,
## plants his palm and the leaf keeps ahead of it; after F his hand rides the leaf.

@export_group("Wiring")
@export var body: CharacterBody3D
@export var visual: HenryUALAnimation

@export_group("Reach")
## Bone the reach is measured from.
@export var shoulder_bone: StringName = &"upperarm_l"
## Slower than this Henry is not walking into anything, m/s.
@export var min_speed_mps: float = 0.35
## A leaf this far ahead of the shoulder draws the hand out, metres.
@export var reach_ahead_m: float = 1.0
## The palm leads the shoulder by this much while pushing: past the capsule, so
## the hand, not the chest, moves the door.
@export var push_ahead_m: float = 0.58
## Palm height below the shoulder, metres.
@export var hand_drop_m: float = 0.2
## Doors farther than this are ignored, metres.
@export var scan_radius_m: float = 3.0

var _index: int = -1


func _ready() -> void:
	if body == null:
		body = get_parent() as CharacterBody3D


func _physics_process(delta: float) -> void:
	if body == null:
		return
	HingedDoor.blocker = body
	var shoulder: Vector3 = _shoulder()
	var goal: Dictionary = {}
	for node: Node in get_tree().get_nodes_in_group(HingedDoor.GROUP):
		var door := node as HingedDoor
		if door == null or door.global_position.distance_to(body.global_position) > scan_radius_m:
			continue
		goal = door.get_hand_hold()
		if goal.is_empty():
			goal = _walk_push(door, shoulder, delta)
		if not goal.is_empty():
			break
	var ik: DoorHandIK = _hand_ik()
	if ik == null:
		return
	if goal.is_empty():
		ik.release()
	else:
		ik.set_goal(goal["point"], goal["normal"], float(goal.get("weight", 1.0)))


## Walking into an unlatched leaf: the hand reaches out as it nears, then pushes.
func _walk_push(door: HingedDoor, shoulder: Vector3, delta: float) -> Dictionary:
	if door.is_latched() or door.is_pulling():
		return {}
	var velocity := Vector3(body.velocity.x, 0.0, body.velocity.z)
	if velocity.length() < min_speed_mps:
		return {}
	var direction: Vector3 = velocity.normalized()
	var side: float = door.side_of(body.global_position)
	var origin: Vector3 = shoulder + Vector3.DOWN * hand_drop_m
	var hit: Dictionary = door.leaf_ray(origin, direction, side)
	if hit.is_empty():
		return {}
	var ahead: float = float(hit["distance"])
	if ahead > reach_ahead_m:
		return {}
	door.push_with_hand(origin + direction * push_ahead_m, side, delta)
	hit["weight"] = clampf(inverse_lerp(reach_ahead_m, push_ahead_m + 0.1, ahead), 0.0, 1.0)
	return hit


func _shoulder() -> Vector3:
	var fallback: Vector3 = body.global_position + Vector3.UP * 1.4
	if visual == null or visual.skeleton == null:
		return fallback
	var skeleton: Skeleton3D = visual.skeleton
	if _index < 0:
		_index = skeleton.find_bone(shoulder_bone)
	if _index < 0:
		return fallback
	return skeleton.global_transform * skeleton.get_bone_global_pose(_index).origin


func _hand_ik() -> DoorHandIK:
	if visual == null or visual.skeleton == null:
		return null
	return visual.skeleton.get_node_or_null(^"DoorHand") as DoorHandIK
