class_name WindGusts
extends Node3D

## Wind streaks in Henry's view while the wind is up outdoors: rare in a stiff
## breeze, frequent in a blizzard, and a burst when the weather turns.

## Wind below this shows no streaks, m/s.
const MIN_WIND_MPS: float = 6.0
const MAX_WIND_MPS: float = 17.0
const POOL_SIZE: int = 8
## Seconds between streaks at MIN and at MAX wind.
const SLOW_INTERVAL: float = 2.6
const FAST_INTERVAL: float = 0.6
const BURST_COUNT: int = 5
const BURST_SPACING: float = 0.3
const LIFT_POOL_SIZE: int = 4

var weather: WeatherController
var thermal: ThermalManager
var player: Node3D

var _pool: Array[WindStreak] = []
var _lifts: Array[SnowLift] = []
var _lift_index: int = 0
var _next: float = 0.0
var _burst_left: int = 0
var _search_left: float = 0.0


func _ready() -> void:
	top_level = true
	for i: int in range(POOL_SIZE):
		var streak := WindStreak.new()
		streak.autoplay = false
		streak.visible = false
		streak.width = 0.06
		streak.color = Color(0.95, 0.97, 1.0, 0.7)
		streak.finished.connect(streak.hide)
		add_child(streak)
		_pool.append(streak)
	for i: int in range(LIFT_POOL_SIZE):
		var lift := SnowLift.new()
		add_child(lift)
		_lifts.append(lift)


## Several streaks in quick succession: the moment the weather turns.
func burst() -> void:
	_burst_left = BURST_COUNT
	_next = 0.0


func _process(delta: float) -> void:
	if weather == null or player == null:
		_search_left -= delta
		if _search_left <= 0.0:
			_search_left = 1.0
			_find_systems()
		return
	var wind: float = weather.get_wind_speed_mps()
	if thermal != null and thermal.is_sheltered():
		_burst_left = 0
		return
	if _burst_left <= 0 and wind < MIN_WIND_MPS:
		return
	_next -= delta
	if _next > 0.0:
		return
	_spawn(wind)
	if _burst_left > 0:
		_burst_left -= 1
		_next = BURST_SPACING
	else:
		var t: float = inverse_lerp(MIN_WIND_MPS, MAX_WIND_MPS, clampf(wind, MIN_WIND_MPS, MAX_WIND_MPS))
		_next = lerpf(SLOW_INTERVAL, FAST_INTERVAL, t) * randf_range(0.7, 1.3)


## Places one free streak in front of the camera, running with the wind.
func _spawn(wind: float) -> void:
	var streak: WindStreak = null
	for candidate: WindStreak in _pool:
		if not candidate.visible:
			streak = candidate
			break
	var camera: Camera3D = get_viewport().get_camera_3d()
	if streak == null or camera == null:
		return
	var along: Vector3 = weather.get_wind_direction()
	along.y = 0.0
	along = along.normalized() if along.length() > 0.01 else Vector3.RIGHT
	var ahead: Vector3 = -camera.global_basis.z
	ahead.y = 0.0
	ahead = ahead.normalized()
	var right: Vector3 = ahead.cross(Vector3.UP)
	var centre: Vector3 = player.global_position + ahead * randf_range(4.0, 12.0) \
		+ right * randf_range(-5.0, 5.0) + Vector3.UP * randf_range(0.2, 2.2)
	streak.length = randf_range(4.0, 7.0)
	streak.loop_spread = streak.length * randf_range(0.06, 0.09)
	streak.loop_at = randf_range(0.35, 0.6)
	streak.loop_tilt_deg = randf_range(-35.0, 35.0)
	streak.duration = clampf(24.0 / maxf(wind, 1.0), 1.1, 2.4)
	streak.rebuild_path()
	var side: Vector3 = along.cross(Vector3.UP)
	streak.global_basis = Basis(along, Vector3.UP, side)
	streak.global_position = centre - along * streak.length * 0.5
	streak.play()
	_lift_snow(centre - along * streak.length * 0.3, along, side)


## The gust touches the ground ahead of its streak and lifts loose snow there.
func _lift_snow(above: Vector3, along: Vector3, side: Vector3) -> void:
	var query := PhysicsRayQueryParameters3D.create(above + Vector3.UP * 2.0, above + Vector3.DOWN * 6.0)
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	var lift: SnowLift = _lifts[_lift_index]
	_lift_index = (_lift_index + 1) % _lifts.size()
	lift.global_transform = Transform3D(Basis(along, Vector3.UP, side), hit["position"])
	lift.lift()


func _find_systems() -> void:
	for node: Node in get_tree().root.find_children("*", "", true, false):
		if weather == null and node is WeatherController and not (node as WeatherController).profiles.is_empty():
			weather = node
		elif thermal == null and node is ThermalManager:
			thermal = node
	if player == null:
		player = get_tree().get_first_node_in_group(&"player") as Node3D
