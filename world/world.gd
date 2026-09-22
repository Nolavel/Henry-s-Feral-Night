# =============================================================================
# world.gd — the composition root.
#
# Everything alive at runtime is created and wired here, in one place, and
# THIS FILE DOES NOT GROW AS SYSTEMS ARE ADDED. Three declarative lists say
# what exists; the loops below are fixed.
#
# Adding a system, a 3D entity or a UI scene is ONE LINE in the relevant
# array, plus an optional on_world_ready(context) in the thing itself.
#
# The three lists are separate because the three categories are built
# differently and parented differently:
#   1) WORLD_SYSTEM_SCRIPTS — Node classes via .new(), parented to World.
#   2) WORLD_3D_ENTITY_SCENES — .tscn via instantiate(), under StreamContainer.
#   3) WORLD_UI_SCENES — Control scenes, under a dedicated CanvasLayer.
#
# What this file is NOT about: world CONTENT. Chunks and their contents belong
# to the streaming pipeline, which is independent of this lifecycle.
#
# Borrowed wholesale from the ADT project's world.gd. See
# docs/technical/WORLD_ARCHITECTURE.md for what was taken and why.
# =============================================================================
class_name World
extends Node3D

## Optional lifecycle hook. Anything in the three lists below, plus the
## player, may implement it; nodes that do not are skipped silently.
const WORLD_READY_METHOD: StringName = &"on_world_ready"

## Node systems — .new(), parented to World.
const WORLD_SYSTEM_SCRIPTS: Array[GDScript] = [
	preload("res://scripts/systems/world/WeatherController.gd"),
	preload("res://scripts/systems/save/save_manager.gd"),
]

## Standalone 3D scenes — instantiate(), parented to StreamContainer.
const WORLD_3D_ENTITY_SCENES: Array[PackedScene] = []

## Screen-space UI scenes — instantiate(), parented to a shared CanvasLayer.
const WORLD_UI_SCENES: Array[PackedScene] = [
	preload("res://scenes/ui/hud/sleep_prompt.tscn"),
]

const UI_CANVAS_LAYER_INDEX: int = 40
## Lift above the spawn marker, so the capsule does not start inside the floor.
const SPAWN_CLEARANCE: float = 1.0

@export_group("Scene wiring")
## Container the streaming pipeline fills. Created if absent.
@export var stream_container: Node3D
## Player already present in the scene; one is not spawned when this is set.
@export var player: Node3D
## Camera already present in the scene.
@export var camera: Camera3D
## Where the player starts. Freed after use, as the old GameRouter did.
@export var first_spawner_marker: Marker3D

var _systems: Array[Node] = []
var _context: WorldContext


func _ready() -> void:
	await get_tree().process_frame
	initialize()


## Builds the world. Public and idempotent so tests can drive it directly
## instead of waiting for a frame.
func initialize() -> void:
	if _context != null:
		return
	_resolve_scene_nodes()
	_build_systems()
	_place_player()
	_context = _build_context()
	_notify(player)
	for system: Node in _systems:
		_notify(system)
	_build_3d_entities()
	_build_ui()
	print("[World] initialized with %d systems" % _systems.size())


## The context handed to every system; null before initialize() has run.
func get_context() -> WorldContext:
	return _context


## Finds the container and the player/camera the scene already carries.
func _resolve_scene_nodes() -> void:
	if stream_container == null:
		stream_container = get_node_or_null("StreamContainer") as Node3D
	if stream_container == null:
		stream_container = Node3D.new()
		stream_container.name = "StreamContainer"
		add_child(stream_container)
	if player == null:
		player = get_node_or_null("Player") as Node3D
	if camera == null:
		camera = get_node_or_null("PlayerCamera") as Camera3D


func _build_systems() -> void:
	for system_script: GDScript in WORLD_SYSTEM_SCRIPTS:
		var instance: Node = system_script.new()
		add_child(instance)
		_systems.append(instance)


## Moves the player onto the spawn marker, then drops the marker.
func _place_player() -> void:
	if player == null or first_spawner_marker == null:
		return
	player.global_position = (
		first_spawner_marker.global_position + Vector3(0.0, SPAWN_CLEARANCE, 0.0)
	)
	first_spawner_marker.queue_free()
	first_spawner_marker = null


func _build_context() -> WorldContext:
	var context := WorldContext.new()
	context.player = player
	context.camera = camera
	context.stream_container = stream_container
	context.systems = _systems
	return context


func _build_3d_entities() -> void:
	for scene: PackedScene in WORLD_3D_ENTITY_SCENES:
		var instance: Node = scene.instantiate()
		stream_container.add_child(instance)
		_notify(instance)


func _build_ui() -> void:
	if WORLD_UI_SCENES.is_empty():
		return
	var canvas := CanvasLayer.new()
	canvas.name = "WorldUI"
	canvas.layer = UI_CANVAS_LAYER_INDEX
	add_child(canvas)
	for scene: PackedScene in WORLD_UI_SCENES:
		var instance: Node = scene.instantiate()
		canvas.add_child(instance)
		_notify(instance)


## Calls the optional lifecycle hook, if the node implements it.
func _notify(node: Node) -> void:
	if node != null and node.has_method(WORLD_READY_METHOD):
		node.call(WORLD_READY_METHOD, _context)
