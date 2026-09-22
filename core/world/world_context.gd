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
