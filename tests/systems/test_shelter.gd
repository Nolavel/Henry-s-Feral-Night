extends SceneTree

## Covers the shelter you have to prepare: breaches that cost warmth by which
## way they face, boards that close them, and a fire that cannot heat a hole.
## Run: godot --headless --script tests/systems/test_shelter.gd

## Wind blowing towards -Z, so a breach facing +Z takes it head on.
const NORTH_WIND: Vector3 = Vector3(0.0, 0.0, -1.0)
const STEP_MINUTES: float = 10.0

var _failures: int = 0


func _process(_delta: float) -> bool:
	_run()
	return true


func _run() -> void:
	_test_a_breachless_zone_behaves_as_before()
	_test_a_breach_facing_the_wind_costs_more_than_one_in_the_lee()
	_test_boarding_restores_the_shelter()
	_test_a_fire_cannot_heat_a_holed_shelter()
	_test_boarding_costs_an_item()
	_test_boards_survive_a_save_round_trip()
	_test_a_holed_shelter_freezes_the_player_faster()
	if _failures > 0:
		push_error("shelter: %d check(s) failed" % _failures)
		quit(1)
		return
	print("shelter: all checks passed")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("shelter: %s" % message)


func _dispose(node: Node) -> void:
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	node.free()


## A zone with one breach turned to face `facing`.
func _make_zone(severity: float, facing: Vector3) -> ThermalZone:
	var zone := ThermalZone.new()
	zone.wind_exposure = 0.1
	zone.temperature_offset_c = 14.0
	zone.is_interior = true
	zone.max_heated_offset_c = 20.0
	root.add_child(zone)
	if severity > 0.0:
		var breach := ShelterBreach.new()
		breach.name = "Window"
		breach.severity = severity
		root.add_child(breach)
		root.remove_child(breach)
		zone.add_child(breach)
		## look_at aims -Z at the target, and -Z is the breach's outward face.
		breach.look_at_from_position(Vector3.ZERO, facing, Vector3.UP)
	zone.refresh_breaches()
	return zone


## The old behaviour, unchanged: no breaches means the authored number stands.
func _test_a_breachless_zone_behaves_as_before() -> void:
	var zone := _make_zone(0.0, Vector3.FORWARD)
	_check(
		is_equal_approx(zone.get_wind_exposure(NORTH_WIND), zone.wind_exposure),
		"a breachless zone reported %.3f, expected its authored %.3f"
		% [zone.get_wind_exposure(NORTH_WIND), zone.wind_exposure]
	)
	_check(is_equal_approx(zone.get_sealed_fraction(), 1.0), "a breachless zone is not sealed")
	_check(
		is_equal_approx(zone.get_heat_ceiling_c(), zone.max_heated_offset_c),
		"a breachless zone lost heat ceiling"
	)
	_dispose(zone)


## The whole point: where the hole points decides what it costs.
func _test_a_breach_facing_the_wind_costs_more_than_one_in_the_lee() -> void:
	var windward := _make_zone(0.6, Vector3.BACK)
	var leeward := _make_zone(0.6, Vector3.FORWARD)
	var into: float = windward.get_wind_exposure(NORTH_WIND)
	var away: float = leeward.get_wind_exposure(NORTH_WIND)
	_check(
		into > away,
		"facing the wind cost %.3f, facing away cost %.3f — the direction did nothing"
		% [into, away]
	)
	_check(into > windward.wind_exposure, "a windward hole added no exposure at all")
	_check(
		is_equal_approx(away, leeward.wind_exposure),
		"a hole in the lee still cost %.3f above the base leak" % (away - leeward.wind_exposure)
	)
	_dispose(windward)
	_dispose(leeward)


func _test_boarding_restores_the_shelter() -> void:
	var zone := _make_zone(0.6, Vector3.BACK)
	var breach: ShelterBreach = zone.get_breaches()[0]
	var open: float = zone.get_wind_exposure(NORTH_WIND)
	_check(breach.board_up(), "boarding an open breach was refused")
	_check(not breach.board_up(), "boarding an already boarded breach was allowed twice")
	_check(
		zone.get_wind_exposure(NORTH_WIND) < open,
		"boarding the hole did not reduce exposure"
	)
	_check(
		is_equal_approx(zone.get_wind_exposure(NORTH_WIND), zone.wind_exposure),
		"a boarded shelter is not back to its base leak"
	)
	_check(is_equal_approx(zone.get_sealed_fraction(), 1.0), "a boarded shelter is not sealed")
	_dispose(zone)


## A fire in a holed room is a fire outside. This is what makes boarding worth
## the trouble rather than optional decoration.
func _test_a_fire_cannot_heat_a_holed_shelter() -> void:
	var holed := _make_zone(0.5, Vector3.BACK)
	var sealed := _make_zone(0.5, Vector3.BACK)
	sealed.get_breaches()[0].board_up()

	for zone: ThermalZone in [holed, sealed]:
		zone.add_heat_source()
		for i: int in range(40):
			zone.advance_heating(0.5)

	_check(
		holed.get_total_offset_c() < sealed.get_total_offset_c(),
		"the holed room reached %.2f and the boarded one %.2f"
		% [holed.get_total_offset_c(), sealed.get_total_offset_c()]
	)
	_check(
		holed.get_heated_offset_c() <= holed.get_heat_ceiling_c() + 0.01,
		"the holed room burned to %.2f, past its ceiling of %.2f"
		% [holed.get_heated_offset_c(), holed.get_heat_ceiling_c()]
	)
	_check(
		sealed.get_heated_offset_c() > sealed.max_heated_offset_c * 0.9,
		"the boarded room only reached %.2f of %.2f"
		% [sealed.get_heated_offset_c(), sealed.max_heated_offset_c]
	)

	## Tearing the boards off mid-night must drop the stored warmth too.
	sealed.get_breaches()[0].tear_open()
	sealed.advance_heating(0.1)
	_check(
		sealed.get_heated_offset_c() <= sealed.get_heat_ceiling_c() + 0.01,
		"pulling the boards off left %.2f stored above a ceiling of %.2f"
		% [sealed.get_heated_offset_c(), sealed.get_heat_ceiling_c()]
	)
	_dispose(holed)
	_dispose(sealed)


func _test_boarding_costs_an_item() -> void:
	var zone := _make_zone(0.5, Vector3.BACK)
	var breach: ShelterBreach = zone.get_breaches()[0]
	var inventory := InventoryComponent.new()
	root.add_child(inventory)

	_check(breach.repair_item_id == &"boards", "a breach costs nothing to board")
	_check(ItemCatalog.get_item(&"boards") != null, "the catalog has no boards to repair with")
	_check(not inventory.has_item(&"boards"), "the inventory started with boards")
	inventory.try_add(ItemCatalog.get_item(&"boards"))
	_check(inventory.has_item(&"boards"), "boards would not go into the inventory")

	## The interactable spends exactly one and refuses when there are none.
	_check(inventory.try_remove(&"boards"), "spending a board failed")
	_check(not inventory.has_item(&"boards"), "spending a board left it in the inventory")
	_check(not inventory.try_remove(&"boards"), "an empty inventory still yielded a board")
	_dispose(inventory)
	_dispose(zone)


func _test_boards_survive_a_save_round_trip() -> void:
	var zone := _make_zone(0.5, Vector3.BACK)
	zone.name = "Cabin"
	var breach: ShelterBreach = zone.get_breaches()[0]
	var state := ShelterState.new()
	root.add_child(state)

	var context := WorldContext.new()
	context.world = zone
	state.on_world_ready(context)
	breach.board_up()

	var saved: Dictionary = state.get_save_data()
	_check(
		SaveManager.implements_save_contract(state),
		"ShelterState does not implement the whole save contract"
	)

	breach.tear_open()
	_check(not breach.is_boarded(), "tearing the boards off did nothing")
	state.load_save_data(saved)
	_check(breach.is_boarded(), "a loaded save did not put the boards back")
	_dispose(state)
	_dispose(zone)


## The reason any of this exists: a hole in the wall has to be felt.
func _test_a_holed_shelter_freezes_the_player_faster() -> void:
	var holed: float = _survive_a_night(0.7)
	var sealed: float = _survive_a_night(0.0)
	_check(
		holed < sealed,
		"a night in a holed shelter ended at %.2f C, a sealed one at %.2f C"
		% [holed, sealed]
	)


## Runs one night in a shelter with a breach of the given severity facing the
## wind, and reports the body temperature left at the end.
func _survive_a_night(severity: float) -> float:
	var weather := WeatherController.new()
	weather.profiles = WeatherController.load_profiles_from("res://resources/weather")
	weather.starting_profile_id = &"windy"
	weather.scheduler_enabled = false
	root.add_child(weather)
	weather.initialize()

	## The hole is turned into whatever the profile is actually blowing, so
	## this measures the breach and not a guess about the bearing.
	var zone := _make_zone(severity, -weather.get_wind_direction())

	var thermal := ThermalManager.new()
	thermal.weather_controller = weather
	root.add_child(thermal)
	thermal.initialize()
	thermal._on_zone_entered(zone)

	var hour: float = 20.0
	for i: int in range(36):
		hour = fmod(hour + STEP_MINUTES / 60.0, 24.0)
		thermal._on_time_update(hour)
	var result: float = thermal.get_body_temperature_c()

	_dispose(thermal)
	_dispose(weather)
	_dispose(zone)
	return result
