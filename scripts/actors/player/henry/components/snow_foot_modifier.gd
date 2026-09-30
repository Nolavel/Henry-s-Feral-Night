class_name SnowFootModifier
extends SkeletonModifier3D

## Snow has weight: a planted boot lands on the snow top and sinks as it packs,
## instead of dropping through to the ground the walk clip stands on.

## Bones on the UAL rig.
const THIGHS: Array[StringName] = [&"thigh_l", &"thigh_r"]
const CALVES: Array[StringName] = [&"calf_l", &"calf_r"]
const FEET: Array[StringName] = [&"foot_l", &"foot_r"]
const PELVIS: StringName = &"pelvis"

## Share of the lower boot's lift the hips follow, so the knees do not fold.
@export_range(0.0, 1.0) var hip_follow: float = 0.6
## How fast a boot's lift eases out, metres per second.
@export var ease_rate: float = 6.0
## How fast a swinging boot rises to clear the snow, metres per second.
@export var rise_rate: float = 3.0
## Gap kept between a swinging boot's sole and the snow top, metres.
@export var clearance_m: float = 0.03
## Ankle bone height above the sole, metres.
@export var ankle_m: float = 0.08

var _lift: Array[float] = [0.0, 0.0]
var _applied: Array[float] = [0.0, 0.0]
var _hip: float = 0.0
var _index: Dictionary = {}


func _process_modification() -> void:
	var skeleton: Skeleton3D = get_skeleton()
	var shell: SnowShell = SnowShell.active
	if skeleton == null or not is_instance_valid(shell):
		return
	var delta: float = maxf(get_process_delta_time(), 0.001)
	for side: int in range(2):
		var want: float = shell.get_foot_raise(side)
		## A swinging boot clears the snow ahead of it by a hand's width, no more.
		if shell.get_foot_snow_top(side) == -INF:
			want = _swing_clearance(skeleton, shell, side)
		var rate: float = rise_rate if want > _lift[side] else ease_rate
		_lift[side] = move_toward(_lift[side], want, rate * delta)
	_hip = lerpf(_hip, minf(_lift[0], _lift[1]) * hip_follow, clampf(delta * 8.0, 0.0, 1.0))
	if _lift[0] <= 0.001 and _lift[1] <= 0.001 and _hip <= 0.001:
		_applied = [0.0, 0.0]
		return
	## World metres up, in skeleton space (the rig may be scaled).
	var up: Vector3 = skeleton.global_transform.basis.inverse() * Vector3.UP
	var pelvis: int = _bone(skeleton, PELVIS)
	if pelvis >= 0 and _hip > 0.001:
		var pose: Transform3D = skeleton.get_bone_global_pose(pelvis)
		pose.origin += up * _hip
		skeleton.set_bone_global_pose(pelvis, pose)
	for side: int in range(2):
		var lift: float = _lift[side] - _hip
		_applied[side] = _hip
		if absf(lift) > 0.001:
			_applied[side] += _reach(skeleton, side, up * lift) / up.length()


## Two-bone solve: moves the ankle by `offset`, bending the knee in its own plane
## and keeping the boot's orientation. Returns how far up it really moved.
func _reach(skeleton: Skeleton3D, side: int, offset: Vector3) -> float:
	var t: int = _bone(skeleton, THIGHS[side])
	var c: int = _bone(skeleton, CALVES[side])
	var f: int = _bone(skeleton, FEET[side])
	if t < 0 or c < 0 or f < 0:
		return 0.0
	var hip_pose: Transform3D = skeleton.get_bone_global_pose(t)
	var knee_pose: Transform3D = skeleton.get_bone_global_pose(c)
	var foot_pose: Transform3D = skeleton.get_bone_global_pose(f)
	var hip: Vector3 = hip_pose.origin
	var knee: Vector3 = knee_pose.origin
	var ankle: Vector3 = foot_pose.origin
	var upper: float = hip.distance_to(knee)
	var lower: float = knee.distance_to(ankle)
	var target: Vector3 = ankle + offset
	var reach: Vector3 = target - hip
	var d: float = clampf(reach.length(), 0.01, upper + lower - 0.001)
	var dir: Vector3 = reach.normalized()
	var bend: Vector3 = (knee - hip) - dir * (knee - hip).dot(dir)
	if bend.length_squared() < 1e-8:
		return 0.0
	bend = bend.normalized()
	var cos_a: float = clampf((upper * upper + d * d - lower * lower) / (2.0 * upper * d), -1.0, 1.0)
	var new_knee: Vector3 = hip + dir * upper * cos_a + bend * upper * sqrt(1.0 - cos_a * cos_a)
	var new_ankle: Vector3 = hip + dir * d
	var turn_thigh := Quaternion((knee - hip).normalized(), (new_knee - hip).normalized())
	hip_pose.basis = Basis(turn_thigh) * hip_pose.basis
	skeleton.set_bone_global_pose(t, hip_pose)
	var old_shin: Vector3 = Basis(turn_thigh) * (ankle - knee)
	var turn_shin := Quaternion(old_shin.normalized(), (new_ankle - new_knee).normalized())
	knee_pose.basis = Basis(turn_shin) * Basis(turn_thigh) * knee_pose.basis
	knee_pose.origin = new_knee
	skeleton.set_bone_global_pose(c, knee_pose)
	foot_pose.origin = new_ankle
	skeleton.set_bone_global_pose(f, foot_pose)
	return (new_ankle - ankle).dot(offset.normalized())


## Lift that lets the clip's swinging boot pass over the snow under it.
func _swing_clearance(skeleton: Skeleton3D, shell: SnowShell, side: int) -> float:
	var f: int = _bone(skeleton, FEET[side])
	if f < 0:
		return 0.0
	var ankle: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(f).origin
	var top: float = shell.field.get_snow_top(ankle.x, ankle.z)
	if top == -INF:
		return 0.0
	return maxf(top + clearance_m - (ankle.y - ankle_m), 0.0)


## World metres the `side` boot was really lifted above the walk clip last frame.
func get_lift(side: int) -> float:
	return _applied[side]


func _bone(skeleton: Skeleton3D, bone: StringName) -> int:
	if not _index.has(bone):
		_index[bone] = skeleton.find_bone(bone)
	return _index[bone]
