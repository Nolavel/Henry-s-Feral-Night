extends SceneTree

## Stove (#42): one log shows per fuel unit left, the door slots glow only while
## the fire burns, and a cold empty stove shows no logs.
## Run: godot --headless --script tests/systems/test_stove_visual.gd

var _failures: int = 0
var _frame: int = 0


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		var stove := HeatSource.new()
		stove.starts_burning = false
		stove.burn_duration_h = 6.0
		stove.hours_per_fuel_unit = 2.0
		var visual := StoveVisual.new()
		stove.add_child(visual)
		root.add_child(stove)
		_check(visual.get_visible_log_count() == 0 and not visual.is_glowing(), "a cold empty stove shows logs or glow")
		stove.ignite()
		_check(visual.get_visible_log_count() == 3, "a full 6 h load does not show 3 logs (%d)" % visual.get_visible_log_count())
		_check(visual.is_glowing(), "a burning stove does not glow")
		stove.restore_fuel(1.5, true)
		_check(visual.get_visible_log_count() == 1, "1.5 h left does not show 1 log")
		stove.extinguish()
		_check(not visual.is_glowing(), "an extinguished stove still glows")
		print("test_stove_visual: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
		quit(1 if _failures > 0 else 0)
	return false


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)
