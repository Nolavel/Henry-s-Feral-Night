extends SceneTree

## Phase 5 clothing contract: layered slots, per-instance state, outside-in
## moisture and save-compatible equipment/inventory transfer.
## Run: godot --headless --script tests/systems/test_clothing_layers.gd

const LAYOUT: String = "res://data/equipment/player_layout.tres"

var _failures: int = 0
var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_test_layered_occupancy_and_legacy_aliases()
	_test_outside_in_wetting()
	_test_wetness_and_condition_reduce_protection()
	_test_instance_state_survives_inventory_transfer()
	_test_equipment_save_migration()
	_test_shared_garment_data_is_immutable_at_runtime()
	if _failures > 0:
		push_error("clothing layers: %d check(s) failed" % _failures)
		quit(1)
	else:
		print("clothing layers: phase 5 contract passed")
		quit(0)
	return false


func _make_equipment() -> EquipmentComponent:
	var equipment := EquipmentComponent.new()
	equipment.layout = load(LAYOUT) as EquipmentLayout
	root.add_child(equipment)
	equipment.initialize()
	return equipment


func _test_layered_occupancy_and_legacy_aliases() -> void:
	var equipment := _make_equipment()
	_check(
		equipment.equip(&"torso_base", &"thermal_shirt") == EquipmentComponent.Refusal.NONE,
		"base layer refused"
	)
	_check(
		equipment.equip(&"torso_mid", &"wool_sweater") == EquipmentComponent.Refusal.NONE,
		"mid layer refused"
	)
	_check(
		equipment.equip(&"torso", &"worn_coat") == EquipmentComponent.Refusal.NONE,
		"legacy torso alias did not migrate to outer layer"
	)
	_check(equipment.get_equipped(&"torso_outer") == &"worn_coat", "outer coat missing")
	_check(equipment.get_equipped(&"torso") == &"worn_coat", "legacy getter alias stopped working")
	_check(equipment.get_equipped(&"torso_base") == &"thermal_shirt", "base layer displaced")
	_check(equipment.get_equipped(&"torso_mid") == &"wool_sweater", "mid layer displaced")
	_dispose(equipment)


func _test_outside_in_wetting() -> void:
	var equipment := _make_equipment()
	equipment.equip(&"torso_base", &"thermal_shirt")
	equipment.equip(&"torso_mid", &"wool_sweater")
	equipment.equip(&"torso_outer", &"worn_coat")
	equipment.advance_garment_moisture(1.0, 1.0, 0.0)

	var outer: float = float(equipment.get_garment_state(&"torso_outer").get("wetness", 0.0))
	var mid: float = float(equipment.get_garment_state(&"torso_mid").get("wetness", 0.0))
	var base: float = float(equipment.get_garment_state(&"torso_base").get("wetness", 0.0))
	_check(outer > mid, "outer layer did not take more moisture than mid")
	_check(mid > base, "mid layer did not protect base")
	_check(base > 0.0, "penetrating moisture never reached base layer")

	var unprotected := _make_equipment()
	unprotected.equip(&"torso_base", &"thermal_shirt")
	unprotected.advance_garment_moisture(1.0, 1.0, 0.0)
	var bare_base: float = float(unprotected.get_garment_state(&"torso_base").get("wetness", 0.0))
	_check(base < bare_base, "outer/mid layers did not protect the base layer")
	_dispose(unprotected)
	_dispose(equipment)


func _test_wetness_and_condition_reduce_protection() -> void:
	var equipment := _make_equipment()
	equipment.equip(&"torso_outer", &"worn_coat")
	var dry_insulation: float = equipment.get_effective_insulation_c()
	var dry_wind: float = equipment.get_wind_protection()
	var dry_water: float = equipment.get_water_protection()

	equipment.set_garment_wetness(&"torso_outer", 1.0)
	var wet_insulation: float = equipment.get_effective_insulation_c()
	_check(wet_insulation < dry_insulation, "soaked coat did not lose insulation")

	equipment.set_garment_wetness(&"torso_outer", 0.0)
	equipment.damage_garment(&"torso_outer", 0.5)
	_check(equipment.get_effective_insulation_c() < dry_insulation, "condition did not lower insulation")
	_check(equipment.get_wind_protection() < dry_wind, "condition did not lower wind protection")
	_check(equipment.get_water_protection() < dry_water, "condition did not lower water protection")

	var thermal := ThermalManager.new()
	thermal.equipment = equipment
	root.add_child(thermal)
	thermal.initialize()
	_check(
		is_equal_approx(thermal.get_insulation_c(), equipment.get_effective_insulation_c()),
		"ThermalManager does not consume effective clothing insulation"
	)
	_dispose(thermal)
	_dispose(equipment)


func _test_instance_state_survives_inventory_transfer() -> void:
	var equipment := _make_equipment()
	var inventory := InventoryComponent.new()
	inventory.equipment = equipment
	root.add_child(inventory)

	equipment.equip(&"torso_outer", &"worn_coat")
	equipment.set_garment_wetness(&"torso_outer", 0.62)
	equipment.damage_garment(&"torso_outer", 0.23)
	_check(equipment.unequip_to_inventory(&"torso_outer", inventory), "stateful unequip to inventory failed")
	_check(equipment.get_equipped(&"torso_outer") == &"", "coat remained equipped after transfer")

	var carried: Array[Dictionary] = inventory.get_entries()
	_check(carried.size() == 1, "inventory did not receive one coat instance")
	if carried.size() == 1:
		var state: Dictionary = carried[0].get("instance_state", {})
		_check(is_equal_approx(float(state.get("wetness", 0.0)), 0.62), "inventory lost garment wetness")
		_check(is_equal_approx(float(state.get("condition", 1.0)), 0.77), "inventory lost garment condition")

	_check(
		equipment.equip_from_inventory(&"torso_outer", &"worn_coat", inventory)
			== EquipmentComponent.Refusal.NONE,
		"stateful re-equip failed"
	)
	var restored: Dictionary = equipment.get_garment_state(&"torso_outer")
	_check(is_equal_approx(float(restored.get("wetness", 0.0)), 0.62), "re-equip reset wetness")
	_check(is_equal_approx(float(restored.get("condition", 1.0)), 0.77), "re-equip reset condition")
	_check(inventory.get_count(&"worn_coat") == 0, "re-equipped coat duplicated in inventory")
	_dispose(inventory)
	_dispose(equipment)


func _test_equipment_save_migration() -> void:
	var equipment := _make_equipment()
	equipment.equip(&"torso_outer", &"worn_coat")
	equipment.set_garment_wetness(&"torso_outer", 0.4)
	equipment.damage_garment(&"torso_outer", 0.1)
	var payload: Dictionary = equipment.get_save_data()
	_check(payload.has("garment_states"), "new equipment save has no garment_states extension")

	var restored := _make_equipment()
	restored.load_save_data(payload)
	var restored_state: Dictionary = restored.get_garment_state(&"torso_outer")
	_check(is_equal_approx(float(restored_state.get("wetness", 0.0)), 0.4), "save/load lost wetness")
	_check(is_equal_approx(float(restored_state.get("condition", 1.0)), 0.9), "save/load lost condition")

	var old_save := {
		"body": {"torso": "worn_coat"},
		"pockets": {"torso/coat_left": "tinned_stew"},
	}
	var migrated := _make_equipment()
	migrated.load_save_data(old_save)
	_check(migrated.get_equipped(&"torso_outer") == &"worn_coat", "old torso slot did not migrate")
	_check(
		migrated.get_pocket_item(&"torso_outer", &"coat_left") == &"tinned_stew",
		"old pocket path did not migrate"
	)
	var default_state: Dictionary = migrated.get_garment_state(&"torso_outer")
	_check(is_zero_approx(float(default_state.get("wetness", -1.0))), "old save did not default garment dry")
	_check(is_equal_approx(float(default_state.get("condition", 0.0)), 1.0), "old save did not default full condition")

	var invalid := _make_equipment()
	invalid.load_save_data({"body": {"torso_shell": "worn_coat"}, "pockets": {}})
	_check(invalid.get_equipped(&"torso_outer") == &"", "unknown old layer slot silently migrated")

	_dispose(invalid)
	_dispose(migrated)
	_dispose(restored)
	_dispose(equipment)


func _test_shared_garment_data_is_immutable_at_runtime() -> void:
	var coat: GarmentData = ItemCatalog.get_item(&"worn_coat").garment
	var authored_insulation: float = coat.get_base_insulation_c()
	var authored_waterproof: float = coat.waterproof
	var equipment := _make_equipment()
	equipment.equip(&"torso_outer", &"worn_coat")
	equipment.set_garment_wetness(&"torso_outer", 1.0)
	equipment.damage_garment(&"torso_outer", 0.5)
	_check(is_equal_approx(coat.get_base_insulation_c(), authored_insulation), "runtime state mutated shared insulation")
	_check(is_equal_approx(coat.waterproof, authored_waterproof), "runtime state mutated shared waterproof")
	_dispose(equipment)


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
	push_error("clothing layers: " + message)
