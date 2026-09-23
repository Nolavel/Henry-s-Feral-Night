extends SceneTree

## The interact key must reach a pickup with no body of its own: the shape cast
## hits the InteractiveArea itself.
## Run: godot --headless --script tests/systems/test_interaction.gd

const AREA_SCENE: String = "res://scenes/environment/interactive/InteractiveArea.tscn"
const PICKUP_SCRIPT: String = "res://scripts/environment/interactive/item_pickup.gd"
const SETTLE_FRAMES: int = 6
const AFTER_PICKUP_FRAMES: int = 4

var _failures: int = 0
var _frame: int = 0
var _pickup: ItemPickup
var _manager: InteractionManager
var _inventory: InventoryComponent


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		_build()
	elif _frame == SETTLE_FRAMES:
		_check_pickup()
	elif _frame == SETTLE_FRAMES + AFTER_PICKUP_FRAMES:
		_finish()
	return false


func _build() -> void:
	var player := CharacterBody3D.new()
	player.add_to_group("player")
	var body_shape := CollisionShape3D.new()
	body_shape.shape = CapsuleShape3D.new()
	player.add_child(body_shape)
	_inventory = InventoryComponent.new()
	_inventory.max_carry_weight = 60.0
	player.add_child(_inventory)

	_manager = InteractionManager.new()
	var cast := ShapeCast3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 2.0
	cast.shape = sphere
	cast.target_position = Vector3.ZERO
	cast.collide_with_areas = true
	_manager.add_child(cast)
	_manager.shape_cast = cast
	_manager.player = player
	player.add_child(_manager)
	root.add_child(player)

	var area: Node = (load(AREA_SCENE) as PackedScene).instantiate()
	area.set_script(load(PICKUP_SCRIPT))
	_pickup = area as ItemPickup
	_pickup.item_id = &"firewood"
	_pickup.position = Vector3(0.5, 0.0, 0.0)
	root.add_child(_pickup)


func _check_pickup() -> void:
	_check(_pickup.can_interact(), "the pickup is in reach but cannot be interacted with")
	var press := InputEventAction.new()
	press.action = &"interact"
	press.pressed = true
	_manager._input(press)
	_check(_inventory.get_count(&"firewood") == 1, "interact did not put the firewood in the pack")


## Frames after pickup must not touch the freed item.
func _finish() -> void:
	_check(_manager.detected_areas.is_empty(), "the manager still holds the picked-up item")
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
