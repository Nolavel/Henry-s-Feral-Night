extends SceneTree

## #134: weight must be felt before the hard limit and clothing wetness must be
## readable without duplicating simulation formulas in presentation.
## Run: godot --headless --script tests/systems/test_systemic_pressure.gd

var _failures: int = 0
var _ran: bool = false

func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_test_load_pressure()
	_test_wetness_feedback()
	if _failures > 0:
		push_error("systemic pressure: %d check(s) failed" % _failures)
		quit(1)
	else:
		print("systemic pressure: load, wetness and Hub feedback passed")
		quit(0)
	return false

func _test_load_pressure() -> void:
	var body := CharacterBody3D.new()
	body.add_to_group(&"player")
	root.add_child(body)

	var inventory := InventoryComponent.new()
	inventory.max_carry_weight = 30.0
	body.add_child(inventory)

	var movement := MovementController.new()
	movement.name = "MovementController"
	body.add_child(movement)

	var bio := BioMonitorManager.new()
	bio.name = "BioMonitorManager"
	bio.carry_inventory = inventory
	body.add_child(bio)

	var hub := PlayerHubComponent.new()
	hub.inventory = inventory
	body.add_child(hub)

	_check(is_equal_approx(movement.get_load_speed_multiplier(), 1.0), "empty pack slows movement")
	var cargo: ItemResource = ItemCatalog.get_item(&"tinned_stew")
	var guard: int = 0
	while inventory.get_load_fraction() < 0.92 and inventory.get_add_refusal(cargo) == &"" and guard < 500:
		inventory.try_add(cargo)
		guard += 1

	_check(inventory.get_load_fraction() > 0.80, "test could not build a heavy pack")
	_check(movement.get_load_speed_multiplier() < 0.90, "heavy pack has no visible movement cost")
	_check(movement.get_load_accel_multiplier() < 0.92, "heavy pack has no acceleration cost")
	_check(bio.get_energy_drain_multiplier() > 1.20, "heavy pack has no fatigue cost")
	_check(bio.get_energy_drain_reason() == &"load", "BioMonitor does not explain load fatigue")

	var readout: Dictionary = hub.get_survival_readout()
	_check(float(readout["move_multiplier"]) < 0.90, "Hub does not expose movement cost")
	_check(float(readout["energy_multiplier"]) > 1.20, "Hub does not expose fatigue cost")
	body.queue_free()

func _test_wetness_feedback() -> void:
	var thermal := ThermalManager.new()
	thermal.drying_starts_c = -100.0
	thermal.drying_full_c = -99.0
	root.add_child(thermal)
	thermal.initialize()
	thermal.add_wetness(0.20)
	_check(thermal.get_wetness_stage() == ThermalManager.WetnessStage.DAMP, "20% wetness is not DAMP")
	thermal.add_wetness(0.30)
	_check(thermal.get_wetness_stage() == ThermalManager.WetnessStage.WET, "50% wetness is not WET")
	_check(thermal.is_clothing_drying(), "warm dry conditions do not report drying")
	_check(thermal.get_wetness_insulation_multiplier() < 0.70, "50% wetness barely affects insulation")

	var body := Node.new()
	root.add_child(body)
	var inventory := InventoryComponent.new()
	body.add_child(inventory)
	var hub := PlayerHubComponent.new()
	hub.inventory = inventory
	body.add_child(hub)
	hub.set_thermal_manager(thermal)
	var readout: Dictionary = hub.get_survival_readout()
	_check(int(readout["wetness_stage"]) == int(ThermalManager.WetnessStage.WET), "Hub does not expose wetness stage")
	_check(bool(readout["drying"]), "Hub does not expose drying state")
	_check(float(readout["insulation_multiplier"]) < 0.70, "Hub hides wet insulation loss")
	body.queue_free()
	thermal.queue_free()

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("systemic pressure: " + message)
