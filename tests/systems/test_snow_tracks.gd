extends SceneTree

## Packed snow that leaves the window is kept in world tiles and comes back
## filled in for its age. Run: godot --headless --script tests/systems/test_snow_tracks.gd

var _failures: int = 0


func _process(_delta: float) -> bool:
	_test_a_trail_comes_back_filled_for_its_age()
	_test_the_staying_window_is_not_filed()
	_test_tracks_survive_a_save()
	_test_the_shell_saves_its_tracks()
	if _failures > 0:
		push_error("snow tracks: %d check(s) failed" % _failures)
		quit(1)
		return true
	print("snow tracks: all checks passed")
	quit(0)
	return true


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("snow tracks: %s" % message)


## A 25.6 m window at 1024 texels with a 0.3 m deep trail along one column band.
func _trail() -> Image:
	var img := Image.create_empty(1024, 1024, false, Image.FORMAT_RF)
	for y: int in range(1024):
		for x: int in range(200, 260):
			img.set_pixel(x, y, Color(0.3, 0, 0))
	return img


func _test_a_trail_comes_back_filled_for_its_age() -> void:
	var store := SnowTrackStore.new()
	var origin := Vector2(-12.8, -12.8)
	store.store(_trail(), origin, 25.6, Rect2())
	var fresh: Image = store.restore(origin, 25.6, 256)
	var deep: float = fresh.get_pixel(57, 128).r
	_check(absf(deep - 0.3) < 0.01, "a fresh trail came back %.3f m deep, not 0.3" % deep)
	_check(fresh.get_pixel(150, 128).r < 0.005, "packing appeared off the trail")
	for i: int in range(600):
		store.advance(0.001)
	var aged: float = store.restore(origin, 25.6, 256).get_pixel(57, 128).r
	var expect: float = 0.3 * pow(0.999, 600)
	_check(absf(aged - expect) < 0.01, "an aged trail came back %.3f m, expected %.3f" % [aged, expect])


func _test_the_staying_window_is_not_filed() -> void:
	var store := SnowTrackStore.new()
	var origin := Vector2(0.0, 0.0)
	store.store(_trail(), origin, 25.6, Rect2(Vector2(9.6, 0.0), Vector2(25.6, 25.6)))
	var keys: Array = store.tiles.keys()
	_check(not keys.is_empty(), "the tiles leaving the window were not filed")
	for key: Vector2i in keys:
		_check(key.x < 3, "tile %s is still on screen but was filed" % key)


func _test_tracks_survive_a_save() -> void:
	var store := SnowTrackStore.new()
	store.store(_trail(), Vector2(-12.8, -12.8), 25.6, Rect2())
	store.advance(0.3)
	var copy := SnowTrackStore.new()
	copy.load_save_data(JSON.parse_string(JSON.stringify(store.get_save_data())))
	_check(copy.tiles.size() == store.tiles.size(), "tiles were lost in a save")
	_check(is_equal_approx(copy.clock, store.clock), "the fill clock was lost in a save")
	var a: float = store.restore(Vector2(-12.8, -12.8), 25.6, 256).get_pixel(57, 128).r
	var b: float = copy.restore(Vector2(-12.8, -12.8), 25.6, 256).get_pixel(57, 128).r
	_check(absf(a - b) < 0.001, "a loaded trail differs from the saved one")


func _test_the_shell_saves_its_tracks() -> void:
	var shell: Node = load("res://scripts/systems/world/snow/snow_shell.gd").new()
	_check(SaveManager.implements_save_contract(shell), "the snow shell is not a save participant")
	shell.free()
