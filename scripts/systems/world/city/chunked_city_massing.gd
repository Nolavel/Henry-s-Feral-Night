class_name ChunkedCityMassing
extends Node3D

## Experimental chunk-aware Key West city renderer for issue #138.
## It is deliberately isolated from the production streaming path.
##
## Ring 0: per-chunk oriented building proxies.
## Near detail: exact OSM footprint extrusion, built lazily per chunk.
## Roads: per-chunk ribbon batches.
## Airport: explicit runway/taxiway/apron layer.
## Metadata stays in the dataset and can be surfaced as debug labels.

var terrain: IslandTerrain
var data: Dictionary = {}
var chunk_size_m: float = 512.0
var detail_radius_m: float = 1150.0
var massing_radius_m: float = 3600.0

var _chunks: Dictionary = {}
var _buildings: Array = []
var _roads: Array = []
var _airport_features: Array = []
var _airport_node: Node3D
var _labels_node: Node3D
var _grid_node: Node3D
var _global_visuals: Node3D
var _ring0_roads: Node3D
var _enrichment: Dictionary = {}
var _visual_materials: Dictionary = {}
var _stream_to_chunk: Dictionary = {}
var _stream_active: Dictionary = {}
var _stream_ring0_ready: bool = false

var _massing_material: StandardMaterial3D
var _detail_material: StandardMaterial3D
var _road_material: StandardMaterial3D
var _runway_material: StandardMaterial3D
var _taxiway_material: StandardMaterial3D
var _apron_material: StandardMaterial3D


func configure(terrain_node: IslandTerrain, data_path: String, enrichment_path: String = "") -> bool:
	terrain = terrain_node
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(data_path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("ChunkedCityMassing: invalid dataset %s" % data_path)
		return false
	data = parsed as Dictionary
	chunk_size_m = float(data.get("chunk_size_m", 512.0))
	var rings: Dictionary = data.get("rings", {})
	detail_radius_m = float(rings.get("detail_radius_m", 1150.0))
	massing_radius_m = float(rings.get("massing_radius_m", 3600.0))
	_buildings = data.get("buildings", [])
	_roads = data.get("roads", [])
	_airport_features = data.get("airport_features", [])
	if not enrichment_path.is_empty() and FileAccess.file_exists(enrichment_path):
		var parsed_enrichment: Variant = JSON.parse_string(FileAccess.get_file_as_string(enrichment_path))
		if typeof(parsed_enrichment) == TYPE_DICTIONARY:
			_enrichment = parsed_enrichment as Dictionary
	_visual_materials = KeyWestCityVisuals.make_materials()
	_make_materials()
	_create_chunk_states()
	_build_airport_layer()
	_build_global_visuals()
	return true


## Runtime-source API consumed by StreamingSystem. The JSON snapshot stays
## untouched; only exact chunk geometry is created/destroyed around the focus.
func get_stream_chunks() -> Array:
	_index_stream_chunks()
	var descriptors: Array = []
	var radius: float = chunk_size_m * 0.70710678
	for stream_id_variant: Variant in _stream_to_chunk:
		var stream_id := stream_id_variant as StringName
		var cid: String = String(_stream_to_chunk[stream_id])
		var state: Dictionary = _chunks[cid]
		var center: Vector2 = state["center"]
		descriptors.append({
			"id": stream_id,
			"position": Vector3(center.x, 0.0, center.y),
			"radius": radius,
		})
	return descriptors


func build_stream_ring0(_container: Node3D) -> void:
	if _stream_ring0_ready:
		return
	_index_stream_chunks()
	if _ring0_roads == null:
		_ring0_roads = KeyWestCityVisuals.build_ring0_road_surface(
			_roads, terrain, _enrichment, _visual_materials
		)
		if _ring0_roads != null and _ring0_roads.get_child_count() > 0:
			add_child(_ring0_roads)
		elif _ring0_roads != null:
			_ring0_roads.free()
			_ring0_roads = null
	for state_variant: Variant in _chunks.values():
		var state := state_variant as Dictionary
		_ensure_massing(state)
		var massing := state["massing"] as Node3D
		if massing != null:
			massing.visible = true
		var detail := state["detail"] as Node3D
		if detail != null:
			detail.visible = false
		var roads := state["roads"] as Node3D
		if roads != null:
			roads.visible = false
	_stream_ring0_ready = true


func activate_stream_chunk(stream_id: StringName, _container: Node3D) -> Node3D:
	_index_stream_chunks()
	var cid: String = String(_stream_to_chunk.get(stream_id, ""))
	if cid.is_empty() or not _chunks.has(cid):
		return null
	var state := _chunks[cid] as Dictionary
	_ensure_massing(state)
	_ensure_detail(state)
	_ensure_roads(state)
	var massing := state["massing"] as Node3D
	if massing != null:
		massing.visible = false
	var detail := state["detail"] as Node3D
	if detail != null:
		detail.visible = true
	var roads := state["roads"] as Node3D
	if roads != null:
		roads.visible = true
	_stream_active[stream_id] = true
	return state["node"] as Node3D


func deactivate_stream_chunk(stream_id: StringName) -> void:
	var cid: String = String(_stream_to_chunk.get(stream_id, ""))
	if cid.is_empty() or not _chunks.has(cid):
		return
	var state := _chunks[cid] as Dictionary
	var detail := state["detail"] as Node3D
	if is_instance_valid(detail):
		detail.queue_free()
	state["detail"] = null
	var roads := state["roads"] as Node3D
	if is_instance_valid(roads):
		roads.queue_free()
	state["roads"] = null
	var massing := state["massing"] as Node3D
	if massing != null:
		massing.visible = true
	_stream_active.erase(stream_id)


func get_stream_active_detail_count() -> int:
	return _stream_active.size()


func _index_stream_chunks() -> void:
	if not _stream_to_chunk.is_empty():
		return
	for cid_variant: Variant in _chunks:
		var cid: String = String(cid_variant)
		var stream_id := StringName("kw_city_%s" % cid.replace(":", "_"))
		_stream_to_chunk[stream_id] = cid


func get_stats() -> Dictionary:
	return data.get("stats", {})


func get_airport_center() -> Vector2:
	var airport: Dictionary = data.get("airport", {})
	var center: Variant = airport.get("center")
	if center is Array and center.size() >= 2:
		return Vector2(float(center[0]), float(center[1]))
	return Vector2.ZERO


func get_airport_metadata() -> Dictionary:
	var airport: Dictionary = data.get("airport", {})
	return airport.get("metadata", {})


func get_densest_chunk_center() -> Vector2:
	var best_count: int = -1
	var best := Vector2.ZERO
	var chunks: Dictionary = data.get("chunks", {})
	for chunk_variant: Variant in chunks.values():
		var chunk := chunk_variant as Dictionary
		var count: int = (chunk.get("building_ids", []) as Array).size()
		if count <= best_count:
			continue
		best_count = count
		var origin_values: Array = chunk.get("origin", [])
		if origin_values.size() < 2:
			continue
		best = Vector2(
			float(origin_values[0]) + chunk_size_m * 0.5,
			float(origin_values[1]) + chunk_size_m * 0.5
		)
	return best


func set_focus(point: Vector2, show_all_massing: bool = false) -> void:
	for state_variant: Variant in _chunks.values():
		var state := state_variant as Dictionary
		var center: Vector2 = state["center"]
		var distance: float = center.distance_to(point)
		var detailed: bool = distance <= detail_radius_m
		var massing: bool = show_all_massing or distance <= massing_radius_m

		if detailed:
			_ensure_detail(state)
			_ensure_roads(state)
			var detail_node: Node3D = state["detail"]
			if detail_node != null:
				detail_node.visible = true
			var mass_node: Node3D = state["massing"]
			if mass_node != null:
				mass_node.visible = false
			var road_node: Node3D = state["roads"]
			if road_node != null:
				road_node.visible = true
		else:
			_ensure_massing(state)
			if massing:
				_ensure_roads(state)
			var detail_node: Node3D = state["detail"]
			if detail_node != null:
				detail_node.visible = false
			var mass_node: Node3D = state["massing"]
			if mass_node != null:
				mass_node.visible = massing
			var road_node: Node3D = state["roads"]
			if road_node != null:
				road_node.visible = massing


func set_chunk_grid_visible(enabled: bool) -> void:
	if enabled and _grid_node == null:
		_grid_node = _build_chunk_grid()
	if _grid_node != null:
		_grid_node.visible = enabled


func show_metadata_labels(point: Vector2, radius_m: float = 500.0) -> void:
	clear_metadata_labels()
	_labels_node = Node3D.new()
	_labels_node.name = "MetadataLabels"
	add_child(_labels_node)

	var candidates: Array = []
	for building_variant: Variant in _buildings:
		var building := building_variant as Dictionary
		var proxy: Dictionary = building.get("proxy", {})
		var position := Vector2(float(proxy.get("x", 0.0)), float(proxy.get("z", 0.0)))
		var distance: float = position.distance_to(point)
		if distance > radius_m:
			continue
		var metadata: Dictionary = building.get("metadata", {})
		var label_text: String = _building_label(metadata)
		if label_text.is_empty():
			continue
		candidates.append([distance, position, label_text])
	candidates.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))

	var placed: int = 0
	for candidate_variant: Variant in candidates:
		if placed >= 10:
			break
		var candidate := candidate_variant as Array
		var p: Vector2 = candidate[1]
		_add_label(String(candidate[2]), p, 13.0)
		placed += 1

	var road_candidates: Array = []
	for road_variant: Variant in _roads:
		var road := road_variant as Dictionary
		var name: String = String(road.get("name", ""))
		if name.is_empty():
			continue
		var points: Array = road.get("points", [])
		if points.size() < 2:
			continue
		var middle: Array = points[points.size() / 2]
		var p := Vector2(float(middle[0]), float(middle[1]))
		var distance: float = p.distance_to(point)
		if distance <= radius_m:
			road_candidates.append([distance, p, name])
	road_candidates.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	placed = 0
	for candidate_variant: Variant in road_candidates:
		if placed >= 12:
			break
		var candidate := candidate_variant as Array
		_add_label(String(candidate[2]), candidate[1], 7.0)
		placed += 1


func clear_metadata_labels() -> void:
	if _labels_node != null and is_instance_valid(_labels_node):
		_labels_node.queue_free()
	_labels_node = null


func _building_label(metadata: Dictionary) -> String:
	var name: String = String(metadata.get("name", ""))
	if not name.is_empty():
		return name
	var number: String = String(metadata.get("addr:housenumber", ""))
	var street: String = String(metadata.get("addr:street", ""))
	if not number.is_empty() and not street.is_empty():
		return "%s %s" % [number, street]
	return ""


func _add_label(text: String, position: Vector2, lift: float) -> void:
	var label := Label3D.new()
	label.text = text
	label.position = Vector3(
		position.x,
		maxf(terrain.get_height(position.x, position.y), 0.0) + lift,
		position.y
	)
	label.font_size = 28
	label.outline_size = 7
	label.pixel_size = 0.075
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	_labels_node.add_child(label)


func _make_materials() -> void:
	_massing_material = _standard_material(Color(0.48, 0.51, 0.53), 0.92)
	_detail_material = _visual_materials.get("building", _standard_material(Color(0.72, 0.74, 0.74), 0.88))
	_road_material = _visual_materials.get("asphalt", _standard_material(Color(0.13, 0.14, 0.15), 0.97))
	_runway_material = _standard_material(Color(0.10, 0.11, 0.12), 0.94)
	_taxiway_material = _standard_material(Color(0.20, 0.21, 0.22), 0.94)
	_apron_material = _standard_material(Color(0.31, 0.32, 0.33), 0.93)


func _standard_material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material


func _create_chunk_states() -> void:
	var chunks: Dictionary = data.get("chunks", {})
	for cid: String in chunks:
		var chunk := chunks[cid] as Dictionary
		var origin_values: Array = chunk.get("origin", [])
		if origin_values.size() < 2:
			continue
		var center := Vector2(
			float(origin_values[0]) + chunk_size_m * 0.5,
			float(origin_values[1]) + chunk_size_m * 0.5
		)
		var holder := Node3D.new()
		holder.name = "CityChunk_%s" % cid.replace(":", "_")
		add_child(holder)
		_chunks[cid] = {
			"data": chunk,
			"node": holder,
			"center": center,
			"massing": null,
			"detail": null,
			"roads": null,
		}


func _ensure_massing(state: Dictionary) -> void:
	if state["massing"] != null:
		return
	var chunk: Dictionary = state["data"]
	var building_ids: Array = chunk.get("building_ids", [])
	if building_ids.is_empty():
		return

	var box := BoxMesh.new()
	box.size = Vector3.ONE
	box.material = _massing_material
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = box
	multimesh.instance_count = building_ids.size()

	for local_i: int in range(building_ids.size()):
		var building := _buildings[int(building_ids[local_i])] as Dictionary
		var proxy: Dictionary = building.get("proxy", {})
		var x: float = float(proxy.get("x", 0.0))
		var z: float = float(proxy.get("z", 0.0))
		var width: float = maxf(float(proxy.get("width", 2.5)), 2.5)
		var depth: float = maxf(float(proxy.get("depth", 2.5)), 2.5)
		var height: float = maxf(float(building.get("height", 3.0)), 3.0)
		var angle: float = float(proxy.get("angle", 0.0))
		var ground: float = maxf(terrain.get_height(x, z), 0.0)
		var basis := Basis(Vector3.UP, angle).scaled(Vector3(width, height, depth))
		multimesh.set_instance_transform(
			local_i,
			Transform3D(basis, Vector3(x, ground + height * 0.5 + 0.04, z))
		)

	var instance := MultiMeshInstance3D.new()
	instance.name = "Ring0Massing"
	instance.multimesh = multimesh
	(state["node"] as Node3D).add_child(instance)
	state["massing"] = instance


func _ensure_detail(state: Dictionary) -> void:
	if state["detail"] != null:
		return
	var chunk: Dictionary = state["data"]
	var building_ids: Array = chunk.get("building_ids", [])
	if building_ids.is_empty():
		return
	var holder := Node3D.new()
	holder.name = "BuildingDetail"
	var mesh := _build_exact_building_mesh(building_ids)
	if mesh != null:
		var instance := MeshInstance3D.new()
		instance.name = "FootprintWalls"
		instance.mesh = mesh
		holder.add_child(instance)
	var roof_mesh := KeyWestCityVisuals.build_roof_mesh(
		_buildings, building_ids, terrain, _enrichment, _visual_materials.get("roof")
	)
	if roof_mesh != null:
		var roof_instance := MeshInstance3D.new()
		roof_instance.name = "Roofs"
		roof_instance.mesh = roof_mesh
		holder.add_child(roof_instance)
	var facade_node := KeyWestCityVisuals.build_facade_accents(
		_buildings, building_ids, terrain, _visual_materials.get("awning")
	)
	if facade_node != null:
		holder.add_child(facade_node)
	if holder.get_child_count() == 0:
		holder.free()
		return
	(state["node"] as Node3D).add_child(holder)
	state["detail"] = holder


func _build_exact_building_mesh(building_ids: Array) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	for id_variant: Variant in building_ids:
		var building := _buildings[int(id_variant)] as Dictionary
		var footprint_values: Array = building.get("footprint", [])
		if footprint_values.size() < 3:
			continue
		var polygon := PackedVector2Array()
		for point_variant: Variant in footprint_values:
			var point := point_variant as Array
			polygon.append(Vector2(float(point[0]), float(point[1])))
		var triangles: PackedInt32Array = Geometry2D.triangulate_polygon(polygon)
		if triangles.is_empty():
			continue
		var height: float = KeyWestCityVisuals.effective_height(building, _enrichment)
		var facade: Color = KeyWestCityVisuals.facade_color(building, _enrichment)
		var roof: Color = KeyWestCityVisuals.roof_color(building, _enrichment)

		var roof_base: int = vertices.size()
		for p: Vector2 in polygon:
			var ground: float = maxf(terrain.get_height(p.x, p.y), 0.0)
			vertices.append(Vector3(p.x, ground + height + 0.05, p.y))
			normals.append(Vector3.UP)
			colors.append(roof)
		for triangle_index: int in triangles:
			indices.append(roof_base + triangle_index)

		for i: int in range(polygon.size()):
			var a: Vector2 = polygon[i]
			var b: Vector2 = polygon[(i + 1) % polygon.size()]
			var ground_a: float = maxf(terrain.get_height(a.x, a.y), 0.0)
			var ground_b: float = maxf(terrain.get_height(b.x, b.y), 0.0)
			var side := (b - a).normalized()
			var normal := Vector3(side.y, 0.0, -side.x)
			var base: int = vertices.size()
			vertices.append(Vector3(a.x, ground_a + 0.03, a.y))
			vertices.append(Vector3(b.x, ground_b + 0.03, b.y))
			vertices.append(Vector3(a.x, ground_a + height + 0.05, a.y))
			vertices.append(Vector3(b.x, ground_b + height + 0.05, b.y))
			for _j: int in range(4):
				normals.append(normal)
				colors.append(facade)
			indices.append_array([
				base, base + 1, base + 2,
				base + 2, base + 1, base + 3,
			])

	if vertices.is_empty():
		return null
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _detail_material)
	return mesh


func _ensure_roads(state: Dictionary) -> void:
	if state["roads"] != null:
		return
	var chunk: Dictionary = state["data"]
	var segments: Array = chunk.get("road_segments", [])
	if segments.is_empty():
		return
	var node := KeyWestCityVisuals.build_road_node(
		segments, _roads, terrain, _enrichment, _visual_materials
	)
	if node == null or node.get_child_count() == 0:
		if node != null:
			node.free()
		return
	(state["node"] as Node3D).add_child(node)
	state["roads"] = node


func _build_road_mesh(segments: Array) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for segment_variant: Variant in segments:
		var segment := segment_variant as Dictionary
		var road := _roads[int(segment.get("road_id", -1))] as Dictionary
		var a_values: Array = segment.get("a", [])
		var b_values: Array = segment.get("b", [])
		if a_values.size() < 2 or b_values.size() < 2:
			continue
		_append_ribbon_segment(
			vertices, normals, indices,
			Vector2(float(a_values[0]), float(a_values[1])),
			Vector2(float(b_values[0]), float(b_values[1])),
			maxf(float(road.get("width", 4.0)) * 0.5, 1.0),
			0.12
		)
	if vertices.is_empty():
		return null
	return _mesh_from_arrays(vertices, normals, indices, _road_material)


func _build_airport_layer() -> void:
	_airport_node = Node3D.new()
	_airport_node.name = "AirportBlock"
	add_child(_airport_node)

	var runway_segments: Array = []
	var taxiway_segments: Array = []
	var areas: Array = []
	for feature_variant: Variant in _airport_features:
		var feature := feature_variant as Dictionary
		var kind: String = String(feature.get("kind", ""))
		if bool(feature.get("is_area", false)):
			areas.append(feature)
		elif kind == "runway":
			runway_segments.append(feature)
		elif kind in ["taxiway", "taxilane"]:
			taxiway_segments.append(feature)

	_add_airport_ribbons(runway_segments, _runway_material, 0.22, "Runways")
	_add_airport_ribbons(taxiway_segments, _taxiway_material, 0.20, "Taxiways")
	_add_airport_areas(areas)
	KeyWestCityVisuals.add_airport_markings(_airport_node, _airport_features, terrain, _visual_materials)


func _build_global_visuals() -> void:
	if _enrichment.is_empty():
		return
	_global_visuals = KeyWestCityVisuals.build_supplemental_node(terrain, _enrichment, _visual_materials)
	if _global_visuals != null and _global_visuals.get_child_count() > 0:
		add_child(_global_visuals)
	elif _global_visuals != null:
		_global_visuals.free()
		_global_visuals = null


func _add_airport_ribbons(features: Array, material: Material, lift: float, node_name: String) -> void:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for feature_variant: Variant in features:
		var feature := feature_variant as Dictionary
		var points: Array = feature.get("points", [])
		var half_width: float = maxf(float(feature.get("width", 10.0)) * 0.5, 2.0)
		for i: int in range(points.size() - 1):
			var a_values: Array = points[i]
			var b_values: Array = points[i + 1]
			_append_ribbon_segment(
				vertices, normals, indices,
				Vector2(float(a_values[0]), float(a_values[1])),
				Vector2(float(b_values[0]), float(b_values[1])),
				half_width, lift
			)
	if vertices.is_empty():
		return
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = _mesh_from_arrays(vertices, normals, indices, material)
	_airport_node.add_child(instance)


func _add_airport_areas(features: Array) -> void:
	for feature_variant: Variant in features:
		var feature := feature_variant as Dictionary
		var values: Array = feature.get("points", [])
		if values.size() < 3:
			continue
		var polygon := PackedVector2Array()
		for point_variant: Variant in values:
			var point := point_variant as Array
			polygon.append(Vector2(float(point[0]), float(point[1])))
		var triangles: PackedInt32Array = Geometry2D.triangulate_polygon(polygon)
		if triangles.is_empty():
			continue
		var vertices := PackedVector3Array()
		var normals := PackedVector3Array()
		var indices := PackedInt32Array()
		for p: Vector2 in polygon:
			vertices.append(Vector3(p.x, maxf(terrain.get_height(p.x, p.y), 0.0) + 0.16, p.y))
			normals.append(Vector3.UP)
		for index: int in triangles:
			indices.append(index)
		var material: Material = _apron_material
		var kind: String = String(feature.get("kind", ""))
		if kind == "runway":
			material = _runway_material
		elif kind in ["taxiway", "taxilane"]:
			material = _taxiway_material
		var instance := MeshInstance3D.new()
		instance.name = "AirportArea_%s_%s" % [kind, feature.get("id", 0)]
		instance.mesh = _mesh_from_arrays(vertices, normals, indices, material)
		_airport_node.add_child(instance)


func _append_ribbon_segment(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	indices: PackedInt32Array,
	a: Vector2,
	b: Vector2,
	half_width: float,
	lift: float
) -> void:
	var delta := b - a
	if delta.length_squared() < 0.25:
		return
	var direction := delta.normalized()
	var side := Vector2(-direction.y, direction.x) * half_width
	var ay: float = maxf(terrain.get_height(a.x, a.y), 0.0) + lift
	var by: float = maxf(terrain.get_height(b.x, b.y), 0.0) + lift
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


func _mesh_from_arrays(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	indices: PackedInt32Array,
	material: Material
) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	return mesh


func _build_chunk_grid() -> Node3D:
	var holder := Node3D.new()
	holder.name = "ChunkGrid"
	add_child(holder)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var half: float = 2.5
	for state_variant: Variant in _chunks.values():
		var state := state_variant as Dictionary
		var chunk: Dictionary = state["data"]
		var origin_values: Array = chunk.get("origin", [])
		if origin_values.size() < 2:
			continue
		var ox: float = float(origin_values[0])
		var oz: float = float(origin_values[1])
		var a := Vector2(ox, oz)
		var b := Vector2(ox + chunk_size_m, oz)
		var c := Vector2(ox + chunk_size_m, oz + chunk_size_m)
		var d := Vector2(ox, oz + chunk_size_m)
		_append_ribbon_segment(vertices, normals, indices, a, b, half, 0.35)
		_append_ribbon_segment(vertices, normals, indices, b, c, half, 0.35)
		_append_ribbon_segment(vertices, normals, indices, c, d, half, 0.35)
		_append_ribbon_segment(vertices, normals, indices, d, a, half, 0.35)
	var material := _standard_material(Color(0.92, 0.08, 0.06), 0.82)
	material.emission_enabled = true
	material.emission = Color(0.92, 0.08, 0.06)
	material.emission_energy_multiplier = 1.8
	var instance := MeshInstance3D.new()
	instance.mesh = _mesh_from_arrays(vertices, normals, indices, material)
	holder.add_child(instance)
	return holder
