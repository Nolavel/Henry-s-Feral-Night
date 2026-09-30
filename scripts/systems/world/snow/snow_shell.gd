class_name SnowShell
extends Node3D

## Deformable snow around Henry. SnowField says how much snow lies where; an
## upward camera sees whatever presses into it and packs it down for good.

const SURFACE_SHADER: Shader = preload("res://shaders/environment/snow/snow_ground.gdshader")
const CONTACT_SHADER: Shader = preload("res://shaders/environment/snow/snow_contact_depth.gdshader")
const ACCUMULATE_SHADER: Shader = preload("res://shaders/environment/snow/snow_accumulate.gdshader")
const WEATHER_SCRIPT: GDScript = preload("res://scripts/systems/world/WeatherController.gd")
const TERRAIN_SCRIPT: GDScript = preload("res://scripts/systems/world/terrain/island_terrain.gd")
const PRESENTATION_SCRIPT: GDScript = preload("res://scripts/systems/world/snow/snow_presentation_system.gd")
const PICKUP_SCRIPT: GDScript = preload("res://scripts/environment/interactive/item_pickup.gd")
## Contact capture side on the medium tier; the packed field keeps its resolution.
const MEDIUM_CONTACT_RES: int = 512
## Change in storm share that is worth rebuilding the window for.
const STORM_REBUILD_STEP: float = 0.05
## Colliders in this group are kept clear of snow, like swept steps.
const SWEPT_GROUP: StringName = &"snow_swept"
const SENSOR_SCRIPT: GDScript = preload("res://scripts/actors/player/henry/components/foot_contact_sensor.gd")
## Render layer 19 (snow_contact): meshes on it press into the snow.
const CONTACT_LAYER: int = RenderLayers.SNOW_CONTACT

@export_group("Window")
## Side of the square window around the player, in metres.
@export var window_m: float = 25.6
## Mesh spacing around Henry, where prints are read up close, in metres.
@export var near_spacing_m: float = 0.03
## Half width of that dense core; spacing grows towards the window edge.
@export var near_half_m: float = 3.5
## Mesh spacing at the window edge, in metres.
@export var far_spacing_m: float = 0.25
## Texels along one side of the settled field.
@export_range(32, 256) var field_res: int = 128
## Texels along one side of the packed-snow field.
@export_range(128, 2048) var packed_res: int = 1024
## Texels along one side of the contact capture, rendered every frame.
@export_range(128, 2048) var contact_res: int = 1024
## The window moves in steps of this size, so the snow never swims.
@export var recentre_step_m: float = 3.2
## Frame budget for a window move while walking; the old window stays live meanwhile.
@export var rebuild_budget_usec: int = 4000

@export_group("Snow")
## Settled depth at snow_cover 0 and 1, in metres.
@export var cover_depth_m: Vector2 = Vector2(0.05, 0.25)
## Tallest wind drift and lee pile at snow_cover 1, in metres.
@export var drift_m: float = 0.3
@export var lee_m: float = 0.6
## Snow thins out towards this height and never lies below it.
@export var sea_level_m: float = 0.04
## Baked city wind field; used only over island terrain.
@export_file("*.png") var wind_field_path: String = "res://data/world/key_west/snow_wind.png"
## Share of the settled depth a foot or body packs down.
@export_range(0.0, 1.0) var max_pack: float = 0.85
## Steepest a trench wall is drawn, degrees (loose snow ~40).
@export_range(20.0, 80.0) var repose_deg: float = 40.0

@export_group("Fill")
## Seconds packed snow takes to fill back in with no snow falling.
@export var fill_calm_s: float = 900.0
## Seconds it takes in a whiteout.
@export var fill_whiteout_s: float = 45.0

@export_group("Movement")
## Speed share left in the deepest snow Henry wades through.
@export_range(0.2, 1.0) var deep_snow_speed: float = 0.6
## Depth at which wading is slowest, in metres.
@export var deep_snow_m: float = 0.5
## Deeper than this Henry wades: his whole body ploughs a trench. Shallower,
## only planted soles press, so steps stay separate prints.
@export var wade_depth_m: float = 0.3
## Henry starts high-stepping at the first depth and fully wades by the second.
@export var wade_gait_m: Vector2 = Vector2(0.1, 0.28)
## Width of one sole and how far it reaches past the heel and toe bones.
@export var sole_width_m: float = 0.11
@export var sole_margin_m: float = 0.05
## Width and length of the toe that drags through snow on a lifted foot.
@export var drag_size_m: Vector2 = Vector2(0.07, 0.14)

## Henry's live snow window (min corner, size, 1 when live), the same as the snow_window global.
static var live_window: Vector4 = Vector4.ZERO

var field: SnowField = SnowField.new()

var _field_tex: ImageTexture
var _surface: ShaderMaterial
var _mesh: MeshInstance3D
var _contact: SubViewport
var _contact_cam: Camera3D
var _contact_quad: ShaderMaterial
var _accum: Array[SubViewport] = []
var _accum_mat: Array[ShaderMaterial] = []
var _parity: int = 0
var _warmup: int = 3
var _pending_shift: Vector2 = Vector2.ZERO
## Packed snow kept after it leaves the window, and its restore image for the window.
var tracks: SnowTrackStore = SnowTrackStore.new()
var _restore_tex: ImageTexture
var _restore_all: bool = false
var _base_y: float = 0.0
## The move a streamed rebuild is working on.
var _move_from: Vector2 = Vector2(INF, INF)
var _move_cover: float = 0.0
var _move_wind: Vector2 = Vector2(0, -1)
var _player: Node3D
var _mover: Node
var _weather: WeatherController
var _presentation: Node
var _terrain: IslandTerrain
var _world_root: Node
var _sensor: FootContactSensor
var _soles: Array[MeshInstance3D] = []
var _drags: Array[MeshInstance3D] = []
var _wading: bool = false
var _gait: Node


func _ready() -> void:
	if not SnowField.high_quality():
		set_process(false)
		set_physics_process(false)
		return
	if SnowField.quality() == &"medium":
		contact_res = MEDIUM_CONTACT_RES
	field.window_m = window_m
	field.res = field_res
	field.sea_level_m = sea_level_m
	field.cover_depth_m = cover_depth_m
	field.drift_m = drift_m
	field.lee_m = lee_m
	field.ground_sampler = _sample_ground
	_build_surface()
	_build_capture()


func on_world_ready(context: WorldContext) -> void:
	if not SnowField.high_quality():
		return
	_player = context.player
	_world_root = context.world
	_weather = context.get_system(WEATHER_SCRIPT) as WeatherController
	_presentation = context.get_system(PRESENTATION_SCRIPT)
	_terrain = context.find_in_scene(TERRAIN_SCRIPT) as IslandTerrain
	## Only the island has a sea; a test floor at y 0 is not water.
	field.sea_level_m = sea_level_m if _terrain != null else -INF
	if _terrain != null and not wind_field_path.is_empty():
		field.load_wind_field(wind_field_path)
	if _player != null:
		_mover = _player.get_node_or_null(^"MovementController")
		_gait = _player.find_child("Wade", true, false)
	_sensor = context.find_in_scene(SENSOR_SCRIPT) as FootContactSensor
	## Pickups press snow: tag the ones already placed once, then each as it spawns.
	if _world_root != null:
		for pickup: Node in _world_root.find_children("*", "", true, false):
			if is_instance_of(pickup, PICKUP_SCRIPT):
				tag_contact(pickup)
	if is_inside_tree() and not get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.connect(_on_node_added)


## Puts every mesh under `root` on the contact layer, so it presses into snow.
func tag_contact(root: Node, on: bool = true) -> void:
	if root is VisualInstance3D and not is_ancestor_of(root):
		var visual := root as VisualInstance3D
		visual.layers = (visual.layers | CONTACT_LAYER) if on else (visual.layers & ~CONTACT_LAYER)
	for child: Node in root.get_children():
		tag_contact(child, on)


func _physics_process(_delta: float) -> void:
	if _player == null:
		return
	var at: Vector3 = _player.global_position
	_follow(Vector2(at.x, at.z))
	var depth: float = field.get_depth(at.x, at.z)
	if _mover != null and &"snow_speed_multiplier" in _mover:
		_mover.set(&"snow_speed_multiplier", get_speed_multiplier(depth))
	if _gait != null:
		_gait.set(&"wade", clampf(inverse_lerp(wade_gait_m.x, wade_gait_m.y, depth), 0.0, 1.0))
	var wading: bool = depth > wade_depth_m
	if wading != _wading:
		_wading = wading
		tag_contact(_player, wading)
	_place_soles()


## Sets a sole under each foot as it lands; a lifted foot presses nothing.
func _place_soles() -> void:
	for side: int in range(_soles.size()):
		var sole: MeshInstance3D = _soles[side]
		var foot: Dictionary = _sensor.get_foot(side) if _sensor != null else {}
		var planted: bool = not foot.is_empty() and _sensor.is_planted(side)
		_place_drag(side, foot, planted)
		## A planted sole stays where it landed: the walk clip glides, a boot does not.
		var landed: bool = planted and not sole.visible
		sole.visible = planted
		if not landed:
			continue
		var heel: Vector3 = foot["heel"]
		var toe: Vector3 = foot["toe"]
		var along := Vector3(toe.x - heel.x, 0.0, toe.z - heel.z)
		if along.length_squared() < 0.0001:
			along = Vector3.FORWARD * 0.2
		var bottom: float = minf(float(foot["ball"].y), toe.y) - 0.03
		var centre := Vector3((heel.x + toe.x) * 0.5, bottom + 0.15, (heel.z + toe.z) * 0.5)
		var basis := Basis.looking_at(along.normalized(), Vector3.UP)
		sole.global_transform = Transform3D(
			basis.scaled_local(Vector3(sole_width_m, 0.3, along.length() + sole_margin_m * 2.0)), centre
		)


func _process(delta: float) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera != null and camera != _contact_cam:
		camera.cull_mask &= ~CONTACT_LAYER
	var density: float = 0.0
	if _weather != null:
		density = clampf(_weather.get_snowfall_density(), 0.0, 1.0)
	var fill: float = delta / lerpf(fill_calm_s, fill_whiteout_s, density)
	if _warmup > 0:
		fill = 1.0
		_warmup -= 1
	else:
		tracks.advance(fill)
		## A fresh window or a load takes every texel from the restored tiles.
		if _restore_all:
			_pending_shift = Vector2(4.0, 4.0)
			_restore_all = false
	var target: int = _parity
	var mat: ShaderMaterial = _accum_mat[target]
	mat.set_shader_parameter("shift_uv", _pending_shift)
	mat.set_shader_parameter("fill", fill)
	mat.set_shader_parameter("base_y", _base_y)
	_pending_shift = Vector2.ZERO
	_accum[target].render_target_update_mode = SubViewport.UPDATE_ONCE
	_surface.set_shader_parameter("packed_field", _accum[target].get_texture())
	_parity = 1 - _parity


## Moves the window so it is centred near a point and rebuilds the settled field.
func recentre_to(centre: Vector2) -> void:
	if _surface == null:
		return  # Low snow tier: no window.
	var wanted: Vector2 = _snapped_origin(centre)
	if field.origin.x != INF and wanted.is_equal_approx(field.origin):
		return
	var old: Vector2 = field.origin
	var cover: float = _cover()
	var wind: Vector2 = _wind()
	field.storm_share = _storm_share()
	field.rebuild(wanted, cover, wind)
	_apply_window(old, wanted, cover, wind)


## Speed share while wading through `depth_m` of settled snow.
func get_speed_multiplier(depth_m: float) -> float:
	var t: float = clampf((depth_m - cover_depth_m.x) / maxf(deep_snow_m - cover_depth_m.x, 0.01), 0.0, 1.0)
	return lerpf(1.0, deep_snow_speed, t)


func get_origin() -> Vector2:
	return field.origin


## Streams window moves while walking: a move is rebuilt a slice per frame and
## switched in whole. The first window and long jumps are rebuilt at once.
func _follow(centre: Vector2) -> void:
	if _surface == null:
		return
	if field.is_rebuilding():
		if field.step_rebuild(rebuild_budget_usec):
			_apply_window(_move_from, field.origin, _move_cover, _move_wind)
		return
	var wanted: Vector2 = _snapped_origin(centre)
	var storm: float = _storm_share()
	## A storm reshaping the drifts rebuilds the window where it stands.
	var restorm: bool = absf(storm - field.storm_share) >= STORM_REBUILD_STEP
	if field.origin.x != INF and wanted.is_equal_approx(field.origin) and not restorm:
		return
	if field.origin.x == INF or wanted.distance_to(field.origin) > window_m * 0.5:
		recentre_to(centre)
		return
	_move_from = field.origin
	_move_cover = _cover()
	_move_wind = _wind()
	field.storm_share = storm
	field.begin_rebuild(wanted, _move_cover, _move_wind)
	if field.step_rebuild(rebuild_budget_usec):
		_apply_window(_move_from, field.origin, _move_cover, _move_wind)


func _snapped_origin(centre: Vector2) -> Vector2:
	var half: float = window_m * 0.5
	return Vector2(snappedf(centre.x - half, recentre_step_m), snappedf(centre.y - half, recentre_step_m))


## Puts a freshly rebuilt field on screen: shader, packed-snow shift, globals.
func _apply_window(old: Vector2, wanted: Vector2, cover: float, wind: Vector2) -> void:
	var half: float = window_m * 0.5
	_keep_tracks(old, wanted)
	if old.x != INF:
		_pending_shift += (wanted - old) / window_m
	_base_y = _floor_y()
	## Chunk-wide snow reads the same settled depth and hides inside this window.
	RenderingServer.global_shader_parameter_set(&"snow_settled_depth", field.settled_depth(cover))
	RenderingServer.global_shader_parameter_set(&"snow_drift_m", field.drift_amplitude(cover))
	RenderingServer.global_shader_parameter_set(&"snow_wind", wind.normalized() if wind.length_squared() > 0.0001 else Vector2(0, -1))
	live_window = Vector4(wanted.x, wanted.y, window_m, 1.0)
	RenderingServer.global_shader_parameter_set(&"snow_window", live_window)
	_field_tex.set_image(field.image)
	_surface.set_shader_parameter("origin", wanted)
	_mesh.global_position = Vector3(wanted.x + half, 0.0, wanted.y + half)
	_contact_cam.global_transform = Transform3D(
		Basis(Vector3.RIGHT, Vector3.BACK, Vector3.DOWN),
		Vector3(wanted.x + half, _base_y - 5.0, wanted.y + half)
	)
	_contact_quad.set_shader_parameter("base_y", _base_y)


func _build_surface() -> void:
	field.image = Image.create_empty(field_res, field_res, false, Image.FORMAT_RGBAF)
	_field_tex = ImageTexture.create_from_image(field.image)
	_surface = ShaderMaterial.new()
	_surface.shader = SURFACE_SHADER
	_surface.set_shader_parameter("field", _field_tex)
	_surface.set_shader_parameter("window_m", window_m)
	_surface.set_shader_parameter("packed_texel_m", window_m / float(packed_res))
	_surface.set_shader_parameter("repose_tan", tan(deg_to_rad(repose_deg)))
	_mesh = MeshInstance3D.new()
	_mesh.name = "SnowShellMesh"
	_mesh.mesh = _graded_grid()
	_mesh.material_override = _surface
	_mesh.extra_cull_margin = 400.0
	add_child(_mesh)


## A square grid, dense near the middle where Henry stands and coarser outwards.
## A lifted foot's toe follows the boot every frame and presses only as deep
## as it actually dips into the snow, so a low swing drags a furrow.
func _place_drag(side: int, foot: Dictionary, planted: bool) -> void:
	var drag: MeshInstance3D = _drags[side]
	drag.visible = not foot.is_empty() and not planted
	if not drag.visible:
		return
	var ball: Vector3 = foot["ball"]
	var toe: Vector3 = foot["toe"]
	var along := Vector3(toe.x - ball.x, 0.0, toe.z - ball.z)
	if along.length_squared() < 0.0001:
		along = Vector3.FORWARD
	var bottom: float = minf(ball.y, toe.y) - 0.02
	var centre := Vector3((ball.x + toe.x) * 0.5, bottom + 0.15, (ball.z + toe.z) * 0.5)
	var basis := Basis.looking_at(along.normalized(), Vector3.UP)
	drag.global_transform = Transform3D(
		basis.scaled_local(Vector3(drag_size_m.x, 0.3, drag_size_m.y)), centre
	)


func _graded_grid() -> ArrayMesh:
	var half: float = window_m * 0.5
	var side: PackedFloat32Array = [0.0]
	var at: float = 0.0
	var step: float = near_spacing_m
	while at < half:
		if at >= near_half_m:
			step = minf(step * 1.025, far_spacing_m)
		at = minf(at + step, half)
		side.append(at)
	var axis: PackedFloat32Array = []
	for i: int in range(side.size() - 1, 0, -1):
		axis.append(-side[i])
	axis.append_array(side)
	var n: int = axis.size()
	var verts := PackedVector3Array()
	verts.resize(n * n)
	for iz: int in range(n):
		for ix: int in range(n):
			verts[iz * n + ix] = Vector3(axis[ix], 0.0, axis[iz])
	var indices := PackedInt32Array()
	indices.resize((n - 1) * (n - 1) * 6)
	var k: int = 0
	for iz: int in range(n - 1):
		for ix: int in range(n - 1):
			var a: int = iz * n + ix
			indices[k] = a
			indices[k + 1] = a + 1
			indices[k + 2] = a + n
			indices[k + 3] = a + 1
			indices[k + 4] = a + n + 1
			indices[k + 5] = a + n
			k += 6
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _build_capture() -> void:
	_contact = _viewport("SnowContact", contact_res)
	_contact.disable_3d = false
	_contact.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_contact_cam = Camera3D.new()
	_contact_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_contact_cam.size = window_m
	_contact_cam.near = 0.05
	_contact_cam.far = 12.0
	_contact_cam.cull_mask = CONTACT_LAYER
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(1000.0, 0.0, 0.0)
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	_contact_cam.environment = env
	_contact.add_child(_contact_cam)
	_contact_quad = ShaderMaterial.new()
	_contact_quad.shader = CONTACT_SHADER
	var quad := MeshInstance3D.new()
	quad.mesh = QuadMesh.new()
	quad.material_override = _contact_quad
	quad.layers = CONTACT_LAYER
	quad.extra_cull_margin = 16384.0
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	quad.position = Vector3(0, 0, -1)
	_contact_cam.add_child(quad)
	for i: int in range(2):
		var sole := MeshInstance3D.new()
		sole.name = "Sole%d" % i
		## An oval with a flat bottom: a boot sole, not a brick.
		var oval := CylinderMesh.new()
		oval.top_radius = 0.5
		oval.bottom_radius = 0.5
		oval.height = 1.0
		oval.radial_segments = 20
		oval.rings = 1
		sole.mesh = oval
		sole.layers = CONTACT_LAYER
		sole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sole.visible = false
		add_child(sole)
		_soles.append(sole)
		var drag := MeshInstance3D.new()
		drag.name = "Drag%d" % i
		drag.mesh = oval
		drag.layers = CONTACT_LAYER
		drag.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		drag.visible = false
		add_child(drag)
		_drags.append(drag)
	for i: int in range(2):
		var vp: SubViewport = _viewport("SnowPacked%d" % i, packed_res)
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		var mat := ShaderMaterial.new()
		mat.shader = ACCUMULATE_SHADER
		mat.set_shader_parameter("contact_tex", _contact.get_texture())
		mat.set_shader_parameter("field", _field_tex)
		mat.set_shader_parameter("max_pack", max_pack)
		var rect := ColorRect.new()
		rect.size = Vector2(packed_res, packed_res)
		rect.material = mat
		vp.add_child(rect)
		_accum.append(vp)
		_accum_mat.append(mat)
	_restore_tex = ImageTexture.create_from_image(Image.create_empty(packed_res / 4, packed_res / 4, false, Image.FORMAT_RF))
	for mat: ShaderMaterial in _accum_mat:
		mat.set_shader_parameter("restore", _restore_tex)
	_accum_mat[0].set_shader_parameter("previous", _accum[1].get_texture())
	_accum_mat[1].set_shader_parameter("previous", _accum[0].get_texture())


## Files the packing leaving the window and prepares what the new window restores.
func _keep_tracks(old: Vector2, wanted: Vector2) -> void:
	if _accum.is_empty():
		return
	if old.x != INF:
		var packed: Image = _accum[1 - _parity].get_texture().get_image()
		if packed != null and not packed.is_empty():
			tracks.store(packed, old, window_m, Rect2(wanted, Vector2.ONE * window_m))
	else:
		_restore_all = true
	_restore_tex.set_image(tracks.restore(wanted, window_m, packed_res / 4))


func get_save_key() -> StringName:
	return &"snow_tracks"


func get_save_data() -> Dictionary:
	if not _accum.is_empty() and field.origin.x != INF:
		var packed: Image = _accum[1 - _parity].get_texture().get_image()
		if packed != null and not packed.is_empty():
			tracks.store(packed, field.origin, window_m, Rect2())
	return tracks.get_save_data()


func load_save_data(data: Dictionary) -> void:
	tracks.load_save_data(data)
	if _restore_tex != null and field.origin.x != INF:
		_restore_tex.set_image(tracks.restore(field.origin, window_m, packed_res / 4))
		_restore_all = true


func _viewport(node_name: String, side: int) -> SubViewport:
	var vp := SubViewport.new()
	vp.name = node_name
	vp.size = Vector2i(side, side)
	vp.use_hdr_2d = true
	vp.disable_3d = true
	vp.transparent_bg = false
	vp.msaa_3d = Viewport.MSAA_DISABLED
	add_child(vp)
	return vp


## Settled cover, never read back from RenderingServer (that stalls).
## Share of fresh storm snow, from the presentation system; 0.4 without one.
func _storm_share() -> float:
	if _presentation != null and _presentation.has_method(&"get_storm_share"):
		return clampf(float(_presentation.call(&"get_storm_share")), 0.0, 1.0)
	return field.storm_share


func _cover() -> float:
	if _presentation != null:
		return clampf(float(_presentation.call(&"get_settled_snow")), 0.0, 1.0)
	if _weather != null:
		return clampf(_weather.get_snow_cover(), 0.0, 1.0)
	return 0.5


func _wind() -> Vector2:
	if _weather == null:
		return Vector2(0, -1)
	var wind: Vector3 = _weather.get_wind_direction()
	return Vector2(wind.x, wind.z)


func _floor_y() -> float:
	if _player == null or not is_inside_tree():
		return 0.0
	var query := PhysicsRayQueryParameters3D.create(
		_player.global_position + Vector3.UP * 0.5, _player.global_position + Vector3.DOWN * 5.0
	)
	query.exclude = _exclude()
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	return (hit["position"] as Vector3).y if not hit.is_empty() else _player.global_position.y


func _exclude() -> Array[RID]:
	var out: Array[RID] = []
	if _player is CollisionObject3D:
		out.append((_player as CollisionObject3D).get_rid())
	return out


## Ground height and what covers it, for SnowField: 0 open, 1 a wall that
## shelters its lee, 2 under a roof (no snow, no lee pile).
func _sample_ground(at: Vector2) -> Vector2:
	var ground_y: float = _base_y
	if _terrain != null:
		ground_y = _terrain.get_height(at.x, at.y)
	if not is_inside_tree():
		return Vector2(ground_y, 0.0)
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		Vector3(at.x, ground_y + 6.0, at.y), Vector3(at.x, ground_y - 4.0, at.y)
	)
	query.exclude = _exclude()
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return Vector2(ground_y, 0.0 if _terrain != null else 1.0)
	var hit_at: Vector3 = hit["position"]
	var normal: Vector3 = hit["normal"]
	var collider: Object = hit.get("collider")
	if collider is Node and (collider as Node).is_in_group(SWEPT_GROUP):
		return Vector2(hit_at.y, 2.0)
	## Steep faces, and anything standing over a metre high, are walls: snow
	## drapes low decks and crates, never a house.
	if hit_at.y > ground_y + 0.3 and (
		normal.y < 0.7 or hit_at.y > ground_y + 1.0 or not _is_broad(space, hit_at)
	):
		return Vector2(ground_y, 1.0)
	## A floor, deck or crate top: snow lies on it unless a roof covers it.
	var up := PhysicsRayQueryParameters3D.create(hit_at + Vector3.UP * 0.2, hit_at + Vector3.UP * 12.0)
	up.exclude = _exclude()
	if not space.intersect_ray(up).is_empty():
		return Vector2(hit_at.y, 2.0)
	if _terrain != null and hit_at.y <= ground_y + 0.3:
		return Vector2(ground_y, 0.0)
	return Vector2(hit_at.y, 0.0)


## True when a raised surface is wide enough to hold snow, not a rail or post top.
func _is_broad(space: PhysicsDirectSpaceState3D, at: Vector3) -> bool:
	for offset: Vector3 in [Vector3(0.15, 0, 0), Vector3(-0.15, 0, 0), Vector3(0, 0, 0.15), Vector3(0, 0, -0.15)]:
		var query := PhysicsRayQueryParameters3D.create(
			at + offset + Vector3.UP * 0.5, at + offset + Vector3.DOWN * 0.2
		)
		query.exclude = _exclude()
		var hit: Dictionary = space.intersect_ray(query)
		if hit.is_empty() or absf((hit["position"] as Vector3).y - at.y) > 0.05:
			return false
	return true


func _on_node_added(node: Node) -> void:
	if is_instance_of(node, PICKUP_SCRIPT):
		## Its visuals are built in _ready, after node_added fires.
		node.ready.connect(tag_contact.bind(node), CONNECT_ONE_SHOT)
