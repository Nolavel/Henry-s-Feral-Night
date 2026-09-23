extends SceneTree

## InteractComponent: picks the target in front, acts at arm's length, walks
## over to a farther one, ignores what is behind, survives the item freeing.
## Run: godot --headless --script tests/systems/test_interaction.gd

const AREA_SCENE: String = "res://scenes/environment/interactive/InteractiveArea.tscn"
const PICKUP_SCRIPT: String = "res://scripts/environment/interactive/item_pickup.gd"
## A body with the walk contract; the walk arrives at once.
const WALKER_SOURCE: String = """extends CharacterBody3D
signal movement_stopped
func move_to_position(point: Vector3) -> void:
	global_position = point
func stop_moving() -> void:
	movement_stopped.emit()
"""

var _failures: int = 0
var _frame: int = 0
var _player: CharacterBody3D
var _component: InteractComponent
var _inventory: InventoryComponent
var _near: ItemPickup
var _far: ItemPickup
var _behind: ItemPickup


## Stages step on physics frames: detection and the walk both run there.
func _physics_process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		1:
			_build()
		4:
			_check_near_first()
		7:
			_check_far_next()
		10:
			_check_after_walk()
		13:
			_check_behind_ignored()
			_finish()
	return false


func _build() -> void:
	var walker := GDScript.new()
	walker.source_code = WALKER_SOURCE
	walker.reload()
	_player = CharacterBody3D.new()
	_player.set_script(walker)
	_player.add_to_group("player")
	var body_shape := CollisionShape3D.new()
	body_shape.shape = CapsuleShape3D.new()
	_player.add_child(body_shape)
	_inventory = InventoryComponent.new()
	_inventory.max_carry_weight = 60.0
	_player.add_child(_inventory)
	_component = InteractComponent.new()
	_player.add_child(_component)
	root.add_child(_player)
	_near = _spawn(Vector3(0.0, 0.0, -0.6))
	_far = _spawn(Vector3(0.3, 0.0, -2.2))
	_behind = _spawn(Vector3(0.0, 0.0, 2.0))


func _spawn(at: Vector3) -> ItemPickup:
	var area: Node = (load(AREA_SCENE) as PackedScene).instantiate()
	area.set_script(load(PICKUP_SCRIPT))
	var pickup := area as ItemPickup
	pickup.item_id = &"firewood"
	pickup.position = at
	root.add_child(pickup)
	return pickup


func _check_near_first() -> void:
	_check(_component.current_target == _near, "the item at arm's length is not the target")
	_check(_component.is_target_in_reach(), "the item at 0.6 m is not in reach")
	_component.try_interact()
	_check(_inventory.get_count(&"firewood") == 1, "F did not pick up the near item")


func _check_far_next() -> void:
	_check(_component.current_target == _far, "the item 2.2 m ahead is not the next target")
	_check(not _component.is_target_in_reach(), "the item 2.2 m ahead counts as in reach")
	_component.try_interact()


func _check_after_walk() -> void:
	_check(_inventory.get_count(&"firewood") == 2, "Henry did not walk over and pick up the far item")


func _check_behind_ignored() -> void:
	_check(_component.current_target == null, "an item behind Henry was targeted")
	_check(_inventory.get_count(&"firewood") == 2, "something else was picked up")


func _finish() -> void:
	if _failures > 0:
		push_error("interaction: %d check(s) failed" % _failures)
		quit(1)
		return
	print("interaction: all checks passed")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("interaction: %s" % message)
