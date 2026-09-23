extends SceneTree

## Covers the equipment and inventory port: the refusals that keep the model
## honest, pockets that belong to the garment, and the reason this port
## happened at all — clothing that measurably slows freezing.
## Run: godot --headless --script tests/systems/test_equipment.gd

const LAYOUT: String = "res://data/equipment/player_layout.tres"
const STEP_MINUTES: float = 10.0

var _failures: int = 0


func _process(_delta: float) -> bool:
	_run()
	return true


func _run() -> void:
	_test_the_catalog_resolves_the_shipped_items()
	_test_a_garment_only_fits_its_own_slot()
	_test_an_occupied_slot_refuses_rather_than_swapping()
	_test_pockets_belong_to_the_garment()
	_test_a_coat_cannot_be_removed_with_a_full_pocket()
	_test_auto_stow_skips_the_reserved_fixture()
	_test_equipment_survives_a_save_round_trip()
	_test_weight_gates_the_inventory()
	_test_clothing_slows_freezing()
	if _failures > 0:
		push_error("equipment: %d check(s) failed" % _failures)
		quit(1)
		return
	print("equipment: all checks passed")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("equipment: %s" % message)


func _dispose(node: Node) -> void:
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	node.free()


func _make_equipment(starters: Array[StringName] = []) -> EquipmentComponent:
	var component := EquipmentComponent.new()
	component.layout = load(LAYOUT) as EquipmentLayout
	component.starter_garment_ids = starters
	root.add_child(component)
	component.initialize()
	return component


func _test_the_catalog_resolves_the_shipped_items() -> void:
	for id: StringName in [&"worn_coat", &"knit_hat", &"work_trousers", &"worn_boots"]:
		var item: ItemResource = ItemCatalog.get_item(id)
		_check(item != null, "the catalog does not resolve '%s'" % id)
		if item != null:
			_check(item.garment != null, "'%s' is not a garment" % id)
			_check(item.garment.insulation_c > 0.0, "'%s' insulates nothing" % id)

	var stew: ItemResource = ItemCatalog.get_item(&"tinned_stew")
	_check(stew != null and stew.consumable != null, "tinned stew is not consumable")
	if stew != null and stew.consumable != null:
		_check(stew.consumable.calories > 0.0, "tinned stew restores no calories")
	_check(ItemCatalog.get_item(&"not_an_item") == null, "the catalog invented an item")


func _test_a_garment_only_fits_its_own_slot() -> void:
	var equipment := _make_equipment()
	_check(
		equipment.can_equip(&"head", &"worn_coat") == EquipmentComponent.Refusal.WRONG_BODY_SLOT,
		"a coat was accepted on the head"
	)
	_check(
		equipment.equip(&"torso", &"worn_coat") == EquipmentComponent.Refusal.NONE,
		"a coat was refused on the torso"
	)
	_check(
		equipment.can_equip(&"torso", &"knit_hat") == EquipmentComponent.Refusal.SLOT_OCCUPIED,
		"an occupied torso did not report itself occupied"
	)
	_check(
		equipment.can_equip(&"no_such_slot", &"knit_hat") == EquipmentComponent.Refusal.NO_SUCH_SLOT,
		"an unknown slot was not reported"
	)
	_dispose(equipment)


## Swapping would mean silently displacing an item this component cannot put
## anywhere, so it refuses instead.
func _test_an_occupied_slot_refuses_rather_than_swapping() -> void:
	var equipment := _make_equipment()
	equipment.equip(&"torso", &"worn_coat")
	var refusal: int = equipment.equip(&"torso", &"work_trousers")
	_check(refusal != EquipmentComponent.Refusal.NONE, "an occupied slot accepted a second item")
	_check(
		equipment.get_equipped(&"torso") == &"worn_coat",
		"the original garment was displaced"
	)
	_dispose(equipment)


## Slot count belongs to the garment: take the coat off and its pockets go.
func _test_pockets_belong_to_the_garment() -> void:
	var equipment := _make_equipment()
	_check(equipment.get_available_pockets().is_empty(), "pockets existed with nothing worn")

	equipment.equip(&"torso", &"worn_coat")
	_check(
		equipment.get_available_pockets().size() == 2,
		"the coat brought %d pockets, expected 2" % equipment.get_available_pockets().size()
	)
	_check(
		equipment.stow(&"torso", &"coat_left", &"tinned_stew") == EquipmentComponent.Refusal.NONE,
		"a tin would not go in a coat pocket"
	)
	_check(
		equipment.can_stow(&"torso", &"coat_left", &"tinned_stew")
			== EquipmentComponent.Refusal.SLOT_OCCUPIED,
		"a full pocket accepted a second item"
	)
	_check(
		equipment.can_stow(&"legs", &"thigh_left", &"tinned_stew")
			== EquipmentComponent.Refusal.NO_SUCH_SLOT,
		"a pocket existed on trousers that are not worn"
	)
	_dispose(equipment)


func _test_a_coat_cannot_be_removed_with_a_full_pocket() -> void:
	var equipment := _make_equipment()
	equipment.equip(&"torso", &"worn_coat")
	equipment.stow(&"torso", &"coat_left", &"tinned_stew")

	_check(equipment.unequip(&"torso") == &"", "a coat came off with a full pocket")
	_check(equipment.get_equipped(&"torso") == &"worn_coat", "the coat was removed anyway")

	equipment.take_from_pocket(&"torso", &"coat_left")
	_check(equipment.unequip(&"torso") == &"worn_coat", "an emptied coat would not come off")
	_dispose(equipment)


## Kenny's fixture is a decision Henry makes, never where spare weight lands.
func _test_auto_stow_skips_the_reserved_fixture() -> void:
	var equipment := _make_equipment()
	## With nothing worn the pack is the only home, and it should take it —
	## the point is that the reserved fixture never does.
	_check(
		equipment.stow_anywhere(&"tinned_stew") == EquipmentComponent.Refusal.NONE,
		"a tin found no home at all with an empty pack available"
	)
	_check(
		equipment.get_equipped(&"pack") == &"tinned_stew",
		"auto-stow did not use the pack"
	)
	_check(
		equipment.get_equipped(&"back_fixture") == &"",
		"auto-stow filled the reserved back fixture"
	)

	## Fill the pack, so the only remaining non-garment slot is the reserved
	## fixture. It must still refuse.
	_check(
		equipment.stow_anywhere(&"tinned_stew") != EquipmentComponent.Refusal.NONE,
		"a second tin found a home although only the reserved fixture was free"
	)
	_check(
		equipment.get_equipped(&"back_fixture") == &"",
		"the reserved fixture took the overflow"
	)

	equipment.unequip(&"pack")
	equipment.equip(&"torso", &"worn_coat")
	_check(
		equipment.stow_anywhere(&"tinned_stew") == EquipmentComponent.Refusal.NONE,
		"a tin found no coat pocket"
	)
	_check(
		equipment.get_pocket_item(&"torso", &"coat_left") == &"tinned_stew",
		"the tin did not land in the first empty pocket"
	)
	_dispose(equipment)


func _test_equipment_survives_a_save_round_trip() -> void:
	var equipment := _make_equipment()
	equipment.equip(&"torso", &"worn_coat")
	equipment.equip(&"head", &"knit_hat")
	equipment.stow(&"torso", &"coat_right", &"tinned_stew")
	var expected: float = equipment.get_total_insulation_c()

	var payload: Dictionary = equipment.get_save_data()
	_check(
		typeof(payload.get("body")) == TYPE_DICTIONARY,
		"the payload does not carry a plain body dictionary"
	)

	var restored := _make_equipment()
	restored.load_save_data(payload)
	_check(restored.get_equipped(&"torso") == &"worn_coat", "the coat did not survive the save")
	_check(restored.get_equipped(&"head") == &"knit_hat", "the hat did not survive the save")
	_check(
		restored.get_pocket_item(&"torso", &"coat_right") == &"tinned_stew",
		"the pocket contents did not survive the save"
	)
	_check(
		is_equal_approx(restored.get_total_insulation_c(), expected),
		"insulation did not survive the save"
	)
	_dispose(restored)
	_dispose(equipment)


func _test_weight_gates_the_inventory() -> void:
	var inventory := InventoryComponent.new()
	inventory.max_carry_weight = 1.0
	root.add_child(inventory)

	var stew: ItemResource = ItemCatalog.get_item(&"tinned_stew")
	_check(inventory.try_add(stew), "a light item was refused")
	_check(inventory.try_add(stew), "a second light item was refused")
	_check(inventory.get_count(&"tinned_stew") == 2, "the stack did not grow")

	var coat: ItemResource = ItemCatalog.get_item(&"worn_coat")
	_check(not inventory.try_add(coat), "an overweight item was accepted")
	_check(
		inventory.get_total_weight() <= inventory.max_carry_weight,
		"the carried weight exceeded the limit"
	)
	_dispose(inventory)


## The reason this port happened: clothing has to be worth wearing.
func _test_clothing_slows_freezing() -> void:
	var bare := _make_thermal_rig([])
	_simulate(bare["thermal"], 3.0)
	var bare_temp: float = bare["thermal"].get_body_temperature_c()
	_check(
		is_zero_approx(bare["equipment"].get_total_insulation_c()),
		"an unclothed Henry reported insulation"
	)
	_dispose_rig(bare)

	var dressed := _make_thermal_rig(
		[&"worn_coat", &"knit_hat", &"work_trousers", &"worn_boots"] as Array[StringName]
	)
	var insulation: float = dressed["equipment"].get_total_insulation_c()
	_check(insulation > 5.0, "a fully dressed Henry insulated only %.1f C" % insulation)
	_simulate(dressed["thermal"], 3.0)

	_check(
		dressed["thermal"].get_body_temperature_c() > bare_temp,
		"clothing did not slow freezing: dressed %.2f C vs bare %.2f C"
			% [dressed["thermal"].get_body_temperature_c(), bare_temp]
	)

	## Taking the coat off must be felt immediately, not only next save.
	dressed["equipment"].unequip(&"torso")
	_check(
		dressed["equipment"].get_total_insulation_c() < insulation,
		"removing the coat did not lower insulation"
	)
	_check(
		dressed["thermal"].get_insulation_c() < insulation,
		"the thermal model did not see the coat come off"
	)
	_dispose_rig(dressed)


func _make_thermal_rig(starters: Array[StringName]) -> Dictionary:
	var equipment := _make_equipment(starters)
	var thermal := ThermalManager.new()
	thermal.ambient_min_c = -18.0
	thermal.ambient_max_c = -18.0
	thermal.equipment = equipment
	root.add_child(thermal)
	thermal.initialize()
	return {"thermal": thermal, "equipment": equipment}


func _dispose_rig(rig: Dictionary) -> void:
	_dispose(rig["thermal"])
	_dispose(rig["equipment"])


func _simulate(thermal: ThermalManager, hours: float) -> void:
	var step: float = STEP_MINUTES / 60.0
	var elapsed: float = 0.0
	var clock: float = 0.0
	thermal.reset_clock()
	thermal._on_time_update(clock)
	while elapsed < hours:
		clock = fmod(clock + step, 24.0)
		thermal._on_time_update(clock)
		elapsed += step
