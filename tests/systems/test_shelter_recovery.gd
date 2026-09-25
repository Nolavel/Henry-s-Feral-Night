extends SceneTree

## Recovery by the stove (#42): a RestSpot sits Henry down, F waits, moving stands him up;
## vitals show rising/falling trend marks; wet clothes steam only near a burning stove.
## Run: godot --headless --script tests/systems/test_shelter_recovery.gd

var _failures: int = 0
var _frame: int = 0
var _time: float = 0.0
var _cluster: VitalCluster
var _steam: DryingSteamComponent
var _thermal: ThermalManager
var _stove: HeatSource


func _process(delta: float) -> bool:
	_frame += 1
	_time += delta
	if _frame == 1:
		_test_rest()
		_start_trend_and_steam()
	elif _frame == 3:
		_check(not _steam.is_steaming(), "dry clothes steam")
		_thermal.add_wetness(0.6)
	elif _frame == 5:
		_check(not _steam.is_steaming(), "wet clothes steam with the stove cold")
		_stove.ignite()
	elif _frame == 7:
		_check(_steam.is_steaming(), "wet clothes by a burning stove do not steam")
		_cluster.set_vital(&"warmth", 0.5)
		_cluster.set_wetness(0.6)
	elif _frame == 8:
		_cluster.set_vital(&"warmth", 0.7)
		_cluster.set_wetness(0.3)
	elif _time > _cluster.trend_window * 2.5:
		_check(_cluster.get_trend(&"warmth") == 1, "rising warmth shows no up mark")
		_check(_cluster.get_trend(&"wetness") == -1, "drying clothes show no down mark")
		_check(_cluster.get_trend(&"hunger") == 0, "a steady vital shows a trend")
		_test_wait()
		_test_table()
		print("test_shelter_recovery: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
		quit(1 if _failures > 0 else 0)
	return false


func _test_rest() -> void:
	var body := CharacterBody3D.new()
	body.add_to_group(&"player")
	var rest := RestComponent.new()
	rest.name = "RestComponent"
	body.add_child(rest)
	root.add_child(body)
	var seat := Node3D.new()
	seat.position = Vector3(2.0, 0.0, 1.0)
	seat.rotation.y = 0.7
	root.add_child(seat)
	_check(rest.sit(seat), "Henry did not sit")
	_check(rest.is_sitting(), "Henry does not report sitting")
	_check(Vector2(body.global_position.x, body.global_position.z).distance_to(Vector2(2.0, 1.0)) < 0.01,
		"Henry was not moved onto the seat")
	_check(not rest.sit(seat), "Henry sat twice")
	var press := InputEventAction.new()
	press.action = &"interact"
	press.pressed = true
	rest._input(press)
	_check(rest.is_sitting(), "F stood Henry up instead of offering to wait")
	var move := InputEventAction.new()
	move.action = &"move_forward"
	move.pressed = true
	rest._input(move)
	_check(not rest.is_sitting(), "moving did not stand Henry up")


func _start_trend_and_steam() -> void:
	_cluster = VitalCluster.new()
	_cluster.trend_window = 0.2
	root.add_child(_cluster)
	_cluster.set_vital(&"hunger", 0.8)
	_thermal = ThermalManager.new()
	root.add_child(_thermal)
	_stove = HeatSource.new()
	_stove.starts_burning = false
	root.add_child(_stove)
	_steam = DryingSteamComponent.new()
	_steam.position = Vector3(1.0, 0.0, 0.0)
	root.add_child(_steam)
	_steam.set_thermal(_thermal)


## Sitting by a MealTable lays out the carried food; eating takes it off; standing clears it.
func _test_table() -> void:
	var body := CharacterBody3D.new()
	var inventory := InventoryComponent.new()
	body.add_child(inventory)
	var rest := RestComponent.new()
	body.add_child(rest)
	root.add_child(body)
	var table := MealTable.new()
	table.position = Vector3(20.3, 0.0, 0.5)
	root.add_child(table)
	var seat := Node3D.new()
	seat.position = Vector3(20.0, 0.0, 0.0)
	root.add_child(seat)
	inventory.try_add(load("res://data/items/tinned_stew.tres") as ItemResource)
	inventory.try_add(load("res://data/items/tinned_stew.tres") as ItemResource)
	inventory.try_add(load("res://data/items/road_flare.tres") as ItemResource)
	rest.sit(seat)
	_check(table.get_laid_ids() == [&"tinned_stew", &"tinned_stew"], "the table does not show the two tins only: %s" % [table.get_laid_ids()])
	var targets: Array[TableFood] = table.get_targets()
	_check(targets.size() == 1 and targets[0].item_id == &"tinned_stew" and targets[0].count == 2,
		"the table does not offer one F — Eat target for the two tins")
	inventory.try_remove(&"tinned_stew")
	_check(table.get_laid_ids().size() == 1, "an eaten tin stayed on the table")
	rest.stand()
	_check(table.get_laid_ids().is_empty(), "the table kept the food after Henry stood up")


## Waiting advances the clock without sleep; it stops at once when no fire warms Henry.
func _test_wait() -> void:
	var sleep := SleepController.new()
	sleep.thermal_manager = _thermal
	root.add_child(sleep)
	_thermal.global_position = Vector3(50.0, 0.0, 0.0)  # far from the stove
	var reasons: Array[String] = []
	sleep.wait_completed.connect(func(_h: float, key: String) -> void: reasons.append(key))
	var cold: float = sleep.try_wait(6.0)
	_check(is_equal_approx(cold, 0.25), "a wait with no fire did not stop after the first step (%.2f)" % cold)
	_check(reasons == ["WAIT_ENDED_FIRE_OUT"], "an early stop did not say the stove went out: %s" % [reasons])
	_thermal.global_position = _stove.global_position + Vector3(1.0, 0.0, 0.0)
	var warm: float = sleep.try_wait(2.0)
	_check(warm > 0.25, "a wait by the burning stove stopped at once")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)
