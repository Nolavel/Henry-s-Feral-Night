extends SceneTree

## Held flare: quick-use spends a pocketed flare into the shared hand socket,
## the arm eases into the held pose, and a second quick-use drops it burning.
## Run: godot --headless --script tests/systems/test_held_light.gd

const VISUAL: String = "res://scenes/actors/player/HenryUALVisual.tscn"
const BODY_SOURCE: String = """extends CharacterBody3D
var animation_component: HenryUALAnimation
func get_locomotion_speed_ratio() -> float:
	return 0.0
func get_crouch_speed_ratio() -> float:
	return 0.0
func is_crouching() -> bool:
	return false
func get_view_direction() -> Vector3:
	return Vector3.FORWARD
"""

var _failures: int = 0
var _frame: int = 0
var _body: CharacterBody3D
var _visual: HenryUALAnimation
var _inventory: InventoryComponent
var _equipment: EquipmentComponent
var _light: HeldLightComponent


func _process(delta: float) -> bool:
	_frame += 1
	match _frame:
		1:
			_build()
			_check(not _light.light(), "a flare lit with none in the inventory")
			_inventory.try_add(load("res://data/items/road_flare.tres") as ItemResource)
			_check(_light.light(), "a flare in the inventory did not light")
			_check(not _inventory.has_item(&"road_flare"), "lighting did not spend the flare")
			var flare := _visual.get_held_prop() as HeldFlare
			_check(flare != null and flare.is_burning(), "no burning flare in Henry's hand")
			_check(flare != null and flare.get_parent() == _visual.get_hand_socket(), "the flare is not on the shared hand socket")
			_check(_visual.get_hand_socket().bone_name == &"hand_l", "the hand socket is not on the Idle_Torch hand (hand_l)")
		10:
			_visual.update_animation_blend(0.5)
			_check(float(_visual.animation_tree.get("parameters/hold_pose/blend_amount")) > 0.9, "the arm did not rise into the held pose")
			_light.drop()
			_check(not _light.is_holding() and _visual.get_held_prop() == null, "dropping left the flare in hand")
		11:
			_visual.update_animation_blend(0.5)
			_check(float(_visual.animation_tree.get("parameters/hold_pose/blend_amount")) < 0.1, "the arm stayed raised after the drop")
			var dropped: Array[Node] = root.find_children("*", "HeldFlare", true, false)
			_check(dropped.size() == 1 and (dropped[0] as HeldFlare).is_burning(), "the dropped flare is not burning on the ground")
			_check(_equipment.stow_anywhere(&"road_flare") == EquipmentComponent.Refusal.NONE,
				"a second flare would not enter a Quick Access pocket")
			_check(_light.light(), "L-style light() could not consume a pocketed flare")
			var pocketed: int = 0
			for pocket: Dictionary in _equipment.get_available_pockets():
				if pocket["item_id"] == &"road_flare":
					pocketed += 1
			_check(pocketed == 0, "lighting left the flare in its pocket")
			_finish()
	return false


func _build() -> void:
	var script := GDScript.new()
	script.source_code = BODY_SOURCE
	_check(script.reload() == OK, "test body script did not compile")
	_body = CharacterBody3D.new()
	_body.set_script(script)
	_equipment = EquipmentComponent.new()
	_equipment.name = "EquipmentComponent"
	_equipment.layout = load("res://data/equipment/player_layout.tres") as EquipmentLayout
	_equipment.starter_garment_ids = [&"worn_coat"]
	_body.add_child(_equipment)
	_inventory = InventoryComponent.new()
	_inventory.equipment = _equipment
	_body.add_child(_inventory)
	_visual = (load(VISUAL) as PackedScene).instantiate() as HenryUALAnimation
	_body.add_child(_visual)
	_body.set(&"animation_component", _visual)
	_light = HeldLightComponent.new()
	_light.inventory = _inventory
	_body.add_child(_light)
	root.add_child(_body)


func _finish() -> void:
	if _failures > 0:
		push_error("held light: %d check(s) failed" % _failures)
		quit(1)
		return
	print("held light: all checks passed")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("held light: %s" % message)
