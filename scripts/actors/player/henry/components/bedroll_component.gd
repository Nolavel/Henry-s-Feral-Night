class_name BedrollComponent
extends Node

## Lays Henry's bedroll on the ground so he can sleep away from a bed (B, until
## the inventory has a Use action). The laid roll offers F — Sleep through the
## usual SleepSpot and a prompt to roll it back up. Saved while laid out.

signal bedroll_laid(bedroll: Node3D)
signal bedroll_packed

const ACTION: StringName = &"lay_bedroll"
const ITEM_ID: StringName = &"bedroll"
const INTERACTIVE_SCENE: String = "res://scenes/environment/interactive/InteractiveArea.tscn"
const SLEEP_SPOT_SCRIPT: String = "res://scripts/environment/interactive/sleep_spot.gd"
const PICKUP_SCRIPT: String = "res://scripts/environment/interactive/item_pickup.gd"
const PACK_KEY: String = "BEDROLL_PACK"

@export var inventory: InventoryComponent

var _laid: Node3D


func _ready() -> void:
	add_to_group(&"saveable")
	if inventory == null:
		inventory = InventoryComponent.find_in(get_parent())


func _unhandled_input(event: InputEvent) -> void:
	if InputMap.has_action(ACTION) and event.is_action_pressed(ACTION):
		lay_down()


func is_laid() -> bool:
	return is_instance_valid(_laid)


func get_laid_bedroll() -> Node3D:
	return _laid if is_laid() else null


## Spends the bedroll from the inventory and spreads it at Henry's feet,
## lengthwise along where he faces. Refused while one is already laid.
func lay_down() -> bool:
	var body := get_parent() as CharacterBody3D
	if is_laid() or body == null or inventory == null or body.velocity.y < -0.5:  # not mid-fall
		return false
	if not inventory.try_remove(ITEM_ID):
		return false
	var facing: Vector3 = body.global_transform.basis.z
	facing.y = 0.0
	var spot: Vector3 = body.global_position + facing.normalized() * 1.1
	_spawn(Transform3D(Basis(Vector3.UP, atan2(facing.x, facing.z)), spot))
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
