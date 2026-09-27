class_name StoveWarmer
extends Node3D

## The cooking ring on the stove top. F with a warmable item carried puts one
## there; while the stove burns it warms over WARM_HOURS of game time; then F
## eats or drinks it straight off the stove. Saved with the world.

signal state_changed(state: State)

enum State { EMPTY, WARMING, READY }

const WARM_HOURS: float = 0.5
const INTERACTIVE_SCENE: String = "res://scenes/environment/interactive/InteractiveArea.tscn"
const PROMPT_SCRIPT: String = "res://scripts/environment/stove/stove_warmer_prompt.gd"
const PUT_KEY: String = "WARM_PUT"
const WARMING_KEY: String = "WARM_WARMING"
const EAT_KEY: String = "TABLE_EAT"
const DRINK_KEY: String = "TABLE_DRINK"

@export var source: HeatSource

var _state: State = State.EMPTY
## The raw item while warming, the warmed one when ready.
var _item_id: StringName = &""
var _progress_h: float = 0.0
var _prop: Node3D
var _prompt: InteractiveArea
var _steam: GPUParticles3D


func _ready() -> void:
	add_to_group(&"saveable")
	if source == null:
		source = get_parent() as HeatSource
	if source != null:
		source.heat_elapsed.connect(advance)
	_build_prompt()
	_refresh()


func get_state() -> State:
	return _state


func get_item_id() -> StringName:
	return _item_id


## The first carried item that warms into something, or empty.
func find_warmable(inventory: InventoryComponent) -> StringName:
	if inventory == null:
		return &""
	for entry: Dictionary in inventory.get_entries():
		var item: ItemResource = ItemCatalog.get_item(entry["id"])
		if item != null and item.warms_into != &"":
			return item.id
	return &""


## Takes one warmable item from the pack and sets it on the ring.
func put(inventory: InventoryComponent, item_id: StringName) -> bool:
	var item: ItemResource = ItemCatalog.get_item(item_id)
	if _state != State.EMPTY or item == null or item.warms_into == &"" or not inventory.try_remove(item_id):
		return false
	_item_id = item_id
	_progress_h = 0.0
	_set_state(State.WARMING)
	return true


## Game time the stove burned through; the item warms only while it burns.
func advance(hours: float) -> void:
	if _state != State.WARMING:
		return
	_progress_h += hours
	if _progress_h >= WARM_HOURS:
		var raw: ItemResource = ItemCatalog.get_item(_item_id)
		_item_id = raw.warms_into if raw != null else &""
		_set_state(State.READY if _item_id != &"" else State.EMPTY)


## Eats or drinks the warmed item off the ring.
func take(eater: ConsumptionController) -> bool:
	if _state != State.READY or eater == null:
		return false
	if eater.consume_from_world(_item_id) != ConsumptionController.Refusal.NONE:
		return false
	_item_id = &""
	_set_state(State.EMPTY)
	return true


## F on the ring: put, or eat, depending on state. Called by the prompt.
func interact_with(player: Node) -> void:
	if player == null:
		return
	match _state:
		State.EMPTY:
			var inventory: InventoryComponent = InventoryComponent.find_in(player)
			put(inventory, find_warmable(inventory))
		State.READY:
			take(player.get_node_or_null(^"ConsumptionController") as ConsumptionController)


func can_interact_with(player: Node) -> bool:
	match _state:
		State.EMPTY:
			return source != null and source.is_burning() and find_warmable(InventoryComponent.find_in(player)) != &""
		State.READY:
			return true
	return false


func get_prompt_text(player: Node) -> String:
	match _state:
		State.EMPTY:
			var raw: ItemResource = ItemCatalog.get_item(find_warmable(InventoryComponent.find_in(player)))
			return "%s: %s" % [tr(PUT_KEY), tr(raw.display_name) if raw != null else ""]
		State.WARMING:
			return tr(WARMING_KEY)
	var hot: ItemResource = ItemCatalog.get_item(_item_id)
	var drink: bool = hot != null and hot.consumable != null and hot.consumable.calories <= 0.0
	return "%s: %s" % [tr(DRINK_KEY if drink else EAT_KEY), tr(hot.display_name) if hot != null else ""]


func _set_state(state: State) -> void:
	_state = state
	_refresh()
	state_changed.emit(state)


func _refresh() -> void:
	if is_instance_valid(_prop):
		_prop.queue_free()
	_prop = null
	if _item_id != &"":
		_prop = _make_prop(_item_id)
		add_child(_prop)
	if _steam != null:
		_steam.emitting = _state == State.READY
	if _prompt != null:
		_prompt.call(&"refresh_label")


## A tin on the ring for stew; a small pot for snow and water.
func _make_prop(item_id: StringName) -> Node3D:
	var node := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	var metal := StandardMaterial3D.new()
	metal.metallic = 0.8
	metal.roughness = 0.4
	if item_id == &"tinned_stew" or item_id == &"tinned_stew_hot":
		mesh.top_radius = 0.037
		mesh.bottom_radius = 0.037
		mesh.height = 0.075
		metal.albedo_color = Color(0.62, 0.6, 0.55)
	else:
		mesh.top_radius = 0.07
		mesh.bottom_radius = 0.06
		mesh.height = 0.08
		metal.albedo_color = Color(0.35, 0.36, 0.38)
		var fill := MeshInstance3D.new()
		var surface := CylinderMesh.new()
		surface.top_radius = 0.064
		surface.bottom_radius = 0.064
		surface.height = 0.01
		var look := StandardMaterial3D.new()
		look.albedo_color = Color(0.93, 0.95, 0.98) if item_id == &"snow_handful" else Color(0.55, 0.62, 0.66)
		surface.material = look
		fill.mesh = surface
		fill.position.y = 0.03
		node.add_child(fill)
	mesh.material = metal
	node.mesh = mesh
	node.position.y = mesh.height * 0.5
	var holder := Node3D.new()
	holder.add_child(node)
	return holder


func _build_prompt() -> void:
	var area: Node3D = (load(INTERACTIVE_SCENE) as PackedScene).instantiate()
	area.name = "Warm"
	area.set_script(load(PROMPT_SCRIPT))
	area.set(&"warmer", self)
	area.set(&"interactable_scene", null)
	area.set(&"object_on_ground", false)
	area.set(&"icon_height_offset", 0.25)
	area.set(&"info_height_offset", 0.4)
	var col := area.get_node_or_null(^"CollisionShape3D") as CollisionShape3D
	if col != null:
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.3, 0.3, 0.3)
		col.shape = shape
	add_child(area)
	_prompt = area as InteractiveArea
	_steam = GPUParticles3D.new()
	_steam.amount = 16
	_steam.lifetime = 1.4
	_steam.emitting = false
	_steam.position.y = 0.1
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3.UP
	process.spread = 6.0
	process.initial_velocity_min = 0.15
	process.initial_velocity_max = 0.3
	process.gravity = Vector3(0.0, 0.05, 0.0)
	_steam.process_material = process
	var puff := QuadMesh.new()
	puff.size = Vector2(0.06, 0.06)
	var look := StandardMaterial3D.new()
	look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	look.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	look.albedo_color = Color(1.0, 1.0, 1.0, 0.35)
	look.disable_fog = true
	var soft := GradientTexture2D.new()
	soft.fill = GradientTexture2D.FILL_RADIAL
	soft.fill_from = Vector2(0.5, 0.5)
	soft.fill_to = Vector2(1.0, 0.5)
	var falloff := Gradient.new()
	falloff.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	falloff.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	soft.gradient = falloff
	look.albedo_texture = soft
	puff.material = look
	_steam.draw_pass_1 = puff
	add_child(_steam)


func get_save_key() -> StringName:
	return &"stove_warmer"


func get_save_data() -> Dictionary:
	return {"state": int(_state), "item": String(_item_id), "progress": _progress_h}


func load_save_data(data: Dictionary) -> void:
	_state = int(data.get("state", 0)) as State
	_item_id = StringName(data.get("item", ""))
	_progress_h = float(data.get("progress", 0.0))
	if _item_id == &"" or ItemCatalog.get_item(_item_id) == null:
		_state = State.EMPTY
		_item_id = &""
	_refresh()
