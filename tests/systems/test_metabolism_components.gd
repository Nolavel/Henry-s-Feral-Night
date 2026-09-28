extends SceneTree

## Phase 3: BioMonitorManager is a compatibility facade; metabolic state belongs
## to three small components without changing save shape or public behaviour.

var _failures: int = 0
var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_test_real_player_composition()
	_test_legacy_save_shape_and_round_trip()
	_test_step_equivalence()
	_test_carry_affects_fatigue_only()
	_test_food_does_not_touch_hydration()
	_test_sleep_crosses_all_three_tracks()
	_test_one_step_emits_once_per_track()
	if _failures > 0:
		push_error("metabolism components: %d check(s) failed" % _failures)
		quit(1)
	else:
		print("metabolism components: split facade contract passed")
		quit(0)
	return false


func _make_bio(energy_percent: float = 100.0) -> BioMonitorManager:
	var bio := BioMonitorManager.new()
	bio.initial_energy_percent = energy_percent
	root.add_child(bio)
	return bio


func _test_real_player_composition() -> void:
	var player := (load("res://scenes/actors/player/player.tscn") as PackedScene).instantiate()
	root.add_child(player)
	var bio := player.get_node(^"BioMonitorManager") as BioMonitorManager
	var hunger := player.get_node(^"HungerComponent") as HungerComponent
	var hydration := player.get_node(^"HydrationComponent") as HydrationComponent
	var fatigue := player.get_node(^"FatigueComponent") as FatigueComponent
	_check(bio.get_hunger_component() == hunger, "facade does not use player's HungerComponent")
	_check(bio.get_hydration_component() == hydration, "facade does not use player's HydrationComponent")
	_check(bio.get_fatigue_component() == fatigue, "facade does not use player's FatigueComponent")
	bio.current_calories = 777.0
	_check(is_equal_approx(hunger.current_calories, 777.0), "legacy current_calories is duplicated in manager")
	fatigue.set_current(44.0)
	_check(is_equal_approx(bio.current_energy, 44.0), "component state is not visible through facade")
	_dispose(player)


func _test_legacy_save_shape_and_round_trip() -> void:
	var bio := _make_bio()
	bio.current_calories = 731.0
	bio.current_hydration = 42.0
	bio.current_energy = 19.0
	var saved: Dictionary = bio.get_save_data()
	var keys: Array = saved.keys()
	keys.sort()
	_check(keys == ["calories", "energy", "hydration"], "bio save payload shape changed: %s" % [keys])
	_check(bio.get_save_key() == &"bio", "bio save key changed")
	var fresh := _make_bio()
	fresh.load_save_data(JSON.parse_string(JSON.stringify(saved)))
	_check(is_equal_approx(fresh.current_calories, 731.0), "legacy calories did not round-trip")
	_check(is_equal_approx(fresh.current_hydration, 42.0), "legacy hydration did not round-trip")
	_check(is_equal_approx(fresh.current_energy, 19.0), "legacy energy did not round-trip")
	_dispose(bio)
	_dispose(fresh)


func _test_step_equivalence() -> void:
	var hourly := _make_bio()
	var quarter := _make_bio()
	for _i: int in range(24):
		hourly.pass_awake_hours(1.0)
	for _i: int in range(96):
		quarter.pass_awake_hours(0.25)
	_check(is_equal_approx(hourly.current_calories, quarter.current_calories), "hunger depends on step size")
	_check(is_equal_approx(hourly.current_hydration, quarter.current_hydration), "hydration depends on step size")
	_check(is_equal_approx(hourly.current_energy, quarter.current_energy), "fatigue depends on step size")
	_dispose(hourly)
	_dispose(quarter)


func _test_carry_affects_fatigue_only() -> void:
	var light := _make_bio()
	var heavy := _make_bio()
	var empty := InventoryComponent.new()
	root.add_child(empty)
	var pack := InventoryComponent.new()
	pack.max_carry_weight = 30.0
	root.add_child(pack)
	var cargo: ItemResource = ItemCatalog.get_item(&"tinned_stew")
	while pack.try_add(cargo):
		pass
	light.carry_inventory = empty
	heavy.carry_inventory = pack
	light.pass_awake_hours(1.0)
	heavy.pass_awake_hours(1.0)
	_check(is_equal_approx(light.current_calories, heavy.current_calories), "carry weight changed hunger")
	_check(is_equal_approx(light.current_hydration, heavy.current_hydration), "carry weight changed hydration")
	_check(heavy.current_energy < light.current_energy, "carry weight did not change fatigue")
	_dispose(empty)
	_dispose(pack)
	_dispose(light)
	_dispose(heavy)


func _test_food_does_not_touch_hydration() -> void:
	var bio := _make_bio()
	bio.current_calories = 500.0
	bio.current_hydration = 35.0
	bio.add_calories(250.0)
	_check(is_equal_approx(bio.current_calories, 750.0), "food did not reach HungerComponent")
	_check(is_equal_approx(bio.current_hydration, 35.0), "calories silently changed hydration")
	_dispose(bio)


func _test_sleep_crosses_all_three_tracks() -> void:
	var bio := _make_bio(40.0)
	var before_c: float = bio.current_calories
	var before_h: float = bio.current_hydration
	var before_e: float = bio.current_energy
	bio.rest_sleep(4.0)
	_check(bio.current_calories < before_c, "sleep billed no hunger")
	_check(bio.current_hydration < before_h, "sleep billed no hydration")
	_check(bio.current_energy > before_e, "sleep restored no fatigue")
	_dispose(bio)


func _test_one_step_emits_once_per_track() -> void:
	var bio := _make_bio()
	var hunger_events: Array[float] = []
	var hydration_events: Array[float] = []
	var fatigue_events: Array[float] = []
	bio.hunger_level_changed.connect(func(value: float) -> void: hunger_events.append(value))
	bio.thirst_level_changed.connect(func(value: float) -> void: hydration_events.append(value))
	bio.energy_level_changed.connect(func(value: float) -> void: fatigue_events.append(value))
	bio.pass_awake_hours(0.25)
	_check(hunger_events.size() == 1, "one step emitted hunger %d times" % hunger_events.size())
	_check(hydration_events.size() == 1, "one step emitted hydration %d times" % hydration_events.size())
	_check(fatigue_events.size() == 1, "one step emitted fatigue %d times" % fatigue_events.size())
	_dispose(bio)


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
	push_error("metabolism components: " + message)
