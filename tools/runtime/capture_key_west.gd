extends SceneTree

## Godot-first geographic/city proof for issue #138.
## NOAA terrain + ocean-connected ice mask + OSM road/building massing. Stage 4 run.
## No Blender edits, no First Exit move, no production city assets.
const HEIGHT_IMAGE: String = "res://world/terrain/key_west_preview_2m_la8.png"
const HEIGHT_META: String = "res://world/terrain/key_west_preview_2m_la8.json"
const OCEAN_MASK: String = "res://docs/runtime_previews/key_west/ocean_connected_mask.png"
const CITY_JSON: String = "res://docs/runtime_previews/key_west/city_preview.json"
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
var _city_built: bool = false


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var parsed_meta: Variant = JSON.parse_string(FileAccess.get_file_as_string(HEIGHT_META))
	if typeof(parsed_meta) != TYPE_DICTIONARY:
		push_error("key west capture: missing metadata")
		quit(1)
		return
	_meta = parsed_meta as Dictionary
	_span_x = float(_meta["width"] - 1) * float(_meta["m_per_px"])
	_span_z = float(_meta["height"] - 1) * float(_meta["m_per_px"])
	_centre = Vector3(
		float(_meta["origin_x"]) + _span_x * 0.5,
		0.0,
		float(_meta["origin_z"]) + _span_z * 0.5
	)
	_build_stage()
	_add_attribution()


func _process(_delta: float) -> bool:
	_frame += 1
	if not _city_built and _frame >= 3:
		_build_city_preview()
		_city_built = true
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

	_build_masked_ice()

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


func _build_masked_ice() -> void:
	var mask_image: Image = Image.load_from_file(OCEAN_MASK)
	if mask_image == null or mask_image.is_empty():
		push_error("key west capture: missing ocean mask")
		return
	var mask_texture := ImageTexture.create_from_image(mask_image)

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
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		discard;
	}
	float ocean = texture(ocean_mask, uv).r;
	if (ocean < 0.5) {
		discard;
	}
	ALBEDO = vec3(0.52, 0.59, 0.66);
	ROUGHNESS = 0.34;
	METALLIC = 0.06;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("ocean_mask", mask_texture)
	material.set_shader_parameter(
		"world_origin",
		Vector2(float(_meta["origin_x"]), float(_meta["origin_z"]))
	)
	material.set_shader_parameter("world_size", Vector2(_span_x, _span_z))

	var ice := MeshInstance3D.new()
	ice.name = "FrozenSea"
	var plane := PlaneMesh.new()
	plane.size = Vector2(_span_x, _span_z)
	plane.material = material
	ice.mesh = plane
	# Below sea level rather than above it: the ice must never create fake ponds.
	ice.position = _centre + Vector3(0.0, -0.04, 0.0)
	root.add_child(ice)


func _build_city_preview() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CITY_JSON))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("key west capture: missing city preview data")
		return
	var city := parsed as Dictionary
	var buildings: Array = city.get("buildings", [])
	var roads: Array = city.get("roads", [])
	_build_building_multimesh(buildings)
	_build_road_mesh(roads)
	_snowify_terrain()
	print(
		"key west city: buildings=%d roads=%d" %
		[buildings.size(), roads.size()]
	)


func _build_building_multimesh(buildings: Array) -> void:
	if buildings.is_empty():
		return
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.70, 0.72, 0.73)
	material.roughness = 0.88
	box.material = material

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.instance_count = buildings.size()

	for i: int in range(buildings.size()):
		var building: Dictionary = buildings[i]
		var x: float = float(building["x"])
		var z: float = float(building["z"])
		var width: float = maxf(float(building["width"]), 2.5)
		var depth: float = maxf(float(building["depth"]), 2.5)
		var building_height: float = maxf(float(building["height"]), 3.0)
		var angle: float = float(building["angle"])
		var ground: float = _terrain.get_height(x, z)
		var basis := Basis(Vector3.UP, angle).scaled(
			Vector3(width, building_height, depth)
		)
		var transform := Transform3D(
			basis,
			Vector3(x, ground + building_height * 0.5 + 0.05, z)
		)
		multimesh.set_instance_transform(i, transform)

	var instance := MultiMeshInstance3D.new()
	instance.name = "OSMBuildingMassing"
	instance.multimesh = multimesh
	root.add_child(instance)


func _build_road_mesh(roads: Array) -> void:
	if roads.is_empty():
		return
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()

	for road_variant: Variant in roads:
		var road := road_variant as Dictionary
		var points: Array = road.get("points", [])
		var half_width: float = maxf(float(road.get("width", 4.0)) * 0.5, 1.0)
		for i: int in range(points.size() - 1):
			var a_values: Array = points[i]
			var b_values: Array = points[i + 1]
			var a := Vector2(float(a_values[0]), float(a_values[1]))
			var b := Vector2(float(b_values[0]), float(b_values[1]))
			var delta := b - a
			if delta.length_squared() < 0.25:
				continue
			var direction := delta.normalized()
			var side := Vector2(-direction.y, direction.x) * half_width
			var ay: float = maxf(_terrain.get_height(a.x, a.y), 0.02) + 0.10
			var by: float = maxf(_terrain.get_height(b.x, b.y), 0.02) + 0.10
			var base: int = vertices.size()
			vertices.append(Vector3(a.x + side.x, ay, a.y + side.y))
			vertices.append(Vector3(a.x - side.x, ay, a.y - side.y))
			vertices.append(Vector3(b.x + side.x, by, b.y + side.y))
			vertices.append(Vector3(b.x - side.x, by, b.y - side.y))
			for _j: int in range(4):
				normals.append(Vector3.UP)
			indices.append_array([
				base, base + 2, base + 1,
				base + 1, base + 2, base + 3,
			])

	if vertices.is_empty():
		return
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.24, 0.25, 0.26)
	material.roughness = 0.96
	mesh.surface_set_material(0, material)

	var roads_instance := MeshInstance3D.new()
	roads_instance.name = "OSMRoadMassing"
	roads_instance.mesh = mesh
	root.add_child(roads_instance)


func _add_attribution() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 100
	var label := Label.new()
	label.text = "NOAA terrain  •  Map data © OpenStreetMap contributors — ODbL"
	label.position = Vector2(16.0, 970.0)
	label.add_theme_font_size_override("font_size", 13)
	label.modulate = Color(0.95, 0.95, 0.95, 0.88)
	canvas.add_child(label)
	root.add_child(canvas)


func _apply_shot(index: int) -> void:
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
