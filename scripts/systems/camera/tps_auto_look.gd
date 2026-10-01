class_name TpsAutoLook
extends RefCounted

## Camera turns the player did not make: recentring behind a walking Henry and
## steering away from walls. All wait for the mouse to rest; none undo themselves.

## Seconds the mouse must rest before any automatic turn starts.
var cooldown: float = 0.9
var recenter_enabled: bool = true
## Recentring speed at full sprint, degrees per second; walking scales it down.
var recenter_rate_deg: float = 90.0
## Heading offsets beyond this are left alone: Henry walks at the camera.
var recenter_max_angle_deg: float = 110.0
## Fastest steer away from an obstacle at the boom's side, degrees per second.
var whisker_rate_deg: float = 45.0
## Fastest turn toward an angle with room for the boom, degrees per second.
var room_rate_deg: float = 120.0

var _idle: float = 0.0


## Feeds this frame's mouse travel; any travel restarts the cooldown.
func note_look(look: Vector2, delta: float) -> void:
	if look.length_squared() > 1e-12:
		_idle = 0.0
	else:
		_idle += delta


func is_active() -> bool:
	return _idle >= cooldown


func get_idle_time() -> float:
	return _idle


## Yaw step toward Henry's heading. Strafing or backing up keeps the camera:
## those keys say the player is placing the view on purpose.
func recenter_step(view_yaw: float, heading_yaw: float, speed_ratio: float, move_axis: Vector2, delta: float) -> float:
	if not recenter_enabled or not is_active() or speed_ratio < 0.05:
		return 0.0
	if absf(move_axis.x) > 0.1 or move_axis.y < -0.1:
		return 0.0
	var diff: float = angle_difference(view_yaw, heading_yaw)
	var limit: float = deg_to_rad(recenter_max_angle_deg)
	if absf(diff) > limit:
		return 0.0
	var weight: float = 1.0 - smoothstep(limit * 0.6, limit, absf(diff))
	var step: float = deg_to_rad(recenter_rate_deg) * speed_ratio * weight * delta
	return signf(diff) * minf(absf(diff), step)


## Yaw step toward the side whose whiskers see more room; rooms are 0..1 for
## booms swung to lower and to higher yaw.
func whisker_step(lower_room: float, higher_room: float, speed_ratio: float, delta: float) -> float:
	if not is_active() or speed_ratio < 0.05:
		return 0.0
	var push: float = higher_room - lower_room
	if absf(push) < 0.15:
		return 0.0
	return signf(push) * deg_to_rad(whisker_rate_deg) * minf(absf(push), 1.0) * delta


## Step of an angle toward `target` at the room-finding rate.
func room_step(offset: float, delta: float) -> float:
	if not is_active():
		return 0.0
	var step: float = deg_to_rad(room_rate_deg) * delta
	return signf(offset) * minf(absf(offset), step)
