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
const CITY_DIAGNOSTIC_INTERVAL_USEC: int = 1_000_000

var _day_night: DayNightManager
var _camera: TpsCamera
var _city: ChunkedCityMassing
var _streaming: StreamingSystem
var _player: Node3D
var _has_massing_focus: bool = false
var _last_massing_focus := Vector2.ZERO
var _ring0_roads_retired: bool = false
var _streaming_policy_applied: bool = false
var _exact_city_owner: StringName = &""
var _last_city_diag_usec: int = 0


func _ready() -> void:
	## StreamingSystem uses the default priority. Run this policy afterwards so
	## broad radius scans can be narrowed to one exact city owner before render.
	process_priority = 100
	set_process(true)
	call_deferred(&"_refresh_bindings")


func _process(_delta: float) -> void:
	_refresh_bindings()
	_apply_sky_policy()
	_apply_camera_policy()
	_apply_streaming_policy()
	_enforce_exact_city_residency()
	_update_local_city_massing()
	_print_city_stream_diagnostics()


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
			_exact_city_owner = &""
			_last_city_diag_usec = 0
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
	## Keep the generic StreamingSystem conservative. Its circular runtime bands
	## can overlap at a 512 m grid corner, so _enforce_exact_city_residency() below
	## performs the Hoarbound-specific square ownership hand-off afterwards.
	_streaming.load_margin_m = minf(_streaming.load_margin_m, STREAM_LOAD_MARGIN_M)
	_streaming.unload_hysteresis_m = minf(
		_streaming.unload_hysteresis_m,
		STREAM_UNLOAD_HYSTERESIS_M
	)
	_streaming_policy_applied = true
	## Registration may already have scanned once using the former 140 m margin.
	## Re-scan immediately, then exact ownership removes the overlapping neighbours.
	_streaming.scan(_player.global_position)


## Exact Key West detail ownership. A chunk owns the half-open square described
## by its authored origin and chunk_size_m. During a boundary crossing the old
## ACTIVE owner stays alive until the new owner becomes ACTIVE, then every sibling
## is released. That gives one steady-state detail chunk without a one-frame hole.
func _enforce_exact_city_residency() -> void:
	if _city == null or _streaming == null or _player == null:
		return
	_city._index_stream_chunks()
	if _city._stream_to_chunk.is_empty():
		return

	var focus := Vector2(_player.global_position.x, _player.global_position.z)
	var owner: StringName = _owned_city_stream_id(focus)
	if owner == &"":
		_exact_city_owner = &""
		for stream_id_variant: Variant in _city._stream_to_chunk:
			var stream_id := stream_id_variant as StringName
			if _streaming.get_state(stream_id) != StreamingSystem.CellState.UNLOADED:
				_streaming._release(stream_id)
		return

	_exact_city_owner = owner
	var owner_state: StreamingSystem.CellState = _streaming.get_state(owner)
	if owner_state == StreamingSystem.CellState.UNLOADED:
		_streaming._request(owner)
		owner_state = _streaming.get_state(owner)
	var owner_active: bool = owner_state == StreamingSystem.CellState.ACTIVE

	for stream_id_variant: Variant in _city._stream_to_chunk:
		var stream_id := stream_id_variant as StringName
		if stream_id == owner:
			continue
		var state: StreamingSystem.CellState = _streaming.get_state(stream_id)
		if state == StreamingSystem.CellState.UNLOADED:
			continue
		## Pending neighbours produced by the generic radius scan are always safe
		## to cancel. Keep an old ACTIVE owner only while the new one is not live.
		if state == StreamingSystem.CellState.ACTIVE and not owner_active:
			continue
		_streaming._release(stream_id)


func _owned_city_stream_id(focus: Vector2) -> StringName:
	for stream_id_variant: Variant in _city._stream_to_chunk:
		var stream_id := stream_id_variant as StringName
		var cid: String = String(_city._stream_to_chunk.get(stream_id, ""))
		if cid.is_empty() or not _city._chunks.has(cid):
			continue
		var state := _city._chunks[cid] as Dictionary
		var chunk := state.get("data", {}) as Dictionary
		var origin_values: Array = chunk.get("origin", [])
		if origin_values.size() < 2:
			continue
		var origin := Vector2(float(origin_values[0]), float(origin_values[1]))
		var local: Vector2 = focus - origin
		if local.x >= 0.0 and local.y >= 0.0 \
				and local.x < _city.chunk_size_m and local.y < _city.chunk_size_m:
			return stream_id
	return &""


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


## Console-only diagnostics for the next Fort Street pass. This intentionally
## runs at 1 Hz and does not touch the visible StatsDisplay panel.
func _print_city_stream_diagnostics() -> void:
	if _city == null:
		return
	var now_usec: int = Time.get_ticks_usec()
	if _last_city_diag_usec > 0 and now_usec - _last_city_diag_usec < CITY_DIAGNOSTIC_INTERVAL_USEC:
		return
	_last_city_diag_usec = now_usec

	var roots: Dictionary = {}
	for state_variant: Variant in _city._chunks.values():
		var state := state_variant as Dictionary
		_register_category_root(roots, state.get("detail"), "detail_buildings")
		_register_category_root(roots, state.get("massing"), "massing")
		_register_category_root(roots, state.get("roads"), "roads")
		_register_category_root(roots, state.get("prop_visuals"), "props")
		_register_category_root(roots, state.get("props"), "props")
	if is_instance_valid(_city._global_visuals):
		var global_props := (_city._global_visuals as Node).find_child("StreetProps", true, false)
		_register_category_root(roots, global_props, "props")

	var counts := {
		"detail_buildings": 0,
		"massing": 0,
		"roads": 0,
		"props": 0,
		"other": 0,
	}
	_collect_multimesh_instances(_city, "other", roots, counts)
	var total: int = 0
	for value: Variant in counts.values():
		total += int(value)

	print("[CityMultiMeshJSON] %s" % JSON.stringify({
		"schema": "hoarbound_city_multimesh_v1",
		"ticks_msec": Time.get_ticks_msec(),
		"exact_owner": String(_exact_city_owner),
		"active_city_chunks": _city.get_stream_active_detail_count(),
		"detail_buildings": int(counts["detail_buildings"]),
		"massing": int(counts["massing"]),
		"roads": int(counts["roads"]),
		"props": int(counts["props"]),
		"other": int(counts["other"]),
		"visible_multimesh_instances": total,
	}))


func _register_category_root(roots: Dictionary, node_variant: Variant, category: String) -> void:
	if node_variant == null or not is_instance_valid(node_variant):
		return
	var node := node_variant as Node
	roots[node.get_instance_id()] = category


func _collect_multimesh_instances(
	node: Node,
	inherited_category: String,
	roots: Dictionary,
	counts: Dictionary
) -> void:
	var category: String = inherited_category
	if roots.has(node.get_instance_id()):
		category = String(roots[node.get_instance_id()])
	if node is MultiMeshInstance3D:
		var instance := node as MultiMeshInstance3D
		if instance.is_visible_in_tree() and instance.multimesh != null:
			var visible_count: int = instance.multimesh.visible_instance_count
			if visible_count < 0:
				visible_count = instance.multimesh.instance_count
			counts[category] = int(counts.get(category, 0)) + maxi(visible_count, 0)
	for child: Node in node.get_children():
		_collect_multimesh_instances(child, category, roots, counts)
