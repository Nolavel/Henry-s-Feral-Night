extends SceneTree

## Phase 4 status-layer contract. Simulation must work without any presentation node.

var _failures: int = 0
var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_test_edges_are_idempotent()
	_test_save_round_trip()
	_test_modifier_order_is_deterministic()
	_test_severity_interpolation()
	_test_world_context_binds_thermal()
	_test_real_threshold_bindings()
	_test_named_modifier_consumers()
	if _failures > 0:
		push_error("afflictions: %d check(s) failed" % _failures)
		quit(1)
	else:
		print("afflictions: persistence, edges and modifiers passed")
		quit(0)
	return false


func _make_afflictions(parent: Node = root) -> AfflictionComponent:
	var component := AfflictionComponent.new()
	component.name = "AfflictionComponent"
	parent.add_child(component)
	return component


func _test_edges_are_idempotent() -> void:
	var aff := _make_afflictions()
	var activated: Array[StringName] = []
	var changed: Array[StringName] = []
	var recovered: Array[StringName] = []
	aff.affliction_activated.connect(func(id: StringName, _s: float, _src: StringName) -> void: activated.append(id))
	aff.affliction_changed.connect(func(id: StringName, _s: float) -> void: changed.append(id))
	aff.affliction_recovered.connect(func(id: StringName) -> void: recovered.append(id))

	_check(aff.set_condition(&"hypothermia", true, 1.0, &"test"), "first activation was refused")
	aff.set_condition(&"hypothermia", true, 1.0, &"test")
	_check(activated.size() == 1, "same affliction activated more than once")
	aff.set_condition(&"hypothermia", true, 2.0, &"test")
	_check(changed.size() == 1 and is_equal_approx(aff.get_severity(&"hypothermia"), 2.0),
		"severity update did not produce one change")
	_check(aff.get_active_ids() == [&"hypothermia"], "non-stackable affliction duplicated")
	aff.set_condition(&"hypothermia", false)
	aff.set_condition(&"hypothermia", false)
	_check(recovered.size() == 1, "recovery emitted more than once")
	_check(not aff.has_affliction(&"hypothermia"), "recovered affliction stayed active")
	_dispose(aff)


func _test_save_round_trip() -> void:
	var aff := _make_afflictions()
	aff.set_condition(&"hypothermia", true, 2.0, &"thermal")
	var context := SimulationStepContext.new(10.0, 11.5, &"test")
	aff.advance_simulation(1.5, context)
	var saved: Dictionary = aff.get_save_data()
	_check(SaveManager.implements_save_contract(aff), "AfflictionComponent is not saveable")
	_dispose(aff)

	var fresh := _make_afflictions()
	fresh.load_save_data(JSON.parse_string(JSON.stringify(saved)))
	_check(fresh.has_affliction(&"hypothermia"), "active affliction vanished on load")
	_check(is_equal_approx(fresh.get_severity(&"hypothermia"), 2.0), "severity changed on load")
	_check(is_equal_approx(fresh.get_elapsed_hours(&"hypothermia"), 1.5), "elapsed time changed on load")
	_check(fresh.get_save_key() == &"afflictions", "affliction save key changed")
	_dispose(fresh)

	var empty := _make_afflictions()
	empty.load_save_data({})
	_check(empty.get_active_ids().is_empty(), "old save without afflictions created a condition")
	_dispose(empty)


func _test_modifier_order_is_deterministic() -> void:
	var a := _make_afflictions()
	var b := _make_afflictions()
	for id: StringName in [&"dehydration", &"exhaustion", &"hypothermia"]:
		a.set_condition(id, true, 1.0, &"test")
	for id: StringName in [&"hypothermia", &"exhaustion", &"dehydration"]:
		b.set_condition(id, true, 1.0, &"test")
	for stat: StringName in [
		&"movement_speed_multiplier",
		&"fatigue_rate_multiplier",
		&"recovery_rate_multiplier",
		&"work_duration_multiplier",
	]:
		_check(is_equal_approx(a.get_multiplier(stat), b.get_multiplier(stat)),
			"modifier '%s' depends on activation order" % stat)
	_check(a.get_active_ids().size() == 3, "three non-stackable conditions did not remain unique")
	_dispose(a)
	_dispose(b)


func _test_severity_interpolation() -> void:
	var aff := _make_afflictions()
	aff.set_condition(&"hypothermia", true, 1.0, &"test")
	var half: float = aff.get_multiplier(&"movement_speed_multiplier")
	aff.set_condition(&"hypothermia", true, 2.0, &"test")
	var full: float = aff.get_multiplier(&"movement_speed_multiplier")
	_check(is_equal_approx(half, 0.9), "severity 1/2 did not interpolate movement modifier to 0.9")
	_check(is_equal_approx(full, 0.8), "max hypothermia severity did not apply full movement modifier")
	_check(full < half and half < 1.0, "severity does not scale consequence monotonically")
	_dispose(aff)


func _test_world_context_binds_thermal() -> void:
	var player := Node3D.new()
	root.add_child(player)
	var aff := _make_afflictions(player)
	var thermal := ThermalManager.new()
	root.add_child(thermal)
	thermal.initialize()
	var context := WorldContext.new()
	context.player = player
	context.systems = [thermal]
	aff.on_world_ready(context)
	thermal.apply_body_temperature_delta(-4.0)
	_check(aff.has_affliction(&"hypothermia"), "world context did not bind ThermalManager to afflictions")
	thermal.apply_body_temperature_delta(10.0)
	_check(not aff.has_affliction(&"hypothermia"), "context-bound hypothermia did not recover")
	_dispose(thermal)
	_dispose(player)


func _test_real_threshold_bindings() -> void:
	var player := (load("res://scenes/actors/player/player.tscn") as PackedScene).instantiate()
	root.add_child(player)
	var hydration := player.get_node(^"HydrationComponent") as HydrationComponent
	var fatigue := player.get_node(^"FatigueComponent") as FatigueComponent
	var aff := player.get_node(^"AfflictionComponent") as AfflictionComponent

	hydration.set_current(0.0)
	hydration.refresh_critical()
	_check(aff.has_affliction(&"dehydration"), "hydration critical edge did not activate dehydration")
	hydration.set_current(hydration.max_hydration)
	hydration.refresh_critical()
	_check(not aff.has_affliction(&"dehydration"), "hydration recovery did not clear dehydration")

	fatigue.set_current(0.0)
	fatigue.refresh_critical()
	_check(aff.has_affliction(&"exhaustion"), "fatigue critical edge did not activate exhaustion")
	fatigue.set_current(fatigue.max_energy)
	fatigue.refresh_critical()
	_check(not aff.has_affliction(&"exhaustion"), "fatigue recovery did not clear exhaustion")

	var thermal := ThermalManager.new()
	root.add_child(thermal)
	thermal.initialize()
	aff.bind_thermal(thermal)
	thermal.apply_body_temperature_delta(-4.0)
	_check(aff.has_affliction(&"hypothermia") and is_equal_approx(aff.get_severity(&"hypothermia"), 1.0),
		"HYPOTHERMIC stage did not activate severity 1")
	thermal.apply_body_temperature_delta(-2.0)
	_check(is_equal_approx(aff.get_severity(&"hypothermia"), 2.0),
		"CRITICAL thermal stage did not raise severity")
	thermal.apply_body_temperature_delta(10.0)
	_check(not aff.has_affliction(&"hypothermia"), "thermal recovery did not clear hypothermia")
	_dispose(thermal)
	_dispose(player)


func _test_named_modifier_consumers() -> void:
	var player := (load("res://scenes/actors/player/player.tscn") as PackedScene).instantiate()
	root.add_child(player)
	var aff := player.get_node(^"AfflictionComponent") as AfflictionComponent
	var movement := player.get_node(^"MovementController") as MovementController
	var fatigue := player.get_node(^"FatigueComponent") as FatigueComponent

	aff.set_condition(&"exhaustion", true, 1.0, &"test")
	_check(movement.get_status_speed_multiplier() < 1.0, "MovementController ignored named status multiplier")
	aff.set_condition(&"dehydration", true, 1.0, &"test")
	_check(fatigue.get_drain_multiplier() > 1.0, "FatigueComponent ignored named status multiplier")

	var clock := SimulationClock.new()
	root.add_child(clock)
	clock.set_total_hours(12.0, &"seed")
	var actions := TimeCostedActionSystem.new()
	actions.simulation_clock = clock
	root.add_child(actions)
	var request := TimeActionRequest.new()
	request.action_id = &"status_work_test"
	request.duration_hours = 1.0
	request.reason = &"work"
	request.actor = player
	var result: Dictionary = actions.run_to_completion(request)
	_check(float(result.get("elapsed_hours", 0.0)) > 1.0,
		"TimeCostedActionSystem ignored work-duration multiplier")
	_dispose(actions)
	_dispose(clock)
	_dispose(player)


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
	push_error("afflictions: " + message)
