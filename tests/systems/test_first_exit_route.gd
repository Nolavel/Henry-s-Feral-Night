extends SceneTree

## The First Exit greybox carries the working TestScene loop: a shelter with a
## zone, breaches that board up, a stove that heats it, and scarce pickups.
## Run: godot --headless --script tests/systems/test_first_exit_route.gd

const BLOCKOUT: String = "res://scenes/world/first_exit/first_exit_blockout.tscn"

var _failures: int = 0
var _frame: int = 0
var _scene: Node


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		_scene = (load(BLOCKOUT) as PackedScene).instantiate()
		root.add_child(_scene)
	elif _frame == 3:
		_check_shelter()
		_check_pickups()
		_finish()
	return false


func _check_shelter() -> void:
	var zone := _scene.find_child("ShelterZone", true, false) as ThermalZone
	_check(zone != null, "the shelter has no ThermalZone")
	if zone == null:
		return
	_check(zone.is_interior, "the shelter zone is not an interior")
	var breaches: Array[ShelterBreach] = zone.get_breaches()
	_check(breaches.size() == 5, "expected 5 openings, found %d" % breaches.size())
	for breach: ShelterBreach in breaches:
		_check(breach.boarded_visual != null, "%s has no boards visual" % breach.name)
		_check(breach.find_child("BoardUp", false, false) is BreachBoardUp, "%s has no board-up prompt" % breach.name)
	var before: float = zone.get_sealed_fraction()
	breaches[0].board_up()
	_check(zone.get_sealed_fraction() > before, "boarding a breach did not seal the shelter more")
	var stove := zone.find_child("Stove", false, false) as HeatSource
	_check(stove != null, "the shelter has no stove")
	if stove != null:
		_check(stove.heats_zone == zone, "the stove does not heat the shelter zone")
		_check(stove.find_child("Feed", false, false) is HeatSourceFeed, "the stove has no feed prompt")


## Every pickup is a real item, and the route stays short of an easy answer.
func _check_pickups() -> void:
	var totals: Dictionary = {}
	for node: Node in _scene.find_children("*", "Area3D", true, false):
		var pickup := node as ItemPickup
		if pickup == null:
			continue
		_check(ItemCatalog.get_item(pickup.item_id) != null, "pickup %s holds unknown item %s" % [pickup.name, pickup.item_id])
		totals[pickup.item_id] = int(totals.get(pickup.item_id, 0)) + pickup.count
	_check(int(totals.get(&"boards", 0)) < 5, "enough boards to seal every opening (%d)" % int(totals.get(&"boards", 0)))
	_check(int(totals.get(&"boards", 0)) >= 2, "too few boards to matter (%d)" % int(totals.get(&"boards", 0)))
	_check(int(totals.get(&"tinder", 0)) >= 1, "no tinder anywhere: the stove can never be lit")
	_check(int(totals.get(&"firewood", 0)) >= 2, "not enough firewood for a night")


func _finish() -> void:
	if _failures > 0:
		push_error("first exit route: %d check(s) failed" % _failures)
		quit(1)
		return
	print("first exit route: all checks passed")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("first exit route: %s" % message)
