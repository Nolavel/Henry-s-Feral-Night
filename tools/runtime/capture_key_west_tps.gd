extends SceneTree

## TPS streaming proof for Key West issue #138 — verification run.
## Uses the frozen Stage 5 city_preview.json snapshot unchanged.
## Real Player + TpsCamera, six city points, StreamingSystem owns ACTIVE/UNLOADED.
const HEIGHT_IMAGE: String = "res://world/terrain/key_west_preview_2m_la8.png"
const HEIGHT_META: String = "res://world/terrain/key_west_preview_2m_la8.json"
const OCEAN_MASK: String = "res://docs/runtime_previews/key_west/ocean_connected_mask.png"
const CITY_JSON: String = "res://docs/runtime_previews/key_west/city_preview.json"
const OUT_DIR: String = "res://docs/runtime_previews/key_west_tps"
const PLAYER_SCENE: String = "res://scenes/actors/player/player.tscn"
const CAMERA_SCENE: String = "res://scenes/game/systems/camera/tps_camera.tscn"

const FIRST_WARMUP_FRAMES: int = 180
const BETWEEN_SHOTS_FRAMES: int = 105

var _frame: int = 0
var _shot: int = 0
var _next_capture_frame: int = FIRST_WARMUP_FRAMES

var _terrain: IslandTerrain
var _stream_container: Node3D
var _streaming: StreamingSystem
var _city: ChunkedCityMassing
var _player: Player
var _camera: TpsCamera
var _meta: Dictionary
var _city_data: Dictionary
var _shots: Array[Dictionary] = []
var _overlay: Label
var _records: Array[Dictionary] = []


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_meta = _read_json(HEIGHT_META)
	_city_data = _read_json(CITY_JSON)
	if _meta.is_empty() or _city_data.is_empty():
		push_error("key west TPS capture: missing frozen terrain/city data")
		quit(1)
		return

	_build_stage()
	_shots = _build_shots()
	if _shots.size() != 6:
		push_error("key west TPS capture: expected 6 shots, got %d" % _shots.size())
		quit(1)
		return
	_apply_shot(0)


func _process(_delta: float) -> bool:
	_frame += 1
	if _streaming != null:
		_update_overlay()
	if _frame < _next_capture_frame:
		return false

	_capture_current()
	_shot += 1
	if _shot >= _shots.size():
		_write_report()
		print("key west TPS capture: complete")
		quit()
		return true

	_apply_shot(_shot)
	_next_capture_frame = _frame + BETWEEN_SHOTS_FRAMES
	return false


func _build_stage() -> void:
	_stream_container = Node3D.new()
	_stream_container.name = "StreamContainer"
	root.add_child(_stream_container)

	_terrain = IslandTerrain.new()
	_terrain.name = "KeyWestTerrain"
	_terrain.heightmap_image_path = HEIGHT_IMAGE
	_terrain.heightmap_meta_path = HEIGHT_META
	_terrain.min_visible_height_m = -6.0
	_terrain.collision_radius_m = -100000.0
	_terrain.builds_per_frame = 24
	root.add_child(_terrain)
	_build_masked_ice()

	var player_scene := load(PLAYER_SCENE) as PackedScene
	_player = player_scene.instantiate() as Player
	_player.name = "HenryTPSPreview"
	root.add_child(_player)
	_player.set_physics_process(false)
	_hide_player_hud()

	_city = ChunkedCityMassing.new()
	_city.name = "KeyWestCitySource"
	_stream_container.add_child(_city)
	if not _city.configure(_terrain, CITY_JSON):
		push_error("key west TPS capture: city source failed")
		quit(1)
		return

	var camera_scene := load(CAMERA_SCENE) as PackedScene
	_camera = camera_scene.instantiate() as TpsCamera
	_camera.player = _player
	_camera.far = 9000.0
	root.add_child(_camera)

	_streaming = StreamingSystem.new()
	_streaming.name = "StreamingSystem"
	_streaming.load_margin_m = 150.0
	_streaming.unload_hysteresis_m = 150.0
	_streaming.rescan_distance_m = 20.0
	_streaming.instantiation_budget_per_frame = 1
	root.add_child(_streaming)
	var registered: int = _streaming.register_runtime_source(_city)
	if registered != 148:
		push_warning("key west TPS capture: expected 148 runtime chunks, got %d" % registered)
	_streaming.initialize_runtime_only(_stream_container, _player)

	_build_environment()
	_add_overlay()


func _hide_player_hud() -> void:
	for node_name: StringName in [&"MouseCursorUI", &"VitalHUD"]:
		var node := _player.get_node_or_null(NodePath(String(node_name)))
		if node != null:
			node.queue_free()


func _build_environment() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-47.0, -34.0, 0.0)
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 2600.0
	root.add_child(sun)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.59, 0.63, 0.67)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.80, 0.83, 0.87)
	env.ambient_light_energy = 0.72
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	root.add_child(world_env)
	_snowify_terrain()


func _build_masked_ice() -> void:
	var mask_image: Image = Image.load_from_file(OCEAN_MASK)
	if mask_image == null or mask_image.is_empty():
		push_error("key west TPS capture: missing ocean mask")
		return
	var mask_texture := ImageTexture.create_from_image(mask_image)
	var width_m: float = float(_meta["width"] - 1) * float(_meta["m_per_px"])
	var depth_m: float = float(_meta["height"] - 1) * float(_meta["m_per_px"])
	var centre := Vector3(
		float(_meta["origin_x"]) + width_m * 0.5,
		-0.04,
		float(_meta["origin_z"]) + depth_m * 0.5
	)

	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;
uniform sampler2D ocean_mask : filter_nearest, repeat_disable;
uniform vec2 world_origin;
uniform vec2 world_size;
varying vec3 world_pos;
void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec2 uv = (world_pos.xz - world_origin) / world_size;
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) discard;
	if (texture(ocean_mask, uv).r < 0.5) discard;
	ALBEDO = vec3(0.49, 0.56, 0.63);
	ROUGHNESS = 0.38;
	METALLIC = 0.05;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("ocean_mask", mask_texture)
	material.set_shader_parameter(
		"world_origin",
		Vector2(float(_meta["origin_x"]), float(_meta["origin_z"]))
	)
	material.set_shader_parameter("world_size", Vector2(width_m, depth_m))

	var ice := MeshInstance3D.new()
	ice.name = "FrozenSea"
	var plane := PlaneMesh.new()
	plane.size = Vector2(width_m, depth_m)
	plane.material = material
	ice.mesh = plane
	ice.position = centre
	root.add_child(ice)


func _build_shots() -> Array[Dictionary]:
	var shots: Array[Dictionary] = []
	shots.append(_road_shot(
		"01_duval_old_town", "Duval Street / Old Town",
		"Duval Street", Vector2(-3400.0, 900.0), -8.0, false
	))
	shots.append(_road_shot(
		"02_front_waterfront", "Front Street / waterfront",
		"Front Street", Vector2(-3710.0, 780.0), -9.0, true
	))
	shots.append(_road_shot(
		"03_truman_midtown", "Truman Avenue",
		"Truman Avenue", Vector2(-2550.0, 1260.0), -8.0, false
	))
	shots.append(_road_shot(
		"04_north_roosevelt", "North Roosevelt Boulevard",
		"North Roosevelt Boulevard", Vector2(-450.0, 80.0), -8.0, true
	))

	var airport_values: Array = (_city_data.get("airport", {}) as Dictionary).get("center", [])
	var airport_focus := Vector2(
		float(airport_values[0]) if airport_values.size() > 0 else 1215.0,
		float(airport_values[1]) if airport_values.size() > 1 else 992.0
	)
	var airport_shot := _road_shot(
		"05_eyw_airport", "EYW / South Roosevelt",
		"South Roosevelt Boulevard", airport_focus, -7.0, false
	)
	var airport_position: Vector2 = airport_shot["position"]
	var toward_airport: Vector2 = (airport_focus - airport_position).normalized()
	if toward_airport.length_squared() > 0.1:
		airport_shot["yaw"] = _yaw_for_direction(toward_airport)
	shots.append(airport_shot)

	shots.append(_road_shot(
		"06_stock_island", "Stock Island / MacDonald Avenue",
		"MacDonald Avenue", Vector2(2780.0, -840.0), -8.0, false
	))
	return shots


func _road_shot(
	file_name: String,
	label: String,
	road_name: String,
	preferred: Vector2,
	pitch_deg: float,
	reverse: bool
) -> Dictionary:
	var best_distance: float = INF
	var best_position: Vector2 = preferred
	var best_direction := Vector2(0.0, -1.0)

	for road_variant: Variant in (_city_data.get("roads", []) as Array):
		var road := road_variant as Dictionary
		if String(road.get("name", "")) != road_name:
			continue
		var points: Array = road.get("points", [])
		for i: int in range(points.size() - 1):
			var a_values := points[i] as Array
			var b_values := points[i + 1] as Array
			var a := Vector2(float(a_values[0]), float(a_values[1]))
			var b := Vector2(float(b_values[0]), float(b_values[1]))
			var midpoint := (a + b) * 0.5
			var distance: float = midpoint.distance_to(preferred)
			if distance >= best_distance:
				continue
			var direction := (b - a).normalized()
			if reverse:
				direction = -direction
			best_distance = distance
			best_position = midpoint
			best_direction = direction

	return {
		"file": file_name,
		"label": label,
		"road": road_name,
		"position": best_position,
		"yaw": _yaw_for_direction(best_direction),
		"pitch": pitch_deg,
	}


func _yaw_for_direction(direction: Vector2) -> float:
	return atan2(-direction.x, -direction.y)


func _apply_shot(index: int) -> void:
	var shot: Dictionary = _shots[index]
	var position: Vector2 = shot["position"]
	var ground: float = maxf(_terrain.get_height(position.x, position.y), 0.0)
	var yaw: float = float(shot["yaw"])

	_player.global_position = Vector3(position.x, ground + 1.0, position.y)
	_player.global_rotation.y = yaw
	_player.velocity = Vector3.ZERO
	_camera.set_look(yaw, float(shot["pitch"]))
	_streaming.scan(_player.global_position)
	_terrain.update_now()
	print(
		"key west TPS move: %s position=%s active_before=%d" %
		[shot["label"], _player.global_position, _streaming.get_active_chunks().size()]
	)


func _add_overlay() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 100
	_overlay = Label.new()
	_overlay.position = Vector2(18.0, 18.0)
	_overlay.add_theme_font_size_override("font_size", 17)
	_overlay.add_theme_color_override("font_color", Color(0.96, 0.97, 0.98))
	_overlay.add_theme_color_override("font_shadow_color", Color(0.02, 0.02, 0.03, 0.9))
	_overlay.add_theme_constant_override("shadow_offset_x", 2)
	_overlay.add_theme_constant_override("shadow_offset_y", 2)
	canvas.add_child(_overlay)

	var attribution := Label.new()
	attribution.text = "TPS: project TpsCamera  •  NOAA terrain  •  © OpenStreetMap contributors — ODbL"
	attribution.position = Vector2(18.0, 968.0)
	attribution.add_theme_font_size_override("font_size", 13)
	attribution.modulate = Color(0.95, 0.95, 0.95, 0.86)
	canvas.add_child(attribution)
	root.add_child(canvas)


func _update_overlay() -> void:
	if _shots.is_empty() or _shot >= _shots.size():
		return
	var shot: Dictionary = _shots[_shot]
	var active: int = _streaming.get_active_chunks().size()
	_overlay.text = (
		"%s\n"
		+ "%s\n"
		+ "StreamingSystem: ACTIVE %d / runtime %d  •  exact detail %d"
	) % [
		shot["label"],
		shot["road"],
		active,
		_streaming.get_runtime_chunk_count(),
		_city.get_stream_active_detail_count(),
	]


func _capture_current() -> void:
	var shot: Dictionary = _shots[_shot]
	var active_ids: Array[String] = []
	for id: StringName in _streaming.get_active_chunks():
		active_ids.append(String(id))
	active_ids.sort()

	var path: String = "%s/%s.png" % [OUT_DIR, shot["file"]]
	var error: Error = root.get_viewport().get_texture().get_image().save_png(path)
	if error != OK:
		push_error("key west TPS capture: cannot save %s (%d)" % [path, error])
		return
	_records.append({
		"shot": shot["file"],
		"label": shot["label"],
		"road": shot["road"],
		"player_position": [
			snappedf(_player.global_position.x, 0.01),
			snappedf(_player.global_position.y, 0.01),
			snappedf(_player.global_position.z, 0.01),
		],
		"active_count": active_ids.size(),
		"active_chunks": active_ids,
	})
	print(
		"key west TPS capture: %s active=%d" %
		[path, active_ids.size()]
	)


func _write_report() -> void:
	var report := {
		"source_city_snapshot": "Stage 5 run 36524001180 (unchanged)",
		"streaming_owner": "StreamingSystem",
		"runtime_chunks": _streaming.get_runtime_chunk_count(),
		"shots": _records,
	}
	var path: String = "%s/stream_report.json" % OUT_DIR
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))


func _snowify_terrain() -> void:
	var snow := StandardMaterial3D.new()
	snow.albedo_color = Color(0.79, 0.82, 0.85, 1.0)
	snow.roughness = 0.93
	for child: Node in _terrain.get_children():
		var mesh := child as MeshInstance3D
		if mesh != null:
			mesh.material_override = snow


func _read_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed as Dictionary if typeof(parsed) == TYPE_DICTIONARY else {}
