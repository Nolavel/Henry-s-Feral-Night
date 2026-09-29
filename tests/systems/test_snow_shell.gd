extends SceneTree

## Covers the snow shell's print field: packed snow under the foot, broken
## crust around it, fill-in over time, and prints kept when the window moves.
## Run: godot --headless --script tests/systems/test_snow_shell.gd

const SHELL_SCRIPT: GDScript = preload("res://scripts/systems/world/snow/snow_shell.gd")

var _failures: int = 0


func _process(_delta: float) -> bool:
	_run()
	return true


func _run() -> void:
	_test_a_print_packs_snow_and_breaks_the_crust()
	_test_the_crust_breaks_at_different_heights()
	_test_a_sprint_packs_deeper()
	_test_prints_fill_in()
	_test_prints_survive_a_recentre()
	_test_the_world_builds_it()
	if _failures > 0:
		push_error("snow shell: %d check(s) failed" % _failures)
		quit(1)
		return
	print("snow shell: all checks passed")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("snow shell: %s" % message)


func _shell() -> SnowShell:
	var shell: SnowShell = SHELL_SCRIPT.new()
	root.add_child(shell)
	shell.recentre_to(Vector2.ZERO)
	return shell


func _dispose(node: Node) -> void:
	root.remove_child(node)
	node.free()


func _test_a_print_packs_snow_and_breaks_the_crust() -> void:
	var shell: SnowShell = _shell()
	_check(shell.get_carve_at(0.0, 0.0) == 0.0, "fresh snow is already packed")
	shell.press(0, Vector3.ZERO, Vector3.UP, Vector3.FORWARD, 2.0)
	_check(shell.get_carve_at(0.0, 0.0) > 0.5, "the foot did not pack the snow down")
	_check(shell.get_carve_at(0.0, 0.0) < 1.0, "the foot went through the ground")
	var rim: float = 0.0
	for a: int in range(16):
		var at: Vector2 = Vector2(0.11, 0.0).rotated(a * TAU / 16.0)
		rim = maxf(rim, shell.get_rim_at(at.x, at.y))
	_check(rim > 0.05, "no crust was pushed up around the print")
	_check(shell.get_rim_at(0.0, 0.0) == 0.0, "crust rose inside the print")
	_dispose(shell)


func _test_the_crust_breaks_at_different_heights() -> void:
	var shell: SnowShell = _shell()
	shell.press(0, Vector3.ZERO, Vector3.UP, Vector3.FORWARD, 2.0)
	var low: float = INF
	var high: float = 0.0
	for a: int in range(32):
		var at: Vector2 = Vector2(0.0, -0.22).rotated(a * TAU / 32.0)
		var rim: float = shell.get_rim_at(at.x * 0.5, at.y)
		low = minf(low, rim)
		high = maxf(high, rim)
	_check(high - low > 0.04, "the crust rose evenly all round instead of breaking")
	_dispose(shell)


func _test_a_sprint_packs_deeper() -> void:
	var shell: SnowShell = _shell()
	shell.press(0, Vector3(-2, 0, 0), Vector3.UP, Vector3.FORWARD, 2.0)
	shell.press(0, Vector3(2, 0, 0), Vector3.UP, Vector3.FORWARD, 7.0)
	_check(shell.get_carve_at(2.0, 0.0) > shell.get_carve_at(-2.0, 0.0), "a sprint packed no deeper")
	_dispose(shell)


func _test_prints_fill_in() -> void:
	var shell: SnowShell = _shell()
	shell.press(0, Vector3.ZERO, Vector3.UP, Vector3.FORWARD, 2.0)
	var fresh: float = shell.get_carve_at(0.0, 0.0)
	shell._process(shell.fill_calm_s * 0.5)
	var half: float = shell.get_carve_at(0.0, 0.0)
	_check(half < fresh and half > 0.0, "a print did not partly fill after half its fill time")
	shell._process(shell.fill_calm_s)
	_check(shell.get_carve_at(0.0, 0.0) == 0.0, "a print never filled in")
	_dispose(shell)


func _test_prints_survive_a_recentre() -> void:
	var shell: SnowShell = _shell()
	## Every texel of one print, including edge cells and random clods.
	var points: Array[Vector2] = []
	for iz: int in range(-8, 9):
		for ix: int in range(-4, 5):
			points.append(Vector2(3.0 + ix * 0.025, 1.0 + iz * 0.025))
	shell.press(0, Vector3(3, 0, 1), Vector3.UP, Vector3.FORWARD, 2.0)
	var before: PackedFloat32Array = []
	for at: Vector2 in points:
		before.append(shell.get_carve_at(at.x, at.y) + shell.get_rim_at(at.x, at.y))
	_check(shell.get_carve_at(3.0, 1.0) > 0.5, "no print to carry across the move")
	shell.recentre_to(Vector2(6.4, 3.2))
	_check(shell.get_origin().is_equal_approx(Vector2(-6.4, -9.6)), "the window did not move")
	var moved: int = 0
	for i: int in range(points.size()):
		var at: Vector2 = points[i]
		if not is_equal_approx(shell.get_carve_at(at.x, at.y) + shell.get_rim_at(at.x, at.y), before[i]):
			moved += 1
	_check(moved == 0, "%d print texels moved or vanished with the window" % moved)
	_dispose(shell)


func _test_the_world_builds_it() -> void:
	var source: String = FileAccess.get_file_as_string("res://world/world.gd")
	_check(source.contains("snow/snow_shell.gd"), "world.gd does not build the snow shell")
