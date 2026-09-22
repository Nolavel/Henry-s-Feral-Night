class_name IceField
extends Node3D

## The frozen sea around the island. Only tiles near the player are simulated,
## so this costs the same whether the bay is one hectare or twenty.

## Emitted when a tile enters a worse stage than it was in.
signal stage_changed(tile: Vector2i, stage: Stage)
## Emitted continuously for the tile under the player, for shader and audio.
signal load_tile_changed(tile: Vector2i, integrity: float, stage: Stage)
## Emitted once when a tile gives way, with the world position of the hole.
signal tile_broke(tile: Vector2i, world_position: Vector3)

## Feedback ladder. Audio lands before visuals, so CREAK precedes CRACK.
enum Stage { SOLID, CREAKING, CRACKING, BROKEN }

## How the player is moving, which scales how hard they load the ice.
enum Gait { STILL, CROUCH, WALK, SPRINT }

@export_group("Data")
## Tuning resource. Without one the field refuses to simulate.
@export var profile: IceProfile
## Island outline on the XZ plane. Ice is everything outside it.
@export var shore_polygon: PackedVector2Array = PackedVector2Array()

@export_group("Wiring")
## Body whose position loads the ice; usually Henry.
@export var tracked_body: Node3D

var _integrity: Dictionary = {}
var _stages: Dictionary = {}
var _broken: Dictionary = {}
var _current_tile: Vector2i = Vector2i(2147483647, 2147483647)
var _gait: Gait = Gait.STILL
var _enabled: bool = true


## Tile coordinates containing a world position.
func world_to_tile(world_position: Vector3) -> Vector2i:
	var size: float = _tile_size()
	return Vector2i(int(floor(world_position.x / size)), int(floor(world_position.z / size)))


## World position of a tile's centre, at this field's height.
func tile_to_world(tile: Vector2i) -> Vector3:
	var size: float = _tile_size()
	return Vector3(
		(float(tile.x) + 0.5) * size, global_position.y, (float(tile.y) + 0.5) * size
	)


## Metres from the island outline; negative means the point is on land.
func distance_to_shore(point: Vector2) -> float:
	if shore_polygon.size() < 3:
		return INF
	var nearest: float = INF
	var count: int = shore_polygon.size()
	for i: int in range(count):
		var a: Vector2 = shore_polygon[i]
		var b: Vector2 = shore_polygon[(i + 1) % count]
		nearest = minf(nearest, _distance_to_segment(point, a, b))
	return -nearest if Geometry2D.is_point_in_polygon(point, shore_polygon) else nearest


## Integrity a tile starts with, from how far out to sea it sits.
func get_base_thickness(tile: Vector2i) -> float:
	if profile == null:
		return 1.0
	var centre: Vector3 = tile_to_world(tile)
	var distance: float = distance_to_shore(Vector2(centre.x, centre.z))
	if distance <= profile.solid_until_m:
		return 1.0
	var span: float = maxf(0.001, profile.thinnest_from_m - profile.solid_until_m)
	var t: float = clampf((distance - profile.solid_until_m) / span, 0.0, 1.0)
	return lerpf(1.0, profile.minimum_thickness, t)


## Current integrity of a tile, 1.0 solid to 0.0 gone.
func get_integrity(tile: Vector2i) -> float:
	if _broken.has(tile):
		return 0.0
	if _integrity.has(tile):
		return _integrity[tile]
	return get_base_thickness(tile)


## Feedback stage a tile is in right now.
func get_stage(tile: Vector2i) -> Stage:
	if _broken.has(tile):
		return Stage.BROKEN
	return _stage_for(get_integrity(tile))


## True once a tile has given way; broken tiles never come back.
func is_broken(tile: Vector2i) -> bool:
	return _broken.has(tile)


## Tile the tracked body is standing on.
func get_current_tile() -> Vector2i:
	return _current_tile


## Sets how hard the body is loading the ice.
func set_gait(gait: Gait) -> void:
	_gait = gait


## Stops the field simulating, for cutscenes and for the player in the water.
func set_enabled(enabled: bool) -> void:
	_enabled = enabled


## Tiles currently simulated: the active window around the player.
func get_active_tiles() -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	if profile == null:
		return tiles
	var radius: int = maxi(0, profile.active_radius_tiles)
	for dx: int in range(-radius, radius + 1):
		for dz: int in range(-radius, radius + 1):
			tiles.append(_current_tile + Vector2i(dx, dz))
	return tiles


func _physics_process(delta: float) -> void:
	if not _enabled or tracked_body == null:
		return
	step(tracked_body.global_position, delta)


## Advances the field for one step. Public so tests drive it without frames.
func step(body_position: Vector3, delta: float) -> void:
	if profile == null:
		return
	_current_tile = world_to_tile(body_position)
	_apply_load(_current_tile, delta)
	_recover_window(delta)


## Drains the loaded tile and escalates it through the ladder.
func _apply_load(tile: Vector2i, delta: float) -> void:
	if _broken.has(tile):
		return
	var drain: float = profile.drain_per_second * _gait_multiplier() * delta
	var value: float = maxf(0.0, get_integrity(tile) - drain)
	_integrity[tile] = value
	_settle(tile, value)
	load_tile_changed.emit(tile, value, get_stage(tile))


## Restores every simulated tile the player is not standing on.
func _recover_window(delta: float) -> void:
	var recovery: float = profile.recovery_per_second * delta
	for tile: Vector2i in get_active_tiles():
		if tile == _current_tile or _broken.has(tile) or not _integrity.has(tile):
			continue
		var ceiling: float = get_base_thickness(tile)
		var value: float = minf(ceiling, _integrity[tile] + recovery)
		_integrity[tile] = value
		_settle(tile, value)


## Reports a tile's new stage, and breaks it through the floor exactly once.
func _settle(tile: Vector2i, value: float) -> void:
	var stage: Stage = _stage_for(value)
	if value <= profile.break_at:
		if _broken.has(tile):
			return
		_broken[tile] = true
		_stages[tile] = Stage.BROKEN
		stage_changed.emit(tile, Stage.BROKEN)
		tile_broke.emit(tile, tile_to_world(tile))
		return
	if _stages.get(tile, Stage.SOLID) == stage:
		return
	_stages[tile] = stage
	stage_changed.emit(tile, stage)


func _stage_for(value: float) -> Stage:
	if value <= profile.break_at:
		return Stage.BROKEN
	if value < profile.crack_below:
		return Stage.CRACKING
	if value < profile.creak_below:
		return Stage.CREAKING
	return Stage.SOLID


func _gait_multiplier() -> float:
	match _gait:
		Gait.SPRINT:
			return profile.sprint_multiplier
		Gait.WALK:
			return profile.walk_multiplier
		Gait.CROUCH:
			return profile.crouch_multiplier
		_:
			return 1.0


func _tile_size() -> float:
	return profile.tile_size_m if profile != null else 4.0


## Shortest distance from a point to a segment, used for the shore outline.
func _distance_to_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var length_squared: float = ab.length_squared()
	if length_squared < 0.000001:
		return point.distance_to(a)
	var t: float = clampf((point - a).dot(ab) / length_squared, 0.0, 1.0)
	return point.distance_to(a + ab * t)
