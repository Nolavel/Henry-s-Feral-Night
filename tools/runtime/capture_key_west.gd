extends SceneTree

## Godot-first geographic proof for issue #138.
## NOAA-derived terrain only: no Blender edits, no First Exit, no city content.
## Output: docs/runtime_previews/key_west/*.png.\n## CI marker run: NOAA terrain + ice proof. Raw-height loader verified after parser fix.
const HEIGHT_IMAGE: String = "res://world/terrain/key_west_preview_2m_la8.png"
const HEIGHT_META: String = "res://world/terrain/key_west_preview_2m_la8.json"
const OUT_DIR: String = "res://docs/runtime_previews/key_west"
const WARMUP_FRAMES: int = 90
const BETWEEN_SHOTS_FRAMES: int = 30

var _frame: int = 0
var _shot: int = -1
var _next_capture_frame: int = WARMUP_FRAMES
var _camera: Camera3D
var _terrain: IslandTerrain
var _meta: Dictionary
var _centre: Vector3
var _span_x: float = 1.0
var _span_z: float = 1.0


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_meta = JSON.parse_string(FileAccess.get_file_as_string(HEIGHT_META))
	if _meta.is_empty():
		push_error("key west capture: missing metadata")
		quit(1)
		return
	_span_x = float(_meta["width"] - 1) * float(_meta["m_per_px"])
	_span_z = float(_meta["height"] - 1) * float(_meta["m_per_px"])
	_centre = Vector3(
		float(_meta["origin_x"]) + _span_x * 0.5,
		0.0,
		float(_meta["origin_z"]) + _span_z * 0.5
	)
	_build_stage()


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < WARMUP_FRAMES:
		return false
	if _frame < _next_capture_frame:
		return false
	if _shot >= 0:
		_capture()
	_shot += 1
	if _shot >= 4:
		print("key west capture: complete")
		quit()
		return true
	_apply_shot(_shot)
	_next_capture_frame = _frame + BETWEEN_SHOTS_FRAMES
	return false


func _build_stage() -> void:
	_camera = Camera3D.new()
	_camera.name = "PreviewCamera"
	_camera.far = 30000.0
	_camera.near = 0.5
	root.add_child(_camera)
	_camera.make_current()

	_terrain = IslandTerrain.new()
	_terrain.name = "KeyWestTerrain"
	_terrain.heightmap_image_path = HEIGHT_IMAGE
	_terrain.heightmap_meta_path = HEIGHT_META
	_terrain.min_visible_height_m = -6.0
	_terrain.collision_radius_m = -100000.0
	_terrain.builds_per_frame = 16
	root.add_child(_terrain)

	var ice := MeshInstance3D.new()
	ice.name = "FrozenSea"
	var plane := PlaneMesh.new()
	plane.size = Vector2(_span_x * 1.25, _span_z * 1.45)
	var ice_material := StandardMaterial3D.new()
	ice_material.albedo_color = Color(0.55, 0.62, 0.68, 1.0)
	ice_material.roughness = 0.32
	ice_material.metallic = 0.08
	plane.material = ice_material
	ice.mesh = plane
	ice.position = _centre + Vector3(0.0, 0.035, 0.0)
	root.add_child(ice)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, -32.0, 0.0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 12000.0
	root.add_child(sun)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.66, 0.69, 0.72)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.82, 0.84, 0.88)
	env.ambient_light_energy = 0.75
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	root.add_child(world_env)


func _apply_shot(index: int) -> void:
	_snowify_terrain()
	match index:
		0:
			_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
			_camera.size = maxf(_span_z * 1.08, _span_x / 1.55 * 1.08)
			_camera.look_at_from_position(
				_centre + Vector3(0.0, 9000.0, 0.0),
				_centre,
				Vector3(0.0, 0.0, -1.0)
			)
		1:
			_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
			_camera.size = 4300.0
			var key_west := _centre + Vector3(-1150.0, 0.0, 900.0)
			_camera.look_at_from_position(
				key_west + Vector3(0.0, 6500.0, 0.0),
				key_west,
				Vector3(0.0, 0.0, -1.0)
			)
		2:
			_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
			_camera.fov = 55.0
			_camera.look_at_from_position(
				_centre + Vector3(300.0, 3900.0, 6100.0),
				_centre + Vector3(-900.0, 0.0, 250.0)
			)
		3:
			_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
			_camera.fov = 48.0
			var coast := _centre + Vector3(-2300.0, 0.0, 1600.0)
			_camera.look_at_from_position(
				coast + Vector3(-350.0, 70.0, 520.0),
				coast + Vector3(500.0, 1.0, -250.0)
			)
	if _terrain != null:
		_terrain.update_now()


func _snowify_terrain() -> void:
	if _terrain == null:
		return
	var snow := StandardMaterial3D.new()
	snow.albedo_color = Color(0.78, 0.81, 0.84, 1.0)
	snow.roughness = 0.92
	for child: Node in _terrain.get_children():
		var mesh := child as MeshInstance3D
		if mesh != null:
			mesh.material_override = snow


func _capture() -> void:
	var names: Array[String] = [
		"01_cluster_top",
		"02_key_west_top",
		"03_cluster_oblique",
		"04_coast_scale",
	]
	var path: String = "%s/%s.png" % [OUT_DIR, names[_shot]]
	var error: Error = root.get_viewport().get_texture().get_image().save_png(path)
	if error != OK:
		push_error("key west capture: cannot save %s (%d)" % [path, error])
	else:
		print("key west capture: ", path)
