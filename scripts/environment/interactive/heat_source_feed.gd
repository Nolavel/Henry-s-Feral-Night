class_name HeatSourceFeed
extends InteractiveArea

## Lights and feeds one HeatSource. Firewood buys hours; a dead fire also
## needs tinder. Without this, a fire could only ever burn down.

## Emitted when a staged act starts: lighting (true) or adding a log (false).
signal act_started(lighting: bool)
## Emitted after fuel went in, carrying the hours the fire now has.
signal fuel_added(source: HeatSource, remaining_hours: float)
## Emitted when the player has nothing to feed it with, or it is already full.
signal feed_refused(reason: Refusal)

## Why a feed attempt was turned down.
enum Refusal { NONE, NO_SOURCE, ALREADY_FULL, NO_FUEL, NO_TINDER, NO_INVENTORY }

## Label shown over the fire, resolved through localisation.
const PROMPT_KEY: String = "FEED_PROMPT"
const LIGHT_KEY: String = "LIGHT_PROMPT"
const LIGHT_REQUIREMENTS_KEY: String = "LIGHT_REQUIREMENTS"
## Real seconds of the staged acts: kneel, door, tinder, log, strike, catch.
const LIGHT_SECONDS: float = 5.0
## Door, log, door on a fire that already burns.
const ADD_SECONDS: float = 2.0

@export_group("Fire")
## The fire this prompt feeds. Defaults to a HeatSource sibling or parent.
@export var heat_source: HeatSource

@export_group("Cost")
## Item spent per feed. Empty means feeding costs nothing.
@export var fuel_item_id: StringName = &"firewood"
## Item spent only to light a dead fire. Empty means lighting is free.
@export var tinder_item_id: StringName = &"tinder"
## Units of fuel one item is worth, through HeatSource.hours_per_fuel_unit.
@export var units_per_item: float = 1.0

var _inventory: InventoryComponent
var _act_left: float = 0.0
var _act_lighting: bool = false


func _ready() -> void:
	## Found before super(), which sizes the highlight ring from a mesh.
	if heat_source == null:
		heat_source = _find_source()
	if interactive_mesh == null and heat_source != null:
		interactive_mesh = _first_mesh(heat_source)
	if player_animation_action == &"":
		player_animation_action = &"none"  # the staged act plays its own clip
	super()
	_update_label()
	if heat_source != null:
		heat_source.burning_changed.connect(func(_b: bool) -> void: _update_label())


## Offers itself while the fire can take fuel; a missing item is said on F.
func can_interact() -> bool:
	return super() and heat_source != null and heat_source.can_refuel() and not is_acting()


func is_acting() -> bool:
	return _act_left > 0.0


## The staged act, as the player does it: items go in at once, the fire takes
## after LIGHT_SECONDS (lighting) or ADD_SECONDS (a log on a live fire).
func begin_act() -> Refusal:
	var refusal: Refusal = can_feed()
	if refusal != Refusal.NONE:
		feed_refused.emit(refusal)
		return refusal
	_act_lighting = not heat_source.is_burning()
	_act_left = LIGHT_SECONDS if _act_lighting else ADD_SECONDS
	var inventory: InventoryComponent = _get_inventory()
	if _act_lighting and tinder_item_id != &"":
		inventory.try_remove(tinder_item_id)
	if fuel_item_id != &"":
		inventory.try_remove(fuel_item_id)
	var visual: StoveVisual = _visual()
	if visual != null:
		visual.begin_act(_act_lighting, _act_left)
	var player: Node = get_tree().get_first_node_in_group(&"player") if is_inside_tree() else null
	if player != null:
		if player.has_method(&"hold_still"):
			player.call(&"hold_still", _act_left)
		if player.has_method(&"play_action_animation"):
			player.call(&"play_action_animation", &"fix" if _act_lighting else &"interact")
	act_started.emit(_act_lighting)
	return Refusal.NONE


func _process(delta: float) -> void:
	if _act_left <= 0.0:
		return
	_act_left -= delta
	if _act_left <= 0.0:
		_finish_act()


## The fire catches (or takes the log): only now does it burn and give heat.
func _finish_act() -> void:
	_act_left = 0.0
	heat_source.refuel(units_per_item)
	var visual: StoveVisual = _visual()
	if visual != null:
		visual.end_act()
	fuel_added.emit(heat_source, heat_source.get_remaining_hours())
	_update_label()


func _update_label() -> void:
	var lighting: bool = heat_source != null and not heat_source.is_burning()
	set_item_name(tr(LIGHT_KEY if lighting else PROMPT_KEY))
	set_description(tr(LIGHT_REQUIREMENTS_KEY) if lighting else "")


func _visual() -> StoveVisual:
	return heat_source.find_child("StoveVisual", true, false) as StoveVisual if heat_source != null else null


## Whether the fire can be fed right now, without feeding it.
func can_feed() -> Refusal:
	if heat_source == null:
		return Refusal.NO_SOURCE
	if not heat_source.can_refuel():
		return Refusal.ALREADY_FULL
	var inventory: InventoryComponent = _get_inventory()
	if fuel_item_id != &"" or tinder_item_id != &"":
		if inventory == null:
			return Refusal.NO_INVENTORY
	if fuel_item_id != &"" and not inventory.has_item(fuel_item_id):
		return Refusal.NO_FUEL
	## Tinder is only owed when the fire is out and has to be started.
	if _needs_tinder() and not inventory.has_item(tinder_item_id):
		return Refusal.NO_TINDER
	return Refusal.NONE


## Spends the items, then feeds the fire. Nothing is spent on a refusal.
func feed() -> Refusal:
	var refusal: Refusal = can_feed()
	if refusal != Refusal.NONE:
		feed_refused.emit(refusal)
		return refusal

	var inventory: InventoryComponent = _get_inventory()
	var needed_tinder: bool = _needs_tinder()
	if needed_tinder and not inventory.try_remove(tinder_item_id):
		feed_refused.emit(Refusal.NO_TINDER)
		return Refusal.NO_TINDER
	if fuel_item_id != &"" and not inventory.try_remove(fuel_item_id):
		feed_refused.emit(Refusal.NO_FUEL)
		return Refusal.NO_FUEL

	heat_source.refuel(units_per_item)
	fuel_added.emit(heat_source, heat_source.get_remaining_hours())
	return Refusal.NONE


func _on_interaction_performed() -> void:
	var refusal: Refusal = begin_act()
	if refusal != Refusal.NONE:
		show_message(tr(describe_refusal(refusal)))


## Names a refusal as a localisation key, never as a hardcoded sentence.
static func describe_refusal(refusal: Refusal) -> String:
	match refusal:
		Refusal.NO_SOURCE:
			return "FEED_REFUSED_NO_SOURCE"
		Refusal.ALREADY_FULL:
			return "FEED_REFUSED_ALREADY_FULL"
		Refusal.NO_FUEL:
			return "FEED_REFUSED_NO_FUEL"
		Refusal.NO_TINDER:
			return "FEED_REFUSED_NO_TINDER"
		Refusal.NO_INVENTORY:
			return "FEED_REFUSED_NO_INVENTORY"
		_:
			return ""


## A dead fire has to be started, which costs tinder on top of the wood.
func _needs_tinder() -> bool:
	return tinder_item_id != &"" and not heat_source.is_burning()


## The player's inventory, found once and cached. Level objects cannot be
## wired to the player in the editor, so the group is the handle.
func _get_inventory() -> InventoryComponent:
	if is_instance_valid(_inventory):
		return _inventory
	_inventory = InventoryComponent.find_in(get_tree().get_first_node_in_group("player"))
	return _inventory


## The stove's own body, for the highlight ring to sit under.
static func _first_mesh(node: Node) -> MeshInstance3D:
	for child: Node in node.get_children():
		var mesh := child as MeshInstance3D
		if mesh != null:
			return mesh
	return null


## A fire among the siblings, or the parent itself.
func _find_source() -> HeatSource:
	var parent_source := get_parent() as HeatSource
	if parent_source != null:
		return parent_source
	if get_parent() == null:
		return null
	for sibling: Node in get_parent().get_children():
		var candidate := sibling as HeatSource
		if candidate != null:
			return candidate
	return null
