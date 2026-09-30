class_name DoorHandIK
extends SkeletonModifier3D

## Plants one hand flat on a surface: a two-bone arm solve to the wrist and the
## palm turned into the surface, fingers up. DoorPushComponent feeds the goal.

@export_group("Bones")
@export var upper_bone: StringName = &"upperarm_l"
@export var lower_bone: StringName = &"lowerarm_l"
@export var hand_bone: StringName = &"hand_l"
## Finger roots that give the palm frame: middle along the fingers, index and
## pinky across the knuckles.
@export var middle_bone: StringName = &"middle_01_l"
@export var index_bone: StringName = &"index_01_l"
@export var pinky_bone: StringName = &"pinky_01_l"
## True for a left hand; the palm faces the other way on a right hand.
@export var left_hand: bool = true

@export_group("Motion")
## How fast the arm takes and leaves the surface, weight per second.
@export var blend_in_rate: float = 6.0
@export var blend_out_rate: float = 3.5
## Stiffness of the palm following a moving surface, per second.
@export var follow_rate: float = 18.0
## Palm thickness kept off the surface, metres.
@export var palm_offset_m: float = 0.025
## Wrist sits this far from the palm centre along the fingers, metres.
@export var wrist_back_m: float = 0.08
## 0 keeps the clip's elbow, 1 drops it down and out, like a braced push.
@export_range(0.0, 1.0) var elbow_drop: float = 0.6
## 0 keeps the clip's hand turn, 1 lays the palm flat on the surface.
@export_range(0.0, 1.0) var palm_flatten: float = 0.9

var _goal_point: Vector3 = Vector3.ZERO
var _goal_normal: Vector3 = Vector3.BACK
var _goal_weight: float = 0.0
var _weight: float = 0.0
var _point: Vector3 = Vector3.ZERO
var _normal: Vector3 = Vector3.BACK
var _index: Dictionary = {}


## World palm point, world surface normal (out of the surface), reach weight 0..1.
func set_goal(point: Vector3, normal: Vector3, weight: float = 1.0) -> void:
	_goal_point = point
	_goal_normal = normal.normalized() if normal.length_squared() > 0.0001 else Vector3.BACK
	_goal_weight = clampf(weight, 0.0, 1.0)


func release() -> void:
	_goal_weight = 0.0


func _process_modification() -> void:
	var skeleton: Skeleton3D = get_skeleton()
	if skeleton == null:
		return
	var delta: float = clampf(get_process_delta_time(), 0.001, 0.05)
	var rate: float = blend_in_rate if _goal_weight > _weight else blend_out_rate
	var was: float = _weight
	_weight = move_toward(_weight, _goal_weight, rate * delta)
	if _weight <= 0.001:
		return
	var u: int = _bone(skeleton, upper_bone)
	var l: int = _bone(skeleton, lower_bone)
	var h: int = _bone(skeleton, hand_bone)
	if u < 0 or l < 0 or h < 0:
		return
	var to_rig: Transform3D = skeleton.global_transform.affine_inverse()
	## A fresh reach starts from where the clip holds the palm, not a stale goal.
	if was <= 0.001:
		_point = skeleton.global_transform * skeleton.get_bone_global_pose(h).origin
		_normal = _goal_normal
	var follow: float = 1.0 - exp(-follow_rate * delta)
	_point = _point.lerp(_goal_point, follow)
	_normal = _normal.slerp(_goal_normal, follow).normalized()
	var fingers: Vector3 = Vector3.UP - _normal * Vector3.UP.dot(_normal)
	fingers = fingers.normalized() if fingers.length_squared() > 0.0001 else Vector3.UP
	var wrist_world: Vector3 = _point + _normal * palm_offset_m - fingers * wrist_back_m
	var weight: float = smoothstep(0.0, 1.0, _weight)
	var animated: Vector3 = skeleton.get_bone_global_pose(h).origin
	_solve(skeleton, u, l, h, animated.lerp(to_rig * wrist_world, weight), weight)
	_flatten_palm(skeleton, h, to_rig.basis * fingers, to_rig.basis * -_normal, weight)


## Two-bone solve in rig space: shoulder stays, elbow bends in a plane that eases
## from the clip's towards down-and-out, wrist lands on `target`.
func _solve(skeleton: Skeleton3D, u: int, l: int, h: int, target: Vector3, weight: float) -> void:
	var upper_pose: Transform3D = skeleton.get_bone_global_pose(u)
	var lower_pose: Transform3D = skeleton.get_bone_global_pose(l)
	var hand_pose: Transform3D = skeleton.get_bone_global_pose(h)
	var shoulder: Vector3 = upper_pose.origin
	var elbow: Vector3 = lower_pose.origin
	var wrist: Vector3 = hand_pose.origin
	var a: float = shoulder.distance_to(elbow)
	var b: float = elbow.distance_to(wrist)
	if a < 0.001 or b < 0.001:
		return
	var reach: Vector3 = target - shoulder
	var d: float = clampf(reach.length(), absf(a - b) + 0.001, a + b - 0.001)
	var dir: Vector3 = reach.normalized() if reach.length_squared() > 1e-8 else (wrist - shoulder).normalized()
	var clip_bend: Vector3 = (elbow - shoulder) - dir * (elbow - shoulder).dot(dir)
	var up: Vector3 = (skeleton.global_transform.basis.inverse() * Vector3.UP).normalized()
	var out := Vector3(signf(shoulder.x), 0.0, 0.0)
	var braced: Vector3 = -up + out * 0.6
	var bend: Vector3 = clip_bend.normalized().lerp(braced.normalized(), elbow_drop * weight) if clip_bend.length_squared() > 1e-8 else braced
	bend = bend - dir * bend.dot(dir)
	if bend.length_squared() < 1e-8:
		return
	bend = bend.normalized()
	var cos_a: float = clampf((a * a + d * d - b * b) / (2.0 * a * d), -1.0, 1.0)
	var new_elbow: Vector3 = shoulder + dir * a * cos_a + bend * a * sqrt(1.0 - cos_a * cos_a)
	var new_wrist: Vector3 = shoulder + dir * d
	var turn_upper := Basis(Quaternion((elbow - shoulder).normalized(), (new_elbow - shoulder).normalized()))
	upper_pose.basis = turn_upper * upper_pose.basis
	skeleton.set_bone_global_pose(u, upper_pose)
	var old_fore: Vector3 = turn_upper * (wrist - elbow)
	var turn_lower := Basis(Quaternion(old_fore.normalized(), (new_wrist - new_elbow).normalized()))
	lower_pose.basis = turn_lower * turn_upper * lower_pose.basis
	lower_pose.origin = new_elbow
	skeleton.set_bone_global_pose(l, lower_pose)
	hand_pose.basis = turn_lower * turn_upper * hand_pose.basis
	hand_pose.origin = new_wrist
	skeleton.set_bone_global_pose(h, hand_pose)


## Turns the hand so its fingers run along `fingers` and its palm faces `into`
## (rig space); the palm frame is read from the finger roots.
func _flatten_palm(skeleton: Skeleton3D, h: int, fingers: Vector3, into: Vector3, weight: float) -> void:
	var m: int = _bone(skeleton, middle_bone)
	var i: int = _bone(skeleton, index_bone)
	var p: int = _bone(skeleton, pinky_bone)
	if m < 0 or i < 0 or p < 0:
		return
	var hand_pose: Transform3D = skeleton.get_bone_global_pose(h)
	var along: Vector3 = skeleton.get_bone_global_pose(m).origin - hand_pose.origin
	var across: Vector3 = skeleton.get_bone_global_pose(i).origin - skeleton.get_bone_global_pose(p).origin
	if along.length_squared() < 1e-8 or across.length_squared() < 1e-8:
		return
	## Index to pinky crosses the fingers into the back of a left hand.
	var palm: Vector3 = along.cross(across) * (-1.0 if left_hand else 1.0)
	var have: Basis = _frame(along, palm)
	var want: Basis = _frame(fingers, into)
	if have == Basis() or want == Basis():
		return
	var turn: Quaternion = (want * have.inverse()).get_rotation_quaternion()
	var blended: Quaternion = Quaternion.IDENTITY.slerp(turn, palm_flatten * weight)
	hand_pose.basis = Basis(blended) * hand_pose.basis
	skeleton.set_bone_global_pose(h, hand_pose)


## Orthonormal frame with Y along `primary` and Z towards `secondary`.
static func _frame(primary: Vector3, secondary: Vector3) -> Basis:
	var y: Vector3 = primary.normalized()
	var x: Vector3 = y.cross(secondary)
	if x.length_squared() < 1e-8:
		return Basis()
	x = x.normalized()
	return Basis(x, y, x.cross(y))


func _bone(skeleton: Skeleton3D, bone: StringName) -> int:
	if not _index.has(bone):
		_index[bone] = skeleton.find_bone(bone)
	return _index[bone]
