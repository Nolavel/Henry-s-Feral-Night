class_name WadeModifier
extends SkeletonModifier3D

## Turns any walk into wading through deep snow: the swinging leg lifts its knee
## and folds its shin clear of the snow, and the torso leans into the effort.

## Bones on the UAL rig, and the local axis each flexes about (probed on the rig).
const THIGHS: Array[StringName] = [&"thigh_l", &"thigh_r"]
const CALVES: Array[StringName] = [&"calf_l", &"calf_r"]
const FEET: Array[StringName] = [&"foot_l", &"foot_r"]
const SPINE: StringName = &"spine_01"

## How deep Henry wades, 0 on firm ground to 1 in thigh-deep snow. Set by SnowShell.
@export_range(0.0, 1.0) var wade: float = 0.0
## Extra hip flexion of the swinging leg at full wade, degrees: the knee drives
## up and forward as in knee-deep snow; SnowFootModifier then sets the boot height.
@export var knee_lift_deg: float = 22.0
## Extra knee bend of the swinging leg at full wade, degrees.
@export var shin_fold_deg: float = 18.0
## Forward lean of the torso at full wade, degrees.
@export var lean_deg: float = 14.0
## A foot moving forward this fast relative to the body is fully in swing, m/s.
@export var swing_speed_mps: float = 1.2
## How fast wading eases in and out, per second.
@export var blend_rate: float = 2.5

var _shown: float = 0.0
var _index: Dictionary = {}
var _last_foot: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _swing: Array[float] = [0.0, 0.0]


func _process_modification() -> void:
	var skeleton: Skeleton3D = get_skeleton()
	if skeleton == null:
		return
	_shown = move_toward(_shown, wade, blend_rate * get_process_delta_time())
	if _shown <= 0.001:
		return
	var delta: float = maxf(get_process_delta_time(), 0.001)
	for side: int in range(2):
		var i: int = _bone(skeleton, FEET[side])
		if i < 0:
			return
		## Rig space: the body stands still, a planted foot slides back and the
		## swinging foot travels forward. Only that forward travel lifts the knee.
		var foot: Vector3 = skeleton.get_bone_global_pose(i).origin
		var forward_speed: float = (foot.z - _last_foot[side].z) / delta
		_last_foot[side] = foot
		var target: float = clampf(forward_speed / swing_speed_mps, 0.0, 1.0)
		_swing[side] = lerpf(_swing[side], target, clampf(delta * 14.0, 0.0, 1.0))
		var swing: float = _swing[side] * _swing[side] * (3.0 - 2.0 * _swing[side])
		_flex(skeleton, THIGHS[side], -deg_to_rad(knee_lift_deg) * _shown * swing)
		_flex(skeleton, CALVES[side], deg_to_rad(shin_fold_deg) * _shown * swing)
	_flex(skeleton, SPINE, deg_to_rad(lean_deg) * _shown)


func _flex(skeleton: Skeleton3D, bone: StringName, angle: float) -> void:
	var i: int = _bone(skeleton, bone)
	if i < 0 or is_zero_approx(angle):
		return
	skeleton.set_bone_pose_rotation(i, skeleton.get_bone_pose_rotation(i) * Quaternion(Vector3.RIGHT, angle))


func _bone(skeleton: Skeleton3D, bone: StringName) -> int:
	if not _index.has(bone):
		_index[bone] = skeleton.find_bone(bone)
	return _index[bone]
