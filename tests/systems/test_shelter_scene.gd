extends SceneTree

## Loads the real test_shelter.tscn and checks its wiring, not the classes in
## isolation: a scene can compose working parts into a broken whole.
## Run: godot --headless --script tests/systems/test_shelter_scene.gd

const SHELTER: String = "res://scenes/environment/shelter/test_shelter.tscn"

var _failures: int = 0


func _process(_delta: float) -> bool:
	_run()
	return true


func _run() -> void:
	var shelter := (load(SHELTER) as PackedScene).instantiate() as Node3D
	root.add_child(shelter)
	var player := CharacterBody3D.new()
	player.add_to_group("player")
	var inventory := InventoryComponent.new()
	inventory.max_carry_weight = 60.0
	player.add_child(inventory)
	root.add_child(player)

	var zone := shelter.get_node("Zone") as ThermalZone
	var breach := shelter.get_node("Zone/WestWindow") as ShelterBreach
	var board_up := shelter.get_node("Zone/WestWindow/BoardUp") as BreachBoardUp
	var stove := shelter.get_node("Zone/Stove") as HeatSource
	var feed := shelter.get_node("Zone/Stove/Feed") as HeatSourceFeed

	_check(zone != null and zone.is_interior, "the shelter has no interior zone")
	_check(breach != null, "the window is not a ShelterBreach")
	_check(board_up != null and board_up.breach == breach, "the board-up prompt did not find the window")
	_check(stove != null and feed != null and feed.heat_source == stove, "the feed prompt did not find the stove")
	if _failures > 0:
		_finish()
		return

	_check(zone.get_breaches().has(breach), "the zone does not know about its window")

	## The shelter shows the weather: its walls and roof carry the snow shader.
	var roof := shelter.get_node("Walls/Roof") as MeshInstance3D
	var roof_material := roof.mesh.surface_get_material(0) as ShaderMaterial
	_check(
		roof_material != null
			and roof_material.shader.resource_path == "res://shaders/environment/snow/snow_prop.gdshader",
		"the shelter roof does not use the snow shader"
	)
	_check(not stove.is_burning(), "the stove came lit; a found shelter should start cold")
	_check(not stove.flame_light.visible, "the flame shows on a dead stove")
	_check(not breach.boarded_visual.visible, "the boards show on an open window")

	## The window must face into the blizzard, or the shelter teaches nothing.
	var blizzard := load("res://resources/weather/blizzard.tres") as WeatherProfile
	var wind: Vector3 = Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(blizzard.wind_direction_deg))
	_check(
		breach.get_exposure_against(wind) > breach.severity * 0.9,
		"the window does not face the blizzard: costs %.2f of %.2f"
		% [breach.get_exposure_against(wind), breach.severity]
	)

	## Lay a real three-board armful beside the window. This no longer performs
	## an instant binary repair; hammer+nails place each board later.
	for _i: int in range(3):
		inventory.try_add(ItemCatalog.get_item(&"boards"))
	board_up._on_interaction_performed()
	_check(breach.get_staged_boards() == 3, "the armful was not staged beside the window")
	_check(not inventory.has_item(&"boards"), "staging left boards in Henry's hands")
	_check(not breach.is_boarded(), "laying boards beside the window magically sealed it")
	_check(not breach.boarded_visual.visible, "legacy three-plank visual appeared for staged boards")
	breach.place_board(-0.30)
	breach.place_board(0.0)
	breach.place_board(0.30)
	_check(breach.get_coverage_fraction() > 0.5 and not breach.is_boarded(),
		"three real placements did not leave the intended residual gap")

	## Light it with real items through the real prompt.
	inventory.try_add(ItemCatalog.get_item(&"tinder"))
	inventory.try_add(ItemCatalog.get_item(&"firewood"))
	_check(feed.feed() == HeatSourceFeed.Refusal.NONE, "the stove would not light")
	_check(stove.is_burning(), "the stove did not light")
	_check(stove.flame_light.visible, "the flame did not show")
	for i: int in range(6):
		zone.advance_heating(0.5)
	_check(zone.get_heated_offset_c() > 0.0, "the lit stove did not warm the room")

	_dispose(player)
	_dispose(shelter)
	_test_hand_carried_pickups()
	_finish()


func _test_hand_carried_pickups() -> void:
	var player := CharacterBody3D.new()
	player.add_to_group("player")
	var inventory := InventoryComponent.new()
	player.add_child(inventory)
	root.add_child(player)

	var two_logs := ItemPickup.new()
	two_logs.item_id = &"firewood"
	two_logs.count = 2
	root.add_child(two_logs)
	_check(two_logs.pick_up(), "two logs were refused with empty hands")
	_check(inventory.get_count(&"firewood") == 2, "two picked logs were not carried")

	var third_log := ItemPickup.new()
	third_log.item_id = &"firewood"
	root.add_child(third_log)
	_check(third_log.pick_up(), "the third log was refused")
	_check(inventory.get_count(&"firewood") == 3, "the third log did not join the armful")

	var fourth_log := ItemPickup.new()
	fourth_log.item_id = &"firewood"
	root.add_child(fourth_log)
	_check(not fourth_log.pick_up(), "a fourth log exceeded the three-unit hand limit")
	_check(inventory.get_count(&"firewood") == 3, "a refused fourth log changed the count")
	_dispose(fourth_log)

	var board_while_logs := ItemPickup.new()
	board_while_logs.item_id = &"boards"
	root.add_child(board_while_logs)
	_check(not board_while_logs.pick_up(), "boards mixed into an occupied firewood armful")
	_dispose(board_while_logs)

	while inventory.has_item(&"firewood"):
		inventory.try_remove(&"firewood")
	var three_boards := ItemPickup.new()
	three_boards.item_id = &"boards"
	three_boards.count = 3
	root.add_child(three_boards)
	_check(three_boards.pick_up(), "three boards were refused with free hands")
	_check(inventory.get_count(&"boards") == 3, "three boards were not carried")
	var fourth_board := ItemPickup.new()
	fourth_board.item_id = &"boards"
	root.add_child(fourth_board)
	_check(not fourth_board.pick_up(), "a fourth board exceeded the hand limit")
	_dispose(fourth_board)
	_dispose(player)


func _finish() -> void:
	if _failures > 0:
		push_error("shelter scene: %d check(s) failed" % _failures)
		quit(1)
		return
	print("shelter scene: all checks passed")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("shelter scene: %s" % message)


func _dispose(node: Node) -> void:
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	node.free()
