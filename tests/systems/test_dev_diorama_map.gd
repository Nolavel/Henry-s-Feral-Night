extends SceneTree

## Developer diorama map runtime gate, M-toggle and follow camera contract.

var _failures: int = 0


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	_check(InputMap.has_action(&"toggle_dev_map"), "toggle_dev_map action is missing")
	_check(_action_has_m(), "toggle_dev_map is not bound to physical M")

	await _test_disabled_world_ignores_toggle()
	await _test_enabled_world_toggles_and_follows()

	if _failures > 0:
		push_error("dev diorama map: %d check(s) failed" % _failures)
		quit(1)
		return
	print("dev diorama map: all checks passed")
	quit(0)


func _test_disabled_world_ignores_toggle() -> void:
	var fixture: Dictionary = await _make_fixture(false)
	var map := fixture["map"] as DevDioramaMap
	map._on_toggle_requested()
	_check(not map.is_runtime_toggle_enabled(), "disabled world enabled runtime map")
	_check(not map.is_map_open(), "M opened map while world flag was false")
	_check(not map.visible, "disabled runtime map became visible")
	_dispose(fixture["world"] as Node)
	_dispose(map)


func _test_enabled_world_toggles_and_follows() -> void:
	var fixture: Dictionary = await _make_fixture(true)
	var map := fixture["map"] as DevDioramaMap
	var player := fixture["player"] as Node3D
	var main_camera := fixture["camera"] as Camera3D

	_check(map.is_runtime_toggle_enabled(), "enabled world did not authorize runtime map")
	_check(not map.is_map_open(), "authorized map starts open instead of waiting for M")

	map._on_toggle_requested()
	_check(map.is_map_open() and map.visible, "first M did not open authorized map")
	_check(is_equal_approx(map.get_height_m(), 30.0), "map height is not fixed at 30 m")
	_check(map.get_focus_world().distance_to(player.global_position) < 0.01, "map did not center on Henry")
	_check((main_camera.cull_mask & DevDioramaMap.MAP_LABEL_MASK) == 0, "TPS camera still sees map-only labels")

	map.set_process(false)
	player.global_position += Vector3(20.0, 0.0, -10.0)
	for _i: int in range(20):
		map._process(0.05)
	_check(map.get_focus_world().distance_to(player.global_position) < 0.5, "follow camera did not track Henry")

	map._on_toggle_requested()
	_check(not map.is_map_open() and not map.visible, "second M did not hide authorized map")
	_dispose(fixture["world"] as Node)
	_dispose(map)


func _make_fixture(enabled: bool) -> Dictionary:
	var packed := load("res://scenes/ui/debug/dev_diorama_map.tscn") as PackedScene
	var map := packed.instantiate() as DevDioramaMap
	root.add_child(map)
	await process_frame

	var world := World.new()
	world.name = "World"
	world.enable_runtime_dev_map = enabled
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
	return {"map": map, "world": world, "player": player, "camera": main_camera}


func _action_has_m() -> bool:
	for event: InputEvent in InputMap.action_get_events(&"toggle_dev_map"):
		var key := event as InputEventKey
		if key != null and key.physical_keycode == KEY_M:
			return true
	return false


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
