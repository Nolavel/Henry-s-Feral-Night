extends Node3D

@export var first_spawner_marker: Marker3D
@onready var player: CharacterBody3D = $Player
@onready var camera: Camera3D = $PlayerCamera

func _ready() -> void:
	spawn_player_at_marker()

func spawn_player_at_marker() -> void:
	if not is_instance_valid(first_spawner_marker):
		print("Warning: Initial spawner marker is not set or not valid.")
		return
	
	if not is_instance_valid(player):
		print("Error: Player node not found.")
		return
	player.global_transform.origin = first_spawner_marker.global_transform.origin
	
	first_spawner_marker.queue_free()
	
	print("Player spawned at marker and marker removed.")
