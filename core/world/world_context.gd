class_name WorldContext
extends RefCounted

## Shared references world.gd builds once after the player and camera exist,
## and hands to every system through on_world_ready(context).

## The player body. Systems that need Henry's position read it from here.
var player: Node3D
## The active camera, already targeting the player.
var camera: Camera3D
## Parent for everything the streaming pipeline instantiates.
var stream_container: Node3D
## The composition root itself, so systems can search the scene it owns.
var world: Node3D
## Every system world.gd created, in the order it created them.
var systems: Array[Node] = []


## The one live instance of a system class, or null when it is not in the list.
func get_system(system_script: GDScript) -> Node:
	for system: Node in systems:
		if is_instance_of(system, system_script):
			return system
	return null


## True when every reference a system is likely to need is present.
func is_complete() -> bool:
	return player != null and camera != null and stream_container != null


## The first node of a type in the player's scene tree. For managers authored
## into a scene rather than created by world.gd, such as DayNightManager.
func find_in_scene(type_script: GDScript) -> Node:
	## The world root first: a headless harness that adds the scene to the
	## SceneTree root leaves current_scene null, so it cannot be relied on.
	var roots: Array[Node] = [world, player]
	if player != null and player.is_inside_tree():
		roots.append(player.get_tree().current_scene)
	for root_node: Node in roots:
		var found: Node = _search(root_node, type_script)
		if found != null:
			return found
	return null


static func _search(node: Node, type_script: GDScript) -> Node:
	if node == null:
		return null
	if is_instance_of(node, type_script):
		return node
	for child: Node in node.get_children():
		var found: Node = _search(child, type_script)
		if found != null:
			return found
	return null
