extends SceneTree

## Developer diorama map follow-only camera contract.
## Visual label placement is verified by the preview capture job.

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
	var main_camera := Camera3D.new()
	world.add_child(main_camera)

	var context := WorldContext.new()
	context.world = world
	context.player = player
	context.camera = main_camera
	map.on_world_ready(context)
	map.set_process(false)
	map._process(0.1)

	_check(is_equal_approx(map.get_height_m(), 30.0), "map height is not fixed at 30 m")
	_check(map.get_focus_world().distance_to(player.global_position) < 0.01, "map did not start centered on Henry")
	_check((main_camera.cull_mask & DevDioramaMap.MAP_LABEL_MASK) == 0, "TPS camera still sees map-only labels")

	player.global_position += Vector3(20.0, 0.0, -10.0)
	for _i: int in range(20):
		map._process(0.05)
	_check(map.get_focus_world().distance_to(player.global_position) < 0.5, "follow camera did not track Henry")

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
