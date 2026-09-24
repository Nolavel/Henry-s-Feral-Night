class_name IslandTerrain
extends Node3D

## The island ground built from the heightmap: square chunks with three
## levels of detail, skirts against cracks, and height-field collision only
## near the focus (HeightMapShape3D spacing is 1 m, as is the map).

const SHADER: Shader = preload("res://shaders/environment/terrain/island_terrain.gdshader")
## Grid spacing of each level of detail, in heightmap pixels.
const LOD_STEPS: Array[int] = [1, 4, 16]

@export var chunk_size_px: int = 128
## Chunk centre closer than this gets full detail, then the next level.
@export var lod_distances_m: Array[float] = [192.0, 768.0]
## Chunks within this distance of the focus carry collision.
@export var collision_radius_m: float = 200.0
## Chunks whose ground never rises above this stay unbuilt; the sea covers them.
@export var min_visible_height_m: float = -1.5
@export var skirt_depth_m: float = 3.0
## Seconds between LOD and collision passes.
@export var update_interval_s: float = 0.25
## Chunk meshes built per frame at most, to keep hitches small.
@export var builds_per_frame: int = 2
## What detail follows: the player, else the active camera.
@export var focus: Node3D

var heightmap: IslandHeightmap
var _material: ShaderMaterial
var _chunks: Dictionary = {}
var _timer: float = 0.0
var _queue: Array = []


func _ready() -> void:
	heightmap = IslandHeightmap.load_default()
	if heightmap == null:
		return
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_register_chunks()
	update_now()


func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_timer = update_interval_s
		_plan()
	var built: int = 0
	while built < builds_per_frame and not _queue.is_empty():
		var job: Array = _queue.pop_front()
		_apply_lod(job[0], job[1])
		built += 1


## Composition-root hook: follow the player.
func on_world_ready(context: WorldContext) -> void:
	if focus == null and context.player != null:
		focus = context.player
	update_now()


## Plans and builds everything at once; for tests, spawns and captures.
func update_now() -> void:
	_plan()
	while not _queue.is_empty():
		var job: Array = _queue.pop_front()
		_apply_lod(job[0], job[1])


func get_height(x: float, z: float) -> float:
	return heightmap.get_height(x, z) if heightmap != null else 0.0


## Chunks currently built, for tests and debug overlays.
func get_chunk_count() -> int:
	return _chunks.size()


func get_lod_of(x: float, z: float) -> int:
	var key := Vector2i(floori((x - heightmap.origin.x) / heightmap.metres_per_px) / chunk_size_px,
		floori((z - heightmap.origin.y) / heightmap.metres_per_px) / chunk_size_px)
	return int(_chunks[key]["lod"]) if _chunks.has(key) else -1


func has_collision_at(x: float, z: float) -> bool:
	var key := Vector2i(floori((x - heightmap.origin.x) / heightmap.metres_per_px) / chunk_size_px,
		floori((z - heightmap.origin.y) / heightmap.metres_per_px) / chunk_size_px)
	return _chunks.has(key) and _chunks[key]["body"] != null


func _register_chunks() -> void:
	var cols: int = ceili(float(heightmap.width - 1) / float(chunk_size_px))
	var rows: int = ceili(float(heightmap.height - 1) / float(chunk_size_px))
	for cz: int in range(rows):
		for cx: int in range(cols):
			var peak: float = -INF
			for r: int in range(cz * chunk_size_px, mini((cz + 1) * chunk_size_px, heightmap.height - 1) + 1, 8):
				for c: int in range(cx * chunk_size_px, mini((cx + 1) * chunk_size_px, heightmap.width - 1) + 1, 8):
					peak = maxf(peak, heightmap.height_at_px(c, r))
			if peak < min_visible_height_m:
				continue
			var inst := MeshInstance3D.new()
			inst.name = "Chunk_%d_%d" % [cx, cz]
			inst.material_override = _material
			add_child(inst)
			_chunks[Vector2i(cx, cz)] = {"inst": inst, "lod": -1, "meshes": {}, "body": null}


func _focus_position() -> Vector3:
	if focus != null and is_instance_valid(focus):
		return focus.global_position
	var camera: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	return camera.global_position if camera != null else Vector3.ZERO


func _plan() -> void:
	if heightmap == null:
		return
	var at: Vector3 = _focus_position()
	var planned: Dictionary = {}
	for job: Array in _queue:
		planned[job[0]] = true
	for key: Vector2i in _chunks:
		var centre: Vector2 = _chunk_centre(key)
		var distance: float = centre.distance_to(Vector2(at.x, at.z))
		var lod: int = LOD_STEPS.size() - 1
		for i: int in range(lod_distances_m.size()):
			if distance < lod_distances_m[i]:
				lod = i
				break
		var chunk: Dictionary = _chunks[key]
		if chunk["lod"] != lod and not planned.has(key):
			_queue.append([key, lod])
		_set_collision(key, distance < collision_radius_m + chunk_size_px * heightmap.metres_per_px * 0.71)
	_queue.sort_custom(func(a: Array, b: Array) -> bool: return a[1] < b[1])


func _chunk_centre(key: Vector2i) -> Vector2:
	return heightmap.origin + (Vector2(key) + Vector2(0.5, 0.5)) * float(chunk_size_px) * heightmap.metres_per_px


func _apply_lod(key: Vector2i, lod: int) -> void:
	var chunk: Dictionary = _chunks[key]
	if not chunk["meshes"].has(lod):
		chunk["meshes"][lod] = _build_mesh(key, LOD_STEPS[lod])
	(chunk["inst"] as MeshInstance3D).mesh = chunk["meshes"][lod]
	chunk["lod"] = lod


## A grid of (n + 1)^2 vertices at `step` pixels, normals from the full-res
## heights, plus a skirt hanging from the border so LOD seams never gap.
func _build_mesh(key: Vector2i, step: int) -> ArrayMesh:
	var m: float = heightmap.metres_per_px
	var c0: int = key.x * chunk_size_px
	var r0: int = key.y * chunk_size_px
	var n: int = chunk_size_px / step
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	verts.resize((n + 1) * (n + 1))
	normals.resize((n + 1) * (n + 1))
	for j: int in range(n + 1):
		for i: int in range(n + 1):
			var c: int = c0 + i * step
			var r: int = r0 + j * step
			var h: float = heightmap.height_at_px(c, r)
			verts[j * (n + 1) + i] = Vector3(heightmap.origin.x + c * m, h, heightmap.origin.y + r * m)
			var dx: float = heightmap.height_at_px(c + step, r) - heightmap.height_at_px(c - step, r)
			var dz: float = heightmap.height_at_px(c, r + step) - heightmap.height_at_px(c, r - step)
			normals[j * (n + 1) + i] = Vector3(-dx, 2.0 * step * m, -dz).normalized()
	for j: int in range(n):
		for i: int in range(n):
			var a: int = j * (n + 1) + i
			indices.append_array([a, a + 1, a + n + 1, a + 1, a + n + 2, a + n + 1])
	## Skirt: walk the border and drop a curtain below each edge.
	var border: Array[int] = []
	for i: int in range(n):
		border.append(i)
	for j: int in range(n):
		border.append(j * (n + 1) + n)
	for i: int in range(n, 0, -1):
		border.append(n * (n + 1) + i)
	for j: int in range(n, 0, -1):
		border.append(j * (n + 1))
	var base: int = verts.size()
	for idx: int in border:
		verts.append(verts[idx] - Vector3(0.0, skirt_depth_m, 0.0))
		normals.append(normals[idx])
	for k: int in range(border.size()):
		var a: int = border[k]
		var b: int = border[(k + 1) % border.size()]
		var a2: int = base + k
		var b2: int = base + (k + 1) % border.size()
		indices.append_array([a, a2, b, b, a2, b2])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _set_collision(key: Vector2i, wanted: bool) -> void:
	var chunk: Dictionary = _chunks[key]
	if wanted == (chunk["body"] != null):
		return
	if not wanted:
		(chunk["body"] as Node).queue_free()
		chunk["body"] = null
		return
	var size: int = chunk_size_px + 1
	var data := PackedFloat32Array()
	data.resize(size * size)
	var c0: int = key.x * chunk_size_px
	var r0: int = key.y * chunk_size_px
	for r: int in range(size):
		for c: int in range(size):
			data[r * size + c] = heightmap.height_at_px(c0 + c, r0 + r)
	var shape := HeightMapShape3D.new()
	shape.map_width = size
	shape.map_depth = size
	shape.map_data = data
	var body := StaticBody3D.new()
	body.name = "Collision_%d_%d" % [key.x, key.y]
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	var centre: Vector2 = heightmap.origin + (Vector2(float(c0), float(r0)) + Vector2.ONE * float(chunk_size_px) * 0.5) * heightmap.metres_per_px
	body.position = Vector3(centre.x, 0.0, centre.y)
	add_child(body)
	chunk["body"] = body
