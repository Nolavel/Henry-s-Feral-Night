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

static var _field: SnowField
static var _material: ShaderMaterial


## Mesh for the square chunk at `origin` of side `size_m`, or null when no snow lies there.
static func build(terrain: IslandTerrain, origin: Vector2, size_m: float) -> MeshInstance3D:
	if _field == null:
		_field = SnowField.new()
		_field.load_wind_field(WIND_FIELD_PATH)
		_material = ShaderMaterial.new()
		_material.shader = SHADER
	var n: int = int(size_m / STEP_M) + 1
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var open := PackedByteArray()
	verts.resize(n * n)
	uvs.resize(n * n)
	open.resize(n * n)
	for j: int in range(n):
		for i: int in range(n):
			var at: Vector2 = origin + Vector2(i, j) * STEP_M
			var h: float = terrain.get_height(at.x, at.y)
			var shore: float = smoothstep(SEA_LEVEL_M + SHORE_M.x, SEA_LEVEL_M + SHORE_M.y, h)
			var factor: float = _field.wind_factor(at) * shore
			var k: int = j * n + i
			verts[k] = Vector3(at.x, h, at.y)
			uvs[k] = Vector2(factor, 0.0)
			## Only buildings cut the grid; thin shore snow fades out in the shader.
			open[k] = 0 if _field.is_building(at) else 1
	## Ground normals from neighbouring heights; ridges add their slope in the shader.
	var normals := PackedVector3Array()
	normals.resize(n * n)
	for j: int in range(n):
		for i: int in range(n):
			var hx: float = verts[j * n + mini(i + 1, n - 1)].y - verts[j * n + maxi(i - 1, 0)].y
			var hz: float = verts[mini(j + 1, n - 1) * n + i].y - verts[maxi(j - 1, 0) * n + i].y
			normals[j * n + i] = Vector3(-hx, 2.0 * STEP_M, -hz).normalized()
	var indices := PackedInt32Array()
	for j: int in range(n - 1):
		for i: int in range(n - 1):
			var a: int = j * n + i
			if open[a] + open[a + 1] + open[a + n] + open[a + n + 1] < 4:
				continue
			## Front faces wind clockwise seen from above.
			indices.append_array([a, a + 1, a + n, a + 1, a + n + 1, a + n])
	if indices.is_empty():
		return null
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	## Depth lifts vertices in the shader; keep the chunk from culling early.
	mesh.custom_aabb = AABB(Vector3(origin.x, -5.0, origin.y), Vector3(size_m, 60.0, size_m))
	mesh.surface_set_material(0, _material)
	var inst := MeshInstance3D.new()
	inst.name = "SnowChunkCover"
	inst.mesh = mesh
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return inst
