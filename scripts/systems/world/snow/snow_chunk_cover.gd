class_name SnowChunkCover
extends RefCounted
## Settled snow over a whole streamed city chunk: a grid on the terrain whose
## vertices carry the city wind factor; depth and ridges come from the shader.

const WIND_FIELD_PATH: String = "res://data/world/key_west/snow_wind.png"
const SHADER: Shader = preload("res://shaders/environment/snow/snow_chunk_cover.gdshader")
const STEP_M: float = 2.0
## Snow thins to nothing this close above the sea, as SnowField does.
const SHORE_M: Vector2 = Vector2(0.05, 0.8)
const SEA_LEVEL_M: float = 0.04
## Finished meshes kept after their chunk unloads; the mesh never depends on weather.
const CACHE_SIZE: int = 12

static var _field: SnowField
static var _material: ShaderMaterial
static var _cache: Dictionary = {}
static var _cache_order: Array[Vector2] = []


## One chunk mesh built a few rows per frame; `step` until it returns true.
class Job extends RefCounted:
	var terrain: IslandTerrain
	var origin: Vector2
	var size_m: float
	var n: int
	var row: int = 0
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	var open := PackedByteArray()
	var indices := PackedInt32Array()


## Mesh for the square chunk at `origin` of side `size_m`, or null when no snow lies there.
static func build(terrain: IslandTerrain, origin: Vector2, size_m: float) -> MeshInstance3D:
	if _cache.has(origin):
		return cached(origin)
	var job: Job = begin(terrain, origin, size_m)
	step(job, 1 << 40)
	return finish(job)


## True when a finished mesh for this chunk is cached.
static func is_cached(origin: Vector2) -> bool:
	return _cache.has(origin)


## A new instance of the cached mesh at `origin`, or null (also when that chunk holds no snow).
static func cached(origin: Vector2) -> MeshInstance3D:
	var mesh: ArrayMesh = _cache.get(origin)
	_touch(origin)
	return _instance(mesh) if mesh != null else null


static func begin(terrain: IslandTerrain, origin: Vector2, size_m: float) -> Job:
	_ensure_shared()
	var job := Job.new()
	job.terrain = terrain
	job.origin = origin
	job.size_m = size_m
	job.n = int(size_m / STEP_M) + 1
	var count: int = job.n * job.n
	job.verts.resize(count)
	job.uvs.resize(count)
	job.normals.resize(count)
	job.open.resize(count)
	return job


## Advances the job within `budget_usec`; rows of samples first, then normals and faces.
static func step(job: Job, budget_usec: int) -> bool:
	var start: int = Time.get_ticks_usec()
	var n: int = job.n
	while job.row < 2 * n:
		if job.row < n:
			_sample_row(job, job.row)
		else:
			_shade_row(job, job.row - n)
		job.row += 1
		if Time.get_ticks_usec() - start >= budget_usec:
			break
	return job.row >= 2 * n


## Turns a finished job into its chunk instance and caches the mesh.
static func finish(job: Job) -> MeshInstance3D:
	var mesh: ArrayMesh = null
	if not job.indices.is_empty():
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = job.verts
		arrays[Mesh.ARRAY_NORMAL] = job.normals
		arrays[Mesh.ARRAY_TEX_UV] = job.uvs
		arrays[Mesh.ARRAY_INDEX] = job.indices
		mesh = ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		## Depth lifts vertices in the shader; keep the chunk from culling early.
		mesh.custom_aabb = AABB(Vector3(job.origin.x, -5.0, job.origin.y), Vector3(job.size_m, 60.0, job.size_m))
		mesh.surface_set_material(0, _material)
	_cache[job.origin] = mesh
	_touch(job.origin)
	while _cache_order.size() > CACHE_SIZE:
		_cache.erase(_cache_order.pop_front())
	return _instance(mesh) if mesh != null else null


static func clear_cache() -> void:
	_cache.clear()
	_cache_order.clear()


static func _ensure_shared() -> void:
	if _field != null:
		return
	_field = SnowField.new()
	_field.load_wind_field(WIND_FIELD_PATH)
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	if _field.wind_texture != null:
		_material.set_shader_parameter("wind_tex", _field.wind_texture)
		_material.set_shader_parameter("wind_origin", _field.wind_field_origin)
		_material.set_shader_parameter("wind_extent",
			Vector2(_field.wind_field.get_width(), _field.wind_field.get_height()) * _field.wind_field_cell_m)
		_material.set_shader_parameter("wind_max", _field.wind_field_max)
		_material.set_shader_parameter("storm_share", _field.storm_share)


static func _sample_row(job: Job, j: int) -> void:
	for i: int in range(job.n):
		var at: Vector2 = job.origin + Vector2(i, j) * STEP_M
		var h: float = job.terrain.get_height(at.x, at.y)
		var shore: float = smoothstep(SEA_LEVEL_M + SHORE_M.x, SEA_LEVEL_M + SHORE_M.y, h)
		var k: int = j * job.n + i
		job.verts[k] = Vector3(at.x, h, at.y)
		job.uvs[k] = Vector2(_field.wind_factor(at) * shore, shore)
		## Only buildings cut the grid; thin shore snow fades out in the shader.
		job.open[k] = 0 if _field.is_building(at) else 1


## Ground normals from neighbouring heights; ridges add their slope in the shader.
static func _shade_row(job: Job, j: int) -> void:
	var n: int = job.n
	var v: PackedVector3Array = job.verts
	for i: int in range(n):
		var hx: float = v[j * n + mini(i + 1, n - 1)].y - v[j * n + maxi(i - 1, 0)].y
		var hz: float = v[mini(j + 1, n - 1) * n + i].y - v[maxi(j - 1, 0) * n + i].y
		job.normals[j * n + i] = Vector3(-hx, 2.0 * STEP_M, -hz).normalized()
	if j == n - 1:
		return
	for i: int in range(n - 1):
		var a: int = j * n + i
		if job.open[a] + job.open[a + 1] + job.open[a + n] + job.open[a + n + 1] < 4:
			continue
		## Front faces wind clockwise seen from above.
		job.indices.append_array([a, a + 1, a + n, a + 1, a + n + 1, a + n])


static func _touch(origin: Vector2) -> void:
	_cache_order.erase(origin)
	_cache_order.append(origin)


static func _instance(mesh: ArrayMesh) -> MeshInstance3D:
	var inst := MeshInstance3D.new()
	inst.name = "SnowChunkCover"
	inst.mesh = mesh
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return inst
