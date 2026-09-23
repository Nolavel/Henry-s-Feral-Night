class_name FootprintSystem
extends Node3D

## Presses a print into the snow wherever Henry plants a foot. Decals, so the
## prints lie on whatever the ground is made of without touching it.

const LEFT_PRINT: Texture2D = preload("res://assets/textures/snow/footprint_left.png")
const RIGHT_PRINT: Texture2D = preload("res://assets/textures/snow/footprint_right.png")

## Looked up through the world context, never by node path.
const SENSOR_SCRIPT: GDScript = preload("res://scripts/actors/player/henry/components/foot_contact_sensor.gd")
const WEATHER_SCRIPT: GDScript = preload("res://scripts/systems/world/WeatherController.gd")

@export_group("Prints")
## How many prints exist at once; the oldest is reused first.
@export_range(8, 256) var pool_size: int = 64
## Width and length of one print on the ground, in metres.
@export var print_size_m: Vector2 = Vector2(0.13, 0.3)
## Compressed snow reads darker and bluer than the fresh snow around it.
@export var print_tint: Color = Color(0.5, 0.56, 0.68, 0.85)

@export_group("Fill")
## Seconds a print lasts with no snow falling.
@export var lifetime_calm_s: float = 240.0
## Seconds a print lasts in a whiteout, before snowfall buries it.
@export var lifetime_whiteout_s: float = 25.0

var _pool: Array[Decal] = []
var _age: Array[float] = []
var _next: int = 0
var _weather: WeatherController


func on_world_ready(context: WorldContext) -> void:
	_weather = context.get_system(WEATHER_SCRIPT) as WeatherController
	var sensor := context.find_in_scene(SENSOR_SCRIPT) as FootContactSensor
	if sensor != null and not sensor.foot_planted.is_connected(stamp):
		sensor.foot_planted.connect(stamp)


func _process(delta: float) -> void:
	var lifetime: float = _current_lifetime()
	for i: int in range(_pool.size()):
		var decal: Decal = _pool[i]
		if not decal.visible:
			continue
		_age[i] += delta
		var left: float = 1.0 - _age[i] / lifetime
		if left <= 0.0:
			decal.visible = false
			continue
		decal.modulate.a = print_tint.a * left


## Presses one print. Public so tests and other walkers can stamp too.
func stamp(
	side: int, ground: Vector3, forward: Vector3, _speed_mps: float = 0.0
) -> Decal:
	var decal: Decal = _take()
	decal.texture_albedo = LEFT_PRINT if side == FootContactSensor.Side.LEFT else RIGHT_PRINT
	## The print image has the toe at the top, which a decal maps to its -Z.
	var toe := Vector3(forward.x, 0.0, forward.z).normalized()
	if toe.length_squared() < 0.0001:
		toe = Vector3.FORWARD
	var right: Vector3 = Vector3.UP.cross(-toe).normalized()
	decal.global_transform = Transform3D(Basis(right, Vector3.UP, -toe), ground + Vector3.UP * 0.05)
	decal.modulate = print_tint
	decal.visible = true
	return decal


func get_visible_count() -> int:
	var count: int = 0
	for decal: Decal in _pool:
		if decal.visible:
			count += 1
	return count


## Shorter-lived as snow falls harder, so a blizzard buries the trail.
func _current_lifetime() -> float:
	var density: float = 0.0
	if _weather != null:
		density = clampf(_weather.get_snowfall_density(), 0.0, 1.0)
	return lerpf(lifetime_calm_s, lifetime_whiteout_s, density)


func _take() -> Decal:
	if _pool.size() < pool_size:
		var decal := Decal.new()
		decal.size = Vector3(print_size_m.x, 0.25, print_size_m.y)
		decal.upper_fade = 0.2
		decal.lower_fade = 0.2
		add_child(decal)
		_pool.append(decal)
		_age.append(0.0)
		_next = 0
		return decal
	var reused: Decal = _pool[_next]
	_age[_next] = 0.0
	_next = (_next + 1) % _pool.size()
	return reused
