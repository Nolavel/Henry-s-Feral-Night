extends SceneTree

## Measures TpsCamera in TestScene with the real Henry: look response, judder,
## wall/doorway conflicts, crouch, thin occluders, teleport and sway.
## Run: godot --headless --path . --fixed-fps 144 --script res://tools/runtime/trace_tps_camera.gd -- <label> [scenario...]

## Override with a "scene=res://..." argument; the "shelter" scenario needs Key West.
const SCENE: String = "res://tests/scenes/TestScene.tscn"
const OUT_ROOT: String = "user://traces/tps_camera"
const WARMUP_FRAMES: int = 90
const SETTLE_FRAMES: int = 150
## Radians of turn per pixel, as InputSystems.MOUSE_SENSITIVITY.
const MOUSE_SENSITIVITY: float = 0.003
## Sphere around the render origin that covers the near-plane corners, metres.
const NEAR_PROBE_RADIUS: float = 0.08
## A per-frame change of the head distance above this counts as a pop, metres.
const POP_THRESHOLD: float = 0.3
const OPEN_SPOT: Vector3 = Vector3(8.0, 1.0, 6.0)
const SCENARIOS: PackedStringArray = [
	"look", "walk", "orbit", "door_pass", "crouch", "pole", "teleport", "sway", "assist", "recenter",
]
## Probe points around TestShelter (origin z = 14): name, Henry origin.
const ORBIT_POINTS: Array = [
	["open", Vector3(8.0, 1.0, 6.0)],
	["wall_by_door", Vector3(3.72, 1.0, 15.8)],
	["wall_long", Vector3(0.0, 1.0, 10.33)],
	["room_center", Vector3(0.0, 1.0, 14.0)],
	["room_corner", Vector3(-2.3, 1.0, 16.3)],
	["doorway", Vector3(3.0, 1.0, 14.0)],
	["back_to_wall", Vector3(0.0, 1.0, 11.72)],
	["window", Vector3(-2.3, 1.0, 14.0)],
]
const ORBIT_PITCHES: Array = [-10.0, -40.0, 30.0]


## Runs last in each frame, after every _process, and reports the frame.
class FrameProbe extends Node:
	signal frame_done

	var delta: float = 1.0 / 60.0

	func _init() -> void:
		process_priority = 4096

	func _process(frame_delta: float) -> void:
		delta = frame_delta
		frame_done.emit()


var _label: String = "run"
var _scene_path: String = SCENE
var _spawn_origin: Vector3 = Vector3.ZERO
var _selected: PackedStringArray = []
var _scene: Node
var _player: Player
var _cam: TpsCamera
var _skeleton: Skeleton3D
var _head_bone: int = -1
var _probe: FrameProbe
var _frame: int = 0
var _summary: Dictionary = {}
var _rows: Array[Dictionary] = []
var _last_head_distance: float = -1.0
var _last_render: Vector3 = Vector3.ZERO
## With "shots" in the arguments, frames are saved at the first conflict events.
var _shots: bool = false
var _shots_left: int = 0
var _last_flags: Dictionary = {}


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		_label = args[0]
	for i: int in range(1, args.size()):
		if args[i] == "shots":
			_shots = true
		elif args[i].begins_with("scene="):
			_scene_path = args[i].trim_prefix("scene=")
		else:
			_selected.append(args[i])
	if _selected.is_empty():
		_selected = SCENARIOS
	## Headless windows are 100 px; unscaled, a traced pixel is a screen pixel.
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	_scene = (load(_scene_path) as PackedScene).instantiate()
	root.add_child(_scene)
	_player = _scene.find_child("Player", true, false) as Player
	_cam = _scene.find_child("PlayerCamera", true, false) as TpsCamera
	var skeletons: Array[Node] = _player.find_children("*", "Skeleton3D", true, false)
	if not skeletons.is_empty():
		_skeleton = skeletons[0] as Skeleton3D
		_head_bone = _skeleton.find_bone("Head")
	_probe = FrameProbe.new()
	root.add_child(_probe)
	_run.call_deferred()


func _run() -> void:
	await _frames(WARMUP_FRAMES)
	_spawn_origin = _player.global_position
	var previous: Variant = JSON.parse_string(_read_text(_out_dir().path_join("summary.json")))
	if previous is Dictionary:
		_summary = previous
	_summary["meta"] = {
		"label": _label,
		"frame_rate": _fps(),
		"physics_ticks_per_second": Engine.physics_ticks_per_second,
		"physics_interpolation": ProjectSettings.get_setting("physics/common/physics_interpolation", false),
		"camera_tree_index": _cam.get_index(),
		"player_tree_index": _player.get_index(),
		"head_bone_found": _head_bone >= 0,
	}
	for scenario: String in _selected:
		print("[trace] %s" % scenario)
		match scenario:
			"look": await _scenario_look()
			"walk": await _scenario_walk()
			"orbit": await _scenario_orbit()
			"door_pass": await _scenario_door_pass()
			"crouch": await _scenario_crouch()
			"pole": await _scenario_pole()
			"teleport": await _scenario_teleport()
			"sway": await _scenario_sway()
			"assist": await _scenario_assist()
			"recenter": await _scenario_recenter()
			"shelter": await _scenario_shelter()
			_: push_error("trace: unknown scenario %s" % scenario)
	_write_json("summary.json", _summary)
	print(JSON.stringify(_summary, "  "))
	quit(0)


## Mouse look: per-frame update ratio, first response, steady lag and a flick.
func _scenario_look() -> void:
	await _place(OPEN_SPOT, 0.0, -10.0)
	_begin()
	var rate: float = MOUSE_SENSITIVITY * _cam.look_sensitivity_x
	var cmd: float = _cam.global_rotation.y
	var sweep_frames: int = 108
	var px: float = 8.0
	var changed: int = 0
	var first_change: int = -1
	var lags: Array[float] = []
	var prev_yaw: float = _cam.global_rotation.y
	for i: int in range(sweep_frames * 2):
		if i < sweep_frames:
			_mouse(px, 0.0)
			cmd -= px * rate
		await _sample("look")
		var yaw: float = _cam.global_rotation.y
		var moved: bool = absf(angle_difference(prev_yaw, yaw)) > 1e-6
		if i < sweep_frames:
			if moved:
				changed += 1
				if first_change < 0:
					first_change = i
			if i >= sweep_frames / 2:
				lags.append(rad_to_deg(angle_difference(yaw, cmd)))
		prev_yaw = yaw
	var deg_per_s: float = rad_to_deg(px * rate) * float(_fps())
	var steady_lag_deg: float = _mean(lags)
	var flick: Dictionary = await _flick(120.0)
	_summary["look"] = {
		"frames_with_input": sweep_frames,
		"frames_camera_turned": changed,
		"update_ratio": float(changed) / float(sweep_frames),
		"first_response_frames": first_change,
		"turn_speed_deg_s": deg_per_s,
		"steady_lag_deg": steady_lag_deg,
		"steady_lag_ms": absf(steady_lag_deg) / deg_per_s * 1000.0,
		"flick": flick,
	}
	_end("look")


## One frame of mouse travel, then the time to reach half and 90 % of it.
func _flick(px: float) -> Dictionary:
	await _frames(60)
	var start: float = _cam.global_rotation.y
	var target: float = -px * MOUSE_SENSITIVITY * _cam.look_sensitivity_x
	_mouse(px, 0.0)
	var half: int = -1
	var most: int = -1
	for i: int in range(120):
		await _sample("flick")
		var done: float = angle_difference(start, _cam.global_rotation.y) / target
		if half < 0 and done >= 0.5:
			half = i
		if most < 0 and done >= 0.9:
			most = i
	var frame_ms: float = 1000.0 / float(_fps())
	return {"turn_deg": rad_to_deg(absf(target)), "frames_to_50": half, "frames_to_90": most,
		"ms_to_50": float(half + 1) * frame_ms, "ms_to_90": float(most + 1) * frame_ms}


## Walking and sprinting in the open: how evenly the view advances per frame.
func _scenario_walk() -> void:
	for sprint: bool in [false, true]:
		var key: String = "sprint" if sprint else "walk"
		await _place(OPEN_SPOT, 0.0, -10.0)
		_begin()
		Input.action_press(&"move_forward")
		if sprint:
			Input.action_press(&"sprint")
		var steps: Array[float] = []
		var body_steps: Array[float] = []
		var prev: Vector3 = _render_origin()
		var prev_body: Vector3 = _player.get_global_transform_interpolated().origin
		for i: int in range(288):
			await _sample(key)
			var now: Vector3 = _render_origin()
			if i >= 144:
				steps.append(now.distance_to(prev))
				body_steps.append(_player.get_global_transform_interpolated().origin.distance_to(prev_body))
			prev = now
			prev_body = _player.get_global_transform_interpolated().origin
		Input.action_release(&"move_forward")
		Input.action_release(&"sprint")
		var still: int = 0
		for s: float in steps:
			if s < 1e-5:
				still += 1
		_summary[key] = {
			"frames": steps.size(),
			"camera_frames_without_motion": still,
			"camera_step_mean_m": _mean(steps),
			"camera_step_cv": _std(steps) / maxf(_mean(steps), 1e-9),
			"camera_step_max_m": _max(steps),
			"henry_step_cv": _std(body_steps) / maxf(_mean(body_steps), 1e-9),
		}
		_end(key)


## Continuous 360-degree mouse sweeps at each probe point and pitch.
func _scenario_orbit() -> void:
	var by_point: Dictionary = {}
	for point: Array in ORBIT_POINTS:
		for pitch: float in ORBIT_PITCHES:
			var key: String = "%s_%d" % [point[0], int(pitch)]
			await _place(point[1], 0.0, pitch)
			_begin()
			var px: float = (TAU / 432.0) / (MOUSE_SENSITIVITY * _cam.look_sensitivity_x)
			for i: int in range(432):
				_mouse(px, 0.0)
				await _sample(key)
			by_point[key] = _end(key)
	_summary["orbit"] = by_point


## Walks through the shelter doorway in and out, camera behind, then sideways.
func _scenario_door_pass() -> void:
	await _place(Vector3(6.5, 1.0, 14.0), PI * 0.5, -10.0)
	_begin()
	await _hold_until(&"move_forward", "door_in", func() -> bool: return _player.global_position.x < 0.0, 8.0)
	var px: float = (PI / 108.0) / (MOUSE_SENSITIVITY * _cam.look_sensitivity_x)
	for i: int in range(108):
		_mouse(px, 0.0)
		await _sample("door_turn")
	await _frames(30)
	await _hold_until(&"move_forward", "door_out", func() -> bool: return _player.global_position.x > 6.5, 8.0)
	_summary["door_pass_behind"] = _end("door_pass_behind")
	await _place(Vector3(6.5, 1.0, 14.0), 0.0, -10.0)
	_begin()
	await _hold_until(&"move_left", "side_in", func() -> bool: return _player.global_position.x < 0.0, 8.0)
	await _hold_until(&"move_right", "side_out", func() -> bool: return _player.global_position.x > 6.5, 8.0)
	_summary["door_pass_side"] = _end("door_pass_side")


## Crouching in the open, then under a 1.5 m slab, with a full mouse sweep.
func _scenario_crouch() -> void:
	await _place(OPEN_SPOT, 0.0, -10.0)
	var stand_cam_y: float = _render_origin().y
	var stand_head_y: float = _head().y
	Input.action_press(&"crouch")
	await _frames(120)
	var crouch_cam_y: float = _render_origin().y
	var crouch_head_y: float = _head().y
	Input.action_release(&"crouch")
	_summary["crouch_open"] = {
		"head_drop_m": stand_head_y - crouch_head_y,
		"camera_drop_m": stand_cam_y - crouch_cam_y,
		"crouched": _player.is_crouching(),
	}
	var slab: StaticBody3D = _add_box(Vector3(14.0, 1.6, 9.0), Vector3(3.0, 0.2, 4.0))
	await _place(Vector3(14.0, 1.0, 5.0), PI, -10.0)
	Input.action_press(&"crouch")
	await _frames(60)
	_begin()
	await _hold_until(&"move_forward", "crawl_in", func() -> bool: return _player.global_position.z > 9.0, 8.0)
	await _frames(60)
	var px: float = (TAU / 432.0) / (MOUSE_SENSITIVITY * _cam.look_sensitivity_x)
	for i: int in range(432):
		_mouse(px, 0.0)
		await _sample("crawl_sweep")
	Input.action_release(&"crouch")
	_summary["crouch_low_slab"] = _end("crouch_low_slab")
	slab.queue_free()
	await _frames(2)


## Strafes past a thin pole standing between camera and Henry.
func _scenario_pole() -> void:
	var pole := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 0.08
	cylinder.height = 3.0
	shape.shape = cylinder
	pole.add_child(shape)
	pole.position = Vector3(20.0, 1.5, 1.5)
	_scene.add_child(pole)
	await _place(Vector3(16.5, 1.0, 0.0), 0.0, -10.0)
	_begin()
	await _hold_until(&"move_right", "pole", func() -> bool: return _player.global_position.x > 23.5, 8.0)
	_summary["pole"] = _end("pole")
	pole.queue_free()
	await _frames(2)


## Henry jumps from the open into the shelter without a camera reset.
func _scenario_teleport() -> void:
	await _place(OPEN_SPOT, 0.0, -10.0)
	_begin()
	_player.global_position = Vector3(0.0, 1.0, 14.0)
	_player.velocity = Vector3.ZERO
	var path: Array[Vector3] = []
	var through_walls: int = 0
	var prev: Vector3 = _render_origin()
	for i: int in range(360):
		await _sample("teleport")
		var now: Vector3 = _render_origin()
		if _segment_blocked(prev, now):
			through_walls += 1
		path.append(now)
		prev = now
	var final: Vector3 = path[path.size() - 1]
	var arrived: int = -1
	for i: int in range(path.size()):
		if path[i].distance_to(final) < 0.1:
			arrived = i
			break
	var result: Dictionary = _end("teleport")
	result["frames_to_settle"] = arrived
	result["ms_to_settle"] = float(arrived + 1) * 1000.0 / float(_fps())
	result["frames_moving_through_geometry"] = through_walls
	_summary["teleport"] = result


## Idle breathing: pitch wobble and how far the centre ray drifts at 2 m.
func _scenario_sway() -> void:
	await _place(OPEN_SPOT, 0.0, -10.0)
	_begin()
	var lo: float = INF
	var hi: float = -INF
	for i: int in range(576):
		await _sample("sway")
		var pitch: float = rad_to_deg(_cam.global_rotation.x)
		lo = minf(lo, pitch)
		hi = maxf(hi, pitch)
	var result: Dictionary = _end("sway")
	result["pitch_peak_to_peak_deg"] = hi - lo
	result["centre_ray_drift_at_2m_cm"] = 200.0 * tan(deg_to_rad(hi - lo))
	_summary["sway"] = result


## Back to the wall, view aimed into it: the mouse keeps moving (no automatic
## turn may happen), then rests (a turn may start after the cooldown), then W.
func _scenario_assist() -> void:
	_release_actions()
	_player.global_position = Vector3(0.0, 1.0, 11.72)
	_player.velocity = Vector3.ZERO
	_player.rotation.y = PI
	_cam.set_look(PI, -10.0)
	_snap_camera()
	_begin()
	var aimed: float = _cam.get_yaw()
	var busy_drift: float = 0.0
	for i: int in range(288):
		_mouse(1.0 if i % 2 == 0 else -1.0, 0.0)
		await _sample("assist_busy")
		busy_drift = maxf(busy_drift, absf(rad_to_deg(angle_difference(aimed, _cam.get_yaw()))))
	var held: float = _cam.get_yaw()
	var first_turn: int = -1
	for i: int in range(360):
		await _sample("assist_rest")
		if first_turn < 0 and absf(rad_to_deg(angle_difference(held, _cam.get_yaw()))) > 0.5:
			first_turn = i
	var rest_turn: float = rad_to_deg(angle_difference(held, _cam.get_yaw()))
	Input.action_press(&"move_forward")
	var errors: Array[float] = []
	for i: int in range(144):
		await _sample("assist_walk")
		var v := Vector3(_player.velocity.x, 0.0, _player.velocity.z)
		if v.length() > 0.5:
			errors.append(absf(rad_to_deg(angle_difference(_cam.get_yaw(), atan2(-v.x, -v.z)))))
	Input.action_release(&"move_forward")
	var result: Dictionary = _end("assist")
	result["auto_turn_while_mouse_moves_deg"] = busy_drift
	result["first_auto_turn_after_rest_ms"] = -1.0 if first_turn < 0 else float(first_turn + 1) * 1000.0 / _fps()
	result["auto_turn_after_rest_deg"] = rest_turn
	result["walk_heading_vs_view_deg_mean"] = _mean(errors)
	result["walk_heading_vs_view_deg_max"] = _max(errors)
	_summary["assist"] = result


## Henry walks off 60 degrees right on his own (scripted walk), then strafes on
## D: the view should follow the walk after the cooldown and stay for the strafe.
func _scenario_recenter() -> void:
	await _place(OPEN_SPOT, 0.0, -10.0)
	_begin()
	var start: float = _cam.get_yaw()
	_player.move_to_position(OPEN_SPOT + Vector3(sin(deg_to_rad(60.0)), 0.0, -cos(deg_to_rad(60.0))) * 8.0)
	var first_turn: int = -1
	for i: int in range(576):
		await _sample("recenter_walk")
		if first_turn < 0 and absf(rad_to_deg(angle_difference(start, _cam.get_yaw()))) > 0.5:
			first_turn = i
		if not _player.is_walking_to_target():
			break
	var walked_turn: float = rad_to_deg(angle_difference(start, _cam.get_yaw()))
	_player.stop_moving()
	await _frames(30)
	var before_strafe: float = _cam.get_yaw()
	Input.action_press(&"move_right")
	for i: int in range(432):
		await _sample("recenter_strafe")
	Input.action_release(&"move_right")
	var result: Dictionary = _end("recenter")
	result["walk_first_turn_ms"] = -1.0 if first_turn < 0 else float(first_turn + 1) * 1000.0 / _fps()
	result["walk_view_turn_deg"] = walked_turn
	result["strafe_view_turn_deg"] = rad_to_deg(angle_difference(before_strafe, _cam.get_yaw()))
	_summary["recenter"] = result


## Key West: from the porch through the real shelter door into the room on a
## scripted walk with the mouse at rest, then view sweeps in the door and inside.
func _scenario_shelter() -> void:
	var zone := _scene.find_child("ShelterZone", true, false) as Node3D
	var breach: Node3D = zone.find_child("Door", true, false) as Node3D if zone != null else null
	if breach == null:
		push_warning("trace: no ShelterZone/Door in %s" % _scene_path)
		return
	var door: Node = _nearest_door(breach.global_position)
	if door != null:
		door.call(&"load_door_save_data", {"latched": false, "angle_deg": float(door.get("open_angle_deg"))})
	var doorway: Vector3 = _floor_point(breach.global_position)
	var inside: Vector3 = _floor_point(zone.global_position)
	var to_door: Vector3 = doorway - _spawn_origin
	await _place(_spawn_origin, atan2(-to_door.x, -to_door.z), -10.0)
	_begin()
	for leg: Array in [["shelter_to_door", doorway], ["shelter_in", inside]]:
		_player.move_to_position(leg[1])
		for i: int in range(1440):
			await _sample(leg[0])
			if not _player.is_walking_to_target():
				break
	var result: Dictionary = _end("shelter_walk_in")
	result["reached_inside_m"] = Vector2(_player.global_position.x - inside.x, _player.global_position.z - inside.z).length()
	result["door_found"] = door != null
	_summary["shelter_walk_in"] = result
	var sweeps: Dictionary = {}
	for point: Array in [["shelter_doorway", doorway], ["shelter_inside", inside]]:
		for pitch: float in ORBIT_PITCHES:
			var key: String = "%s_%d" % [point[0], int(pitch)]
			await _place(point[1], 0.0, pitch)
			_begin()
			var px: float = (TAU / 432.0) / (MOUSE_SENSITIVITY * _cam.look_sensitivity_x)
			for i: int in range(432):
				_mouse(px, 0.0)
				await _sample(key)
			sweeps[key] = _end(key)
	_summary["shelter_orbit"] = sweeps


func _nearest_door(at: Vector3) -> Node:
	var best: Node = null
	var best_distance: float = 4.0
	for node: Node in get_nodes_in_group(&"hinged_doors"):
		var door := node as Node3D
		if door != null and door.global_position.distance_to(at) < best_distance:
			best = door
			best_distance = door.global_position.distance_to(at)
	return best


## Henry's origin standing on the floor under `at`.
func _floor_point(at: Vector3) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 1.5, at + Vector3.DOWN * 6.0)
	query.exclude = [_player.get_rid()]
	var hit: Dictionary = _space().intersect_ray(query)
	return (hit["position"] as Vector3) + Vector3.UP * 1.0 if not hit.is_empty() else at


func _release_actions() -> void:
	for action: StringName in [&"move_forward", &"move_backward", &"move_left", &"move_right", &"sprint", &"crouch"]:
		Input.action_release(action)


## Holds an action until the condition holds or the timeout passes.
func _hold_until(action: StringName, tag: String, done: Callable, timeout: float) -> void:
	Input.action_press(action)
	var frames: int = int(timeout * float(_fps()))
	for i: int in range(frames):
		await _sample(tag)
		if done.call():
			break
	Input.action_release(action)


func _place(at: Vector3, yaw: float, pitch: float) -> void:
	_release_actions()
	_player.global_position = at
	_player.velocity = Vector3.ZERO
	_player.rotation.y = yaw
	_cam.set_look(yaw, pitch)
	_snap_camera()
	await _frames(SETTLE_FRAMES)


## Puts the camera on its goal at once; the probe uses a public snap if one exists.
func _snap_camera() -> void:
	if _cam.has_method(&"snap_to_target"):
		_cam.call(&"snap_to_target")
		return
	_cam.set("_has_position", false)
	_cam.set("_collision_distance", -1.0)


func _mouse(dx: float, dy: float) -> void:
	var event := InputEventMouseMotion.new()
	event.relative = Vector2(dx, dy)
	event.screen_relative = Vector2(dx, dy)
	Input.parse_input_event(event)


func _frames(count: int) -> void:
	for i: int in range(count):
		await _probe.frame_done
		_frame += 1


func _begin() -> void:
	_shots_left = 4
	_last_flags = {}
	_rows.clear()
	_last_head_distance = -1.0
	_last_render = _render_origin()


## Waits one frame, then records the camera against the world.
func _sample(tag: String) -> void:
	await _frames(1)
	var render: Vector3 = _render_origin()
	var head: Vector3 = _head()
	var distance: float = render.distance_to(head)
	var jump: float = 0.0 if _last_head_distance < 0.0 else distance - _last_head_distance
	_last_head_distance = distance
	_rows.append({
		"frame": _frame,
		"tag": tag,
		"physics_frames": Engine.get_physics_frames(),
		"henry_x": _player.global_position.x, "henry_y": _player.global_position.y,
		"henry_z": _player.global_position.z,
		"cam_x": render.x, "cam_y": render.y, "cam_z": render.z,
		"yaw_deg": rad_to_deg(_cam.global_rotation.y),
		"pitch_deg": rad_to_deg(_cam.global_rotation.x),
		"h_offset": _cam.h_offset,
		"boom": _cam.get_boom_length(),
		"head_distance": distance,
		"head_distance_jump": jump,
		"render_inside": _point_inside(render),
		"node_inside": _point_inside(_cam.global_position),
		"near_clip": _near_clipped(render),
		"node_near_clip": _near_clipped(_cam.global_position),
		"head_occluded": _segment_blocked(render, head),
		"body_hidden": _cam.is_body_hidden(),
		"body_fade": float(_cam.call(&"get_body_fade")) if _cam.has_method(&"get_body_fade") else float(_cam.is_body_hidden()),
	})
	_last_render = render
	if _shots:
		_shoot_on_events(tag, _rows[_rows.size() - 1])


## Saves the frame when a conflict starts or the boom pops, a few per scenario.
func _shoot_on_events(tag: String, row: Dictionary) -> void:
	var event: String = ""
	for key: String in ["body_hidden", "near_clip", "head_occluded", "render_inside"]:
		if row[key] and not _last_flags.get(key, false):
			event = key
		_last_flags[key] = row[key]
	if event.is_empty() and absf(row["head_distance_jump"]) > POP_THRESHOLD:
		event = "pop"
	if event.is_empty() or _shots_left <= 0:
		return
	_shots_left -= 1
	var image: Image = root.get_texture().get_image()
	if image == null:
		return
	var dir: String = _out_dir().path_join("shots")
	DirAccess.make_dir_recursive_absolute(dir)
	image.save_png(dir.path_join("%06d_%s_%s.png" % [_frame, tag, event]))


## Aggregates the rows since _begin(), writes them to CSV and returns metrics.
func _end(name: String) -> Dictionary:
	var frames: int = _rows.size()
	var counts: Dictionary = {"render_inside": 0, "node_inside": 0, "near_clip": 0, "node_near_clip": 0,
		"head_occluded": 0, "body_hidden": 0}
	var min_distance: float = INF
	var faded: int = 0
	var max_fade: float = 0.0
	var max_drop: float = 0.0
	var pops: int = 0
	for row: Dictionary in _rows:
		for key: String in counts.keys():
			if row[key]:
				counts[key] += 1
		min_distance = minf(min_distance, row["head_distance"])
		if row["body_fade"] > 0.0:
			faded += 1
		max_fade = maxf(max_fade, row["body_fade"])
		max_drop = maxf(max_drop, -float(row["head_distance_jump"]))
		if absf(row["head_distance_jump"]) > POP_THRESHOLD:
			pops += 1
	_write_csv(name + ".csv")
	var result: Dictionary = {"frames": frames, "min_head_distance_m": min_distance,
		"max_single_frame_pull_in_m": max_drop, "pops_over_%.1fm" % POP_THRESHOLD: pops,
		"frames_body_faded": faded, "max_body_fade": max_fade}
	for key: String in counts.keys():
		result["frames_" + key] = counts[key]
	return result


## Frame rate from the frame delta; --fixed-fps makes it exact.
func _fps() -> float:
	return 1.0 / maxf(_probe.delta, 1e-6)


func _render_origin() -> Vector3:
	return _cam.get_camera_transform().origin


## Henry's head bone; the capsule top is a fallback if the rig is missing.
func _head() -> Vector3:
	if _skeleton != null and _head_bone >= 0:
		return _skeleton.global_transform * _skeleton.get_bone_global_pose(_head_bone).origin
	return _player.global_position + Vector3.UP * 0.69


func _point_inside(point: Vector3) -> bool:
	var query := PhysicsPointQueryParameters3D.new()
	query.position = point
	query.exclude = [_player.get_rid()]
	return not _space().intersect_point(query, 1).is_empty()


func _near_clipped(point: Vector3) -> bool:
	var sphere := SphereShape3D.new()
	sphere.radius = NEAR_PROBE_RADIUS
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, point)
	query.exclude = [_player.get_rid()]
	return not _space().intersect_shape(query, 1).is_empty()


func _segment_blocked(from: Vector3, to: Vector3) -> bool:
	if from.distance_to(to) < 0.001:
		return false
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [_player.get_rid()]
	query.hit_from_inside = true
	return not _space().intersect_ray(query).is_empty()


func _space() -> PhysicsDirectSpaceState3D:
	return _cam.get_world_3d().direct_space_state


func _add_box(center: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = center
	_scene.add_child(body)
	return body


func _write_csv(file_name: String) -> void:
	if _rows.is_empty():
		return
	var path: String = _out_dir().path_join(file_name)
	var file := FileAccess.open(path, FileAccess.WRITE)
	var keys: Array = _rows[0].keys()
	file.store_line(",".join(PackedStringArray(keys)))
	for row: Dictionary in _rows:
		var cells: PackedStringArray = []
		for key: Variant in keys:
			cells.append(str(row[key]))
		file.store_line(",".join(cells))


func _write_json(file_name: String, data: Dictionary) -> void:
	var file := FileAccess.open(_out_dir().path_join(file_name), FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "  "))


func _read_text(path: String) -> String:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""


func _out_dir() -> String:
	var dir: String = ProjectSettings.globalize_path(OUT_ROOT.path_join(_label))
	DirAccess.make_dir_recursive_absolute(dir)
	return dir


static func _mean(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var total: float = 0.0
	for v: float in values:
		total += v
	return total / float(values.size())


static func _std(values: Array[float]) -> float:
	if values.size() < 2:
		return 0.0
	var mean: float = _mean(values)
	var total: float = 0.0
	for v: float in values:
		total += (v - mean) * (v - mean)
	return sqrt(total / float(values.size()))


static func _max(values: Array[float]) -> float:
	var best: float = 0.0
	for v: float in values:
		best = maxf(best, v)
	return best
