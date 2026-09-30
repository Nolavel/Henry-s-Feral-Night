extends SceneTree

## Developer diorama map state transitions and camera contract.
## No rendering assertion: CI screenshots cover the actual shared-world view.

var _failures: int = 0


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var packed := load("res://scenes/ui/debug/dev_diorama_map.tscn") as PackedScene
	var map := packed.instantiate() as DevDioramaMap
	root.add_child(map)
	await process_frame

	var world := Node3D.new()
	world.name = "World"
	root.add_child(world)
	var player := Node3D.new()
	player.name = "Player"
	player.global_position = Vector3(12.0, 2.0, -8.0)
	world.add_child(player)

	var context := WorldContext.new()
	context.world = world
	context.player = player
	map.on_world_ready(context)
	map.set_process(false)
	map._process(0.1)

	_check(map.get_mode() == DevDioramaMap.Mode.FOLLOW, "map did not start in FOLLOW")
	_check(is_equal_approx(map.get_height_m(), 30.0), "default map height is not 30 m")
	_check(map.get_focus_world().distance_to(player.global_position) < 0.01, "FOLLOW is not centered on Henry")

	var free_focus := player.global_position + Vector3(18.0, 0.0, -11.0)
	map.set_free_focus(free_focus)
	_check(map.get_mode() == DevDioramaMap.Mode.FREE, "explicit free focus did not enter FREE")
	_check(Vector2(map.get_focus_world().x, map.get_focus_world().z).distance_to(Vector2(free_focus.x, free_focus.z)) < 0.01,
		"FREE focus moved away from the requested world point")

	map.recenter()
	_check(map.get_mode() == DevDioramaMap.Mode.RECENTERING, "CENTER did not enter RECENTERING")
	for _i: int in range(10):
		map._process(0.05)
	_check(map.get_mode() == DevDioramaMap.Mode.FOLLOW, "recenter did not return to FOLLOW")
	_check(map.get_focus_world().distance_to(player.global_position) < 0.05, "recenter did not return to Henry")

	_dispose(map)
	_dispose(world)
	if _failures > 0:
		push_error("dev diorama map: %d check(s) failed" % _failures)
		quit(1)
		return
	print("dev diorama map: all checks passed")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("dev diorama map: %s" % message)


func _dispose(node: Node) -> void:
	if node == null:
		return
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	node.free()
