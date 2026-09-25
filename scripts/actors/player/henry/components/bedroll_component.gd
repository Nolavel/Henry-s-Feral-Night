class_name BedrollComponent
extends Node

## Lays Henry's bedroll so he can sleep away from a bed: Use in the Hub shows a
## placement preview in front of him, F places it, Esc cancels. Saved while laid.

signal bedroll_laid(bedroll: Node3D)
signal bedroll_packed

const CONFIRM_ACTION: StringName = &"interact"
const CANCEL_ACTION: StringName = &"pause"
const PLACE_HINT_KEY: String = "BEDROLL_PLACE_HINT"
## Metres in front of Henry the roll's centre lands.
const PLACE_DISTANCE: float = 1.3
const ITEM_ID: StringName = &"bedroll"
const INTERACTIVE_SCENE: String = "res://scenes/environment/interactive/InteractiveArea.tscn"
const SLEEP_SPOT_SCRIPT: String = "res://scripts/environment/interactive/sleep_spot.gd"
const PICKUP_SCRIPT: String = "res://scripts/environment/interactive/item_pickup.gd"
const PACK_KEY: String = "BEDROLL_PACK"

@export var inventory: InventoryComponent

var _laid: Node3D
var _preview: Node3D


func _ready() -> void:
	add_to_group(&"saveable")
	if inventory == null:
		inventory = InventoryComponent.find_in(get_parent())


## F and Esc belong to the preview while it is up, before InteractComponent hears F.
func _input(event: InputEvent) -> void:
	if not is_placing():
		return
	if event.is_action_pressed(CONFIRM_ACTION) and not event.is_echo():
		confirm_placement()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(CANCEL_ACTION):
		cancel_placement()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if is_placing():
		_preview.global_transform = _front_transform()


## Item Use contract (PlayerHubComponent): Use on the bedroll starts placement.
func can_use(item_id: StringName) -> bool:
	return item_id == ITEM_ID and not is_laid() and not is_placing() and inventory != null and inventory.has_item(item_id)


func use(item_id: StringName) -> bool:
	return can_use(item_id) and begin_placement()


func is_placing() -> bool:
	return is_instance_valid(_preview)


## Shows a see-through roll in front of Henry that follows where he faces.
func begin_placement() -> bool:
	if is_placing() or is_laid() or inventory == null or not inventory.has_item(ITEM_ID):
		return false
	var world: Node = get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	_preview = Node3D.new()
	_preview.name = "BedrollPreview"
	world.add_child(_preview)
	var ghost := StandardMaterial3D.new()
	ghost.albedo_color = Color(0.55, 0.9, 0.6, 0.35)
	ghost.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ghost.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var pad := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.75, 0.06, 1.9)
	box.material = ghost
	pad.mesh = box
	pad.position = Vector3(0.0, 0.03, 0.0)
	_preview.add_child(pad)
	var hint := Label3D.new()
	hint.text = tr(PLACE_HINT_KEY)
	hint.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	hint.font_size = 28
	hint.position = Vector3(0.0, 0.5, 0.0)
	_preview.add_child(hint)
	_preview.global_transform = _front_transform()
	return true


func confirm_placement() -> bool:
	if not is_placing():
		return false
	var xf: Transform3D = _preview.global_transform
	_clear_preview()
	return _lay_at(xf)


func cancel_placement() -> void:
	_clear_preview()


func _clear_preview() -> void:
	if is_instance_valid(_preview):
		_preview.queue_free()
	_preview = null


## Lengthwise in front of Henry; the body faces -Z.
func _front_transform() -> Transform3D:
	var body := get_parent() as Node3D
	if body == null:
		return Transform3D.IDENTITY
	var facing: Vector3 = -body.global_transform.basis.z
	facing.y = 0.0
	facing = facing.normalized() if facing.length() > 0.01 else Vector3.FORWARD
	return Transform3D(Basis(Vector3.UP, atan2(facing.x, facing.z)), body.global_position + facing * PLACE_DISTANCE)


func is_laid() -> bool:
	return is_instance_valid(_laid)


func get_laid_bedroll() -> Node3D:
	return _laid if is_laid() else null


## Spends the bedroll and lays it straight in front of Henry, no preview.
func lay_down() -> bool:
	return _lay_at(_front_transform())


func _lay_at(xf: Transform3D) -> bool:
	var body := get_parent() as CharacterBody3D
	if is_laid() or body == null or inventory == null or body.velocity.y < -0.5:  # not mid-fall
		return false
	if not inventory.try_remove(ITEM_ID):
		return false
	_spawn(xf)
	if body.has_method(&"play_action_animation"):
		body.call(&"play_action_animation", &"fix")
	return true


func _spawn(xf: Transform3D) -> void:
	var roll := Node3D.new()
	roll.name = "LaidBedroll"
	var world: Node = get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	world.add_child(roll)
	roll.global_transform = xf
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = Color(0.2, 0.26, 0.2)
	cloth.roughness = 1.0
	var pad := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.75, 0.06, 1.9)
	box.material = cloth
	pad.mesh = box
	pad.position = Vector3(0.0, 0.03, 0.0)
	roll.add_child(pad)
	var head := MeshInstance3D.new()
	var bundle := CylinderMesh.new()
	bundle.top_radius = 0.1
	bundle.bottom_radius = 0.1
	bundle.height = 0.75
	bundle.material = cloth
	head.mesh = bundle
	head.transform = Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(0.0, 0.1, -0.85))
	roll.add_child(head)
	_prompt(roll, "Sleep", SLEEP_SPOT_SCRIPT, Vector3(0.6, 0.0, 0.2), Vector3(1.0, 1.4, 1.4), pad, {})
	var pack: Node3D = _prompt(roll, "Pack", PICKUP_SCRIPT, Vector3(0.0, 0.0, -1.2), Vector3(0.9, 1.2, 0.7), head,
		{&"item_id": ITEM_ID})
	pack.connect(&"picked_up", _on_packed)
	_laid = roll
	(pack as InteractiveArea).set_item_name(tr(PACK_KEY))
	bedroll_laid.emit(roll)


## An InteractiveArea with its own trigger box; props are set before _ready.
func _prompt(parent: Node3D, node_name: String, script_path: String, pos: Vector3, size: Vector3,
		mesh: MeshInstance3D, props: Dictionary) -> Node3D:
	var prompt: Node3D = (load(INTERACTIVE_SCENE) as PackedScene).instantiate()
	prompt.name = node_name
	prompt.set_script(load(script_path))
	for key: StringName in props:
		prompt.set(key, props[key])
	prompt.set(&"interactable_scene", null)
	prompt.set(&"interactive_mesh", mesh)
	prompt.position = pos
	var col := prompt.get_node_or_null(^"CollisionShape3D") as CollisionShape3D
	if col != null:
		var shape := BoxShape3D.new()
		shape.size = size
		col.shape = shape
	parent.add_child(prompt)
	return prompt


func _on_packed(_item_id: StringName, _count: int) -> void:
	if is_laid():
		_laid.queue_free()
	_laid = null
	bedroll_packed.emit()


func get_save_key() -> StringName:
	return &"bedroll"


func get_save_data() -> Dictionary:
	if not is_laid():
		return {}
	var xf: Transform3D = _laid.global_transform
	return {"x": xf.origin.x, "y": xf.origin.y, "z": xf.origin.z,
		"yaw": xf.basis.get_euler().y}


func load_save_data(data: Dictionary) -> void:
	if is_laid():
		_laid.queue_free()
		_laid = null
	if data.has("x"):
		var origin := Vector3(float(data["x"]), float(data["y"]), float(data["z"]))
		_spawn(Transform3D(Basis(Vector3.UP, float(data.get("yaw", 0.0))), origin))
