class_name HeldLightComponent
extends Node

## Lights a road flare into Henry's raised hand through Use (Hub or a pocket);
## the next quick-access click drops it. Either way it burns out and is gone.

signal flare_lit(flare: HeldFlare)
signal flare_dropped(flare: HeldFlare)

const FLARE_SCENE: PackedScene = preload("res://scenes/actors/player/held/HeldFlare.tscn")
## Seconds a spent flare lingers so its last smoke can clear.
const SPENT_LINGER_S: float = 3.0

@export var inventory: InventoryComponent
@export var flare_item_id: StringName = &"road_flare"

var _flare: HeldFlare
var _context: WorldContext


## Forwarded by Player; the flare needs the context for live wind.
func on_world_ready(context: WorldContext) -> void:
	_context = context


func _ready() -> void:
	if inventory == null:
		inventory = InventoryComponent.find_in(get_parent())


## Item Use contract (PlayerHubComponent): Use on a flare lights it.
func can_use(item_id: StringName) -> bool:
	return item_id == flare_item_id and not is_holding() and inventory != null and inventory.has_item(item_id)


func use(item_id: StringName) -> bool:
	return can_use(item_id) and light()


## Quick access puts away what is in hand first: the burning flare is dropped.
func release_held() -> bool:
	if not is_holding():
		return false
	drop()
	return true


func toggle() -> void:
	if is_holding():
		drop()
	else:
		light()


func is_holding() -> bool:
	return is_instance_valid(_flare)


## Spends one flare from the pack or a Quick Access pocket and puts it,
## burning, in Henry's hand.
func light() -> bool:
	var animation: HenryUALAnimation = _animation()
	if is_holding() or animation == null or inventory == null:
		return false
	if not _take_flare():
		return false
	_flare = FLARE_SCENE.instantiate() as HeldFlare
	animation.hold_in_hand(_flare)
	if _context != null:
		_flare.on_world_ready(_context)
	_flare.spent.connect(_on_spent.bind(_flare))
	flare_lit.emit(_flare)
	return true


## Lays the burning flare on the ground at Henry's feet.
func drop() -> void:
	var animation: HenryUALAnimation = _animation()
	if not is_holding() or animation == null:
		return
	var flare: HeldFlare = _flare
	_flare = null
	var hand_xf: Transform3D = flare.global_transform
	animation.release_hand()
	var world: Node = get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	world.add_child(flare)
	var feet: Vector3 = (get_parent() as Node3D).global_position
	flare.global_transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(hand_xf.origin.x, feet.y + 0.05, hand_xf.origin.z))
	flare_dropped.emit(flare)


func _on_spent(flare: HeldFlare) -> void:
	if flare == _flare:
		_flare = null
		var animation: HenryUALAnimation = _animation()
		if animation != null:
			animation.release_hand()
	if not is_instance_valid(flare):
		return
	if flare.get_parent() == null:
		flare.free()
		return
	get_tree().create_timer(SPENT_LINGER_S).timeout.connect(func() -> void:
		if is_instance_valid(flare):
			flare.queue_free())


func _take_flare() -> bool:
	if inventory.try_remove(flare_item_id):
		return true
	var player: Node = get_parent()
	var equipment := player.get_node_or_null(^"EquipmentComponent") as EquipmentComponent if player != null else null
	if equipment == null:
		return false
	for pocket: Dictionary in equipment.get_available_pockets():
		if pocket["item_id"] != flare_item_id:
			continue
		return equipment.take_from_pocket(pocket["body_slot"], pocket["pocket"]) == flare_item_id
	return false


func _animation() -> HenryUALAnimation:
	var player: Node = get_parent()
	return player.get(&"animation_component") as HenryUALAnimation if player != null else null
