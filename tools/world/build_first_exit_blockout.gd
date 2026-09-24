extends SceneTree

## Builds the First Exit greybox from data/world/first_exit_layout.json onto the
## Graciosa terrain and saves it as a scene. Re-run after editing the layout.
## Run: godot --headless --script res://tools/world/build_first_exit_blockout.gd

const LAYOUT: String = "res://data/world/first_exit_layout.json"
const TERRAIN_DIR: String = "res://experimental_location/Graciosa/terrain_graciosa"
const OUT_SCENE: String = "res://scenes/world/first_exit/first_exit_blockout.tscn"
## Slabs and walls reach this far below the lowest ground under them.
const SINK_M: float = 1.0

var _terrain: Terrain3D
var _root: Node3D
var _concrete := StandardMaterial3D.new()
var _wood := StandardMaterial3D.new()
var _palm := StandardMaterial3D.new()
var _dark := StandardMaterial3D.new()
## Identical pieces share one mesh and one shape, keyed by size and material.
var _meshes: Dictionary = {}
var _shapes: Dictionary = {}


func _initialize() -> void:
	_terrain = Terrain3D.new()
	_terrain.data_directory = TERRAIN_DIR
	root.add_child(_terrain)
	await process_frame
	await process_frame
	_setup_materials()
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	_root = Node3D.new()
	_root.name = "FirstExitBlockout"
	for s: Dictionary in layout["structures"]:
		_build_structure(s)
	for row: Dictionary in layout["palm_rows"]:
		_build_palm_row(row)
	var spawn: Dictionary = layout["spawn"]
	var marker := Marker3D.new()
	marker.name = "SpawnPoint"
	marker.position = _ground(float(spawn["x"]), float(spawn["z"])) + Vector3.UP * 0.2
	marker.rotation.y = deg_to_rad(float(spawn["yaw_deg"]))
	_add(_root, marker)
	var packed := PackedScene.new()
	packed.pack(_root)
	var err: Error = ResourceSaver.save(packed, OUT_SCENE)
	print("first exit blockout: %d nodes -> %s (%s)" % [_count(_root), OUT_SCENE, error_string(err)])
	_root.free()
	quit(0 if err == OK else 1)


func _setup_materials() -> void:
	for pair: Array in [[_concrete, Color(0.62, 0.62, 0.6)], [_wood, Color(0.5, 0.48, 0.45)],
			[_palm, Color(0.36, 0.34, 0.31)], [_dark, Color(0.12, 0.12, 0.13)]]:
		var mat: StandardMaterial3D = pair[0]
		mat.albedo_color = pair[1]
		mat.roughness = 1.0


func _build_structure(s: Dictionary) -> void:
	var node := Node3D.new()
	node.name = String(s["id"]).to_pascal_case()
	var size: Array = s["size"]
	var w: float = float(size[0])
	var d: float = float(size[1])
	var h: float = float(size[2])
	var x: float = float(s["x"])
	var z: float = float(s["z"])
	node.position = Vector3(x, _footprint_min(x, z, w, d, float(s["yaw_deg"])), z)
	node.rotation.y = deg_to_rad(float(s["yaw_deg"]))
	node.set_meta(&"note", s.get("note", ""))
	_add(_root, node)
	match String(s["kind"]):
		"bunker_portal":
			_bunker(node, w, d, h)
		"vent_stack":
			_cylinder(node, Vector3(0, h * 0.5, 0), w * 0.5, h + SINK_M, _concrete)
		"fort_ring":
			_ring(node, w * 0.5, h, 1.2, 14, 2, _concrete)
		"battery":
			_ring(node, w * 0.5, h, 1.4, 9, 0, _concrete, PI)
			_box(node, Vector3(0, -SINK_M * 0.5, 0), Vector3(w, SINK_M + 0.2, d), _concrete)
		"shed":
			_room(node, w, d, h, 0.25, 1.2, [], _wood)
		"house_bungalow":
			_bungalow(node, w, d, h)
		"water_tower":
			_water_tower(node, w, h)
		"chapel":
			_room(node, w, d, h, 0.5, 2.0, [], _concrete)
			_box(node, Vector3(0, h + 2.5, -d * 0.5 + 1.0), Vector3(w * 0.5, 5.0, 1.2), _concrete)
		"bus_shelter":
			_box(node, Vector3(0, h * 0.5, -d * 0.5), Vector3(w, h, 0.15), _concrete)
			_box(node, Vector3(-w * 0.5, h * 0.5, 0), Vector3(0.15, h, d), _concrete)
			_box(node, Vector3(w * 0.5, h * 0.5, 0), Vector3(0.15, h, d), _concrete)
			_box(node, Vector3(0, h, 0), Vector3(w + 0.4, 0.15, d + 0.6), _concrete)
		"pier":
			_pier(node, w, d, h)
		_:
			_box(node, Vector3(0, h * 0.5, 0), Vector3(w, h, d), _concrete)


## Blast door in a concrete face, set into an earth berm behind it.
func _bunker(node: Node3D, w: float, d: float, h: float) -> void:
	_box(node, Vector3(0, h * 0.5 - SINK_M * 0.5, 0), Vector3(w, h + SINK_M, d), _concrete)
	_box(node, Vector3(0, 1.3, d * 0.5 + 0.05), Vector3(2.6, 2.6, 0.2), _dark)
	_box(node, Vector3(-2.2, 1.6, d * 0.5 + 1.0), Vector3(0.6, 3.2, 2.0), _concrete)
	_box(node, Vector3(2.2, 1.6, d * 0.5 + 1.0), Vector3(0.6, 3.2, 2.0), _concrete)
	var berm: MeshInstance3D = _box(node, Vector3(0, h * 0.35, -d * 0.5 - 3.0), Vector3(w + 6.0, h, 8.0), _palm)
	berm.rotation.x = deg_to_rad(-18.0)


## Tropical house on piers: floor, veranda, walls with big openings, roof, chimney.
func _bungalow(node: Node3D, w: float, d: float, h: float) -> void:
	var floor_y: float = 0.8
	for px: float in [-w * 0.5 + 0.3, 0.0, w * 0.5 - 0.3]:
		for pz: float in [-d * 0.5 + 0.3, d * 0.5 - 0.3, d * 0.5 + 2.7]:
			_box(node, Vector3(px, (floor_y - SINK_M) * 0.5, pz), Vector3(0.3, floor_y + SINK_M, 0.3), _wood)
	_box(node, Vector3(0, floor_y, 0), Vector3(w, 0.2, d), _wood)
	_box(node, Vector3(0, floor_y, d * 0.5 + 1.5), Vector3(w, 0.15, 3.0), _wood)
	var walls := Node3D.new()
	walls.name = "Walls"
	walls.position.y = floor_y
	_add(node, walls)
	_room(walls, w, d, h - floor_y, 0.2, 1.1, [[-w * 0.25, 2.0], [w * 0.3, 1.6]], _wood, false)
	var roof: MeshInstance3D = _box(node, Vector3(0, h + 0.4, 0.8), Vector3(w + 1.0, 0.15, d + 3.6), _wood)
	roof.rotation.x = deg_to_rad(6.0)
	_box(node, Vector3(w * 0.5 - 0.8, h + 1.0, -d * 0.5 + 1.0), Vector3(0.7, 2.6, 0.7), _concrete)


## Four walls with a door gap on +Z and optional window gaps [offset, width] on +Z/-Z.
func _room(node: Node3D, w: float, d: float, h: float, t: float, door_w: float,
		windows: Array, mat: Material, with_roof: bool = true) -> void:
	var base: float = -SINK_M if node.position.y == 0.0 and node is Node3D and node.name != "Walls" else 0.0
	var wall_h: float = h - base
	var cy: float = base + wall_h * 0.5
	_box(node, Vector3(-w * 0.5, cy, 0), Vector3(t, wall_h, d), mat)
	_box(node, Vector3(w * 0.5, cy, 0), Vector3(t, wall_h, d), mat)
	_wall_with_gaps(node, -d * 0.5, w, t, base, h, windows, mat)
	var front: Array = [[0.0, door_w, true]]
	for win: Array in windows:
		front.append([win[0], win[1], false])
	_wall_with_gaps(node, d * 0.5, w, t, base, h, front, mat)
	if with_roof:
		_box(node, Vector3(0, h, 0), Vector3(w + 0.4, 0.2, d + 0.4), mat)


## A wall along X at depth z, broken by gaps [centre, width, is_door].
func _wall_with_gaps(node: Node3D, z: float, w: float, t: float, base: float, h: float,
		gaps: Array, mat: Material) -> void:
	var cuts: Array = []
	for g: Array in gaps:
		cuts.append([float(g[0]) - float(g[1]) * 0.5, float(g[0]) + float(g[1]) * 0.5, g.size() > 2 and bool(g[2])])
	cuts.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var cursor: float = -w * 0.5
	for cut: Array in cuts:
		if cut[0] > cursor:
			_box(node, Vector3((cursor + cut[0]) * 0.5, (base + h) * 0.5, z), Vector3(cut[0] - cursor, h - base, t), mat)
		var sill: float = 0.0 if cut[2] else 0.9
		var head: float = 2.1 if cut[2] else 2.0
		if sill > base:
			_box(node, Vector3((cut[0] + cut[1]) * 0.5, (base + sill) * 0.5, z), Vector3(cut[1] - cut[0], sill - base, t), mat)
		if head < h:
			_box(node, Vector3((cut[0] + cut[1]) * 0.5, (head + h) * 0.5, z), Vector3(cut[1] - cut[0], h - head, t), mat)
		cursor = cut[1]
	if cursor < w * 0.5:
		_box(node, Vector3((cursor + w * 0.5) * 0.5, (base + h) * 0.5, z), Vector3(w * 0.5 - cursor, h - base, t), mat)


func _ring(node: Node3D, radius: float, h: float, t: float, segments: int, gaps: int,
		mat: Material, arc: float = TAU) -> void:
	var seg_len: float = arc * radius / float(segments) * 1.02
	for i: int in range(segments):
		if i < gaps:
			continue
		var a: float = -arc * 0.5 + arc * (float(i) + 0.5) / float(segments)
		var wall: MeshInstance3D = _box(node, Vector3(sin(a) * radius, (h - SINK_M) * 0.5, cos(a) * radius),
			Vector3(seg_len, h + SINK_M, t), mat)
		wall.rotation.y = a


func _water_tower(node: Node3D, w: float, h: float) -> void:
	var leg: float = w * 0.4
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_box(node, Vector3(sx * leg, (h - 4.0 - SINK_M) * 0.5, sz * leg), Vector3(0.35, h - 4.0 + SINK_M, 0.35), _concrete)
	_cylinder(node, Vector3(0, h - 2.0, 0), w * 0.55, 4.0, _concrete)
	_cylinder(node, Vector3(0, h + 0.3, 0), w * 0.3, 0.6, _concrete)


## Deck from the shore out over the sea on piles; +Z runs seaward.
func _pier(node: Node3D, w: float, d: float, h: float) -> void:
	_box(node, Vector3(0, h, d * 0.5), Vector3(w, 0.2, d), _wood)
	var n: int = int(d / 4.0)
	for i: int in range(n + 1):
		for sx: float in [-w * 0.5 + 0.2, w * 0.5 - 0.2]:
			_box(node, Vector3(sx, (h - 3.0) * 0.5, float(i) * 4.0), Vector3(0.3, h + 3.0, 0.3), _wood)


func _build_palm_row(row: Dictionary) -> void:
	var a := Vector2(float(row["from"][0]), float(row["from"][1]))
	var b := Vector2(float(row["to"][0]), float(row["to"][1]))
	var n: int = maxi(1, int(a.distance_to(b) / float(row["spacing"])))
	var group := Node3D.new()
	group.name = "Palms_" + String(row["id"]).to_pascal_case()
	_add(_root, group)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(row["id"])
	for i: int in range(n + 1):
		var p: Vector2 = a.lerp(b, float(i) / float(n))
		p += Vector2(rng.randf_range(-3.0, 3.0), rng.randf_range(-3.0, 3.0))
		var lean: float = deg_to_rad(float(row["lean_to_deg"]) + rng.randf_range(-25.0, 25.0))
		_palm_tree(group, _ground(p.x, p.y), lean, snappedf(rng.randf_range(7.0, 11.0), 1.0), rng)


## Dead palm: a leaning, curving trunk of four segments and a drooped crown.
func _palm_tree(parent: Node3D, base: Vector3, lean_yaw: float, height: float, rng: RandomNumberGenerator) -> void:
	var tree := Node3D.new()
	tree.name = "Palm"
	tree.position = base
	tree.rotation.y = lean_yaw
	_add(parent, tree)
	var seg: float = height / 4.0
	var top := Vector3(0, -0.5, 0)
	var tilt: float = 0.0
	for i: int in range(4):
		tilt += deg_to_rad(rng.randf_range(3.0, 7.0))
		var dir := Vector3(0, cos(tilt), -sin(tilt))
		var mid: Vector3 = top + dir * seg * 0.5
		var trunk: MeshInstance3D = _cylinder(tree, mid, 0.22 - 0.03 * float(i), seg + 0.1, _palm, i == 0)
		trunk.rotation.x = -tilt
		top += dir * seg
	for k: int in range(6):
		var frond := Node3D.new()
		frond.position = top
		frond.rotation = Vector3(deg_to_rad(rng.randf_range(35.0, 70.0)), TAU * float(k) / 6.0, 0.0)
		_add(tree, frond)
		var leaf: MeshInstance3D = _box(frond, Vector3(0, 0, 1.4), Vector3(0.35, 0.04, 2.8), _palm, false)
		leaf.rotation.x = deg_to_rad(20.0)


func _box(parent: Node3D, pos: Vector3, size: Vector3, mat: Material, collide: bool = true) -> MeshInstance3D:
	var key: String = "box%s%d" % [size.snappedf(0.01), mat.get_instance_id()]
	if not _meshes.has(key):
		var mesh := BoxMesh.new()
		mesh.size = size
		mesh.material = mat
		_meshes[key] = mesh
		var shape := BoxShape3D.new()
		shape.size = size
		_shapes[key] = shape
	var inst := MeshInstance3D.new()
	inst.mesh = _meshes[key]
	inst.position = pos
	_add(parent, inst)
	if collide:
		_add_body(inst, _shapes[key])
	return inst


func _cylinder(parent: Node3D, pos: Vector3, radius: float, height: float, mat: Material,
		collide: bool = true) -> MeshInstance3D:
	var key: String = "cyl%.2f_%.2f_%d" % [radius, height, mat.get_instance_id()]
	if not _meshes.has(key):
		var mesh := CylinderMesh.new()
		mesh.top_radius = radius
		mesh.bottom_radius = radius
		mesh.height = height
		mesh.radial_segments = 10
		mesh.material = mat
		_meshes[key] = mesh
		var shape := CylinderShape3D.new()
		shape.radius = radius
		shape.height = height
		_shapes[key] = shape
	var inst := MeshInstance3D.new()
	inst.mesh = _meshes[key]
	inst.position = pos
	_add(parent, inst)
	if collide:
		_add_body(inst, _shapes[key])
	return inst


func _add_body(inst: MeshInstance3D, shape: Shape3D) -> void:
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	col.shape = shape
	_add(inst, body)
	_add(body, col)


func _add(parent: Node, child: Node) -> void:
	parent.add_child(child, true)
	child.owner = _root


func _ground(x: float, z: float) -> Vector3:
	var h: float = _terrain.data.get_height(Vector3(x, 0.0, z))
	return Vector3(x, 0.0 if is_nan(h) else h, z)


## Lowest ground under a rotated footprint, so nothing floats.
func _footprint_min(x: float, z: float, w: float, d: float, yaw_deg: float) -> float:
	var yaw: float = deg_to_rad(yaw_deg)
	var lowest: float = INF
	for sx: float in [-0.5, 0.0, 0.5]:
		for sz: float in [-0.5, 0.0, 0.5]:
			var lx: float = sx * w
			var lz: float = sz * d
			var p := Vector2(x + lx * cos(yaw) + lz * sin(yaw), z - lx * sin(yaw) + lz * cos(yaw))
			lowest = minf(lowest, _ground(p.x, p.y).y)
	return lowest


func _count(node: Node) -> int:
	var total: int = 1
	for child: Node in node.get_children():
		total += _count(child)
	return total
