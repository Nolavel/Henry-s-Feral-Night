class_name PlayerHubComponent
extends Node

## Henry's inspection state (Tab): movement stops, a camera frames his back and
## the pack opens on him. Presents InventoryComponent and pockets; stores nothing.

signal hub_opened
signal hub_closed
## Emitted after an item moved between the pack and a Quick Access zone.
signal contents_changed
## Emitted when a quick-stowed item has dropped into the pack.
signal stow_landed

const ACTION: StringName = &"open hub"
const CLOSE_ACTION: StringName = &"pause"
const OVERWEIGHT: StringName = &"overweight"
## Pockets the pack contents already stand for; not offered as Quick Access.
## Seconds the stowed item rises, then drops into the open top flap.
const STOW_LIFT_TIME: float = 0.28
const STOW_DROP_TIME: float = 0.32
const EXCLUDED_ZONES: Array[StringName] = [&"pack/pack_main"]

@export var inventory: InventoryComponent
@export var equipment: EquipmentComponent
@export_group("Camera")
## Metres out from the pack, to its side and above it, the Hub camera stands.
@export var camera_back: float = 1.3
@export var camera_side: float = 0.4
@export var camera_height: float = 0.3
@export var camera_blend_time: float = 0.45

## The pack on Henry; resolved from his visual when left empty.
var pack: PackRig
var _open: bool = false
var _stows_in_flight: int = 0
var _camera: Camera3D
var _previous_camera: Camera3D
var _panel: PlayerHubPanel


func _ready() -> void:
	var body: Node = get_parent()
	if inventory == null:
		inventory = InventoryComponent.find_in(body)
	if equipment == null and body != null:
		equipment = body.get_node_or_null(^"EquipmentComponent") as EquipmentComponent


func _unhandled_input(event: InputEvent) -> void:
	if InputMap.has_action(ACTION) and event.is_action_pressed(ACTION):
		toggle()
		get_viewport().set_input_as_handled()


## Esc closes the Hub before the pause menu hears it.
func _input(event: InputEvent) -> void:
	if _open and InputMap.has_action(CLOSE_ACTION) and event.is_action_pressed(CLOSE_ACTION):
		close()
		get_viewport().set_input_as_handled()


func is_open() -> bool:
	return _open


func toggle() -> bool:
	return close() if _open else open()


## Enters the Hub. Refused mid-fall, while carrying in both hands or mid-action.
func open() -> bool:
	if _open or not _can_open():
		return false
	_open = true
	var pack: PackRig = _pack()
	if pack != null:
		pack.set_openness(PackRig.Openness.FULL)
	_enter_camera()
	_show_panel()
	hub_opened.emit()
	return true


func close() -> bool:
	if not _open:
		return false
	_open = false
	var pack: PackRig = _pack()
	if pack != null:
		pack.set_openness(PackRig.Openness.CLOSED)
	_exit_camera()
	if is_instance_valid(_panel):
		_panel.queue_free()
	_panel = null
	hub_closed.emit()
	return true


## Pack contents: id, count, name, weight and size class per stack.
func get_pack_items() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if inventory == null:
		return out
	for entry: Dictionary in inventory.get_entries():
		var item: ItemResource = ItemCatalog.get_item(entry["id"])
		if item == null:
			continue
		out.append({"id": item.id, "count": entry["count"], "name": item.display_name,
			"weight": item.weight, "size": item.size_class})
	return out


## Quick Access zones: pockets on what Henry wears. Keys: path, name, max_size, item_id.
func get_quick_access_zones() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if equipment == null:
		return out
	for pocket: Dictionary in equipment.get_available_pockets():
		var path: StringName = equipment.pocket_path(pocket["body_slot"], pocket["pocket"])
		if EXCLUDED_ZONES.has(path):
			continue
		var definition: EquipmentSlotDefinition = pocket["definition"]
		out.append({"path": path, "name": definition.display_name,
			"max_size": definition.max_size, "item_id": pocket["item_id"]})
	return out


## Whether an item from the pack fits a zone, and why not.
func can_place(item_id: StringName, zone_path: StringName) -> EquipmentComponent.Refusal:
	if equipment == null or inventory == null or not inventory.has_item(item_id):
		return EquipmentComponent.Refusal.UNKNOWN_ITEM
	var parts: PackedStringArray = String(zone_path).split(EquipmentComponent.POCKET_SEPARATOR)
	if parts.size() != 2 or EXCLUDED_ZONES.has(zone_path):
		return EquipmentComponent.Refusal.NO_SUCH_SLOT
	return equipment.can_stow(StringName(parts[0]), StringName(parts[1]), item_id)


## Moves one item from the pack into a Quick Access zone.
func move_to_zone(item_id: StringName, zone_path: StringName) -> EquipmentComponent.Refusal:
	var refusal: EquipmentComponent.Refusal = can_place(item_id, zone_path)
	if refusal != EquipmentComponent.Refusal.NONE:
		return refusal
	var parts: PackedStringArray = String(zone_path).split(EquipmentComponent.POCKET_SEPARATOR)
	inventory.try_remove(item_id)
	equipment.stow(StringName(parts[0]), StringName(parts[1]), item_id)
	contents_changed.emit()
	return EquipmentComponent.Refusal.NONE


## Returns a zone's item to the pack. Empty on success, else a refusal reason.
func move_to_pack(zone_path: StringName) -> StringName:
	var parts: PackedStringArray = String(zone_path).split(EquipmentComponent.POCKET_SEPARATOR)
	if equipment == null or inventory == null or parts.size() != 2:
		return &"no_such_slot"
	var body_slot := StringName(parts[0])
	var pocket := StringName(parts[1])
	var item_id: StringName = equipment.take_from_pocket(body_slot, pocket)
	if item_id == &"":
		return &"empty"
	## Taken out first, so its own weight is not counted twice by the pack.
	if not inventory.try_add(ItemCatalog.get_item(item_id)):
		equipment.stow(body_slot, pocket, item_id)
		return OVERWEIGHT
	contents_changed.emit()
	return &""


## Tap-F stow: the item's visual lifts, flies into the top flap and is freed.
## The item is already in the inventory; this is presentation only.
func stow_visual(visual: Node3D) -> void:
	var rig: PackRig = _pack()
	if visual == null:
		return
	if rig == null or not rig.is_inside_tree() or not visual.is_inside_tree():
		visual.queue_free()
		stow_landed.emit()
		return
	_stows_in_flight += 1
	if not _open:
		rig.set_openness(PackRig.Openness.TOP_ONLY)
	var start: Vector3 = visual.global_position
	var mouth: Vector3 = rig.global_transform * Vector3(0.0, rig.size.y * 0.5 + 0.08, 0.0)
	var peak: Vector3 = start.lerp(mouth, 0.35) + Vector3(0.0, 0.45, 0.0)
	var tween: Tween = visual.create_tween().set_trans(Tween.TRANS_SINE)
	tween.tween_property(visual, ^"global_position", peak, STOW_LIFT_TIME).set_ease(Tween.EASE_OUT)
	tween.tween_property(visual, ^"global_position", mouth, STOW_DROP_TIME).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(visual, ^"scale", visual.scale * 0.35, STOW_DROP_TIME)
	tween.tween_callback(_on_stow_landed.bind(visual))


func _on_stow_landed(visual: Node3D) -> void:
	visual.queue_free()
	_stows_in_flight = maxi(0, _stows_in_flight - 1)
	stow_landed.emit()
	var rig: PackRig = _pack()
	if rig != null and not _open and _stows_in_flight == 0:
		rig.set_openness(PackRig.Openness.CLOSED)


## Where the Hub camera settles: out from the pack's face, looking at it.
func get_camera_target() -> Transform3D:
	var body := get_parent() as Node3D
	var pack: PackRig = _pack()
	var centre: Vector3
	var outward: Vector3
	if pack != null and pack.is_inside_tree():
		centre = pack.global_position
		outward = -pack.global_transform.basis.z
	else:
		## The body faces -Z, so its back is +Z.
		centre = body.global_position + Vector3(0.0, 1.2, 0.0) + body.global_transform.basis.z * 0.25
		outward = body.global_transform.basis.z
	outward.y = 0.0
	outward = outward.normalized() if outward.length() > 0.01 else Vector3.BACK
	var side: Vector3 = Vector3.UP.cross(outward).normalized()
	var eye: Vector3 = centre + outward * camera_back + side * camera_side + Vector3(0.0, camera_height, 0.0)
	return Transform3D(Basis.IDENTITY, eye).looking_at(centre, Vector3.UP)


func get_weight() -> float:
	return inventory.get_total_weight() if inventory != null else 0.0


func get_max_weight() -> float:
	return inventory.max_carry_weight if inventory != null else 0.0


func _can_open() -> bool:
	var body := get_parent() as CharacterBody3D
	if body != null and body.velocity.y < -0.5:
		return false
	var visual: HenryUALAnimation = _visual()
	return visual == null or not (visual.is_carrying() or visual.is_action_locking())


func _visual() -> HenryUALAnimation:
	var body: Node = get_parent()
	return body.get_node_or_null(^"HenryUALVisual") as HenryUALAnimation if body != null else null


func _pack() -> PackRig:
	if pack == null:
		var visual: HenryUALAnimation = _visual()
		pack = visual.get_pack_rig() if visual != null else null
	return pack


## Blends from the game camera to one over Henry's shoulder, facing his pack.
func _enter_camera() -> void:
	var body := get_parent() as Node3D
	if body == null or not body.is_inside_tree():
		return
	_previous_camera = body.get_viewport().get_camera_3d()
	_camera = Camera3D.new()
	_camera.name = "HubCamera"
	_camera.top_level = true
	_camera.fov = 50.0
	body.add_child(_camera)
	var target: Transform3D = get_camera_target()
	_camera.global_transform = _previous_camera.global_transform if _previous_camera != null else target
	_camera.make_current()
	create_tween().set_trans(Tween.TRANS_SINE).tween_property(_camera, ^"global_transform", target, camera_blend_time)


func _exit_camera() -> void:
	if is_instance_valid(_previous_camera):
		_previous_camera.make_current()
	if is_instance_valid(_camera):
		_camera.queue_free()
	_camera = null
	_previous_camera = null


func _show_panel() -> void:
	if not is_inside_tree():
		return
	_panel = PlayerHubPanel.new()
	_panel.hub = self
	add_child(_panel)
