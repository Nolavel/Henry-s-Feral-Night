extends SceneTree

## Lighting as an act (#42): F spends tinder and a log at once, the door opens
## and a weak flame grows, but the fire only burns and heats after LIGHT_SECONDS;
## a log on a live fire takes ADD_SECONDS and no tinder. Henry holds still meanwhile.
## Run: godot --headless --script tests/systems/test_stove_act.gd

const BODY: String = """extends CharacterBody3D
var held: float = 0.0
func hold_still(seconds: float) -> void:
	held = seconds
func play_action_animation(_action: StringName) -> bool:
	return true
"""

var _failures: int = 0
var _time: float = 0.0
var _phase: int = 0
var _stove: HeatSource
var _visual: StoveVisual
var _feed: HeatSourceFeed
var _inventory: InventoryComponent
var _body: CharacterBody3D


func _process(delta: float) -> bool:
	_time += delta
	match _phase:
		0:
			_build()
			_check(_visual.get_capacity_logs() == 3, "a 6 h stove at 2 h a log shows more than 3 logs")
			_check(_feed.begin_act() == HeatSourceFeed.Refusal.NONE, "F did not start lighting")
			_check(not _stove.is_burning(), "the fire burned before the act finished")
			_check(not _inventory.has_item(&"tinder") and _inventory.get_count(&"firewood") == 1,
				"lighting did not take one tinder and one log")
			_check(is_equal_approx(float(_body.get(&"held")), HeatSourceFeed.LIGHT_SECONDS), "Henry was not held for the lighting")
			_check(not _feed.can_interact(), "the stove offered F again mid-act")
			_phase = 1
			_time = 0.0
		1:
			if _time > 0.6 and _time < 0.7:
				_check(_visual.is_door_open(), "the door did not open for lighting")
			if _time > HeatSourceFeed.LIGHT_SECONDS + 0.8:
				_check(_stove.is_burning(), "the fire did not take after the lighting act")
				_check(not _visual.is_door_open(), "the door stayed open after lighting")
				_check(_feed.begin_act() == HeatSourceFeed.Refusal.NONE, "a log on the live fire was refused")
				_check(_inventory.get_count(&"firewood") == 0, "adding a log did not take it")
				_check(is_equal_approx(float(_body.get(&"held")), HeatSourceFeed.ADD_SECONDS), "adding a log is not the short act")
				_phase = 2
				_time = 0.0
		2:
			if _time > HeatSourceFeed.ADD_SECONDS + 0.5:
				_check(is_equal_approx(_stove.get_remaining_hours(), 4.0), "two logs did not make 4 h (%.2f)" % _stove.get_remaining_hours())
				print("test_stove_act: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
				quit(1 if _failures > 0 else 0)
	return false


func _build() -> void:
	var script := GDScript.new()
	script.source_code = BODY
	script.reload()
	_body = CharacterBody3D.new()
	_body.set_script(script)
	_body.add_to_group(&"player")
	_inventory = InventoryComponent.new()
	_body.add_child(_inventory)
	root.add_child(_body)
	for id: String in ["tinder", "firewood", "firewood"]:
		_inventory.try_add(load("res://data/items/%s.tres" % id) as ItemResource)
	_stove = HeatSource.new()
	_stove.starts_burning = false
	_stove.burn_duration_h = 6.0
	_stove.hours_per_fuel_unit = 2.0
	_visual = StoveVisual.new()
	_visual.name = "StoveVisual"
	_stove.add_child(_visual)
	_feed = HeatSourceFeed.new()
	_feed.heat_source = _stove
	_feed.interactive_mesh = MeshInstance3D.new()
	_feed.add_child(_feed.interactive_mesh)
	_stove.add_child(_feed)
	root.add_child(_stove)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)
