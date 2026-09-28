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
## One valid wheel strike happened. Lockout clicks deliberately do not emit it.
signal lighter_struck(success: bool, strike_index: int)
signal lighter_lockout_started(seconds: float)

## Why a feed attempt was turned down.
enum Refusal { NONE, NO_SOURCE, ALREADY_FULL, NO_FUEL, NO_TINDER, NO_INVENTORY, NO_LIGHTER, BUSY }
enum StrikeResult { IGNORED, LOCKED, SPARK, IGNITED }

## Label shown over the fire, resolved through localisation.
const PROMPT_KEY: String = "FEED_PROMPT"
const LIGHT_KEY: String = "LIGHT_PROMPT"
const LIGHT_REQUIREMENTS_KEY: String = "LIGHT_REQUIREMENTS"
## Lighting is now event-driven; this is only the held-pose/reference duration.
const LIGHT_SECONDS: float = 5.0
## Door, log, door on a fire that already burns.
const ADD_SECONDS: float = 2.0
const STRIKE_ACTION: StringName = &"fire"

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
## One physical log is one short WORKING action. Repeating the interaction adds
## a second log if the stove still has room.
@export_range(0.1, 60.0, 0.1) var add_time_cost_minutes: float = 0.5

@export_group("Lighter interaction")
## A second click inside this real-time window is treated as an accidental double-click.
@export_range(0.05, 0.5, 0.01) var double_click_window_seconds: float = 0.22
## During lockout LMB produces no strike animation, spark or light.
@export_range(0.5, 10.0, 0.1) var lighter_lockout_seconds: float = 5.0
@export_range(0.0, 1.0, 0.05) var first_strike_success_chance: float = 0.35
@export_range(0.0, 1.0, 0.05) var second_strike_success_chance: float = 0.65
## Normal rhythm is guaranteed to catch by this strike even if earlier rolls miss.
@export_range(1, 5, 1) var guaranteed_success_strike: int = 3

var _inventory: InventoryComponent
var _act_left: float = 0.0
var _act_lighting: bool = false
var _door_open: bool = false
var _action_managed: bool = false
var _action_id: StringName = &""
var _feed_was_burning: bool = false
var _ignition_session: bool = false
var _strike_count: int = 0
var _last_strike_seconds: float = -1000.0
var _lockout_until_seconds: float = 0.0
var _strike_rng := RandomNumberGenerator.new()


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
	_strike_rng.randomize()
	_update_label()
	if heat_source != null:
		heat_source.burning_changed.connect(func(_b: bool) -> void: _update_label())


## Offers itself while the fire can take fuel; a missing item is said on F.
func can_interact() -> bool:
	return super() and heat_source != null and not is_acting()


func is_acting() -> bool:
	return _act_left > 0.0


## Advances one explicit step. Opening never spends resources. With the door
## open, one interaction loads exactly one log; a cold stove with fuel then
## prioritises ignition. A burning stove may be fed repeatedly until full.
func begin_act() -> Refusal:
	if heat_source == null:
		return Refusal.NO_SOURCE
	if is_acting():
		return Refusal.BUSY
	if not _door_open:
		_door_open = true
		if _visual() != null:
			_visual().set_door_open(true)
		return Refusal.NONE

	var inventory: InventoryComponent = _get_inventory()
	if inventory == null:
		return Refusal.NO_INVENTORY

	## Once a cold stove has any loaded wood, the next step is ignition. More
	## wood can be added after it catches, so the player is never forced to
	## auto-fill the stove before lighting it.
	if not heat_source.is_burning() and heat_source.get_remaining_hours() > 0.0:
		if not _has_lighter():
			return Refusal.NO_LIGHTER
		return _start_light_action()

	if _has_room_for_one_log() and inventory.has_item(fuel_item_id):
		return _start_feed_action()

	## A burning stove with no useful feed step closes on the next interaction.
	if heat_source.is_burning():
		_close_door()
		return Refusal.NONE

	return Refusal.NO_FUEL


func _unhandled_input(event: InputEvent) -> void:
	if not _ignition_session or not event.is_action_pressed(STRIKE_ACTION):
		return
	var mouse := event as InputEventMouseButton
	attempt_lighter_strike(-1.0, mouse != null and mouse.double_click)
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _act_left <= 0.0:
		return
	if _action_managed:
		var actions: TimeCostedActionSystem = _actions()
		if actions != null and actions.get_active_action_id() == _action_id:
			if _act_lighting and _ignition_session:
				return
			_act_left = _act_duration_seconds() * (1.0 - actions.get_progress())
			return
		_action_managed = false
	if _act_lighting and _ignition_session:
		return
	_act_left -= delta
	if _act_left <= 0.0:
		if _act_lighting:
			_finish_light_act()
		else:
			_finish_feed_act()


func _start_light_action() -> Refusal:
	_act_lighting = true
	_act_left = LIGHT_SECONDS
	_begin_ignition_session()
	var player: Node = get_tree().get_first_node_in_group(&"player") if is_inside_tree() else null
	var actions: TimeCostedActionSystem = _actions()
	if actions != null:
		var request := TimeActionRequest.new()
		_action_id = StringName("light_stove:%d" % get_instance_id())
		request.action_id = _action_id
		request.duration_hours = light_time_cost_minutes / 60.0
		request.reason = &"light_stove"
		request.actor = player
		request.target = heat_source
		request.player_mode = _resolve_player_mode(&"WORKING")
		request.stop_check = _light_stop_reason
		request.on_complete = _light_action_completed
		request.on_cancel = _light_action_cancelled
		_action_managed = actions.start_manual_action(request)
		if not _action_managed:
			_clear_act()
			return Refusal.BUSY
	_begin_visual_act(player)
	show_message(tr("STOVE_LIGHTER_STRIKE"))
	return Refusal.NONE


func _start_feed_action() -> Refusal:
	_act_lighting = false
	_act_left = ADD_SECONDS
	_feed_was_burning = heat_source.is_burning()
	var player: Node = get_tree().get_first_node_in_group(&"player") if is_inside_tree() else null
	var actions: TimeCostedActionSystem = _actions()
	if actions != null:
		var request := TimeActionRequest.new()
		_action_id = StringName("feed_stove:%d" % get_instance_id())
		request.action_id = _action_id
		request.duration_hours = add_time_cost_minutes / 60.0
		request.presentation_seconds = ADD_SECONDS
		request.reason = &"feed_stove"
		request.actor = player
		request.target = heat_source
		request.player_mode = _resolve_player_mode(&"WORKING")
		request.stop_check = _feed_stop_reason
		request.on_complete = _feed_action_completed
		request.on_cancel = _feed_action_cancelled
		_action_managed = actions.start_action(request)
		if not _action_managed:
			_clear_act()
			return Refusal.BUSY
	_begin_visual_act(player)
	return Refusal.NONE


func _begin_visual_act(player: Node) -> void:
	var visual: StoveVisual = _visual()
	if visual != null:
		visual.begin_act(_act_lighting, _act_left)
	if player != null:
		if player.has_method(&"hold_still"):
			player.call(&"hold_still", _act_left)
		if not _act_lighting and player.has_method(&"play_action_animation"):
			player.call(&"play_action_animation", &"interact")
	act_started.emit(_act_lighting)


func _act_duration_seconds() -> float:
	return LIGHT_SECONDS if _act_lighting else ADD_SECONDS


func _begin_ignition_session() -> void:
	_ignition_session = true
	_strike_count = 0
	_last_strike_seconds = -1000.0
	_lockout_until_seconds = 0.0


## Testable gameplay seam used by LMB input. Double-click lockout intentionally
## produces no spark/VFX and resets the normal strike rhythm.
func attempt_lighter_strike(now_seconds: float = -1.0, force_double_click: bool = false) -> int:
	if not _ignition_session or heat_source == null or heat_source.is_burning():
		return StrikeResult.IGNORED
	var now: float = _strike_now_seconds() if now_seconds < 0.0 else now_seconds
	if now < _lockout_until_seconds:
		show_message(tr("STOVE_LIGHTER_LOCKED") % maxf(_lockout_until_seconds - now, 0.0))
		return StrikeResult.LOCKED
	if force_double_click or now - _last_strike_seconds <= double_click_window_seconds:
		_lockout_until_seconds = now + lighter_lockout_seconds
		_last_strike_seconds = -1000.0
		_strike_count = 0
		lighter_lockout_started.emit(lighter_lockout_seconds)
		show_message(tr("STOVE_LIGHTER_LOCKED") % lighter_lockout_seconds)
		return StrikeResult.LOCKED

	_last_strike_seconds = now
	_strike_count += 1
	var success: bool = _roll_lighter_success()
	_play_lighter_strike(success)
	lighter_struck.emit(success, _strike_count)
	if not success:
		show_message(tr("STOVE_LIGHTER_MISS"))
		return StrikeResult.SPARK

	_ignition_session = false
	show_message(tr("STOVE_LIGHTER_FLAME"))
	var actions: TimeCostedActionSystem = _actions()
	if _action_managed and actions != null and actions.get_active_action_id() == _action_id:
		if not actions.complete_active():
			return StrikeResult.IGNORED
	else:
		_finish_light_act()
	return StrikeResult.IGNITED


func get_lighter_lockout_remaining(now_seconds: float = -1.0) -> float:
	var now: float = _strike_now_seconds() if now_seconds < 0.0 else now_seconds
	return maxf(_lockout_until_seconds - now, 0.0)


func _roll_lighter_success() -> bool:
	if _strike_count >= guaranteed_success_strike:
		return true
	var chance: float = first_strike_success_chance if _strike_count <= 1 else second_strike_success_chance
	return _strike_rng.randf() <= chance


func _play_lighter_strike(success: bool) -> void:
	var anchor: Node3D = _lighter_vfx_anchor()
	if anchor != null:
		LighterStrikeVFX.spawn(anchor, success)
	var player: Node = get_tree().get_first_node_in_group(&"player") if is_inside_tree() else null
	if player != null and player.has_method(&"play_action_animation"):
		player.call(&"play_action_animation", &"fix")


func _lighter_vfx_anchor() -> Node3D:
	var player: Node = get_tree().get_first_node_in_group(&"player") if is_inside_tree() else null
	if player != null:
		for child: Node in player.get_children():
			if child.has_method(&"get_hand_socket"):
				var socket: Variant = child.call(&"get_hand_socket")
				if socket is Node3D:
					return socket as Node3D
	if focus_anchor is Node3D:
		return focus_anchor as Node3D
	return self


func _strike_now_seconds() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


func _light_stop_reason() -> StringName:
	if heat_source == null:
		return &"target_lost"
	if not _has_lighter():
		return &"tool_lost"
	return &""


func _light_action_completed(_elapsed_h: float) -> void:
	_action_managed = false
	_finish_light_act()


func _light_action_cancelled(_elapsed_h: float, _reason: StringName) -> void:
	_cancel_act()


func _feed_stop_reason() -> StringName:
	if heat_source == null:
		return &"target_lost"
	var inventory: InventoryComponent = _get_inventory()
	if inventory == null or not inventory.has_item(fuel_item_id):
		return &"resource_lost"
	if not _has_room_for_one_log():
		return &"already_full"
	return &""


func _feed_action_completed(_elapsed_h: float) -> void:
	_action_managed = false
	_finish_feed_act()


func _feed_action_cancelled(_elapsed_h: float, _reason: StringName) -> void:
	_cancel_act()


func _resolve_player_mode(mode_name: StringName) -> int:
	var state: Node = get_node_or_null(^"/root/PlayerState")
	if state == null:
		return -1
	var script: Script = state.get_script() as Script
	if script == null:
		return -1
	var constants: Dictionary = script.get_script_constant_map()
	var modes: Dictionary = constants.get("Mode", {})
	return int(modes.get(String(mode_name), -1))


func _actions() -> TimeCostedActionSystem:
	return TimeCostedActionSystem.find(get_tree()) if is_inside_tree() else null


## The fire catches only after the ignition action completes.
func _finish_light_act() -> void:
	_ignition_session = false
	_act_left = 0.0
	heat_source.restore_fuel(heat_source.get_remaining_hours(), true)
	_close_door()
	var visual: StoveVisual = _visual()
	if visual != null:
		visual.end_act()
	fuel_added.emit(heat_source, heat_source.get_remaining_hours())
	_update_label()


## Commits exactly one log after the staged feed action completes. The door
## stays open so the player may deliberately add a second log or close it.
func _finish_feed_act() -> void:
	var inventory: InventoryComponent = _get_inventory()
	if heat_source == null or inventory == null or not _has_room_for_one_log():
		_cancel_act()
		return
	if not inventory.try_remove(fuel_item_id):
		_cancel_act()
		return
	var hours: float = minf(
		heat_source.burn_duration_h,
		heat_source.get_remaining_hours() + units_per_item * heat_source.hours_per_fuel_unit
	)
	heat_source.restore_fuel(hours, _feed_was_burning or heat_source.is_burning())
	_act_left = 0.0
	var visual: StoveVisual = _visual()
	if visual != null:
		visual.end_act(true)
	fuel_added.emit(heat_source, hours)
	show_message(tr("STOVE_LOADED") % 1)
	_update_label()


func _cancel_act() -> void:
	var keep_door_open: bool = not _act_lighting
	_ignition_session = false
	_strike_count = 0
	_lockout_until_seconds = 0.0
	_action_managed = false
	_act_left = 0.0
	_act_lighting = false
	_action_id = &""
	var visual: StoveVisual = _visual()
	if visual != null:
		visual.end_act(keep_door_open)
	_update_label()


func _clear_act() -> void:
	_ignition_session = false
	_strike_count = 0
	_lockout_until_seconds = 0.0
	_action_managed = false
	_act_left = 0.0
	_act_lighting = false
	_action_id = &""


func _close_door() -> void:
	_door_open = false
	if _visual() != null:
		_visual().set_door_open(false)


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
		if not heat_source.is_burning() and heat_source.get_remaining_hours() > 0.0:
			key = "STOVE_IGNITE"
			detail = tr("STOVE_LIGHTER_READY" if _has_lighter() else "STOVE_NEED_LIGHTER")
		elif inventory != null and inventory.has_item(fuel_item_id) and _has_room_for_one_log():
			key = "STOVE_LOAD"
		elif heat_source.is_burning():
			key = "STOVE_CLOSE"
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
	if not _has_room_for_one_log():
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


func _has_room_for_one_log() -> bool:
	if heat_source == null or heat_source.burn_duration_h <= 0.0:
		return false
	var fuel_hours: float = maxf(units_per_item * heat_source.hours_per_fuel_unit, 0.0)
	if fuel_hours <= 0.0:
		return false
	return heat_source.burn_duration_h - heat_source.get_remaining_hours() + 0.001 >= fuel_hours


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
