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
	_test_player_mode_and_callbacks()
	_test_non_interruptible_action()
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


func _test_player_mode_and_callbacks() -> void:
	var state: Node = root.get_node_or_null(^"PlayerState")
	_check(state != null, "PlayerState autoload missing")
	if state == null:
		return
	state.set_mode(state.Mode.ON_FOOT)

	var rig: Dictionary = _rig()
	var actions := rig["actions"] as TimeCostedActionSystem
	var completed: Array[float] = []
	var seen_modes: Array[int] = []
	var progress: Array[float] = []
	actions.action_started.connect(
		func(_id: StringName, _duration: float) -> void: seen_modes.append(int(state.mode))
	)
	actions.action_progress.connect(
		func(_id: StringName, value: float) -> void: progress.append(value)
	)

	var request := TimeActionRequest.new()
	request.action_id = &"sleep"
	request.duration_hours = 1.0
	request.reason = &"sleep"
	request.player_mode = state.Mode.SLEEPING
	request.interruptible = false
	request.on_complete = func(elapsed: float) -> void: completed.append(elapsed)

	var result: Dictionary = actions.run_to_completion(request)
	_check(bool(result["completed"]), "sleep action did not complete")
	_check(seen_modes.size() == 1 and seen_modes[0] == state.Mode.SLEEPING, "action_started did not observe SLEEPING mode")
	_check(state.mode == state.Mode.ON_FOOT, "completed action did not restore prior PlayerState")
	_check(completed.size() == 1 and is_equal_approx(completed[0], 1.0), "on_complete did not run exactly once")
	_check(not progress.is_empty() and is_equal_approx(progress.back(), 1.0), "progress did not finish at 1.0")
	_dispose_rig(rig)


func _test_non_interruptible_action() -> void:
	var state: Node = root.get_node_or_null(^"PlayerState")
	if state == null:
		return
	state.set_mode(state.Mode.ON_FOOT)

	var rig: Dictionary = _rig()
	var actions := rig["actions"] as TimeCostedActionSystem
	var request := TimeActionRequest.new()
	request.action_id = &"sleep"
	request.duration_hours = 1.0
	request.presentation_seconds = 4.0
	request.reason = &"sleep"
	request.player_mode = state.Mode.SLEEPING
	request.interruptible = false
	_check(actions.start_action(request), "non-interruptible staged action refused to start")
	_check(state.mode == state.Mode.SLEEPING, "staged sleep did not enter SLEEPING")
	_check(not actions.cancel(&"user_cancel"), "non-interruptible sleep accepted cancellation")
	actions._process(4.0)
	_check(not actions.is_active(), "non-interruptible sleep did not finish")
	_check(state.mode == state.Mode.ON_FOOT, "non-interruptible completion did not restore PlayerState")
	_dispose_rig(rig)


func _test_cancel_releases_clock() -> void:
	var rig: Dictionary = _rig()
	var clock := rig["clock"] as SimulationClock
	var actions := rig["actions"] as TimeCostedActionSystem
	var state: Node = root.get_node_or_null(^"PlayerState")
	if state != null:
		state.set_mode(state.Mode.ON_FOOT)
	var cancelled: Array[StringName] = []
	var request := TimeActionRequest.new()
	request.action_id = &"chop"
	request.duration_hours = 0.5
	request.presentation_seconds = 4.0
	request.reason = &"chop"
	request.simulation_step_hours = 0.25
	request.player_mode = state.Mode.WORKING if state != null else -1
	request.on_cancel = func(_elapsed: float, why: StringName) -> void: cancelled.append(why)
	actions.start_action(request)
	if state != null:
		_check(state.mode == state.Mode.WORKING, "working action did not enter WORKING mode")
	actions._process(1.0)
	_check(actions.cancel(&"moved"), "interruptible action refused cancellation")
	_check(not actions.is_active(), "cancelled action stayed active")
	_check(not clock.is_realtime_blocked(), "cancelled action left realtime blocked")
	_check(cancelled.size() == 1 and cancelled[0] == &"moved", "on_cancel did not run exactly once with reason")
	if state != null:
		_check(state.mode == state.Mode.ON_FOOT, "cancelled action did not restore PlayerState")
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
