class_name BreachBoardUp
extends InteractiveArea

## Boards up one ShelterBreach, at the cost of one item. The first thing in
## this game that interacting with actually changes.

## Emitted when the breach was boarded, for audio and the shelter HUD.
signal breach_boarded(breach: ShelterBreach)
## Emitted when the player has nothing to board it with.
signal repair_refused(missing_item_id: StringName)

@export_group("Breach")
## The hole this prompt repairs. Defaults to a ShelterBreach sibling or parent.
@export var breach: ShelterBreach

var _inventory: InventoryComponent


func _ready() -> void:
	super()
	if breach == null:
		breach = _find_breach()
	if breach != null:
		set_item_name(tr(breach.name_key))
	set_description("")


## Only offers itself while the hole is actually open.
func can_interact() -> bool:
	return super() and breach != null and not breach.is_boarded()


## Spends the repair item, then closes the hole. Refuses rather than boarding
## for free, so preparing a shelter stays a cost.
func _on_interaction_performed() -> void:
	if breach == null or breach.is_boarded():
		return
	var cost: StringName = breach.repair_item_id
	if cost != &"":
		var inventory: InventoryComponent = _get_inventory()
		if inventory == null or not inventory.has_item(cost):
			repair_refused.emit(cost)
			return
		if not inventory.try_remove(cost):
			repair_refused.emit(cost)
			return
	if breach.board_up():
		breach_boarded.emit(breach)


## The player's inventory, found once and cached. Level objects cannot be
## wired to the player in the editor, so the group is the handle.
func _get_inventory() -> InventoryComponent:
	if is_instance_valid(_inventory):
		return _inventory
	var player: Node = get_tree().get_first_node_in_group("player")
	_inventory = _search_inventory(player)
	return _inventory


static func _search_inventory(node: Node) -> InventoryComponent:
	if node == null:
		return null
	var found := node as InventoryComponent
	if found != null:
		return found
	for child: Node in node.get_children():
		var nested: InventoryComponent = _search_inventory(child)
		if nested != null:
			return nested
	return null


## A breach among the siblings, or the parent itself.
func _find_breach() -> ShelterBreach:
	var parent_breach := get_parent() as ShelterBreach
	if parent_breach != null:
		return parent_breach
	if get_parent() == null:
		return null
	for sibling: Node in get_parent().get_children():
		var candidate := sibling as ShelterBreach
		if candidate != null:
			return candidate
	return null
