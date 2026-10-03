class_name RuntimePerformancePolicy
extends Node

## Small production performance policy for work that is safe to schedule at runtime.
## It deliberately keeps gameplay systems enabled: the Freeman/parallax sky still
## animates, camera collision still runs, and city detail still streams. The policy
## only reduces redundant work and island-wide residency.

const CAMERA_OPENNESS_PROBE_COUNT: int = 5
const STREAM_LOAD_MARGIN_M: float = 0.0
const STREAM_UNLOAD_HYSTERESIS_M: float = 64.0
const LOCAL_MASSING_RADIUS_CHUNKS: float = 1.55
const MASSING_RESCAN_CHUNKS: float = 0.25

var _day_night: DayNightManager
var _camera: TpsCamera
var _city: ChunkedCityMassing
var _streaming: StreamingSystem
var _player: Node3D
var _has_massing_focus: bool = false
var _last_massing_focus := Vector2.ZERO
var _ring0_roads_retired: bool = false
var _streaming_policy_applied: bool = false


func _ready() -> void:
	set_process(true)
	call_deferred(&"_refresh_bindings")


func _process(_delta: float) -> void:
	_refresh_bindings()
	_apply_sky_policy()
	_apply_camera_policy()
	_apply_streaming_policy()
	_update_local_city_massing()


func _refresh_bindings() -> void:
	if not is_instance_valid(_day_night):
		_day_night = get_parent().get_node_or_null(^"DayNightManager") as DayNightManager
	if not is_instance_valid(_camera):
		_camera = get_viewport().get_camera_3d() as TpsCamera
		if _camera != null:
			_player = _camera.player
	if not is_instance_valid(_player) and _camera != null:
		_player = _camera.player

	var scene := get_tree().current_scene
	if scene == null:
		return
	if not is_instance_valid(_city):
		_city = scene.find_child("KeyWestCity", true, false) as ChunkedCityMassing
		if _city != null:
			_has_massing_focus = false
			_ring0_roads_retired = false
			_streaming_policy_applied = false
	if not is_instance_valid(_streaming):
		_streaming = scene.find_child("StreamingSystem", true, false) as StreamingSystem


func _apply_sky_policy() -> void:
	if _day_night == null or _day_night.sky_resource == null:
		return
	## Freeman/parallax changes cloud_time every rendered frame. Godot's automatic
	## mode already chooses incremental for custom uniforms, so explicitly choosing
	## incremental would be a no-op. For a genuinely dynamic sky the documented
	## fast path is realtime filtering at a 256 px radiance cubemap. This changes
	## only IBL/reflection filtering; the visible Freeman/parallax shader is intact.
	if _day_night.sky_resource.process_mode != Sky.PROCESS_MODE_REALTIME:
		_day_night.sky_resource.process_mode = Sky.PROCESS_MODE_REALTIME
	if _day_night.sky_resource.radiance_size != Sky.RADIANCE_SIZE_256:
		_day_night.sky_resource.radiance_size = Sky.RADIANCE_SIZE_256


func _apply_camera_policy() -> void:
	if _camera == null:
		return
	## Preserve the centre sweep, feelers, overlaps, doorway framing and thin-prop
	## fade logic. Only the adaptive room fan is reduced: five rays still sample
	## left / centre / right with intermediate coverage, down from seven.
	if _camera.probe_count > CAMERA_OPENNESS_PROBE_COUNT:
		_camera.probe_count = CAMERA_OPENNESS_PROBE_COUNT


func _apply_streaming_policy() -> void:
	if _city == null or _streaming == null or _player == null or _streaming_policy_applied:
		return
	## Runtime chunk descriptors use each 512 m square's circumradius. With zero
	## extra margin, the player has one exact chunk at cell centre, two at an edge
	## and four at a corner, which is the minimum seamless boundary overlap.
	_streaming.load_margin_m = minf(_streaming.load_margin_m, STREAM_LOAD_MARGIN_M)
	_streaming.unload_hysteresis_m = minf(
		_streaming.unload_hysteresis_m,
		STREAM_UNLOAD_HYSTERESIS_M
	)
	_streaming_policy_applied = true
	## Registration may already have scanned once using the former 140 m margin.
	## Re-scan immediately so a stationary benchmark does not keep that wider set.
	_streaming.scan(_player.global_position)


func _update_local_city_massing() -> void:
	if _city == null or _player == null or not _city._stream_ring0_ready:
		return

	## The island-wide road ribbon duplicates local streamed road geometry and is
	## almost never useful as a distant silhouette. Keep only per-chunk roads.
	if not _ring0_roads_retired:
		var ring0_roads := _city._ring0_roads as Node3D
		if is_instance_valid(ring0_roads):
			ring0_roads.queue_free()
		_city._ring0_roads = null
		_ring0_roads_retired = true

	var focus := Vector2(_player.global_position.x, _player.global_position.z)
	var rescan: float = maxf(_city.chunk_size_m * MASSING_RESCAN_CHUNKS, 32.0)
	if _has_massing_focus and focus.distance_to(_last_massing_focus) < rescan:
		return
	_last_massing_focus = focus
	_has_massing_focus = true

	## Exact geometry is owned by StreamingSystem. Ring0 building proxies are kept
	## only in the current local neighbourhood (roughly a 3x3 cell ring) instead
	## of all 148 chunks. Active detail chunks keep their proxy resource long
	## enough for OccluderInstance3D generation and clean HLOD hand-off.
	var keep_radius: float = _city.chunk_size_m * LOCAL_MASSING_RADIUS_CHUNKS
	for state_variant: Variant in _city._chunks.values():
		var state := state_variant as Dictionary
		var center: Vector2 = state.get("center", Vector2.ZERO)
		var detail := state.get("detail") as Node3D
		var detail_active: bool = is_instance_valid(detail) and detail.visible
		var keep: bool = detail_active or center.distance_to(focus) <= keep_radius
		var massing := state.get("massing") as Node3D
		if keep:
			if not is_instance_valid(massing):
				_city._ensure_massing(state)
				massing = state.get("massing") as Node3D
			if is_instance_valid(massing):
				massing.visible = not detail_active
			continue
		if is_instance_valid(massing):
			massing.queue_free()
		state["massing"] = null
