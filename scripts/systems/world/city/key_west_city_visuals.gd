class_name KeyWestCityVisuals
extends RefCounted

## Visual-only helpers for the Key West TPS research path.
## No source geometry is authored here: city_preview.json remains the footprint/
## road truth, while visual_enrichment.json may add attributes and small props.

const FACADE_PALETTE: Array[Color] = [
	Color(0.72, 0.76, 0.78),
	Color(0.69, 0.73, 0.75),
	Color(0.76, 0.74, 0.70),
	Color(0.67, 0.72, 0.70),
	Color(0.75, 0.70, 0.68),
	Color(0.66, 0.69, 0.72),
]
const ROOF_PALETTE: Array[Color] = [
	Color(0.24, 0.28, 0.30),
	Color(0.32, 0.34, 0.35),
	Color(0.38, 0.35, 0.31),
	Color(0.45, 0.47, 0.47),
	Color(0.27, 0.32, 0.34),
]


static func make_materials() -> Dictionary:
	var materials: Dictionary = {}
	materials["building"] = _material(Color.WHITE, 0.88, true)
	materials["roof"] = _material(Color.WHITE, 0.82, true)
	materials["asphalt"] = _material(Color(0.13, 0.14, 0.15), 0.96)
	materials["concrete"] = _material(Color(0.34, 0.35, 0.35), 0.94)
	materials["pavers"] = _material(Color(0.38, 0.34, 0.31), 0.93)
	materials["gravel"] = _material(Color(0.42, 0.42, 0.40), 0.98)
	materials["sand"] = _material(Color(0.45, 0.43, 0.37), 0.99)
	materials["sidewalk"] = _material(Color(0.54, 0.55, 0.55), 0.96)
	materials["curb"] = _material(Color(0.72, 0.73, 0.72), 0.94)
	materials["white_line"] = _material(Color(0.97, 0.98, 0.96), 0.72)
	materials["yellow_line"] = _material(Color(1.0, 0.72, 0.08), 0.72)
	(materials["white_line"] as StandardMaterial3D).shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	(materials["yellow_line"] as StandardMaterial3D).shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	materials["coast"] = _material(Color(0.20, 0.23, 0.24), 0.98)
	materials["pier"] = _material(Color(0.30, 0.31, 0.30), 0.96)
	materials["barrier"] = _material(Color(0.31, 0.33, 0.33), 0.93, false, true)
	materials["pole"] = _material(Color(0.22, 0.24, 0.24), 0.90)
	materials["awning"] = _material(Color(0.20, 0.25, 0.28), 0.88)
	return materials


static func effective_height(building: Dictionary, enrichment: Dictionary) -> float:
	var attrs: Dictionary = _building_attrs(building, enrichment)
	var explicit: float = _float_or(attrs.get("height"), -1.0)
	if explicit > 2.2 and explicit < 80.0:
		return explicit
	var floors: float = _float_or(attrs.get("num_floors"), -1.0)
	if floors > 0.0 and floors < 20.0:
		return maxf(3.2, floors * 3.0)
	return maxf(float(building.get("height", 3.6)), 3.0)


static func facade_color(building: Dictionary, enrichment: Dictionary) -> Color:
	var attrs: Dictionary = _building_attrs(building, enrichment)
	var explicit: Color = _parse_color(String(attrs.get("facade_color", "")))
	if explicit.a > 0.0:
		return explicit.darkened(0.18)
	var metadata: Dictionary = building.get("metadata", {})
	var kind: String = String(metadata.get("building", ""))
	var base: Color
	if kind in ["industrial", "warehouse", "hangar", "service"]:
		base = Color(0.54, 0.57, 0.58)
	elif kind in ["retail", "commercial", "hotel"]:
		base = Color(0.70, 0.72, 0.70)
	else:
		var index: int = absi(hash(String(building.get("osm_id", "")))) % FACADE_PALETTE.size()
		base = FACADE_PALETTE[index]
	return base


static func roof_color(building: Dictionary, enrichment: Dictionary) -> Color:
	var attrs: Dictionary = _building_attrs(building, enrichment)
	var explicit: Color = _parse_color(String(attrs.get("roof_color", "")))
	if explicit.a > 0.0:
		return explicit.darkened(0.12)
	var index: int = absi(hash(String(building.get("osm_id", "")) + ":roof")) % ROOF_PALETTE.size()
	return ROOF_PALETTE[index]


static func roof_shape(building: Dictionary, enrichment: Dictionary) -> String:
	var attrs: Dictionary = _building_attrs(building, enrichment)
	var explicit: String = String(attrs.get("roof_shape", ""))
	if explicit in ["flat", "gabled", "hipped", "pyramidal", "skillion", "saltbox", "gambrel"]:
		return explicit
	var metadata: Dictionary = building.get("metadata", {})
	var kind: String = String(metadata.get("building", ""))
	if kind in ["industrial", "warehouse", "hangar", "shed", "carport"]:
		return "gabled"
	if kind in ["house", "detached", "terrace", "static_caravan", "residential"]:
		return "gabled" if (absi(hash(String(building.get("osm_id", "")))) % 3) != 0 else "hipped"
	if kind in ["retail", "commercial", "hotel", "apartments", "office"]:
		return "flat"
	var street: String = String(metadata.get("addr:street", metadata.get("street_hint", "")))
	if street == "Duval Street":
		return "flat" if (absi(hash(String(building.get("osm_id", "")))) % 2) == 0 else "gabled"
	return "gabled" if float(building.get("area_m2", 0.0)) < 260.0 else "flat"


## Footprint as a polygon with positive signed area, so walls built edge by
## edge face out and caps face up whatever order OSM stored it in.
static func normalized_footprint(values: Array) -> PackedVector2Array:
	var polygon := PackedVector2Array()
	for point_variant: Variant in values:
		var point := point_variant as Array
		var p := Vector2(float(point[0]), float(point[1]))
		if polygon.is_empty() or not polygon[polygon.size() - 1].is_equal_approx(p):
			polygon.append(p)
	if polygon.size() > 2 and polygon[0].is_equal_approx(polygon[polygon.size() - 1]):
		polygon.remove_at(polygon.size() - 1)
	if signed_area(polygon) < 0.0:
		polygon.reverse()
	return polygon


static func signed_area(polygon: PackedVector2Array) -> float:
	var area: float = 0.0
	for i: int in range(polygon.size()):
		var a: Vector2 = polygon[i]
		var b: Vector2 = polygon[(i + 1) % polygon.size()]
		area += a.x * b.y - b.x * a.y
	return area * 0.5


## One ground height per building: the lowest corner, so no wall floats.
static func building_base(polygon: PackedVector2Array, terrain: IslandTerrain) -> float:
	var base: float = INF
	for p: Vector2 in polygon:
		base = minf(base, maxf(terrain.get_height(p.x, p.y), 0.0))
	return base if base != INF else 0.0


## The footprint's own oriented box when it is close to a rectangle, else empty.
static func footprint_box(polygon: PackedVector2Array) -> Dictionary:
	if polygon.size() != 4:
		return {}
	var e0: Vector2 = polygon[1] - polygon[0]
	var e1: Vector2 = polygon[2] - polygon[1]
	var width: float = e0.length()
	var depth: float = e1.length()
	if width < 0.5 or depth < 0.5 or absf(e0.normalized().dot(e1.normalized())) > 0.2:
		return {}
	if absf(signed_area(polygon)) < width * depth * 0.85:
		return {}
	var center: Vector2 = (polygon[0] + polygon[1] + polygon[2] + polygon[3]) * 0.25
	return {"center": center, "width": width, "depth": depth, "angle": atan2(e0.y, e0.x)}


## A triangle whose front face points along `facing`, with that as its normal.
static func emit_tri(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	colors: PackedColorArray,
	indices: PackedInt32Array,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	facing: Vector3,
	color: Color
) -> void:
	if (b - a).cross(c - a).dot(facing) < 0.0:
		var swap: Vector3 = b
		b = c
		c = swap
	var normal: Vector3 = facing.normalized()
	var base: int = vertices.size()
	for v: Vector3 in [a, b, c]:
		vertices.append(v)
		normals.append(normal)
		colors.append(color)
	indices.append_array([base, base + 1, base + 2])


static func build_roof_mesh(
	buildings: Array,
	building_ids: Array,
	terrain: IslandTerrain,
	enrichment: Dictionary,
	material: Material
) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	for id_variant: Variant in building_ids:
		var building := buildings[int(id_variant)] as Dictionary
		var shape: String = roof_shape(building, enrichment)
		if shape == "flat":
			continue
		## Pitched roofs sit on the footprint's own box; other shapes keep a flat
		## roof with a parapet, as most of old Key West's odd lots do.
		var polygon: PackedVector2Array = normalized_footprint(building.get("footprint", []))
		var box: Dictionary = footprint_box(polygon)
		if box.is_empty():
			continue
		var center: Vector2 = box["center"]
		var width: float = float(box["width"]) + 0.35
		var depth: float = float(box["depth"]) + 0.35
		var angle: float = box["angle"]
		var height: float = effective_height(building, enrichment)
		var attrs: Dictionary = _building_attrs(building, enrichment)
		var roof_h: float = clampf(_float_or(attrs.get("roof_height"), minf(2.1, maxf(width, depth) * 0.16)), 0.55, 3.0)
		var base_y: float = building_base(polygon, terrain) + height + 0.03
		var color: Color = roof_color(building, enrichment)

		if shape in ["hipped", "pyramidal"]:
			_append_hip_roof(vertices, normals, colors, indices, center, width, depth, angle, base_y, roof_h, color)
		elif shape == "skillion":
			_append_skillion_roof(vertices, normals, colors, indices, center, width, depth, angle, base_y, roof_h, color)
		else:
			_append_gable_roof(vertices, normals, colors, indices, center, width, depth, angle, base_y, roof_h, color)

	if vertices.is_empty():
		return null
	return _mesh(vertices, normals, colors, indices, material)


static func build_facade_accents(
	buildings: Array,
	building_ids: Array,
	terrain: IslandTerrain,
	material: Material
) -> Node3D:
	var transforms: Array[Transform3D] = []
	var window_transforms: Array[Transform3D] = []
	for id_variant: Variant in building_ids:
		var building := buildings[int(id_variant)] as Dictionary
		var metadata: Dictionary = building.get("metadata", {})
		var kind: String = String(metadata.get("building", ""))
		var street: String = String(metadata.get("addr:street", metadata.get("street_hint", "")))
		var add_canopy: bool = kind in ["retail", "commercial", "hotel", "terrace"]
		if street == "Duval Street" and kind not in ["shed", "garage", "roof", "carport"]:
			add_canopy = true
		## Accents sit on the footprint's longest wall, flush with it, never on a proxy box.
		var polygon: PackedVector2Array = normalized_footprint(building.get("footprint", []))
		if polygon.size() < 3:
			continue
		var edge_start: Vector2 = polygon[0]
		var edge_end: Vector2 = polygon[1 % polygon.size()]
		for i: int in range(polygon.size()):
			var a: Vector2 = polygon[i]
			var b: Vector2 = polygon[(i + 1) % polygon.size()]
			if a.distance_to(b) > edge_start.distance_to(edge_end):
				edge_start = a
				edge_end = b
		var width: float = edge_start.distance_to(edge_end)
		var right: Vector2 = (edge_end - edge_start) / maxf(width, 0.001)
		var outward := Vector2(right.y, -right.x)
		var angle: float = atan2(-outward.x, -outward.y)
		var mid: Vector2 = (edge_start + edge_end) * 0.5
		var ground: float = building_base(polygon, terrain)
		if add_canopy and width >= 2.5:
			var front: Vector2 = mid + outward * 0.42
			var basis := Basis(Vector3.UP, angle).scaled(Vector3(maxf(width * 0.68, 2.2), 0.13, 0.85))
			transforms.append(Transform3D(basis, Vector3(front.x, ground + 2.65, front.y)))
		if kind not in ["shed", "garage", "roof", "carport", "warehouse", "hangar"] and width >= 4.0:
			var windows: int = clampi(int(floor(width / 4.5)), 1, 4)
			for wi: int in range(windows):
				var ratio: float = (float(wi) + 0.5) / float(windows) - 0.5
				var wp: Vector2 = mid + right * ratio * width * 0.72 + outward * 0.05
				var wbasis := Basis(Vector3.UP, angle).scaled(Vector3(minf(1.25, width / float(windows) * 0.42), 0.72, 0.09))
				window_transforms.append(Transform3D(wbasis, Vector3(wp.x, ground + 1.55, wp.y)))
	if transforms.is_empty() and window_transforms.is_empty():
		return null
	var holder := Node3D.new()
	holder.name = "FacadeArchetypes"
	if not transforms.is_empty():
		var mesh := BoxMesh.new()
		mesh.size = Vector3.ONE
		mesh.material = material
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = mesh
		multimesh.instance_count = transforms.size()
		for i: int in range(transforms.size()):
			multimesh.set_instance_transform(i, transforms[i])
		var instance := MultiMeshInstance3D.new()
		instance.name = "StorefrontAwnings"
		instance.multimesh = multimesh
		holder.add_child(instance)
	if not window_transforms.is_empty():
		var window_material := _material(Color(0.10, 0.13, 0.15), 0.70)
		var window_mesh := BoxMesh.new()
		window_mesh.size = Vector3.ONE
		window_mesh.material = window_material
		var window_multimesh := MultiMesh.new()
		window_multimesh.transform_format = MultiMesh.TRANSFORM_3D
		window_multimesh.mesh = window_mesh
		window_multimesh.instance_count = window_transforms.size()
		for i: int in range(window_transforms.size()):
			window_multimesh.set_instance_transform(i, window_transforms[i])
		var window_instance := MultiMeshInstance3D.new()
		window_instance.name = "FacadeWindows"
		window_instance.multimesh = window_multimesh
		holder.add_child(window_instance)
	return holder


static func build_ring0_road_surface(
	roads: Array,
	terrain: IslandTerrain,
	enrichment: Dictionary,
	materials: Dictionary
) -> Node3D:
	var holder := Node3D.new()
	holder.name = "Ring0RoadNetwork"
	var groups: Dictionary = {}
	for road_variant: Variant in roads:
		var road := road_variant as Dictionary
		var points: Array = road.get("points", [])
		if points.size() < 2:
			continue
		var attrs: Dictionary = _road_attrs(road, enrichment)
		var surface: String = _road_surface(road, attrs)
		if not groups.has(surface):
			groups[surface] = []
		for i: int in range(points.size() - 1):
			var av := points[i] as Array
			var bv := points[i + 1] as Array
			if av.size() < 2 or bv.size() < 2:
				continue
			(groups[surface] as Array).append([
				Vector2(float(av[0]), float(av[1])),
				Vector2(float(bv[0]), float(bv[1])),
				_road_width(road, attrs),
			])
	for surface: String in groups:
		var vertices := PackedVector3Array()
		var normals := PackedVector3Array()
		var indices := PackedInt32Array()
		for item_variant: Variant in groups[surface]:
			var item := item_variant as Array
			_append_ribbon(
				vertices, normals, indices,
				item[0], item[1], float(item[2]) * 0.5,
				0.24, terrain
			)
		_add_mesh_child(
			holder, "Ring0_%s" % surface,
			vertices, normals, PackedColorArray(), indices,
			materials.get(surface, materials["asphalt"])
		)
	return holder


static func build_road_node(
	segments: Array,
	roads: Array,
	terrain: IslandTerrain,
	enrichment: Dictionary,
	materials: Dictionary
) -> Node3D:
	var holder := Node3D.new()
	holder.name = "RoadVisualDetail"

	var groups: Dictionary = {}
	var sidewalk_segments: Array = []
	var white_segments: Array = []
	var yellow_segments: Array = []
	var arrow_segments: Array = []

	for segment_variant: Variant in segments:
		var segment := segment_variant as Dictionary
		var road_id: int = int(segment.get("road_id", -1))
		if road_id < 0 or road_id >= roads.size():
			continue
		var road := roads[road_id] as Dictionary
		var av: Array = segment.get("a", [])
		var bv: Array = segment.get("b", [])
		if av.size() < 2 or bv.size() < 2:
			continue
		var a := Vector2(float(av[0]), float(av[1]))
		var b := Vector2(float(bv[0]), float(bv[1]))
		if a.distance_squared_to(b) < 0.25:
			continue
		var attrs: Dictionary = _road_attrs(road, enrichment)
		var surface: String = _road_surface(road, attrs)
		if not groups.has(surface):
			groups[surface] = []
		(groups[surface] as Array).append([a, b, _road_width(road, attrs)])

		var klass: String = String(road.get("class", ""))
		var width: float = _road_width(road, attrs)
		var lanes: int = _road_lanes(road, width)
		var oneway: bool = String(road.get("oneway", "")) == "yes" or _has_oneway_flag(attrs)
		if klass in ["primary", "secondary", "tertiary", "trunk"] or (not String(road.get("name", "")).is_empty() and klass == "residential"):
			sidewalk_segments.append([a, b, width])

		if lanes >= 2 and width >= 5.5:
			if oneway:
				for lane_index: int in range(1, lanes):
					var offset: float = -width * 0.5 + width * float(lane_index) / float(lanes)
					white_segments.append([a, b, offset, true])
			else:
				yellow_segments.append([a, b, 0.0, false])
				if lanes >= 4:
					white_segments.append([a, b, -width * 0.25, true])
					white_segments.append([a, b, width * 0.25, true])
		if oneway and a.distance_to(b) > 8.0:
			arrow_segments.append([a, b])

	for surface: String in groups:
		var vertices := PackedVector3Array()
		var normals := PackedVector3Array()
		var indices := PackedInt32Array()
		for item_variant: Variant in groups[surface]:
			var item := item_variant as Array
			_append_ribbon(vertices, normals, indices, item[0], item[1], float(item[2]) * 0.5, 0.27, terrain)
		_add_mesh_child(holder, "Surface_%s" % surface, vertices, normals, PackedColorArray(), indices, materials.get(surface, materials["asphalt"]))

	var sidewalk_vertices := PackedVector3Array()
	var sidewalk_normals := PackedVector3Array()
	var sidewalk_indices := PackedInt32Array()
	var curb_vertices := PackedVector3Array()
	var curb_normals := PackedVector3Array()
	var curb_indices := PackedInt32Array()
	for item_variant: Variant in sidewalk_segments:
		var item := item_variant as Array
		var a: Vector2 = item[0]
		var b: Vector2 = item[1]
		var width: float = float(item[2])
		var direction := (b - a).normalized()
		var side := Vector2(-direction.y, direction.x)
		for sign_value: float in [-1.0, 1.0]:
			var curb_offset: float = sign_value * (width * 0.5 + 0.22)
			var walk_offset: float = sign_value * (width * 0.5 + 1.05)
			_append_ribbon(curb_vertices, curb_normals, curb_indices, a + side * curb_offset, b + side * curb_offset, 0.18, 0.33, terrain)
			_append_ribbon(sidewalk_vertices, sidewalk_normals, sidewalk_indices, a + side * walk_offset, b + side * walk_offset, 0.72, 0.29, terrain)
	_add_mesh_child(holder, "Curbs", curb_vertices, curb_normals, PackedColorArray(), curb_indices, materials["curb"])
	_add_mesh_child(holder, "Sidewalks", sidewalk_vertices, sidewalk_normals, PackedColorArray(), sidewalk_indices, materials["sidewalk"])

	var white_vertices := PackedVector3Array()
	var white_normals := PackedVector3Array()
	var white_indices := PackedInt32Array()
	for item_variant: Variant in white_segments:
		var item := item_variant as Array
		_append_marking(white_vertices, white_normals, white_indices, item[0], item[1], float(item[2]), bool(item[3]), terrain)
	_add_mesh_child(holder, "WhiteMarkings", white_vertices, white_normals, PackedColorArray(), white_indices, materials["white_line"])

	var yellow_vertices := PackedVector3Array()
	var yellow_normals := PackedVector3Array()
	var yellow_indices := PackedInt32Array()
	for item_variant: Variant in yellow_segments:
		var item := item_variant as Array
		_append_marking(yellow_vertices, yellow_normals, yellow_indices, item[0], item[1], float(item[2]), bool(item[3]), terrain)
	_add_mesh_child(holder, "YellowCenterlines", yellow_vertices, yellow_normals, PackedColorArray(), yellow_indices, materials["yellow_line"])

	var arrow_vertices := PackedVector3Array()
	var arrow_normals := PackedVector3Array()
	var arrow_indices := PackedInt32Array()
	for item_variant: Variant in arrow_segments:
		var item := item_variant as Array
		_append_arrows_along(arrow_vertices, arrow_normals, arrow_indices, item[0], item[1], terrain)
	_add_mesh_child(holder, "OneWayArrows", arrow_vertices, arrow_normals, PackedColorArray(), arrow_indices, materials["white_line"])
	return holder


static func build_supplemental_node(terrain: IslandTerrain, enrichment: Dictionary, materials: Dictionary) -> Node3D:
	var holder := Node3D.new()
	holder.name = "OpenDataStreetAndCoast"
	var features: Array = enrichment.get("supplemental", [])

	var sidewalk_v := PackedVector3Array()
	var sidewalk_n := PackedVector3Array()
	var sidewalk_i := PackedInt32Array()
	var coast_v := PackedVector3Array()
	var coast_n := PackedVector3Array()
	var coast_i := PackedInt32Array()
	var pier_v := PackedVector3Array()
	var pier_n := PackedVector3Array()
	var pier_i := PackedInt32Array()
	var barrier_v := PackedVector3Array()
	var barrier_n := PackedVector3Array()
	var barrier_i := PackedInt32Array()
	var lamp_points: Array[Vector2] = []
	var pole_points: Array[Vector2] = []
	var tower_points: Array[Vector2] = []

	for feature_variant: Variant in features:
		var feature := feature_variant as Dictionary
		var kind: String = String(feature.get("kind", ""))
		var geometry: Dictionary = feature.get("geometry", {})
		var geometry_type: String = String(geometry.get("type", ""))
		if geometry_type == "Point":
			var p_values: Array = geometry.get("coordinates", [])
			if p_values.size() < 2:
				continue
			var p := Vector2(float(p_values[0]), float(p_values[1]))
			if kind == "street_lamp":
				lamp_points.append(p)
			elif kind.begins_with("power:"):
				pole_points.append(p)
			else:
				tower_points.append(p)
			continue
		if geometry_type != "LineString":
			continue
		var values: Array = geometry.get("coordinates", [])
		for i: int in range(values.size() - 1):
			var av := values[i] as Array
			var bv := values[i + 1] as Array
			if av.size() < 2 or bv.size() < 2:
				continue
			var a := Vector2(float(av[0]), float(av[1]))
			var b := Vector2(float(bv[0]), float(bv[1]))
			if kind == "sidewalk":
				_append_ribbon(sidewalk_v, sidewalk_n, sidewalk_i, a, b, 0.7, 0.17, terrain)
			elif kind == "coastline":
				_append_ribbon(coast_v, coast_n, coast_i, a, b, 1.15, 0.36, terrain)
			elif kind in ["pier", "breakwater", "groyne"]:
				var half_width: float = 3.2 if kind == "pier" else 4.2
				_append_ribbon(pier_v, pier_n, pier_i, a, b, half_width, 0.42, terrain)
			elif kind.begins_with("barrier:"):
				_append_wall(barrier_v, barrier_n, barrier_i, a, b, 1.35, terrain)

	_add_mesh_child(holder, "MappedSidewalks", sidewalk_v, sidewalk_n, PackedColorArray(), sidewalk_i, materials["sidewalk"])
	_add_mesh_child(holder, "CoastlineEdge", coast_v, coast_n, PackedColorArray(), coast_i, materials["coast"])
	_add_mesh_child(holder, "PiersBreakwaters", pier_v, pier_n, PackedColorArray(), pier_i, materials["pier"])
	_add_mesh_child(holder, "FencesWalls", barrier_v, barrier_n, PackedColorArray(), barrier_i, materials["barrier"])
	var fences := holder.get_node_or_null(^"FencesWalls") as MeshInstance3D
	if fences != null:
		## Mapped fences and walls stop Henry as the buildings do.
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(fences.mesh.get_faces())
		shape.backface_collision = true
		var collision := CollisionShape3D.new()
		collision.shape = shape
		var body := StaticBody3D.new()
		body.name = "FenceCollision"
		body.add_child(collision)
		fences.add_child(body)
	_add_poles(holder, "StreetLamps", lamp_points, 4.6, 0.055, terrain, materials["pole"])
	_add_poles(holder, "PowerPoles", pole_points, 8.5, 0.095, terrain, materials["pole"])
	_add_poles(holder, "Towers", tower_points, 13.0, 0.16, terrain, materials["pole"])
	return holder


static func add_airport_markings(
	parent: Node3D,
	airport_features: Array,
	terrain: IslandTerrain,
	materials: Dictionary
) -> void:
	var white_v := PackedVector3Array()
	var white_n := PackedVector3Array()
	var white_i := PackedInt32Array()
	var yellow_v := PackedVector3Array()
	var yellow_n := PackedVector3Array()
	var yellow_i := PackedInt32Array()

	for feature_variant: Variant in airport_features:
		var feature := feature_variant as Dictionary
		var kind: String = String(feature.get("kind", ""))
		var points: Array = feature.get("points", [])
		if points.size() < 2:
			continue
		var width: float = maxf(float(feature.get("width", 10.0)), 4.0)
		if kind == "runway":
			for i: int in range(points.size() - 1):
				var a_values := points[i] as Array
				var b_values := points[i + 1] as Array
				var a := Vector2(float(a_values[0]), float(a_values[1]))
				var b := Vector2(float(b_values[0]), float(b_values[1]))
				_append_marking(white_v, white_n, white_i, a, b, 0.0, true, terrain, 3.0, 7.0, 0.16)
				var direction := (b - a).normalized()
				var side := Vector2(-direction.y, direction.x)
				_append_marking(white_v, white_n, white_i, a + side * (width * 0.5 - 0.9), b + side * (width * 0.5 - 0.9), 0.0, false, terrain, 10000.0, 0.0, 0.13)
				_append_marking(white_v, white_n, white_i, a - side * (width * 0.5 - 0.9), b - side * (width * 0.5 - 0.9), 0.0, false, terrain, 10000.0, 0.0, 0.13)
			_append_threshold(white_v, white_n, white_i, points[0], points[1], width, terrain)
			_append_threshold(white_v, white_n, white_i, points[points.size() - 1], points[points.size() - 2], width, terrain)
		elif kind in ["taxiway", "taxilane"]:
			for i: int in range(points.size() - 1):
				var a_values := points[i] as Array
				var b_values := points[i + 1] as Array
				_append_marking(
					yellow_v, yellow_n, yellow_i,
					Vector2(float(a_values[0]), float(a_values[1])),
					Vector2(float(b_values[0]), float(b_values[1])),
					0.0, false, terrain, 10000.0, 0.0, 0.12
				)
		elif bool(feature.get("is_area", false)) and kind == "apron":
			for i: int in range(points.size()):
				var a_values := points[i] as Array
				var b_values := points[(i + 1) % points.size()] as Array
				_append_marking(
					yellow_v, yellow_n, yellow_i,
					Vector2(float(a_values[0]), float(a_values[1])),
					Vector2(float(b_values[0]), float(b_values[1])),
					0.0, false, terrain, 10000.0, 0.0, 0.09
				)

	_add_mesh_child(parent, "AirportWhiteMarkings", white_v, white_n, PackedColorArray(), white_i, materials["white_line"])
	_add_mesh_child(parent, "AirportYellowMarkings", yellow_v, yellow_n, PackedColorArray(), yellow_i, materials["yellow_line"])


static func _building_attrs(building: Dictionary, enrichment: Dictionary) -> Dictionary:
	var attrs: Dictionary = enrichment.get("building_attrs", {})
	return attrs.get(String(building.get("osm_id", "")), {})


static func _road_attrs(road: Dictionary, enrichment: Dictionary) -> Dictionary:
	var attrs: Dictionary = enrichment.get("road_attrs", {})
	return attrs.get(String(road.get("osm_id", "")), {})


static func _road_surface(road: Dictionary, attrs: Dictionary) -> String:
	var surface: String = String(road.get("surface", ""))
	if surface.is_empty():
		surface = String(attrs.get("surface", ""))
	match surface:
		"concrete", "concrete:plates":
			return "concrete"
		"paving_stones", "sett", "cobblestone":
			return "pavers"
		"gravel", "fine_gravel", "unpaved":
			return "gravel"
		"sand", "dirt", "ground":
			return "sand"
		_:
			return "asphalt"


static func _road_width(road: Dictionary, attrs: Dictionary) -> float:
	var enriched: float = _float_or(attrs.get("width"), -1.0)
	if enriched >= 2.0 and enriched <= 30.0:
		return enriched
	return clampf(float(road.get("width", 4.5)), 2.4, 20.0)


static func _road_lanes(road: Dictionary, width: float) -> int:
	var text: String = String(road.get("lanes", ""))
	if text.is_valid_int():
		return clampi(int(text), 1, 6)
	return clampi(int(round(width / 3.2)), 1, 4)


static func _has_oneway_flag(attrs: Dictionary) -> bool:
	var value: String = JSON.stringify(attrs.get("road_flags", [])).to_lower()
	return value.contains("one_way") or value.contains("oneway")


static func _append_marking(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	indices: PackedInt32Array,
	a: Vector2,
	b: Vector2,
	offset: float,
	dashed: bool,
	terrain: IslandTerrain,
	dash_length: float = 4.0,
	gap_length: float = 6.0,
	half_width: float = 0.07
) -> void:
	var delta := b - a
	var length: float = delta.length()
	if length < 0.5:
		return
	var direction := delta / length
	var side := Vector2(-direction.y, direction.x)
	var start := a + side * offset
	var end := b + side * offset
	if not dashed:
		_append_ribbon(vertices, normals, indices, start, end, half_width, 0.39, terrain)
		return
	var cursor: float = 0.0
	var period: float = maxf(dash_length + gap_length, 0.1)
	while cursor < length:
		var dash_end: float = minf(cursor + dash_length, length)
		if dash_end - cursor > 0.2:
			_append_ribbon(
				vertices, normals, indices,
				start + direction * cursor,
				start + direction * dash_end,
				half_width, 0.39, terrain
			)
		cursor += period


static func _append_arrows_along(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	indices: PackedInt32Array,
	a: Vector2,
	b: Vector2,
	terrain: IslandTerrain
) -> void:
	var delta := b - a
	var length: float = delta.length()
	if length < 8.0:
		return
	var direction := delta / length
	var count: int = maxi(1, int(floor(length / 28.0)))
	for i: int in range(count):
		var t: float = (float(i) + 0.5) / float(count)
		var center: Vector2 = a.lerp(b, t)
		_append_arrow_at(vertices, normals, indices, center, direction, terrain)


static func _append_arrow_at(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	indices: PackedInt32Array,
	center: Vector2,
	direction: Vector2,
	terrain: IslandTerrain
) -> void:
	var side := Vector2(-direction.y, direction.x)
	var ground: float = maxf(terrain.get_height(center.x, center.y), 0.0) + 0.41
	var p0 := center - direction * 1.65 - side * 0.16
	var p1 := center + direction * 0.35 - side * 0.16
	var p2 := center + direction * 0.35 - side * 0.52
	var p3 := center + direction * 1.95
	var p4 := center + direction * 0.35 + side * 0.52
	var p5 := center + direction * 0.35 + side * 0.16
	var p6 := center - direction * 1.65 + side * 0.16
	var base: int = vertices.size()
	for p: Vector2 in [p0, p1, p2, p3, p4, p5, p6]:
		vertices.append(Vector3(p.x, ground, p.y))
		normals.append(Vector3.UP)
	indices.append_array([
		base, base + 1, base + 6,
		base + 6, base + 1, base + 5,
		base + 2, base + 3, base + 4,
		base + 2, base + 4, base + 5,
	])

static func _append_arrow(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	indices: PackedInt32Array,
	a: Vector2,
	b: Vector2,
	terrain: IslandTerrain
) -> void:
	var direction := (b - a).normalized()
	if direction.length_squared() < 0.1:
		return
	_append_arrow_at(vertices, normals, indices, a.lerp(b, 0.55), direction, terrain)

static func _append_threshold(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	indices: PackedInt32Array,
	end_values: Variant,
	next_values: Variant,
	width: float,
	terrain: IslandTerrain
) -> void:
	var end_arr := end_values as Array
	var next_arr := next_values as Array
	if end_arr.size() < 2 or next_arr.size() < 2:
		return
	var end := Vector2(float(end_arr[0]), float(end_arr[1]))
	var next := Vector2(float(next_arr[0]), float(next_arr[1]))
	var direction := (next - end).normalized()
	var side := Vector2(-direction.y, direction.x)
	var usable: float = maxf(width * 0.5 - 2.0, 2.0)
	for stripe: int in range(-3, 4):
		var offset: float = usable * float(stripe) / 3.5
		var center := end + direction * 5.0 + side * offset
		_append_ribbon(
			vertices, normals, indices,
			center - direction * 3.0,
			center + direction * 3.0,
			0.55, 0.40, terrain
		)


static func _append_ribbon(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	indices: PackedInt32Array,
	a: Vector2,
	b: Vector2,
	half_width: float,
	lift: float,
	terrain: IslandTerrain
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
	indices.append_array([base, base + 2, base + 1, base + 1, base + 2, base + 3])


static func _append_wall(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	indices: PackedInt32Array,
	a: Vector2,
	b: Vector2,
	height: float,
	terrain: IslandTerrain
) -> void:
	var direction := (b - a).normalized()
	if direction.length_squared() < 0.1:
		return
	var normal := Vector3(-direction.y, 0.0, direction.x)
	var ay: float = maxf(terrain.get_height(a.x, a.y), 0.0) + 0.08
	var by: float = maxf(terrain.get_height(b.x, b.y), 0.0) + 0.08
	var base: int = vertices.size()
	vertices.append(Vector3(a.x, ay, a.y))
	vertices.append(Vector3(b.x, by, b.y))
	vertices.append(Vector3(a.x, ay + height, a.y))
	vertices.append(Vector3(b.x, by + height, b.y))
	for _j: int in range(4):
		normals.append(normal)
	indices.append_array([base, base + 1, base + 2, base + 2, base + 1, base + 3])


static func _append_gable_roof(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	colors: PackedColorArray,
	indices: PackedInt32Array,
	center: Vector2,
	width: float,
	depth: float,
	angle: float,
	base_y: float,
	roof_h: float,
	color: Color
) -> void:
	var along_x: bool = width >= depth
	var hw: float = width * 0.5
	var hd: float = depth * 0.5
	if along_x:
		var a := _rotated(center, angle, -hw, -hd)
		var b := _rotated(center, angle, hw, -hd)
		var c := _rotated(center, angle, -hw, hd)
		var d := _rotated(center, angle, hw, hd)
		var r0 := _rotated(center, angle, -hw, 0.0)
		var r1 := _rotated(center, angle, hw, 0.0)
		## Two slopes down from the ridge r0–r1 to the long eaves a–b and c–d.
		_append_roof_tri(vertices, normals, colors, indices, a, b, r1, base_y, base_y, base_y + roof_h, color)
		_append_roof_tri(vertices, normals, colors, indices, a, r1, r0, base_y, base_y + roof_h, base_y + roof_h, color)
		_append_roof_tri(vertices, normals, colors, indices, c, d, r1, base_y, base_y, base_y + roof_h, color)
		_append_roof_tri(vertices, normals, colors, indices, c, r1, r0, base_y, base_y + roof_h, base_y + roof_h, color)
		_append_gable_end(vertices, normals, colors, indices, a, c, r0, center, base_y, roof_h, color)
		_append_gable_end(vertices, normals, colors, indices, b, d, r1, center, base_y, roof_h, color)
	else:
		var a := _rotated(center, angle, -hw, -hd)
		var b := _rotated(center, angle, hw, -hd)
		var c := _rotated(center, angle, -hw, hd)
		var d := _rotated(center, angle, hw, hd)
		var r0 := _rotated(center, angle, 0.0, -hd)
		var r1 := _rotated(center, angle, 0.0, hd)
		_append_roof_tri(vertices, normals, colors, indices, a, r0, c, base_y, base_y + roof_h, base_y, color)
		_append_roof_tri(vertices, normals, colors, indices, c, r0, r1, base_y, base_y + roof_h, base_y + roof_h, color)
		_append_roof_tri(vertices, normals, colors, indices, b, d, r0, base_y, base_y, base_y + roof_h, color)
		_append_roof_tri(vertices, normals, colors, indices, d, r1, r0, base_y, base_y + roof_h, base_y + roof_h, color)
		_append_gable_end(vertices, normals, colors, indices, a, b, r0, center, base_y, roof_h, color)
		_append_gable_end(vertices, normals, colors, indices, c, d, r1, center, base_y, roof_h, color)


## The vertical triangle closing one end of a gable, facing away from the house.
static func _append_gable_end(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	colors: PackedColorArray,
	indices: PackedInt32Array,
	left: Vector2,
	right: Vector2,
	ridge: Vector2,
	center: Vector2,
	base_y: float,
	roof_h: float,
	color: Color
) -> void:
	var out: Vector2 = ((left + right) * 0.5 - center).normalized()
	emit_tri(
		vertices, normals, colors, indices,
		Vector3(left.x, base_y, left.y), Vector3(right.x, base_y, right.y),
		Vector3(ridge.x, base_y + roof_h, ridge.y), Vector3(out.x, 0.0, out.y), color
	)


static func _append_hip_roof(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	colors: PackedColorArray,
	indices: PackedInt32Array,
	center: Vector2,
	width: float,
	depth: float,
	angle: float,
	base_y: float,
	roof_h: float,
	color: Color
) -> void:
	var hw: float = width * 0.5
	var hd: float = depth * 0.5
	var corners := [
		_rotated(center, angle, -hw, -hd),
		_rotated(center, angle, hw, -hd),
		_rotated(center, angle, hw, hd),
		_rotated(center, angle, -hw, hd),
	]
	for i: int in range(4):
		_append_roof_tri(
			vertices, normals, colors, indices,
			corners[i], corners[(i + 1) % 4], center,
			base_y, base_y, base_y + roof_h, color
		)


static func _append_skillion_roof(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	colors: PackedColorArray,
	indices: PackedInt32Array,
	center: Vector2,
	width: float,
	depth: float,
	angle: float,
	base_y: float,
	roof_h: float,
	color: Color
) -> void:
	var hw: float = width * 0.5
	var hd: float = depth * 0.5
	var a := _rotated(center, angle, -hw, -hd)
	var b := _rotated(center, angle, hw, -hd)
	var c := _rotated(center, angle, hw, hd)
	var d := _rotated(center, angle, -hw, hd)
	_append_roof_tri(vertices, normals, colors, indices, a, b, d, base_y, base_y, base_y + roof_h, color)
	_append_roof_tri(vertices, normals, colors, indices, b, c, d, base_y, base_y + roof_h, base_y + roof_h, color)


static func _append_roof_tri(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	colors: PackedColorArray,
	indices: PackedInt32Array,
	a: Vector2,
	b: Vector2,
	c: Vector2,
	ay: float,
	by: float,
	cy: float,
	color: Color
) -> void:
	var va := Vector3(a.x, ay, a.y)
	var vb := Vector3(b.x, by, b.y)
	var vc := Vector3(c.x, cy, c.y)
	var normal := (vb - va).cross(vc - va).normalized()
	if normal.y < 0.0:
		var temp := vb
		vb = vc
		vc = temp
		normal = (vb - va).cross(vc - va).normalized()
	var base: int = vertices.size()
	for value: Vector3 in [va, vb, vc]:
		vertices.append(value)
		normals.append(normal)
		colors.append(color)
	indices.append_array([base, base + 1, base + 2])


static func _rotated(center: Vector2, angle: float, local_x: float, local_z: float) -> Vector2:
	var ca: float = cos(angle)
	var sa: float = sin(angle)
	return center + Vector2(local_x * ca - local_z * sa, local_x * sa + local_z * ca)


static func _add_poles(
	parent: Node3D,
	name_value: String,
	points: Array[Vector2],
	height: float,
	radius: float,
	terrain: IslandTerrain,
	material: Material
) -> void:
	if points.is_empty():
		return
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = height
	cylinder.radial_segments = 6
	cylinder.material = material
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = cylinder
	multimesh.instance_count = points.size()
	for i: int in range(points.size()):
		var p: Vector2 = points[i]
		var ground: float = maxf(terrain.get_height(p.x, p.y), 0.0)
		multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(p.x, ground + height * 0.5, p.y)))
	var instance := MultiMeshInstance3D.new()
	instance.name = name_value
	instance.multimesh = multimesh
	parent.add_child(instance)


static func _add_mesh_child(
	parent: Node3D,
	name_value: String,
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	colors: PackedColorArray,
	indices: PackedInt32Array,
	material: Material
) -> void:
	if vertices.is_empty():
		return
	var instance := MeshInstance3D.new()
	instance.name = name_value
	instance.mesh = _mesh(vertices, normals, colors, indices, material)
	parent.add_child(instance)


static func _mesh(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	colors: PackedColorArray,
	indices: PackedInt32Array,
	material: Material
) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	if not colors.is_empty():
		arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	return mesh


static func _material(color: Color, roughness: float, vertex_color: bool = false, double_sided: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.vertex_color_use_as_albedo = vertex_color
	if double_sided:
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


static func _parse_color(value: String) -> Color:
	if value.is_empty():
		return Color(0, 0, 0, 0)
	if value.begins_with("#") and value.length() in [4, 7, 9]:
		return Color.from_string(value, Color(0, 0, 0, 0))
	return Color(0, 0, 0, 0)


static func _float_or(value: Variant, fallback: float) -> float:
	if value == null:
		return fallback
	if value is float or value is int:
		return float(value)
	var text: String = String(value)
	if text.is_valid_float():
		return float(text)
	return fallback
