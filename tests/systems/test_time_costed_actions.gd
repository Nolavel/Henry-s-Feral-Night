extends SceneTree

## Phase 2 contract: one owner for action lifecycle and game-time cost.
## Run: godot --headless --script tests/systems/test_time_costed_actions.gd

class Probe:
	extends Node
	var total: float = 0.0
	func get_simulation_priority() -> int:
		return 200
	func advance_simulation(hours: float, _context: SimulationStepContext) -> void:
		total += hours


var _failures: int = 0
var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_test_instant_exact_time()
	_test_early_stop()
	_test_staged_action_blocks_realtime()
	_test_cancel_releases_clock()
	if _failures > 0:
		push_error("time-costed actions: %d check(s) failed" % _failures)
		quit(1)
	else:
		print("time-costed actions: lifecycle and clock ownership passed")
		quit(0)
	return false


func _rig() -> Dictionary:
	var clock := SimulationClock.new()
	root.add_child(clock)
	clock.set_total_hours(12.0, &"seed")
	var probe := Probe.new()
	root.add_child(probe)
	clock.register_participant(probe)
	var actions := TimeCostedActionSystem.new()
	actions.simulation_clock = clock
	root.add_child(actions)
	return {"clock": clock, "probe": probe, "actions": actions}


func _test_instant_exact_time() -> void:
	var rig: Dictionary = _rig()
	var clock := rig["clock"] as SimulationClock
	var probe := rig["probe"] as Probe
	var actions := rig["actions"] as TimeCostedActionSystem
	var request := TimeActionRequest.new()
	request.action_id = &"sleep"
	request.duration_hours = 2.0
	request.reason = &"sleep"
	request.simulation_step_hours = 0.25
	var result: Dictionary = actions.run_to_completion(request)
	_check(bool(result["completed"]), "instant action did not complete")
	_check(is_equal_approx(float(result["elapsed_hours"]), 2.0), "instant action elapsed wrong time")
	_check(is_equal_approx(clock.get_total_hours(), 14.0), "instant action did not advance canonical time")
	_check(is_equal_approx(probe.total, 2.0), "simulation participant did not receive action time")
	_check(not clock.is_realtime_blocked(), "completed action left realtime blocked")
	_dispose_rig(rig)


func _test_early_stop() -> void:
	var rig: Dictionary = _rig()
	var actions := rig["actions"] as TimeCostedActionSystem
	var probe := rig["probe"] as Probe
	var request := TimeActionRequest.new()
	request.action_id = &"wait"
	request.duration_hours = 3.0
	request.reason = &"wait"
	request.simulation_step_hours = 0.25
	request.stop_check = func() -> StringName:
		return &"recovered" if probe.total >= 0.5 - 0.0001 else &""
	var result: Dictionary = actions.run_to_completion(request)
	_check(not bool(result["completed"]), "early-stopped action reported completion")
	_check(StringName(result["reason"]) == &"recovered", "early stop lost its reason")
	_check(is_equal_approx(float(result["elapsed_hours"]), 0.5), "early stop was not deterministic at 0.5 h")
	_check(not (rig["clock"] as SimulationClock).is_realtime_blocked(), "early stop left realtime blocked")
	_dispose_rig(rig)


func _test_staged_action_blocks_realtime() -> void:
	var rig: Dictionary = _rig()
	var clock := rig["clock"] as SimulationClock
	var actions := rig["actions"] as TimeCostedActionSystem
	var request := TimeActionRequest.new()
	request.action_id = &"repair"
	request.duration_hours = 0.5
	request.presentation_seconds = 4.0
	request.reason = &"repair"
	request.simulation_step_hours = 0.25
	_check(actions.start_action(request), "staged action refused to start")
	_check(clock.is_realtime_blocked(), "staged action did not own realtime")
	var before: float = clock.get_total_hours()
	_check(not clock.advance_hours(0.1, SimulationClock.REALTIME_REASON), "realtime advanced under controlled action")
	_check(is_equal_approx(clock.get_total_hours(), before), "blocked realtime still changed canonical time")
	actions._process(2.0)
	_check(is_equal_approx(clock.get_total_hours(), before + 0.25), "half presentation did not bill half action time")
	actions._process(2.0)
	_check(not actions.is_active(), "staged action did not complete")
	_check(is_equal_approx(clock.get_total_hours(), before + 0.5), "staged action did not bill declared duration")
	_check(not clock.is_realtime_blocked(), "staged completion left realtime blocked")
	_dispose_rig(rig)


func _test_cancel_releases_clock() -> void:
	var rig: Dictionary = _rig()
	var clock := rig["clock"] as SimulationClock
	var actions := rig["actions"] as TimeCostedActionSystem
	var request := TimeActionRequest.new()
	request.action_id = &"chop"
	request.duration_hours = 0.5
	request.presentation_seconds = 4.0
	request.reason = &"chop"
	request.simulation_step_hours = 0.25
	actions.start_action(request)
	actions._process(1.0)
	_check(actions.cancel(&"moved"), "interruptible action refused cancellation")
	_check(not actions.is_active(), "cancelled action stayed active")
	_check(not clock.is_realtime_blocked(), "cancelled action left realtime blocked")
	_check(clock.advance_hours(0.25, SimulationClock.REALTIME_REASON), "realtime did not resume after cancel")
	_dispose_rig(rig)


func _dispose_rig(rig: Dictionary) -> void:
	for key: String in ["actions", "probe", "clock"]:
		_dispose(rig[key] as Node)


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
	push_error("time-costed actions: " + message)
