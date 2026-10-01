extends SceneTree

## Measures Henry from the model the game loads: skins every visible mesh on the CPU,
## averaged over the idle and crouch-idle cycles, into res://data/characters/henry_metrics.tres.
## Run: xvfb-run godot --path . --rendering-driver vulkan --windowed --resolution 320x180 --script res://tools/runtime/measure_henry_metrics.gd

const OUT: String = "res://data/characters/henry_metrics.tres"
const SETTLE_FRAMES: int = 150
## The idle breathes: poses sampled this many frames apart are averaged.
const SAMPLES: int = 16
const SAMPLE_GAP_FRAMES: int = 9
## Dressed meshes; the pack hangs on its own attachment and is measured apart.
const BODY_PARENTS: Array[String] = ["Skeleton3D", "Hat", "Coat", "Trousers", "Boots"]
const HEAD_BONES: Array[String] = ["Head"]
const SHOULDER_BONES: Array[String] = ["clavicle_l", "clavicle_r", "upperarm_l", "upperarm_r"]
const TORSO_BONES: Array[String] = ["spine_02", "spine_03", "clavicle_l", "clavicle_r"]


## Runs last in each frame, after every _process.
class FrameProbe extends Node:
	signal frame_done

	func _init() -> void:
		process_priority = 4096

	func _process(_delta: float) -> void:
		frame_done.emit()


var _player: CharacterBody3D
var _skeleton: Skeleton3D
var _capsule: CollisionShape3D
var _probe: FrameProbe


func _initialize() -> void:
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20.0, 1.0, 20.0)
	shape.shape = box
	ground.add_child(shape)
	ground.position = Vector3(0.0, -0.5, 0.0)
	root.add_child(ground)
	_player = (load("res://scenes/actors/player/player.tscn") as PackedScene).instantiate() as CharacterBody3D
	root.add_child(_player)
	_player.position = Vector3(0.0, 1.0, 0.0)
	_probe = FrameProbe.new()
	root.add_child(_probe)
	_run.call_deferred()


func _run() -> void:
	_skeleton = _player.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	_capsule = _player.get_node(^"Main_Collision") as CollisionShape3D
	await _frames(SETTLE_FRAMES)
	var metrics := HenryMetrics.new()
	metrics.source = "player.tscn / HenryUALVisual / henry_outfit.glb, idle and crouch idle, %s" % Time.get_date_string_from_system()
	var capsule := _capsule.shape as CapsuleShape3D
	metrics.capsule_radius = capsule.radius
	metrics.capsule_height = capsule.height
	var stand: Dictionary = await _measure_cycle()
	Input.action_press(&"crouch")
	await _frames(SETTLE_FRAMES)
	metrics.crouch_capsule_height = (_capsule.shape as CapsuleShape3D).height
	var crouch: Dictionary = await _measure_cycle()
	Input.action_release(&"crouch")
	metrics.standing_top = stand["top"]
	metrics.standing_eye = stand["eye"]
	metrics.standing_shoulder = stand["shoulder"]
	metrics.standing_shoulder_top = stand["shoulder_top"]
	metrics.crouch_top = crouch["top"]
	metrics.crouch_eye = crouch["eye"]
	metrics.crouch_shoulder = crouch["shoulder"]
	metrics.crouch_shoulder_top = crouch["shoulder_top"]
	metrics.shoulder_joint_width = stand["shoulder_joint_width"]
	metrics.body_width = stand["body_width"]
	metrics.body_depth = stand["body_depth"]
	metrics.pack_behind = stand["pack_behind"]
	metrics.pack_top = stand["pack_top"]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT.get_base_dir()))
	var error: Error = ResourceSaver.save(metrics, OUT)
	print("[metrics] stand %s" % JSON.stringify(stand))
	print("[metrics] crouch %s" % JSON.stringify(crouch))
	print("[metrics] capsule radius %.3f height %.3f crouch %.3f; saved %s (%d)" % [metrics.capsule_radius,
		metrics.capsule_height, metrics.crouch_capsule_height, OUT, error])
	quit(0 if error == OK else 1)


## Mean of every measure over the idle cycle; "<key>_spread" holds its range.
func _measure_cycle() -> Dictionary:
	var samples: Array[Dictionary] = []
	for i: int in range(SAMPLES):
		samples.append(_measure())
		await _frames(SAMPLE_GAP_FRAMES)
	var result: Dictionary = {}
	for key: String in samples[0].keys():
		var low: float = INF
		var high: float = -INF
		var sum: float = 0.0
		for sample: Dictionary in samples:
			low = minf(low, float(sample[key]))
			high = maxf(high, float(sample[key]))
			sum += float(sample[key])
		result[key] = sum / float(samples.size())
		result[key + "_spread"] = high - low
	return result


## Henry's dimensions in the current pose, metres above the capsule's bottom.
func _measure() -> Dictionary:
	var capsule := _capsule.shape as CapsuleShape3D
	var feet_y: float = _player.global_position.y + _capsule.position.y - capsule.height * 0.5
	var lateral: Vector3 = _player.global_basis.x.normalized()
	var forward: Vector3 = -_player.global_basis.z.normalized()
	var points := PackedVector3Array()
	var bones := PackedStringArray()
	for node: Node in _player.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.skin == null or not mesh.is_visible_in_tree() or not BODY_PARENTS.has(String(mesh.get_parent().name)):
			continue
		_skin(mesh, points, bones)
	var sole: float = INF
	var top: float = -INF
	var chin: float = INF
	var crown: float = -INF
	var shoulder_top: float = -INF
	for i: int in range(points.size()):
		var y: float = points[i].y - feet_y
		sole = minf(sole, y)
		top = maxf(top, y)
		if HEAD_BONES.has(bones[i]):
			chin = minf(chin, y)
			crown = maxf(crown, y)
		if SHOULDER_BONES.has(bones[i]):
			shoulder_top = maxf(shoulder_top, y)
	var shoulder_l: Vector3 = _bone("upperarm_l")
	var shoulder_r: Vector3 = _bone("upperarm_r")
	var shoulder: float = (shoulder_l.y + shoulder_r.y) * 0.5 - feet_y
	var chest: float = (_bone("spine_03").y - feet_y)
	var width: Vector2 = Vector2(INF, -INF)
	var depth: Vector2 = Vector2(INF, -INF)
	for i: int in range(points.size()):
		var y: float = points[i].y - feet_y
		var flat: Vector3 = points[i] - _player.global_position
		if absf(y - shoulder) < 0.08:
			width = Vector2(minf(width.x, flat.dot(lateral)), maxf(width.y, flat.dot(lateral)))
		if absf(y - chest) < 0.08 and TORSO_BONES.has(bones[i]):
			depth = Vector2(minf(depth.x, flat.dot(forward)), maxf(depth.y, flat.dot(forward)))
	var pack: Vector3 = _pack_extent(forward, feet_y)
	return {
		"sole": sole, "top": top, "chin": chin, "crown": crown, "eye": (chin + crown) * 0.5,
		"head_bone": _bone("Head").y - feet_y, "shoulder": shoulder, "shoulder_top": shoulder_top,
		"shoulder_joint_width": shoulder_l.distance_to(shoulder_r), "body_width": width.y - width.x,
		"body_depth": depth.y - depth.x, "body_back": depth.x, "pack_behind": maxf(0.0, depth.x - pack.x),
		"pack_top": pack.y, "points": points.size(),
	}


## Pushes every vertex of a skinned mesh through the current skeleton pose.
func _skin(mesh: MeshInstance3D, points: PackedVector3Array, names: PackedStringArray) -> void:
	var skin: Skin = mesh.skin
	var binds: Array[Transform3D] = []
	var bind_bones: PackedStringArray = []
	for bind: int in range(skin.get_bind_count()):
		var bone: int = skin.get_bind_bone(bind)
		if bone < 0:
			bone = _skeleton.find_bone(skin.get_bind_name(bind))
		binds.append(_skeleton.global_transform * _skeleton.get_bone_global_pose(bone) * skin.get_bind_pose(bind))
		bind_bones.append(_skeleton.get_bone_name(bone))
	for surface: int in range(mesh.mesh.get_surface_count()):
		var arrays: Array = mesh.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bone_ids: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var stride: int = bone_ids.size() / maxi(vertices.size(), 1)
		for v: int in range(vertices.size()):
			var sum := Vector3.ZERO
			var best: float = -1.0
			var best_bone: String = ""
			for k: int in range(stride):
				var weight: float = weights[v * stride + k]
				if weight <= 0.0:
					continue
				var bind: int = bone_ids[v * stride + k]
				sum += (binds[bind] * vertices[v]) * weight
				if weight > best:
					best = weight
					best_bone = bind_bones[bind]
			points.append(sum)
			names.append(best_bone)


## Rear-most point of the pack along `forward` (x) and its top above the feet (y).
func _pack_extent(forward: Vector3, feet_y: float) -> Vector3:
	var back: float = INF
	var top: float = -INF
	for node: Node in _player.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.skin != null or not mesh.is_visible_in_tree() or not String(mesh.get_path()).contains("BackpackAttachment"):
			continue
		var box: AABB = mesh.get_aabb()
		for corner: int in range(8):
			var point: Vector3 = mesh.global_transform * box.get_endpoint(corner)
			back = minf(back, (point - _player.global_position).dot(forward))
			top = maxf(top, point.y - feet_y)
	return Vector3(back, top, 0.0)


func _bone(bone_name: String) -> Vector3:
	return _skeleton.global_transform * _skeleton.get_bone_global_pose(_skeleton.find_bone(bone_name)).origin


func _frames(count: int) -> void:
	for i: int in range(count):
		await _probe.frame_done
