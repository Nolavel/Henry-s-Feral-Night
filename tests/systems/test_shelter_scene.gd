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

	## Board it up with a real item through the real prompt.
	inventory.try_add(ItemCatalog.get_item(&"boards"))
	board_up._on_interaction_performed()
	_check(breach.is_boarded(), "the prompt did not board the window")
	_check(breach.boarded_visual.visible, "the boards did not appear")
	_check(not inventory.has_item(&"boards"), "boarding did not spend the boards")

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
	_test_a_pickup_goes_into_the_pack()
	_finish()


func _test_a_pickup_goes_into_the_pack() -> void:
	var player := CharacterBody3D.new()
	player.add_to_group("player")
	var inventory := InventoryComponent.new()
	player.add_child(inventory)
	root.add_child(player)

	var pickup := ItemPickup.new()
	pickup.item_id = &"firewood"
	pickup.count = 2
	root.add_child(pickup)
	_check(pickup.pick_up(), "a pickup refused to go into an empty pack")
	_check(inventory.get_count(&"firewood") == 2, "the pack holds %d firewood, expected 2" % inventory.get_count(&"firewood"))

	inventory.max_carry_weight = inventory.get_total_weight() + 1.0
	var heavy := ItemPickup.new()
	heavy.item_id = &"firewood"
	root.add_child(heavy)
	_check(not heavy.pick_up(), "a pickup went into a full pack")
	_check(inventory.get_count(&"firewood") == 2, "a refused pickup still added wood")
	_dispose(heavy)
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
