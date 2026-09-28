extends SceneTree

## Staged transfers conserve items; held ignition and saved warmup share game time.
class FireParticipant:
	extends Node

	func get_simulation_priority() -> int:
		return 300

	func advance_simulation(hours: float, _context: SimulationStepContext) -> void:
		HeatSource.advance_all_fuel(hours)

var _failures: int = 0


func _initialize() -> void:
	call_deferred(&"_run")


func _run() -> void:
	var previous_locale: String = TranslationServer.get_locale()
	for locale: String in ["en", "ru"]:
		TranslationServer.set_locale(locale)
		for key: String in ["STOVE_WARMING", "STOVE_BURNING", "STOVE_EMPTY", "STOVE_TRANSFER", "STOVE_CANCEL_TRANSFER"]:
			_check(tr(key) != key, "missing stove translation: " + locale + "/" + key)
	TranslationServer.set_locale(previous_locale)
	var clock := SimulationClock.new()
	root.add_child(clock)
	var participant := FireParticipant.new()
	root.add_child(participant)
	clock.register_participant(participant)
	var actions := TimeCostedActionSystem.new()
	actions.simulation_clock = clock
	root.add_child(actions)
	actions.set_process(false)
	var player := CharacterBody3D.new()
	player.add_to_group(&"player")
	var inventory := InventoryComponent.new()
	player.add_child(inventory)
	var carry := CarryComponent.new()
	carry.inventory = inventory
	player.add_child(carry)
	root.add_child(player)
	var stove := HeatSource.new()
	stove.starts_burning = false
	stove.warmup_seconds = 20.0
	var feed := HeatSourceFeed.new()
	feed.name = "Feed"
	feed.heat_source = stove
	stove.add_child(feed)
	root.add_child(stove)
	feed.set_process(false)
	var wood: ItemResource = ItemCatalog.get_item(&"firewood")
	for _i: int in range(3):
		inventory.try_add(wood)
	feed.toggle_door()
	_check(feed.transfer_logs(2) == HeatSourceFeed.Refusal.NONE, "pair load refused")
	actions._process(1.0)
	feed.cancel_act()
	_check(inventory.get_count(&"firewood") == 3 and stove.get_remaining_hours() == 0.0, "cancel lost resources")
	var before: float = clock.get_total_hours()
	_check(feed.transfer_logs(2) == HeatSourceFeed.Refusal.NONE, "pair retry refused")
	actions._process(3.99)
	_check(stove.get_remaining_hours() == 0.0 and inventory.get_count(&"firewood") == 3, "pair committed early")
	actions._process(0.01)
	_check(stove.get_recoverable_log_count() == 2 and inventory.get_count(&"firewood") == 1, "pair changed wrong counts")
	_check(is_equal_approx(clock.get_total_hours() - before, 1.0 / 60.0), "pair billed wrong time")
	_check(feed.begin_act() == HeatSourceFeed.Refusal.HANDS_OCCUPIED, "lighter accepted wood-filled hands")
	_check(feed.transfer_logs(2) == HeatSourceFeed.Refusal.NONE, "one-log fallback refused")
	actions._process(2.0)
	_check(stove.get_recoverable_log_count() == 3 and not carry.is_carrying(), "last carried log failed")
	inventory.try_add(wood)
	_check(feed.transfer_logs(1) == HeatSourceFeed.Refusal.ALREADY_FULL, "full stove wasted a log")
	inventory.try_remove(&"firewood")
	inventory.max_carry_weight = wood.weight * 1.5
	_check(feed.transfer_logs(2) == HeatSourceFeed.Refusal.NONE, "weight-limited return refused")
	actions._process(2.0)
	_check(carry.get_carried_count() == 1 and stove.get_recoverable_log_count() == 2, "return did not show one held log")
	inventory.max_carry_weight = 30.0
	_check(feed.transfer_logs(2) == HeatSourceFeed.Refusal.NONE, "latched repeat return refused")
	actions._process(4.0)
	_check(carry.get_carried_count() == 3 and stove.get_remaining_hours() == 0.0, "repeat return loaded instead or duplicated")
	_check(feed.begin_act() == HeatSourceFeed.Refusal.NONE and not feed.is_acting(), "F did not finish return separately")
	_check(feed.transfer_logs(2) == HeatSourceFeed.Refusal.NONE, "load after return refused")
	actions._process(4.0)
	inventory.try_remove(&"firewood")
	var saved_inventory: Dictionary = inventory.get_save_data()
	var saved_fire: Dictionary = stove.get_fire_save_data()
	stove.restore_fire_save_data(saved_fire)
	inventory.load_save_data(saved_inventory)
	_check(stove.get_recoverable_log_count() == 2, "cold whole logs not restored")
	inventory.try_add(ItemCatalog.get_item(&"boards"))
	_check(feed.transfer_logs(1) != HeatSourceFeed.Refusal.NONE, "return accepted occupied hands")
	inventory.try_remove(&"boards")
	inventory.try_add(ItemCatalog.get_item(&"lighter"))
	inventory.try_add(ItemCatalog.get_item(&"tinder"))
	feed.strike_success_chance = 0.0
	_check(feed.begin_act() == HeatSourceFeed.Refusal.NONE, "lighter preparation refused")
	actions._process(10.0)
	_check(not stove.is_burning(), "manual action auto-ignited")
	for index: int in range(5):
		_check(feed.attempt_lighter_strike(10.0 + index) == HeatSourceFeed.StrikeResult.SPARK, "forced miss ignited")
		feed.advance_lighter_hold(10.0)
		_check(not stove.is_burning(), "held miss retried itself")
	_check(feed.attempt_lighter_strike(14.1) == HeatSourceFeed.StrikeResult.IGNORED, "animation interval not respected")
	_check(feed.attempt_lighter_strike(15.0) == HeatSourceFeed.StrikeResult.FLAME, "sixth strike not guaranteed")
	feed.advance_lighter_hold(2.9)
	_check(not stove.is_burning() and inventory.has_item(&"tinder"), "short hold spent tinder")
	feed.release_lighter()
	feed.strike_success_chance = 1.0
	feed.attempt_lighter_strike(16.0)
	feed.advance_lighter_hold(0.2)
	_check(not stove.is_burning(), "short holds accumulated")
	var state: Node = root.get_node(^"PlayerState")
	state.call(&"open_menu")
	_check(not feed._flame_held and not feed._lighter.is_flame_visible(), "paused menu retained lighter flame")
	feed.advance_lighter_hold(3.0)
	_check(not stove.is_burning() and inventory.has_item(&"tinder"), "menu pause ignited tinder")
	state.call(&"close_menu")
	_check(not feed._flame_held, "closing menu reignited the lighter")
	feed.set_target_state(true, true)
	feed.set_target_state(false, false)
	_check(not feed.is_acting() and inventory.has_item(&"tinder"), "lost focus failed to cancel")
	_check(feed.begin_act() == HeatSourceFeed.Refusal.NONE, "prepare after cancellation failed")
	feed.attempt_lighter_strike(17.0)
	before = clock.get_total_hours()
	feed.advance_lighter_hold(3.0)
	_check(stove.is_burning() and not inventory.has_item(&"tinder"), "three-second hold did not catch")
	_check(is_equal_approx(clock.get_total_hours() - before, 2.0 / 60.0), "ignition billed wrong time")
	_check(is_equal_approx(stove.get_intensity(), 0.08), "fire started fully developed")
	_check(stove.get_recoverable_log_count() == 0, "burning logs became whole wood")
	stove.advance_fuel(10.0 / 3600.0)
	_check(is_equal_approx(stove.get_intensity(), 0.54), "half warmup intensity wrong")
	var half_save: Dictionary = stove.get_fire_save_data()
	stove.restore_fire_save_data(half_save)
	_check(is_equal_approx(stove.get_intensity(), 0.54), "save lost warmup progress")
	stove.advance_fuel(10.0 / 3600.0)
	_check(is_equal_approx(stove.get_intensity(), 1.0), "twenty-second warmup incomplete")
	stove.extinguish()
	_check(stove.get_recoverable_log_count() == 0, "charred remainder returned whole logs")
	stove.restore_fire_save_data({"remaining_h": 4.0, "burning": true})
	_check(is_equal_approx(stove.get_intensity(), 1.0), "old burning save not full strength")
	stove.restore_fire_save_data(half_save)
	clock.advance_hours(1.0, &"sleep")
	_check(is_equal_approx(stove.get_intensity(), 1.0), "sleep did not advance warmup")
	var zone := ThermalZone.new()
	zone.max_heated_offset_c = 18.0
	root.add_child(zone)
	stove.extinguish()
	stove.heats_zone = zone
	stove.restore_fuel(0.5, true)
	stove.advance_fuel(1.0)
	zone.advance_heating(1.0)
	_check(is_equal_approx(zone.get_heated_offset_c(), 3.0), "last half-hour of heat was lost")
	print("test_stove_act: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("stove act: " + message)
