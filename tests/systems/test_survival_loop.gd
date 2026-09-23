extends SceneTree

## Covers the two ends of the survival loop that were stubs: sleeping that
## actually restores energy, and eating that actually reaches the biomonitor.
## Run: godot --headless --script tests/systems/test_survival_loop.gd

const LAYOUT: String = "res://data/equipment/player_layout.tres"

var _failures: int = 0


func _process(_delta: float) -> bool:
	_run()
	return true


func _run() -> void:
	_test_sleep_restores_energy()
	_test_sleep_charges_the_night()
	_test_an_empty_stomach_ruins_the_night()
	_test_eating_from_the_inventory_feeds_the_body()
	_test_eating_from_a_pocket_feeds_the_body()
	_test_a_tin_leaves_an_empty_tin()
	_test_snow_costs_body_heat()
	_test_consume_refusals()
	if _failures > 0:
		push_error("survival loop: %d check(s) failed" % _failures)
		quit(1)
		return
	print("survival loop: all checks passed")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("survival loop: %s" % message)


func _dispose(node: Node) -> void:
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	node.free()


func _make_bio(energy_percent: float = 40.0) -> BioMonitorManager:
	var bio := BioMonitorManager.new()
	bio.initial_energy_percent = energy_percent
	root.add_child(bio)
	return bio


func _make_consumption(bio: BioMonitorManager) -> ConsumptionController:
	var controller := ConsumptionController.new()
	controller.bio_monitor = bio
	controller.inventory = InventoryComponent.new()
	root.add_child(controller.inventory)
	root.add_child(controller)
	return controller


func _test_sleep_restores_energy() -> void:
	var bio := _make_bio(40.0)
	var before: float = bio.current_energy
	bio.rest_sleep(8.0)
	_check(bio.current_energy > before, "eight hours of sleep restored no energy")
	_check(
		bio.current_energy >= bio.max_energy * 0.95,
		"a full night on a fed body only reached %.1f energy" % bio.current_energy
	)
	_dispose(bio)


## The clock jump skips the hourly tick, so sleep has to bill its own hours.
func _test_sleep_charges_the_night() -> void:
	var bio := _make_bio(40.0)
	var calories: float = bio.current_calories
	var hydration: float = bio.current_hydration
	bio.rest_sleep(8.0)
	_check(bio.current_calories < calories, "a night of sleep cost no calories")
	_check(bio.current_hydration < hydration, "a night of sleep cost no water")
	_check(
		bio.current_calories > calories - bio.base_metabolism_rate * 8.0,
		"sleeping burned as much as being awake"
	)
	_dispose(bio)


func _test_an_empty_stomach_ruins_the_night() -> void:
	var fed := _make_bio(40.0)
	var starved := _make_bio(40.0)
	starved.current_calories = 0.0
	starved.current_hydration = 0.0
	fed.rest_sleep(6.0)
	starved.rest_sleep(6.0)
	_check(
		starved.current_energy < fed.current_energy,
		"starving rested as well as fed: %.1f vs %.1f" % [starved.current_energy, fed.current_energy]
	)
	_check(starved.current_energy > 40.0, "a bad night restored nothing at all")
	_dispose(fed)
	_dispose(starved)


func _test_eating_from_the_inventory_feeds_the_body() -> void:
	var bio := _make_bio()
	bio.current_calories = 500.0
	var controller := _make_consumption(bio)
	controller.inventory.try_add(ItemCatalog.get_item(&"tinned_stew"))

	_check(
		controller.consume(&"tinned_stew") == ConsumptionController.Refusal.NONE,
		"a carried tin refused to be eaten"
	)
	_check(bio.current_calories > 900.0, "eating a tin added %.0f kcal" % (bio.current_calories - 500.0))
	_check(not controller.inventory.has_item(&"tinned_stew"), "the tin survived being eaten")
	_dispose(controller.inventory)
	_dispose(controller)
	_dispose(bio)


func _test_eating_from_a_pocket_feeds_the_body() -> void:
	var bio := _make_bio()
	bio.current_calories = 500.0
	var equipment := EquipmentComponent.new()
	equipment.layout = load(LAYOUT) as EquipmentLayout
	root.add_child(equipment)
	equipment.initialize()
	equipment.equip(&"torso", &"worn_coat")
	equipment.stow(&"torso", &"coat_left", &"tinned_stew")

	var controller := ConsumptionController.new()
	controller.bio_monitor = bio
	controller.equipment = equipment
	root.add_child(controller)

	_check(
		controller.consume(&"tinned_stew") == ConsumptionController.Refusal.NONE,
		"a tin in a pocket refused to be eaten"
	)
	_check(bio.current_calories > 900.0, "the pocket tin restored nothing")
	## With no inventory the empty tin has nowhere else to go, so it takes the
	## pocket the stew vacated rather than vanishing.
	_check(
		equipment.get_pocket_item(&"torso", &"coat_left") == &"empty_tin",
		"the pocket holds '%s', expected the empty tin" % equipment.get_pocket_item(&"torso", &"coat_left")
	)
	_dispose(controller)
	_dispose(equipment)
	_dispose(bio)


func _test_a_tin_leaves_an_empty_tin() -> void:
	var bio := _make_bio()
	var controller := _make_consumption(bio)
	controller.inventory.try_add(ItemCatalog.get_item(&"tinned_stew"))
	controller.consume(&"tinned_stew")
	_check(controller.inventory.has_item(&"empty_tin"), "eating left no empty tin behind")
	_dispose(controller.inventory)
	_dispose(controller)
	_dispose(bio)


## Melting snow in the mouth is water bought with body heat, not free water.
func _test_snow_costs_body_heat() -> void:
	var bio := _make_bio()
	bio.current_hydration = 40.0
	var thermal := ThermalManager.new()
	root.add_child(thermal)
	thermal.initialize()
	var before: float = thermal.get_body_temperature_c()

	var controller := _make_consumption(bio)
	controller.thermal_manager = thermal
	controller.inventory.try_add(ItemCatalog.get_item(&"snow_handful"))
	_check(
		controller.consume(&"snow_handful") == ConsumptionController.Refusal.NONE,
		"a handful of snow refused to be eaten"
	)
	_check(bio.current_hydration > 40.0, "snow restored no hydration")
	_check(
		thermal.get_body_temperature_c() < before,
		"snow cost no body heat: %.2f to %.2f" % [before, thermal.get_body_temperature_c()]
	)
	_dispose(controller.inventory)
	_dispose(controller)
	_dispose(thermal)
	_dispose(bio)


func _test_consume_refusals() -> void:
	var bio := _make_bio()
	var controller := _make_consumption(bio)
	_check(
		controller.consume(&"not_an_item") == ConsumptionController.Refusal.UNKNOWN_ITEM,
		"an unknown id was not refused"
	)
	_check(
		controller.consume(&"worn_coat") == ConsumptionController.Refusal.NOT_CONSUMABLE,
		"a coat was eaten"
	)
	_check(
		controller.consume(&"tinned_stew") == ConsumptionController.Refusal.NOT_CARRIED,
		"a tin nobody carries was eaten"
	)
	_dispose(controller.inventory)
	_dispose(controller)
	_dispose(bio)
