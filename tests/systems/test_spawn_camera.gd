extends SceneTree

## Camera ready runs before World applies the marker; the first view must use
## the final spawn heading, and later initialization must preserve mouse look.

var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	var world := World.new()
	world.streaming_enabled = false
	var player := CharacterBody3D.new()
	player.name = "Player"
	player.rotation.y = deg_to_rad(90.0)
	world.add_child(player)
	var camera := TpsCamera.new()
	camera.name = "PlayerCamera"
	camera.player = player
	camera.start_pitch_deg = -17.0
	world.add_child(camera)
	var marker := Marker3D.new()
	marker.position = Vector3(1420, 1.21, -943)
	marker.rotation.y = deg_to_rad(132.0)
	world.add_child(marker)
	world.first_spawner_marker = marker
	root.add_child(world)
	var ready_yaw: float = camera.get_yaw()
	world.initialize()
	var passed: bool = is_equal_approx(ready_yaw, deg_to_rad(90.0))
	passed = passed and is_equal_approx(camera.get_yaw(), player.global_rotation.y)
	passed = passed and is_equal_approx(camera._pitch_deg, -17.0)
	passed = passed and world.first_spawner_marker == null
	camera.set_look(deg_to_rad(45.0), -25.0)
	world.initialize()
	passed = passed and is_equal_approx(camera.get_yaw(), deg_to_rad(45.0))
	passed = passed and is_equal_approx(camera._pitch_deg, -25.0)
	world.free()
	if passed:
		print("spawn camera: PASS (marker heading, initial pitch, idempotent mouse look)")
	else:
		push_error("spawn camera: stale spawn heading or initialization reset mouse look")
	quit(0 if passed else 1)
	return false
