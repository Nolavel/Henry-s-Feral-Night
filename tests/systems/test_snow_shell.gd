extends SceneTree

## Covers SnowField, the one answer to how much snow lies where: realistic
## depth, lee piles behind obstacles, none at the water, and Henry wading slower.
## Run: godot --headless --script tests/systems/test_snow_shell.gd

const SHELL_SCRIPT: GDScript = preload("res://scripts/systems/world/snow/snow_shell.gd")

var _failures: int = 0


func _process(_delta: float) -> bool:
	_run()
	return true


func _run() -> void:
	_test_depth_is_realistic_and_never_negative()
	_test_snow_piles_in_the_lee_of_an_obstacle()
	_test_no_snow_at_or_below_the_water()
	_test_windward_slopes_are_scoured()
	_test_a_recentre_keeps_the_field_on_the_world()
	_test_deeper_snow_is_slower()
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


func _field(sampler: Callable) -> SnowField:
	var field := SnowField.new()
	field.ground_sampler = sampler
	field.sea_level_m = -100.0
	return field


func _flat(at: Vector2) -> Vector2:
	return Vector2(5.0, 0.0)


func _test_depth_is_realistic_and_never_negative() -> void:
	var field: SnowField = _field(_flat)
	field.rebuild(Vector2(-12.8, -12.8), 1.0, Vector2(0, -1))
	var deepest: float = 0.0
	for tz: int in range(-12, 13):
		for tx: int in range(-12, 13):
			var d: float = field.get_depth(tx, tz)
			_check(d >= 0.0, "negative snow depth at %d,%d" % [tx, tz])
			deepest = maxf(deepest, d)
	_check(deepest > 0.1 and deepest < 0.7, "open-ground depth %.2f m is not a real snowpack" % deepest)
	_check(is_equal_approx(field.get_snow_top(0, 0), 5.0 + field.get_depth(0, 0)), "top is not ground + depth")


func _test_snow_piles_in_the_lee_of_an_obstacle() -> void:
	## A box at z in [-1, 0]; the wind blows towards +z.
	var boxed := func(at: Vector2) -> Vector2:
		return Vector2(0.0, 1.0 if absf(at.x) < 2.0 and at.y > -1.0 and at.y < 0.0 else 0.0)
	var field: SnowField = _field(boxed)
	field.rebuild(Vector2(-12.8, -12.8), 1.0, Vector2(0, 1))
	var lee: float = field.get_depth(0.0, 1.2)
	var upwind: float = field.get_depth(0.0, -3.0)
	_check(lee > upwind + 0.2, "no lee pile: %.2f behind vs %.2f upwind" % [lee, upwind])


func _test_no_snow_at_or_below_the_water() -> void:
	var shore := func(at: Vector2) -> Vector2:
		return Vector2(at.x * 0.2, 0.0)
	var field: SnowField = _field(shore)
	field.sea_level_m = 0.0
	field.rebuild(Vector2(-12.8, -12.8), 1.0, Vector2(0, -1))
	_check(field.get_depth(-3.0, 0.0) == 0.0, "snow lies under the water")
	_check(field.get_depth(0.05, 0.0) < 0.02, "snow does not thin out at the water's edge")
	_check(field.get_depth(8.0, 0.0) > 0.1, "no snow well above the water")


func _test_windward_slopes_are_scoured() -> void:
	## Ground rises towards +z; the wind blows towards +z, into the slope.
	var slope := func(at: Vector2) -> Vector2:
		return Vector2(at.y * 0.6, 0.0)
	var into := _field(slope)
	into.rebuild(Vector2(-12.8, -12.8), 1.0, Vector2(0, 1))
	var away := _field(slope)
	away.rebuild(Vector2(-12.8, -12.8), 1.0, Vector2(0, -1))
	var windward: float = 0.0
	var leeward: float = 0.0
	for tx: int in range(-8, 9):
		windward += into.get_depth(tx, 0.0)
		leeward += away.get_depth(tx, 0.0)
	_check(windward < leeward * 0.8, "the windward face keeps as much snow as the lee face")


func _test_a_recentre_keeps_the_field_on_the_world() -> void:
	var field: SnowField = _field(_flat)
	field.rebuild(Vector2(-12.8, -12.8), 1.0, Vector2(0, -1))
	var before: float = field.get_depth(3.0, 1.0)
	field.rebuild(Vector2(-6.4, -9.6), 1.0, Vector2(0, -1))
	_check(is_equal_approx(field.get_depth(3.0, 1.0), before), "depth at a world point changed when the window moved")


func _test_deeper_snow_is_slower() -> void:
	var shell: SnowShell = SHELL_SCRIPT.new()
	var last: float = 2.0
	for i: int in range(0, 11):
		var m: float = shell.get_speed_multiplier(i * 0.06)
		_check(m <= last, "deeper snow was faster at %.2f m" % (i * 0.06))
		last = m
	_check(is_equal_approx(shell.get_speed_multiplier(0.0), 1.0), "bare ground slows Henry")
	_check(shell.get_speed_multiplier(1.0) < 0.7, "waist-deep snow barely slows Henry")
	shell.free()


func _test_the_world_builds_it() -> void:
	var source: String = FileAccess.get_file_as_string("res://world/world.gd")
	_check(source.contains("snow/snow_shell.gd"), "world.gd does not build the snow shell")
