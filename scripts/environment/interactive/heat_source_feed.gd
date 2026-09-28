class_name HeatSourceFeed
extends InteractiveArea

## F opens the door, loads carried logs, then ignites the cold load with a lighter.
## Cold fuel belongs to HeatSource too, so saving never loses a loaded stove.

## Emitted when a staged act starts: lighting (true) or adding a log (false).
signal act_started(lighting: bool)
## Emitted after fuel went in, carrying the hours the fire now has.
signal fuel_added(source: HeatSource, remaining_hours: float)
## Emitted when the player has nothing to feed it with, or it is already full.
signal feed_refused(reason: Refusal)

## Why a feed attempt was turned down.
enum Refusal { NONE, NO_SOURCE, ALREADY_FULL, NO_FUEL, NO_TINDER, NO_INVENTORY, NO_LIGHTER, BUSY }

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

@export_group("Work time")
## Lighting keeps the existing five-second animation; this is its game-time cost.
@export_range(0.1, 60.0, 0.1) var light_time_cost_minutes: float = 2.0

var _inventory: InventoryComponent
var _act_left: float = 0.0
var _act_lighting: bool = false
var _door_open: bool = false
var _action_managed: bool = false
var _action_id: StringName = &""


func _ready() -> void:
	## Found before super(), which sizes the highlight ring from a mesh.
	if heat_source == null:
		heat_source = _find_source()
	if interactive_mesh == null and heat_source != null:
		interactive_mesh = _first_mesh(heat_source)
	if heat_source != null and focus_bodies.is_empty():
		for solid: Node in heat_source.find_children("*", "StaticBody3D", true, false):
			focus_bodies.append(solid as CollisionObject3D)
	if heat_source != null and focus_anchor == null and not focus_bodies.is_empty():
		var anchor := Marker3D.new()
		anchor.name = "FeedFocus"
		anchor.position = Vector3(0.28, 0.4, 0.0) - position
		add_child(anchor)
		focus_anchor = anchor
	if player_animation_action == &"":
		player_animation_action = &"none"  # the staged act plays its own clip
	super()
	_update_label()
	if heat_source != null:
		heat_source.burning_changed.connect(func(_b: bool) -> void: _update_label())


## Offers itself while the fire can take fuel; a missing item is said on F.
func can_interact() -> bool:
	return super() and heat_source != null and not is_acting()


func is_acting() -> bool:
	return _act_left > 0.0


## Advances one explicit step. Opening and loading never silently ignite wood.
func begin_act() -> Refusal:
	if heat_source == null or is_acting():
		return Refusal.NO_SOURCE
	if not _door_open:
		_door_open = true
		if _visual() != null:
			_visual().set_door_open(true)
		return Refusal.NONE
	var inventory: InventoryComponent = _get_inventory()
	if inventory == null:
		return Refusal.NO_INVENTORY
	var available: int = inventory.get_count(fuel_item_id)
	var room: int = maxi(0, floori((heat_source.burn_duration_h - heat_source.get_remaining_hours() + 0.001)
		/ (heat_source.hours_per_fuel_unit * units_per_item)))
	if available > 0 and room > 0:
		var amount: int = mini(available, room)
		for _i: int in range(amount):
			inventory.try_remove(fuel_item_id)
		var hours: float = heat_source.get_remaining_hours() + amount * units_per_item * heat_source.hours_per_fuel_unit
		heat_source.restore_fuel(hours, heat_source.is_burning())
		fuel_added.emit(heat_source, hours)
		show_message(tr("STOVE_LOADED") % amount)
		return Refusal.NONE
	if heat_source.is_burning():
		_door_open = false
		if _visual() != null:
			_visual().set_door_open(false)
		return Refusal.NONE
	if heat_source.get_remaining_hours() <= 0.0:
		return Refusal.NO_FUEL
	if not _has_lighter():
		return Refusal.NO_LIGHTER
	_act_lighting = true
	_act_left = LIGHT_SECONDS
	var player: Node = get_tree().get_first_node_in_group(&"player") if is_inside_tree() else null
	var actions: TimeCostedActionSystem = _actions()
	if actions != null:
		var request := TimeActionRequest.new()
		_action_id = StringName("light_stove:%d" % get_instance_id())
		request.action_id = _action_id
		request.duration_hours = light_time_cost_minutes / 60.0
		request.presentation_seconds = LIGHT_SECONDS
		request.reason = &"light_stove"
		request.actor = player
		request.target = heat_source
		request.stop_check = _light_stop_reason
		request.on_complete = _light_action_completed
		request.on_cancel = _light_action_cancelled
		_action_managed = actions.start_action(request)
		if not _action_managed:
			_act_lighting = false
			_act_left = 0.0
			return Refusal.BUSY

	var visual: StoveVisual = _visual()
	if visual != null:
		visual.begin_act(_act_lighting, _act_left)
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
	if _action_managed:
		var actions: TimeCostedActionSystem = _actions()
		if actions != null and actions.get_active_action_id() == _action_id:
			_act_left = LIGHT_SECONDS * (1.0 - actions.get_progress())
			return
		_action_managed = false
	_act_left -= delta
	if _act_left <= 0.0:
		_finish_act()


func _light_stop_reason() -> StringName:
	if heat_source == null:
		return &"target_lost"
	if not _has_lighter():
		return &"tool_lost"
	return &""


func _light_action_completed(_elapsed_h: float) -> void:
	_action_managed = false
	_finish_act()


func _light_action_cancelled(_elapsed_h: float, _reason: StringName) -> void:
	_action_managed = false
	_act_lighting = false
	_act_left = 0.0
	var visual: StoveVisual = _visual()
	if visual != null:
		visual.end_act()
	_update_label()


func _actions() -> TimeCostedActionSystem:
	return TimeCostedActionSystem.find(get_tree()) if is_inside_tree() else null


## The fire catches (or takes the log): only now does it burn and give heat.
func _finish_act() -> void:
	_act_left = 0.0
	heat_source.restore_fuel(heat_source.get_remaining_hours(), true)
	_door_open = false
	var visual: StoveVisual = _visual()
	if visual != null:
		visual.end_act()
	fuel_added.emit(heat_source, heat_source.get_remaining_hours())
	_update_label()


func _has_lighter() -> bool:
	var inventory: InventoryComponent = _get_inventory()
	if inventory != null and inventory.has_item(&"lighter"):
		return true
	var player: Node = get_tree().get_first_node_in_group(&"player")
	var equipment: EquipmentComponent = player.get_node_or_null(^"EquipmentComponent") as EquipmentComponent if player != null else null
	if equipment != null:
		for pocket: Dictionary in equipment.get_available_pockets():
			if pocket["item_id"] == &"lighter":
				return true
	return false


func _get_interaction_text() -> String:
	var key: String = "STOVE_OPEN"
	var detail: String = ""
	if heat_source != null:
		var capacity: int = ceili(heat_source.burn_duration_h / heat_source.hours_per_fuel_unit)
		var loaded: int = ceili(heat_source.get_remaining_hours() / heat_source.hours_per_fuel_unit - 0.001)
		detail = tr("STOVE_FUEL_DETAIL") % [loaded, capacity, heat_source.get_remaining_hours()]
	if _door_open and heat_source != null:
		var inventory: InventoryComponent = _get_inventory()
		if inventory != null and inventory.has_item(fuel_item_id) and heat_source.can_refuel():
			key = "STOVE_LOAD"
		elif heat_source.is_burning():
			key = "STOVE_CLOSE"
		elif heat_source.get_remaining_hours() > 0.0:
			key = "STOVE_IGNITE"
			detail = tr("STOVE_LIGHTER_READY" if _has_lighter() else "STOVE_NEED_LIGHTER")
		else:
			key = "STOVE_LOAD"
			detail = tr("FEED_REFUSED_NO_FUEL")
	set_description(detail)
	return "[%s] %s" % [_interact_key_label(), tr(key)]


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


## Legacy instantaneous seam for tools; player input uses the staged begin_act().
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
		Refusal.NO_LIGHTER:
			return "STOVE_NEED_LIGHTER"
		Refusal.BUSY:
			return "ACTION_REFUSED_BUSY"
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
		mesh = _first_mesh(child)
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
