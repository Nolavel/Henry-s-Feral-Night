class_name HeldLightComponent
extends Node

## Road flare held-item state.
## Quick Access may draw an unlit flare into Henry's existing hand socket;
## Use lights it, and Use again drops the burning flare.

signal flare_drawn(flare: HeldFlare)
signal flare_lit(flare: HeldFlare)
signal flare_dropped(flare: HeldFlare)

const FLARE_SCENE: PackedScene = preload("res://scenes/actors/player/held/HeldFlare.tscn")
const SPENT_LINGER_S: float = 3.0

@export var inventory: InventoryComponent
@export var flare_item_id: StringName = &"road_flare"

var _flare: HeldFlare
var _source_zone: StringName = &""
var _context: WorldContext


func on_world_ready(context: WorldContext) -> void:
	_context = context


func _ready() -> void:
	if inventory == null:
		inventory = InventoryComponent.find_in(get_parent())


func can_use(item_id: StringName) -> bool:
	return (
		item_id == flare_item_id
		and not is_holding()
		and inventory != null
		and inventory.has_item(item_id)
	)


func use(item_id: StringName) -> bool:
	return can_use(item_id) and light()


## Number-key Quick Access draw: move the unlit flare out of its physical pocket
## into the existing held-item hand socket without consuming or igniting it.
func equip_from_zone(item_id: StringName, zone_path: StringName) -> bool:
	if item_id != flare_item_id or is_holding():
		return false
	var animation: HenryUALAnimation = _animation()
	var equipment: EquipmentComponent = _equipment()
	var parts: PackedStringArray = String(zone_path).split(EquipmentComponent.POCKET_SEPARATOR)
	if animation == null or animation.get_hand_socket() == null or equipment == null or parts.size() != 2:
		return false
	var body_slot := StringName(parts[0])
	var pocket := StringName(parts[1])
	if equipment.get_pocket_item(body_slot, pocket) != item_id:
		return false
	if equipment.take_from_pocket(body_slot, pocket) != item_id:
		return false
	_source_zone = zone_path
	_flare = _make_held_flare(animation)
	if _flare == null:
		_restore_unlit_item()
		return false
	flare_drawn.emit(_flare)
	return true


## Existing Use Selected Item grammar while something is already in hand:
## unlit -> ignite; burning -> drop.
func use_held() -> bool:
	if not is_holding():
		return false
	if not _flare.is_burning():
		return ignite_held()
	drop()
	return true


## Changing Quick Access selection puts an unlit flare back into carried storage.
func put_away_unlit() -> bool:
	if not is_holding_unlit():
		return false
	var animation: HenryUALAnimation = _animation()
	var flare: HeldFlare = _flare
	_flare = null
	if animation != null:
		animation.release_hand()
	if is_instance_valid(flare):
		flare.queue_free()
	_restore_unlit_item()
	return true


## Compatibility seam for callers that ask a held component to release itself.
func release_held() -> bool:
	if not is_holding():
		return false
	if is_holding_unlit():
		return put_away_unlit()
	drop()
	return true


func toggle() -> void:
	if is_holding():
		use_held()
	else:
		light()


func is_holding() -> bool:
	return is_instance_valid(_flare)


func is_holding_unlit() -> bool:
	return is_holding() and not _flare.is_burning()


func is_burning() -> bool:
	return is_holding() and _flare.is_burning()


func get_source_zone() -> StringName:
	return _source_zone


func ignite_held() -> bool:
	if not is_holding_unlit():
		return false
	_source_zone = &""
	_flare.ignite()
	flare_lit.emit(_flare)
	return true


## Hub/direct Use keeps its old behaviour: take one carried flare and light it
## immediately. The number-key path uses equip_from_zone() so the draw is visible.
func light() -> bool:
	var animation: HenryUALAnimation = _animation()
	if is_holding() or animation == null or inventory == null:
		return false
	if not _take_flare():
		return false
	_source_zone = &""
	_flare = _make_held_flare(animation)
	if _flare == null:
		inventory.try_add(ItemCatalog.get_item(flare_item_id))
		return false
	return ignite_held()


func drop() -> void:
	var animation: HenryUALAnimation = _animation()
	if not is_burning() or animation == null:
		return
	var flare: HeldFlare = _flare
	_flare = null
	_source_zone = &""
	var hand_xf: Transform3D = flare.global_transform
	animation.release_hand()
	var world: Node = get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	world.add_child(flare)
	var feet: Vector3 = (get_parent() as Node3D).global_position
	flare.global_transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(hand_xf.origin.x, feet.y + 0.05, hand_xf.origin.z))
	flare_dropped.emit(flare)


func _make_held_flare(animation: HenryUALAnimation) -> HeldFlare:
	if animation == null:
		return null
	var flare := FLARE_SCENE.instantiate() as HeldFlare
	flare.auto_ignite = false
	animation.hold_in_hand(flare)
	if _context != null:
		flare.on_world_ready(_context)
	flare.spent.connect(_on_spent.bind(flare))
	return flare


func _restore_unlit_item() -> void:
	var source: StringName = _source_zone
	_source_zone = &""
	var equipment: EquipmentComponent = _equipment()
	if source != &"" and equipment != null:
		var parts: PackedStringArray = String(source).split(EquipmentComponent.POCKET_SEPARATOR)
		if parts.size() == 2:
			var refusal: EquipmentComponent.Refusal = equipment.stow(
				StringName(parts[0]), StringName(parts[1]), flare_item_id
			)
			if refusal == EquipmentComponent.Refusal.NONE:
				return
	if inventory != null:
		inventory.try_add(ItemCatalog.get_item(flare_item_id))


func _on_spent(flare: HeldFlare) -> void:
	if flare == _flare:
		_flare = null
		_source_zone = &""
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
	var equipment: EquipmentComponent = _equipment()
	if equipment == null:
		return false
	for pocket: Dictionary in equipment.get_available_pockets():
		if pocket["item_id"] != flare_item_id:
			continue
		return equipment.take_from_pocket(pocket["body_slot"], pocket["pocket"]) == flare_item_id
	return false


func _equipment() -> EquipmentComponent:
	var player: Node = get_parent()
	return player.get_node_or_null(^"EquipmentComponent") as EquipmentComponent if player != null else null


func _animation() -> HenryUALAnimation:
	var player: Node = get_parent()
	return player.get(&"animation_component") as HenryUALAnimation if player != null else null
