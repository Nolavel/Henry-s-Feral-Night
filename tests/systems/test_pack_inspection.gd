extends SceneTree

## Full inspection (#75): from the Hub the pack comes off, stands in front of Henry
## fully open, and goes back on when the Hub closes; set down by the stove, it
## opens where it stands and stays there, ajar, afterwards.
## Run: godot --headless --script tests/systems/test_pack_inspection.gd

const VISUAL: String = "res://scenes/actors/player/HenryUALVisual.tscn"

var _failures: int = 0
var _frame: int = 0


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 2:
		var body := CharacterBody3D.new()
		var visual := (load(VISUAL) as PackedScene).instantiate() as HenryUALAnimation
		visual.name = "HenryUALVisual"
		body.add_child(visual)
		var hub := PlayerHubComponent.new()
		hub.inventory = InventoryComponent.new()
		body.add_child(hub.inventory)
		body.add_child(hub)
		root.add_child(body)
		var pack: PackRig = visual.get_pack_rig()
		pack.visible = true
		var opened: Array[PackRig] = []
		hub.inspection_opened.connect(func(p: PackRig) -> void: opened.append(p))

		_check(hub.open_inspection(), "inspection did not open from standing")
		_check(hub.is_open() and hub.is_inspecting(), "the Hub is not in inspection")
		_check(visual.is_pack_down(), "inspection did not take the pack off")
		_check(pack.get_openness() == PackRig.Openness.FULL, "the inspected pack is not fully open")
		_check(opened == [pack], "inspection_opened did not hand over the pack")
		hub.close()
		_check(not visual.is_pack_down(), "closing did not put the pack back on")
		_check(pack.get_openness() == PackRig.Openness.CLOSED, "the pack back on Henry is not closed")

		visual.set_pack_down(Transform3D(Basis.IDENTITY, Vector3(-1.0, 0.0, 0.0)), Transform3D(Basis.IDENTITY, Vector3(1.0, 0.0, 0.0)))
		_check(pack.get_node_or_null(^"Inspect") is PackInspectPrompt, "the set-down pack offers no F — Go through the pack")
		_check(hub.open_inspection(), "inspection did not open on the set-down pack")
		hub.close()
		_check(visual.is_pack_down(), "closing inspection picked up a pack set down by the stove")
		_check(pack.get_openness() == PackRig.Openness.AJAR, "the pack by the stove did not return to ajar")
		visual.pick_pack_up()
		_check(pack.get_node_or_null(^"Inspect") == null, "the inspect prompt stayed on the worn pack")
		print("test_pack_inspection: %s" % ("PASS" if _failures == 0 else "%d FAILED" % _failures))
		quit(1 if _failures > 0 else 0)
	return false


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("FAIL: " + message)
