class_name SnowShell
extends Node3D

## A local layer of real snow depth around Henry: settled cover, wind drifts
## that pile behind obstacles, and prints that break the crust. Visual only.

const SHADER: Shader = preload("res://shaders/environment/snow/snow_ground.gdshader")
const SENSOR_SCRIPT: GDScript = preload("res://scripts/actors/player/henry/components/foot_contact_sensor.gd")
const WEATHER_SCRIPT: GDScript = preload("res://scripts/systems/world/WeatherController.gd")
const TERRAIN_SCRIPT: GDScript = preload("res://scripts/systems/world/terrain/island_terrain.gd")
## Sectors the crust around one print breaks into.
const RIM_SECTORS: int = 7

@export_group("Window")
## Side of the square window around the player, in metres.
@export var window_m: float = 25.6
## Vertices along one side of the shell mesh.
@export_range(32, 512) var mesh_cells: int = 256
## Texels along one side of the print field.
@export_range(64, 1024) var print_res: int = 512
## Texels along one side of the ground and obstacle field.
@export_range(32, 256) var ground_res: int = 128
## The window moves in steps of this size, so the snow never swims.
@export var recentre_step_m: float = 3.2

@export_group("Depth")
## Settled depth at snow_cover 1, before drifts.
@export var depth_m: float = 0.14
## Extra height of the tallest drift ridge at snow_cover 1.
@export var drift_m: float = 0.22
## Extra height piled in the lee of an obstacle at snow_cover 1.
@export var lee_m: float = 0.3

@export_group("Prints")
## Share of the local depth a walking foot packs down.
@export_range(0.0, 1.0) var walk_carve: float = 0.72
## Share of the local depth a sprinting foot packs down.
@export_range(0.0, 1.0) var sprint_carve: float = 0.9
## Tallest broken crust around a print, as a share of the local depth.
@export_range(0.0, 1.0) var rim_rise: float = 0.38
## Half width and half length of a print, in metres.
@export var print_half_m: Vector2 = Vector2(0.075, 0.16)

@export_group("Fill")
## Seconds a print takes to fill with no snow falling.
@export var fill_calm_s: float = 900.0
## Seconds a print takes to fill in a whiteout.
@export var fill_whiteout_s: float = 45.0

var _origin: Vector2 = Vector2(INF, INF)
var _prints: Image
var _ground: Image
var _print_tex: ImageTexture
var _ground_tex: ImageTexture
var _material: ShaderMaterial
var _mesh: MeshInstance3D
var _fill_clock: float = 0.0
var _dirty: bool = false
var _upload_wait: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _player: Node3D
var _weather: WeatherController
var _terrain: IslandTerrain


func _ready() -> void:
	_build()


func on_world_ready(context: WorldContext) -> void:
	_player = context.player
	_weather = context.get_system(WEATHER_SCRIPT) as WeatherController
	_terrain = context.find_in_scene(TERRAIN_SCRIPT) as IslandTerrain
	var sensor := context.find_in_scene(SENSOR_SCRIPT) as FootContactSensor
	if sensor != null and not sensor.foot_planted.is_connected(press):
		sensor.foot_planted.connect(press)


func _physics_process(_delta: float) -> void:
	if _player != null:
		var at: Vector3 = _player.global_position
		recentre_to(Vector2(at.x, at.z))


func _process(delta: float) -> void:
	var density: float = 0.0
	if _weather != null:
		density = clampf(_weather.get_snowfall_density(), 0.0, 1.0)
		var wind: Vector3 = _weather.get_wind_direction()
		var flat := Vector2(wind.x, wind.z)
		if flat.length_squared() > 0.0001:
			_material.set_shader_parameter("wind_dir", flat.normalized())
	_fill_clock += delta / lerpf(fill_calm_s, fill_whiteout_s, density)
	_material.set_shader_parameter("fill_now", _fill_clock)
	_upload_wait -= delta
	if _dirty and _upload_wait <= 0.0:
		flush()


## Moves the window so it is centred near a point; keeps prints already made.
func recentre_to(centre: Vector2) -> void:
	var half: float = window_m * 0.5
	var wanted := Vector2(
		snappedf(centre.x - half, recentre_step_m), snappedf(centre.y - half, recentre_step_m)
	)
	if wanted == _origin:
		return
	var had_origin: bool = _origin.x != INF
	var old_origin: Vector2 = _origin
	_origin = wanted
	_prints = _shifted(_prints, old_origin, had_origin, print_res, Color(0, 0, -1e6))
	var overlap: Rect2i = _shift_rect(old_origin, had_origin, ground_res)
	_ground = _shifted(_ground, old_origin, had_origin, ground_res, Color(0, 1, 0))
	_sample_ground_outside(overlap)
	_ground_tex.set_image(_ground)
	_print_tex.set_image(_prints)
	_material.set_shader_parameter("origin", _origin)
	_mesh.global_position = Vector3(_origin.x + half, 0.0, _origin.y + half)


## Presses a print: packs snow down under the foot and breaks the crust around it.
func press(
	_side: int, point: Vector3, _normal: Vector3, forward: Vector3, speed_mps: float = 0.0
) -> void:
	if _prints == null or _origin.x == INF:
		return
	var sprint: float = clampf((speed_mps - 4.0) / 3.0, 0.0, 1.0)
	var carve: float = lerpf(walk_carve, sprint_carve, sprint)
	var half: Vector2 = print_half_m * Vector2(1.0, 1.0 + 0.25 * sprint)
	var along := Vector2(forward.x, forward.z)
	along = along.normalized() if along.length_squared() > 0.0001 else Vector2(0, -1)
	var across := Vector2(-along.y, along.x)
	var sectors: PackedFloat32Array = []
	for i: int in range(RIM_SECTORS):
		sectors.append(_rng.randf_range(0.25, 1.0))
	var phase: float = _rng.randf() * TAU
	var texel: float = window_m / float(print_res)
	var reach: float = half.y * 1.9
	var centre := Vector2(point.x, point.z)
	var lo: Vector2i = _to_texel(centre - Vector2(reach, reach))
	var hi: Vector2i = _to_texel(centre + Vector2(reach, reach))
	for ty: int in range(maxi(lo.y, 0), mini(hi.y + 1, print_res)):
		for tx: int in range(maxi(lo.x, 0), mini(hi.x + 1, print_res)):
			var world: Vector2 = _origin + (Vector2(tx, ty) + Vector2(0.5, 0.5)) * texel
			var rel: Vector2 = world - centre
			var u: float = rel.dot(across) / half.x
			var v: float = rel.dot(along) / half.y
			var r: float = sqrt(u * u + v * v)
			if r > 1.9:
				continue
			var now: Vector2 = _baked(tx, ty)
			var cell_carve: float = now.x
			var cell_rim: float = now.y
			if r < 1.0:
				## Heel sits deeper than toe; a few clods stay in the bottom.
				var heel: float = 1.0 + 0.12 * clampf(-v, 0.0, 1.0) - 0.1 * clampf(v, 0.0, 1.0)
				var clod: float = _rng.randf_range(0.0, 0.18) if _rng.randf() < 0.12 else 0.0
				var bowl: float = carve * heel * (1.0 - pow(r, 6.0)) - clod
				cell_carve = maxf(cell_carve, clampf(bowl, 0.0, 0.97))
				cell_rim *= r
			else:
				var angle: float = fposmod(atan2(u, v) + phase, TAU)
				var slab: float = sectors[int(angle / TAU * RIM_SECTORS) % RIM_SECTORS]
				var t: float = (r - 1.0) / 0.9
				## A sharp broken edge at the print, then a slope back to fresh snow.
				var lip: float = minf(t / 0.12, 1.0) * pow(1.0 - t, 1.6)
				var rise: float = rim_rise * slab * lip * (1.0 - cell_carve)
				cell_rim = maxf(cell_rim, rise)
			_prints.set_pixel(tx, ty, Color(cell_carve, cell_rim, _fill_clock))
	_dirty = true


## Uploads pending prints to the GPU now instead of on the next tick.
func flush() -> void:
	if _dirty:
		_print_tex.update(_prints)
		_dirty = false
	_upload_wait = 0.1


## Packed-down share at a world point, after fill-in. For tests and tools.
func get_carve_at(x: float, z: float) -> float:
	return _baked_at(x, z).x


## Raised crust at a world point as a share of depth, after fill-in.
func get_rim_at(x: float, z: float) -> float:
	return _baked_at(x, z).y


func get_origin() -> Vector2:
	return _origin


func _build() -> void:
	_rng.randomize()
	_prints = Image.create_empty(print_res, print_res, false, Image.FORMAT_RGBF)
	_prints.fill(Color(0, 0, -1e6))
	_ground = Image.create_empty(ground_res, ground_res, false, Image.FORMAT_RGF)
	_ground.fill(Color(0, 1, 0))
	_print_tex = ImageTexture.create_from_image(_prints)
	_ground_tex = ImageTexture.create_from_image(_ground)
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter("print_field", _print_tex)
	_material.set_shader_parameter("ground_field", _ground_tex)
	_material.set_shader_parameter("window_m", window_m)
	_material.set_shader_parameter("depth_m", depth_m)
	_material.set_shader_parameter("drift_m", drift_m)
	_material.set_shader_parameter("lee_m", lee_m)
	var plane := PlaneMesh.new()
	plane.size = Vector2(window_m, window_m)
	plane.subdivide_width = mesh_cells - 1
	plane.subdivide_depth = mesh_cells - 1
	_mesh = MeshInstance3D.new()
	_mesh.name = "SnowShellMesh"
	_mesh.mesh = plane
	_mesh.material_override = _material
	_mesh.extra_cull_margin = 400.0
	add_child(_mesh)


func _baked_at(x: float, z: float) -> Vector2:
	if _prints == null or _origin.x == INF:
		return Vector2.ZERO
	var t: Vector2i = _to_texel(Vector2(x, z))
	if t.x < 0 or t.y < 0 or t.x >= print_res or t.y >= print_res:
		return Vector2.ZERO
	return _baked(t.x, t.y)


## A texel's carve and rim with fill-in so far applied.
func _baked(tx: int, ty: int) -> Vector2:
	var c: Color = _prints.get_pixel(tx, ty)
	var keep: float = 1.0 - clampf(_fill_clock - c.b, 0.0, 1.0)
	return Vector2(c.r, c.g) * keep


func _to_texel(world: Vector2) -> Vector2i:
	## Snapped first, so a point on a texel edge reads the same cell after a move.
	var p: Vector2 = ((world - _origin) / window_m * float(print_res)).snapped(Vector2(0.001, 0.001))
	return Vector2i(floori(p.x), floori(p.y))


## Where the old window's texels land in a new window of `res`, or empty.
func _shift_rect(old_origin: Vector2, had_origin: bool, res: int) -> Rect2i:
	if not had_origin:
		return Rect2i()
	var shift: Vector2 = (old_origin - _origin) / window_m * float(res)
	var offset := Vector2i(roundi(shift.x), roundi(shift.y))
	return Rect2i(offset, Vector2i(res, res)).intersection(Rect2i(0, 0, res, res))


func _shifted(src: Image, old_origin: Vector2, had_origin: bool, res: int, empty: Color) -> Image:
	var dst: Image = Image.create_empty(res, res, false, src.get_format())
	dst.fill(empty)
	var rect: Rect2i = _shift_rect(old_origin, had_origin, res)
	if rect.has_area():
		var shift: Vector2 = (old_origin - _origin) / window_m * float(res)
		var offset := Vector2i(roundi(shift.x), roundi(shift.y))
		dst.blit_rect(src, Rect2i(rect.position - offset, rect.size), rect.position)
	return dst


## Samples ground height and obstacles for every texel the old window did not cover.
func _sample_ground_outside(kept: Rect2i) -> void:
	if not is_inside_tree():
		return
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var floor_y: float = _player.global_position.y if _player != null else 0.0
	var exclude: Array[RID] = []
	if _player is CollisionObject3D:
		exclude.append((_player as CollisionObject3D).get_rid())
	if _player != null:
		var feet := PhysicsRayQueryParameters3D.create(
			_player.global_position + Vector3.UP * 0.5, _player.global_position + Vector3.DOWN * 5.0
		)
		feet.exclude = exclude
		var under: Dictionary = space.intersect_ray(feet)
		if not under.is_empty():
			floor_y = (under["position"] as Vector3).y
	var texel: float = window_m / float(ground_res)
	for ty: int in range(ground_res):
		for tx: int in range(ground_res):
			if kept.has_point(Vector2i(tx, ty)):
				continue
			var at: Vector2 = _origin + (Vector2(tx, ty) + Vector2(0.5, 0.5)) * texel
			_ground.set_pixel(tx, ty, _sample_ground(space, at, floor_y, exclude))


## Height of the ground and whether something stands on it (G = 1).
func _sample_ground(
	space: PhysicsDirectSpaceState3D, at: Vector2, floor_y: float, exclude: Array[RID]
) -> Color:
	var ground_y: float = floor_y
	if _terrain != null:
		ground_y = _terrain.get_height(at.x, at.y)
	var query := PhysicsRayQueryParameters3D.create(
		Vector3(at.x, ground_y + 6.0, at.y), Vector3(at.x, ground_y - 4.0, at.y)
	)
	query.exclude = exclude
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return Color(ground_y, 0.0 if _terrain != null else 1.0, 0.0)
	var hit_y: float = (hit["position"] as Vector3).y
	if hit_y > ground_y + 0.3:
		return Color(ground_y, 1.0, 0.0)
	return Color(hit_y if _terrain == null else ground_y, 0.0, 0.0)
