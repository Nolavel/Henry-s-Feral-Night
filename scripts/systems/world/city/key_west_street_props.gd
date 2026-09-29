class_name KeyWestStreetProps
extends RefCounted
## Mapped street furniture and trees for Key West as simple instanced models.
## Positions come from Overture/OSM; each prop faces its nearest road.

const VEGETATION_PATH: String = "res://data/world/key_west/vegetation.json"
const ROAD_CELL_M: float = 40.0
const ROAD_SEARCH_M: float = 25.0
const TREE_ROW_SPACING_M: float = 7.0
const WOOD_SPACING_M: float = 12.0
const SCRUB_SPACING_M: float = 5.0
const CROSSING_LENGTH_M: float = 3.0
const PALM_BASE_HEIGHT_M: float = 9.0
const TOMB_SPACING_M: float = 4.5
## Wire height above ground for mapped power and distribution lines.
const POWER_LINE_M: float = 12.5
const MINOR_LINE_M: float = 8.3


## Builds every prop layer; returns an empty node when there is no data.
static func build(terrain: IslandTerrain, enrichment: Dictionary, roads: Array) -> Node3D:
	var holder := Node3D.new()
	holder.name = "StreetProps"
	var index: Dictionary = index_roads(roads)
	var mats: Dictionary = _materials()
	var points: Dictionary = {}
	for feature: Dictionary in enrichment.get("infrastructure", []):
		var geometry: Dictionary = feature.get("geometry", {})
		if String(geometry.get("type", "")) != "Point":
			continue
		var c: Array = geometry.get("coordinates", [])
		var kind: String = String(feature.get("class", ""))
		if not points.has(kind):
			points[kind] = []
		(points[kind] as Array).append(Vector2(float(c[0]), float(c[1])))
	for feature: Dictionary in enrichment.get("supplemental", []):
		var geometry: Dictionary = feature.get("geometry", {})
		var kind: String = String(feature.get("kind", ""))
		if String(geometry.get("type", "")) != "Point" or not kind in ["street_lamp", "power:pole"]:
			continue
		var c: Array = geometry.get("coordinates", [])
		var key: String = "osm_lamp" if kind == "street_lamp" else "osm_pole"
		if not points.has(key):
			points[key] = []
		(points[key] as Array).append(Vector2(float(c[0]), float(c[1])))

	var pole := _cyl_shape(0.15, 8.0)
	_add_facing(holder, "PowerPoles", points.get("osm_pole", []), _power_pole_mesh(mats), index, terrain, false, [pole, Vector3(0, 4.0, 0)])
	_add_facing(holder, "StreetLamps", points.get("osm_lamp", []), _lamp_mesh(mats), index, terrain, true, [_cyl_shape(0.1, 6.0), Vector3(0, 3.0, 0)])
	_add_facing(holder, "TrafficSignals", points.get("traffic_signals", []), _signal_mesh(mats), index, terrain, true, [_cyl_shape(0.15, 5.0), Vector3(0, 2.5, 0)])
	var post := [_cyl_shape(0.06, 2.2), Vector3(0, 1.1, 0)]
	_add_facing(holder, "StopSigns", points.get("stop", []), _stop_mesh(mats), index, terrain, true, post)
	var bench := [_box_shape(Vector3(1.8, 0.9, 0.5)), Vector3(0, 0.45, 0)]
	_add_facing(holder, "BusStops", points.get("bus_stop", []), _bus_stop_mesh(mats), index, terrain, true, bench)
	_add_facing(holder, "Benches", points.get("bench", []), _bench_mesh(mats), index, terrain, true, bench)
	var low := [_cyl_shape(0.28, 0.9), Vector3(0, 0.45, 0)]
	_add_facing(holder, "WasteBaskets", points.get("waste_basket", []), _basket_mesh(mats), index, terrain, true, low)
	_add_facing(holder, "FireHydrants", points.get("fire_hydrant", []), _hydrant_mesh(mats), index, terrain, true, [_cyl_shape(0.18, 0.8), Vector3(0, 0.4, 0)])
	_add_facing(holder, "Bollards", points.get("bollard", []), _bollard_mesh(mats), index, terrain, false, [_cyl_shape(0.1, 1.0), Vector3(0, 0.5, 0)])
	_add_facing(holder, "PostBoxes", points.get("post_box", []), _post_box_mesh(mats), index, terrain, true, [_box_shape(Vector3(0.55, 1.2, 0.55)), Vector3(0, 0.6, 0)])
	_add_crossings(holder, points.get("crossing", []), index, terrain)
	_add_wires(holder, enrichment, terrain, mats)
	_add_tanks(holder, enrichment, terrain, mats)
	_add_vegetation(holder, index, terrain, mats)
	return holder


## Buckets road segments into a coarse grid for nearest-road queries.
static func index_roads(roads: Array) -> Dictionary:
	var cells: Dictionary = {}
	for road: Dictionary in roads:
		var pts: Array = road.get("points", [])
		var width: float = float(road.get("width", 6.0))
		for i: int in range(pts.size() - 1):
			var a := Vector2(float(pts[i][0]), float(pts[i][1]))
			var b := Vector2(float(pts[i + 1][0]), float(pts[i + 1][1]))
			var lo := Vector2i((a.min(b) / ROAD_CELL_M).floor())
			var hi := Vector2i((a.max(b) / ROAD_CELL_M).floor())
			for x: int in range(lo.x, hi.x + 1):
				for y: int in range(lo.y, hi.y + 1):
					var key := Vector2i(x, y)
					if not cells.has(key):
						cells[key] = []
					(cells[key] as Array).append([a, b, width])
	return cells


## Nearest road segment: {point, dir, dist, width}, or empty when none is near.
static func nearest_road(index: Dictionary, p: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_d: float = ROAD_SEARCH_M
	var c := Vector2i((p / ROAD_CELL_M).floor())
	for x: int in range(c.x - 1, c.x + 2):
		for y: int in range(c.y - 1, c.y + 2):
			for seg: Array in index.get(Vector2i(x, y), []):
				var a: Vector2 = seg[0]
				var b: Vector2 = seg[1]
				var q: Vector2 = Geometry2D.get_closest_point_to_segment(p, a, b)
				var d: float = p.distance_to(q)
				if d < best_d and a.distance_to(b) > 0.01:
					best_d = d
					best = {"point": q, "dir": (b - a).normalized(), "dist": d, "width": float(seg[2])}
	return best


## Places a prop at each point; its local +Z looks at the nearest road.
static func _add_facing(parent: Node3D, node_name: String, pts: Array, mesh: Mesh, index: Dictionary,
		terrain: IslandTerrain, face_road: bool, collider: Array = []) -> void:
	if pts.is_empty():
		return
	var xfs: Array[Transform3D] = []
	var mm := _multimesh(mesh, pts.size())
	for i: int in range(pts.size()):
		var p: Vector2 = pts[i]
		var yaw: float = float(hash(p) % 628) * 0.01
		var road: Dictionary = nearest_road(index, p)
		if face_road and not road.is_empty():
			var to_road: Vector2 = road["point"] - p
			if to_road.length() < 0.3:
				## Sits on the centreline: face across the road instead.
				var d: Vector2 = road["dir"]
				to_road = Vector2(-d.y, d.x)
			yaw = atan2(to_road.x, to_road.y)
		elif not road.is_empty():
			var d: Vector2 = road["dir"]
			yaw = atan2(d.x, d.y)
		xfs.append(Transform3D(Basis(Vector3.UP, yaw), _ground(terrain, p)))
		mm.set_instance_transform(i, xfs[i])
	_add_instance(parent, node_name, mm)
	if not collider.is_empty():
		_add_bodies(parent, node_name + "Collision", collider[0], collider[1], xfs)


## Zebra stripes across the road at each mapped crossing.
static func _add_crossings(parent: Node3D, pts: Array, index: Dictionary, terrain: IslandTerrain) -> void:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var ind := PackedInt32Array()
	for p: Vector2 in pts:
		var road: Dictionary = nearest_road(index, p)
		if road.is_empty() or float(road["dist"]) > 3.0:
			continue
		var dir: Vector2 = road["dir"]
		var side := Vector2(-dir.y, dir.x)
		var centre: Vector2 = road["point"]
		var half: float = maxf(float(road["width"]) * 0.5 - 0.4, 1.5)
		var s: float = -half
		while s < half:
			var at: Vector2 = centre + side * (s + 0.25)
			KeyWestCityVisuals._append_ribbon(v, n, ind, at - dir * CROSSING_LENGTH_M * 0.5, at + dir * CROSSING_LENGTH_M * 0.5, 0.25, 0.4, terrain)
			s += 1.0
	if v.is_empty():
		return
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = n
	arrays[Mesh.ARRAY_INDEX] = ind
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var paint := _mat(Color(0.93, 0.94, 0.9), 0.75)
	paint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.surface_set_material(0, paint)
	var inst := MeshInstance3D.new()
	inst.name = "Crossings"
	inst.mesh = mesh
	parent.add_child(inst)


## Mapped trees, tree rows, woods and scrub; palms dominate as in the old town.
static func _add_vegetation(parent: Node3D, index: Dictionary, terrain: IslandTerrain, mats: Dictionary) -> void:
	if not FileAccess.file_exists(VEGETATION_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(VEGETATION_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var trees: Array[Vector2] = []
	var woods: Array[Vector2] = []
	var bushes: Array[Vector2] = []
	var tombs: Array[Vector2] = []
	for f: Dictionary in (parsed as Dictionary).get("features", []):
		var coords: Array = f.get("coordinates", [])
		match String(f.get("kind", "")):
			"tree":
				trees.append(Vector2(float(coords[0]), float(coords[1])))
			"tree_row":
				for i: int in range(coords.size() - 1):
					var a := Vector2(float(coords[i][0]), float(coords[i][1]))
					var b := Vector2(float(coords[i + 1][0]), float(coords[i + 1][1]))
					var count: int = maxi(1, int(a.distance_to(b) / TREE_ROW_SPACING_M))
					for k: int in range(count):
						trees.append(a.lerp(b, (float(k) + 0.5) / float(count)))
			"wood":
				woods.append_array(_scatter(coords, WOOD_SPACING_M, index))
			"scrub":
				bushes.append_array(_scatter(coords, SCRUB_SPACING_M, index))
			"cemetery":
				tombs.append_array(_scatter(coords, TOMB_SPACING_M, index))
	var palms: Array[Transform3D] = []
	var broad: Array[Transform3D] = []
	for p: Vector2 in trees:
		var h: int = absi(hash(p))
		var yaw: float = float(h % 628) * 0.01
		if h % 4 == 0:
			var s: float = 0.7 + float((h / 7) % 60) * 0.01
			broad.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s), _ground(terrain, p)))
		else:
			## Palms from 5 to 12 m.
			var s: float = lerpf(5.0, 12.0, float((h / 11) % 100) * 0.01) / PALM_BASE_HEIGHT_M
			palms.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s), _ground(terrain, p)))
	## Hammocks and mangroves are hardwood: bare in this winter.
	for p: Vector2 in woods:
		var h: int = absi(hash(p))
		var s: float = 0.6 + float((h / 7) % 60) * 0.01
		broad.append(Transform3D(Basis(Vector3.UP, float(h % 628) * 0.01).scaled(Vector3.ONE * s), _ground(terrain, p)))
	var bush_xf: Array[Transform3D] = []
	for p: Vector2 in bushes:
		var h: int = absi(hash(p))
		var s: float = 0.6 + float(h % 70) * 0.01
		bush_xf.append(Transform3D(Basis(Vector3.UP, float(h % 628) * 0.01).scaled(Vector3(s, s * 0.7, s)), _ground(terrain, p)))
	_add_transforms(parent, "Palms", _palm_mesh(mats), palms)
	_add_transforms(parent, "BareTrees", _bare_tree_mesh(mats), broad)
	_add_transforms(parent, "Scrub", _bush_mesh(mats), bush_xf)
	var trunk := _cyl_shape(0.22, 3.0)
	_add_bodies(parent, "PalmCollision", trunk, Vector3(0, 1.5, 0), _unscaled(palms))
	_add_bodies(parent, "BareTreeCollision", trunk, Vector3(0, 1.5, 0), _unscaled(broad))
	## Key West Cemetery: rows of whitewashed above-ground vaults.
	var vaults: Array[Transform3D] = []
	for p: Vector2 in tombs:
		var h: int = absi(hash(p))
		var road: Dictionary = nearest_road(index, p)
		var yaw: float = 0.0 if road.is_empty() else atan2((road["dir"] as Vector2).x, (road["dir"] as Vector2).y)
		var tall: float = 0.7 + float(h % 8) * 0.08
		vaults.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(1.0, tall, 1.0)), _ground(terrain, p)))
	_add_transforms(parent, "CemeteryVaults", _vault_mesh(mats), vaults)
	_add_bodies(parent, "CemeteryVaultCollision", _box_shape(Vector3(0.9, 1.0, 2.0)), Vector3(0, 0.5, 0), _unscaled(vaults))


## Grid points inside a polygon, jittered, kept off roads.
static func _scatter(coords: Array, spacing: float, index: Dictionary) -> Array[Vector2]:
	var poly := PackedVector2Array()
	for c: Array in coords:
		poly.append(Vector2(float(c[0]), float(c[1])))
	var out: Array[Vector2] = []
	if poly.size() < 3:
		return out
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for q: Vector2 in poly:
		lo = lo.min(q)
		hi = hi.max(q)
	var x: float = lo.x
	while x < hi.x:
		var y: float = lo.y
		while y < hi.y:
			var p := Vector2(x, y)
			var h: int = absi(hash(p))
			p += Vector2(float(h % 100) - 50.0, float((h / 100) % 100) - 50.0) * spacing * 0.008
			if Geometry2D.is_point_in_polygon(p, poly):
				var road: Dictionary = nearest_road(index, p)
				if road.is_empty() or float(road["dist"]) > float(road["width"]) * 0.5 + 1.5:
					out.append(p)
			y += spacing
		x += spacing
	return out


## Sagging wires between the vertices of mapped power lines.
static func _add_wires(parent: Node3D, enrichment: Dictionary, terrain: IslandTerrain, mats: Dictionary) -> void:
	var spans: Array[Transform3D] = []
	for f: Dictionary in enrichment.get("infrastructure", []):
		var kind: String = String(f.get("class", ""))
		var geometry: Dictionary = f.get("geometry", {})
		if not kind in ["power_line", "minor_line", "cable", "communication_line"] or String(geometry.get("type", "")) != "LineString":
			continue
		var lift: float = POWER_LINE_M if kind == "power_line" else MINOR_LINE_M
		var c: Array = geometry.get("coordinates", [])
		for i: int in range(c.size() - 1):
			var a: Vector3 = _ground(terrain, Vector2(float(c[i][0]), float(c[i][1]))) + Vector3.UP * lift
			var b: Vector3 = _ground(terrain, Vector2(float(c[i + 1][0]), float(c[i + 1][1]))) + Vector3.UP * lift
			var length: float = a.distance_to(b)
			if length < 1.0:
				continue
			## Two straight halves dipping to a mid-span sag.
			var mid: Vector3 = (a + b) * 0.5 + Vector3.DOWN * minf(length * 0.03, 1.5)
			for pair: Array in [[a, mid], [mid, b]]:
				for side: float in [-0.5, 0.5]:
					var from: Vector3 = pair[0]
					var to: Vector3 = pair[1]
					var shift := (to - from).cross(Vector3.UP).normalized() * side
					var z: Vector3 = to - from
					var basis := Basis.looking_at(z.normalized(), Vector3.UP).scaled_local(Vector3(1, 1, z.length()))
					spans.append(Transform3D(basis, (from + to) * 0.5 + shift))
	_add_transforms(parent, "PowerWires", _compose([[_box(Vector3(0.03, 0.03, 1.0)), Transform3D.IDENTITY, mats["wire"]]]), spans)


## Mapped storage tanks and water towers as cylinders sized to their outline.
static func _add_tanks(parent: Node3D, enrichment: Dictionary, terrain: IslandTerrain, mats: Dictionary) -> void:
	var tanks: Array[Transform3D] = []
	for f: Dictionary in enrichment.get("infrastructure", []):
		var kind: String = String(f.get("class", ""))
		var geometry: Dictionary = f.get("geometry", {})
		if not kind in ["storage_tank", "water_tower"] or String(geometry.get("type", "")) != "Polygon":
			continue
		var ring: Array = (geometry.get("coordinates", [[]]) as Array)[0]
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for c: Array in ring:
			lo = lo.min(Vector2(float(c[0]), float(c[1])))
			hi = hi.max(Vector2(float(c[0]), float(c[1])))
		var r: float = clampf((hi - lo).length() * 0.35, 2.0, 30.0)
		var h: float = 30.0 if kind == "water_tower" else clampf(r * 0.8, 4.0, 14.0)
		tanks.append(Transform3D(Basis.IDENTITY.scaled(Vector3(r, h, r)), _ground(terrain, (lo + hi) * 0.5)))
	_add_transforms(parent, "StorageTanks", _compose([[_cyl(1.0, 1.0, 16), _at(0, 0.5, 0), mats["tank"]]]), tanks)
	var body := StaticBody3D.new()
	body.name = "StorageTankCollision"
	for xf: Transform3D in tanks:
		var shape := CylinderShape3D.new()
		shape.radius = xf.basis.x.length()
		shape.height = xf.basis.y.length()
		var col := CollisionShape3D.new()
		col.shape = shape
		col.position = xf.origin + Vector3.UP * shape.height * 0.5
		body.add_child(col)
	if body.get_child_count() > 0:
		parent.add_child(body)
	else:
		body.free()


## One static body per layer; shapes stay unscaled so physics stays exact.
static func _add_bodies(parent: Node3D, node_name: String, shape: Shape3D, offset: Vector3, xfs: Array[Transform3D]) -> void:
	if xfs.is_empty():
		return
	var body := StaticBody3D.new()
	body.name = node_name
	for xf: Transform3D in xfs:
		var col := CollisionShape3D.new()
		col.shape = shape
		col.transform = xf * Transform3D(Basis.IDENTITY, offset)
		body.add_child(col)
	parent.add_child(body)


static func _unscaled(xfs: Array[Transform3D]) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for xf: Transform3D in xfs:
		out.append(Transform3D(xf.basis.orthonormalized(), xf.origin))
	return out


static func _cyl_shape(radius: float, height: float) -> CylinderShape3D:
	var c := CylinderShape3D.new()
	c.radius = radius
	c.height = height
	return c


static func _box_shape(size: Vector3) -> BoxShape3D:
	var b := BoxShape3D.new()
	b.size = size
	return b


static func _ground(terrain: IslandTerrain, p: Vector2) -> Vector3:
	return Vector3(p.x, maxf(terrain.get_height(p.x, p.y), 0.0), p.y)


static func _multimesh(mesh: Mesh, count: int) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = count
	return mm


static func _add_transforms(parent: Node3D, node_name: String, mesh: Mesh, xfs: Array[Transform3D]) -> void:
	if xfs.is_empty():
		return
	var mm := _multimesh(mesh, xfs.size())
	for i: int in range(xfs.size()):
		mm.set_instance_transform(i, xfs[i])
	_add_instance(parent, node_name, mm)


static func _add_instance(parent: Node3D, node_name: String, mm: MultiMesh) -> void:
	var inst := MultiMeshInstance3D.new()
	inst.name = node_name
	inst.multimesh = mm
	parent.add_child(inst)


# --- Models: +Z faces the road, origin at the ground --------------------------

static func _materials() -> Dictionary:
	return {
		"metal": _mat(Color(0.24, 0.25, 0.26), 0.7),
		"wood": _mat(Color(0.33, 0.29, 0.25), 0.95),
		"stop": _mat(Color(0.62, 0.08, 0.07), 0.6),
		"sign": _mat(Color(0.1, 0.24, 0.45), 0.6),
		"white": _mat(Color(0.85, 0.86, 0.84), 0.6),
		"lamp": _mat(Color(0.75, 0.72, 0.6), 0.4),
		"signal": _mat(Color(0.12, 0.12, 0.1), 0.6),
		"bin": _mat(Color(0.18, 0.22, 0.2), 0.85),
		"palm_trunk": _mat(Color(0.36, 0.33, 0.29), 0.95),
		"palm_frond": _mat(Color(0.34, 0.33, 0.24), 0.9, true),
		"bark": _mat(Color(0.27, 0.24, 0.21), 0.95),
		"twig": _mat(Color(0.3, 0.27, 0.24), 0.95),
		"hydrant": _mat(Color(0.62, 0.52, 0.12), 0.6),
		"postbox": _mat(Color(0.12, 0.2, 0.42), 0.6),
		"wire": _mat(Color(0.08, 0.08, 0.08), 0.8),
		"tank": _mat(Color(0.7, 0.71, 0.69), 0.6),
		"vault": _mat(Color(0.8, 0.79, 0.75), 0.9),
	}


static func _mat(color: Color, roughness: float, double_sided: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	if double_sided:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## Merges primitive parts into one mesh, one surface per material.
static func _compose(parts: Array) -> ArrayMesh:
	var tools: Dictionary = {}
	for part: Array in parts:
		var mat: Material = part[2]
		if not tools.has(mat):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			tools[mat] = st
		(tools[mat] as SurfaceTool).append_from(part[0] as Mesh, 0, part[1] as Transform3D)
	var mesh := ArrayMesh.new()
	for mat: Material in tools:
		(tools[mat] as SurfaceTool).commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
	return mesh


static func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static func _cyl(radius: float, height: float, segments: int = 8, top: float = -1.0) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.bottom_radius = radius
	c.top_radius = radius if top < 0.0 else top
	c.height = height
	c.radial_segments = segments
	c.rings = 1
	return c


static func _at(x: float, y: float, z: float, basis: Basis = Basis.IDENTITY) -> Transform3D:
	return Transform3D(basis, Vector3(x, y, z))


static func _power_pole_mesh(m: Dictionary) -> ArrayMesh:
	return _compose([
		[_cyl(0.13, 9.0, 6, 0.09), _at(0, 4.5, 0), m["wood"]],
		[_box(Vector3(2.4, 0.12, 0.12)), _at(0, 8.4, 0), m["wood"]],
		[_box(Vector3(1.6, 0.1, 0.1)), _at(0, 7.6, 0), m["wood"]],
		[_cyl(0.3, 0.9, 8), _at(0.0, 6.8, -0.35), m["metal"]],
	])


static func _lamp_mesh(m: Dictionary) -> ArrayMesh:
	return _compose([
		[_cyl(0.08, 7.0, 6, 0.05), _at(0, 3.5, 0), m["metal"]],
		[_box(Vector3(0.08, 0.08, 1.8)), _at(0, 6.9, 0.9), m["metal"]],
		[_box(Vector3(0.3, 0.12, 0.6)), _at(0, 6.82, 1.8), m["lamp"]],
	])


static func _signal_mesh(m: Dictionary) -> ArrayMesh:
	var parts: Array = [
		[_cyl(0.12, 6.0, 8), _at(0, 3.0, 0), m["metal"]],
		[_box(Vector3(0.12, 0.12, 6.0)), _at(0, 5.8, 3.0), m["metal"]],
	]
	for z: float in [3.0, 5.5]:
		parts.append([_box(Vector3(0.36, 1.1, 0.3)), _at(0, 5.1, z), m["signal"]])
	parts.append([_box(Vector3(0.36, 1.1, 0.3)), _at(0, 2.8, 0.2), m["signal"]])
	return _compose(parts)


static func _stop_mesh(m: Dictionary) -> ArrayMesh:
	## Octagon plate facing the road.
	var plate := _cyl(0.38, 0.03, 8)
	var face := Basis(Vector3.RIGHT, PI * 0.5) * Basis(Vector3.UP, PI / 8.0)
	return _compose([
		[_cyl(0.035, 2.4, 6), _at(0, 1.2, 0), m["metal"]],
		[plate, _at(0, 2.2, 0.04, face), m["stop"]],
	])


static func _bus_stop_mesh(m: Dictionary) -> ArrayMesh:
	var parts: Array = [
		[_cyl(0.04, 2.6, 6), _at(-1.6, 1.3, 0.6), m["metal"]],
		[_box(Vector3(0.45, 0.6, 0.03)), _at(-1.6, 2.35, 0.62), m["sign"]],
	]
	parts.append_array(_bench_parts(m, 0.0))
	return _compose(parts)


static func _bench_parts(m: Dictionary, x: float) -> Array:
	return [
		[_box(Vector3(1.8, 0.06, 0.45)), _at(x, 0.45, 0), m["wood"]],
		[_box(Vector3(1.8, 0.4, 0.05)), _at(x, 0.72, -0.22), m["wood"]],
		[_box(Vector3(0.06, 0.45, 0.4)), _at(x - 0.8, 0.22, 0), m["metal"]],
		[_box(Vector3(0.06, 0.45, 0.4)), _at(x + 0.8, 0.22, 0), m["metal"]],
	]


static func _bench_mesh(m: Dictionary) -> ArrayMesh:
	return _compose(_bench_parts(m, 0.0))


static func _basket_mesh(m: Dictionary) -> ArrayMesh:
	return _compose([
		[_cyl(0.28, 0.9, 10), _at(0, 0.45, 0), m["bin"]],
	])


## Palm from the Graciosa blockout: four bent trunk segments, drooping fronds; 9 m tall.
static func _palm_mesh(m: Dictionary) -> ArrayMesh:
	var parts: Array = []
	var seg: float = PALM_BASE_HEIGHT_M / 4.0
	var top := Vector3(0, -0.3, 0)
	var tilt: float = 0.0
	for i: int in range(4):
		tilt += deg_to_rad(4.0 + float(i) * 1.5)
		var dir := Vector3(0, cos(tilt), -sin(tilt))
		var r: float = 0.2 - 0.03 * float(i)
		parts.append([_cyl(r, seg + 0.15, 7, r - 0.03), Transform3D(Basis(Vector3.RIGHT, -tilt), top + dir * seg * 0.5), m["palm_trunk"]])
		top += dir * seg
	for k: int in range(7):
		var yaw: float = TAU * float(k) / 7.0
		var droop: float = deg_to_rad(25.0 + float(k % 3) * 12.0)
		var b := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, droop)
		parts.append([_box(Vector3(0.45, 0.03, 3.0)), Transform3D(b, top + b * Vector3(0, 0, 1.4)), m["palm_frond"]])
	return _compose(parts)


## Leafless winter tree: trunk, five limbs and a second tier of twigs.
static func _bare_tree_mesh(m: Dictionary) -> ArrayMesh:
	var parts: Array = [[_cyl(0.22, 3.2, 7, 0.15), _at(0, 1.6, 0), m["bark"]]]
	for k: int in range(5):
		var yaw: float = TAU * float(k) / 5.0 + 0.3
		var limb := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, deg_to_rad(38.0 + float(k % 2) * 12.0))
		var base := Vector3(0, 2.6 + float(k % 3) * 0.3, 0)
		parts.append([_cyl(0.1, 2.6, 5, 0.05), Transform3D(limb, base + limb * Vector3(0, 1.3, 0)), m["bark"]])
		var tip: Vector3 = base + limb * Vector3(0, 2.4, 0)
		for j: int in range(2):
			var twig := Basis(Vector3.UP, yaw + (float(j) - 0.5) * 1.1) * Basis(Vector3.RIGHT, deg_to_rad(25.0))
			parts.append([_cyl(0.04, 1.4, 4, 0.015), Transform3D(twig, tip + twig * Vector3(0, 0.7, 0)), m["twig"]])
	return _compose(parts)


## Bare shrub: a fan of thin stems.
static func _bush_mesh(m: Dictionary) -> ArrayMesh:
	var parts: Array = []
	for k: int in range(7):
		var b := Basis(Vector3.UP, TAU * float(k) / 7.0) * Basis(Vector3.RIGHT, deg_to_rad(20.0 + float(k % 3) * 12.0))
		parts.append([_cyl(0.03, 1.4, 4, 0.01), Transform3D(b, b * Vector3(0, 0.7, 0)), m["twig"]])
	return _compose(parts)


static func _hydrant_mesh(m: Dictionary) -> ArrayMesh:
	return _compose([
		[_cyl(0.13, 0.7, 8), _at(0, 0.35, 0), m["hydrant"]],
		[_cyl(0.16, 0.08, 8), _at(0, 0.72, 0), m["hydrant"]],
		[_cyl(0.06, 0.34, 6), _at(0, 0.45, 0, Basis(Vector3.FORWARD, PI * 0.5)), m["hydrant"]],
	])


static func _bollard_mesh(m: Dictionary) -> ArrayMesh:
	return _compose([[_cyl(0.1, 1.0, 8), _at(0, 0.5, 0), m["metal"]]])


static func _post_box_mesh(m: Dictionary) -> ArrayMesh:
	return _compose([
		[_box(Vector3(0.5, 0.9, 0.5)), _at(0, 0.75, 0), m["postbox"]],
		[_cyl(0.25, 0.5, 10), _at(0, 1.2, 0, Basis(Vector3.RIGHT, PI * 0.5)), m["postbox"]],
		[_box(Vector3(0.08, 0.3, 0.08)), _at(0.18, 0.15, 0.18), m["metal"]],
		[_box(Vector3(0.08, 0.3, 0.08)), _at(-0.18, 0.15, -0.18), m["metal"]],
	])


## Above-ground vault with a pitched cap, 1 m tall before per-instance height.
static func _vault_mesh(m: Dictionary) -> ArrayMesh:
	return _compose([
		[_box(Vector3(0.9, 0.9, 2.0)), _at(0, 0.45, 0), m["vault"]],
		[_box(Vector3(1.0, 0.1, 2.1)), _at(0, 0.95, 0), m["vault"]],
		[_box(Vector3(0.5, 0.5, 0.08)), _at(0, 1.2, -0.95), m["vault"]],
	])
