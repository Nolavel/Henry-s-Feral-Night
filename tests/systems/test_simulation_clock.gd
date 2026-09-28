extends SceneTree

## Deterministic clock contract for #131 phase 1.
## Run: godot --headless --script tests/systems/test_simulation_clock.gd

class Probe:
	extends Node
	var priority: int = 1000
	var total: float = 0.0
	var calls: int = 0
	var tag: String = ""
	var trace: Array[String] = []

	func get_simulation_priority() -> int:
		return priority

	func advance_simulation(hours: float, context: SimulationStepContext) -> void:
		total += hours
		calls += 1
		if tag != "":
			trace.append("%s:%.2f:%s" % [tag, context.end_total_hours, String(context.reason)])


var _failures: int = 0
var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_test_midnight_and_load()
	_test_explicit_step_equivalence()
	_test_realtime_equivalence()
	_test_stable_priority_order()
	_test_invalid_advance()
	if _failures > 0:
		push_error("simulation clock: %d check(s) failed" % _failures)
		quit(1)
	else:
		print("simulation clock: deterministic time advance passed")
		quit(0)
	return false


func _clock(start: float = 0.0) -> SimulationClock:
	var clock := SimulationClock.new()
	root.add_child(clock)
	clock.set_total_hours(start, &"test_seed")
	return clock


func _test_midnight_and_load() -> void:
	var clock := _clock(23.75)
	var probe := Probe.new()
	root.add_child(probe)
	clock.register_participant(probe)
	_check(clock.set_total_hours(47.5, &"load"), "load set was refused")
	_check(is_equal_approx(probe.total, 0.0), "load accidentally billed simulation")
	_check(clock.get_day_number() == 2, "47.5 h did not resolve to day 2")
	_check(is_equal_approx(clock.get_hour_of_day(), 23.5), "47.5 h hour-of-day is wrong")
	clock.advance_hours(1.0, &"test")
	_check(clock.get_day_number() == 3, "midnight advance did not enter day 3")
	_check(is_equal_approx(clock.get_hour_of_day(), 0.5), "midnight wrap is wrong")
	_check(is_equal_approx(probe.total, 1.0), "participant did not receive one exact hour")
	_dispose(probe)
	_dispose(clock)


func _test_explicit_step_equivalence() -> void:
	var one := _clock(12.0)
	var one_probe := Probe.new()
	root.add_child(one_probe)
	one.register_participant(one_probe)
	one.advance_hours(8.0, &"sleep")

	var many := _clock(12.0)
	var many_probe := Probe.new()
	root.add_child(many_probe)
	many.register_participant(many_probe)
	for _i: int in range(32):
		many.advance_hours(0.25, &"sleep")

	_check(is_equal_approx(one.get_total_hours(), many.get_total_hours()), "8 h total differs from 32 quarter-hours")
	_check(is_equal_approx(one_probe.total, many_probe.total), "8 h simulation differs from 32 quarter-hours")
	_check(one_probe.calls == 32 and many_probe.calls == 32, "fixed 0.25 h slicing is not stable")
	var a: String = JSON.stringify({"time": one.get_total_hours(), "simulated": one_probe.total, "calls": one_probe.calls})
	var b: String = JSON.stringify({"time": many.get_total_hours(), "simulated": many_probe.total, "calls": many_probe.calls})
	_check(a == b, "same initial state + same elapsed time produced different payload")
	_dispose(one_probe)
	_dispose(one)
	_dispose(many_probe)
	_dispose(many)


func _test_realtime_equivalence() -> void:
	var explicit := _clock()
	var explicit_probe := Probe.new()
	root.add_child(explicit_probe)
	explicit.register_participant(explicit_probe)
	explicit.advance_hours(1.0, &"walk")

	var realtime := _clock()
	var realtime_probe := Probe.new()
	root.add_child(realtime_probe)
	realtime.register_participant(realtime_probe)
	for _i: int in range(100):
		realtime.advance_hours(0.01, SimulationClock.REALTIME_REASON)
	realtime.flush_realtime()

	_check(is_equal_approx(realtime.get_total_hours(), 1.0), "100 realtime slices did not reach one hour")
	_check(is_equal_approx(realtime_probe.total, explicit_probe.total), "realtime-equivalent hour bills a different amount")
	_check(realtime_probe.calls == explicit_probe.calls, "realtime and explicit advances use different fixed steps")
	_dispose(explicit_probe)
	_dispose(explicit)
	_dispose(realtime_probe)
	_dispose(realtime)


func _test_stable_priority_order() -> void:
	var clock := _clock()
	var trace: Array[String] = []
	for spec: Dictionary in [
		{"tag": "thermal", "priority": 300},
		{"tag": "weather_a", "priority": 100},
		{"tag": "weather_b", "priority": 100},
		{"tag": "metabolism", "priority": 400},
	]:
		var probe := Probe.new()
		probe.tag = spec["tag"]
		probe.priority = int(spec["priority"])
		probe.trace = trace
		root.add_child(probe)
		clock.register_participant(probe)
	clock.advance_hours(0.25, &"order")
	_check(trace.size() == 4, "not every participant ran")
	if trace.size() == 4:
		_check(trace[0].begins_with("weather_a"), "priority 100 did not run first")
		_check(trace[1].begins_with("weather_b"), "equal priority lost registration order")
		_check(trace[2].begins_with("thermal"), "thermal priority did not run after weather")
		_check(trace[3].begins_with("metabolism"), "metabolism priority did not run last")
	_dispose(clock)


func _test_invalid_advance() -> void:
	var clock := _clock(5.0)
	_check(not clock.advance_hours(0.0, &"zero"), "zero advance was accepted")
	_check(not clock.advance_hours(-1.0, &"negative"), "negative advance was accepted")
	_check(not clock.set_total_hours(-2.0, &"load"), "negative absolute time was accepted")
	_check(is_equal_approx(clock.get_total_hours(), 5.0), "invalid input changed the clock")
	_dispose(clock)


func _dispose(node: Node) -> void:
	if node == null:
		return
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	node.free()


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("simulation clock: " + message)
