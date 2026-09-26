extends Node3D

## Capture-only staging: real island + real shelter door + production prompt.
## No fake action text is authored here; the banner reads the HingedDoor.

@onready var world: Node3D = $World


func _ready() -> void:
	get_tree().current_scene = self
	call_deferred("_stage")


func _stage() -> void:
	# Let World build systems, 3D entities and UI first.
	for _i in range(4):
		await get_tree().process_frame

	var player := world.get_node_or_null(^"Player") as CharacterBody3D
	var camera := world.get_node_or_null(^"PlayerCamera") as Camera3D
	var door := world.get_node_or_null(
		^"FirstExitBlockout/ShelterHouse/House/HouseDoor"
	) as InteractiveArea
	if player == null or camera == null or door == null:
		push_warning("action prompt preview: player/camera/shelter door missing")
		return

	# Door local +Z is the exterior side in the authored shelter.
	var outward := door.global_transform.basis.z
	outward.y = 0.0
	outward = outward.normalized()
	var right := door.global_transform.basis.x
	right.y = 0.0
	right = right.normalized()

	player.global_position = door.global_position + outward * 1.25
	player.global_position.y = door.global_position.y - 2.0
	player.look_at(Vector3(door.global_position.x, player.global_position.y, door.global_position.z), Vector3.UP)
	player.velocity = Vector3.ZERO

	# Freeze only the capture camera controller, not the world.
	camera.process_mode = Node.PROCESS_MODE_DISABLED
	camera.global_position = player.global_position + outward * 3.2 + right * 1.15 + Vector3.UP * 2.15
	camera.look_at(door.global_position + Vector3.UP * 0.25, Vector3.UP)

	# Use the production centre-focus path. Do not force current_target.
	var interact := player.get_node_or_null(^"InteractComponent") as InteractComponent
	camera.look_at(door.global_position + Vector3.UP * 0.15, Vector3.UP)
	if interact != null:
		interact.detect_target()

	await get_tree().physics_frame
	if interact != null:
		interact.detect_target()
	var cursor := player.get_node_or_null(^"MouseCursorUI") as MouseCursorUI
	if interact == null or interact.current_target != door:
		push_error("action prompt preview: centre ray did not acquire shelter door")
		get_tree().quit(1)
		return
	if cursor == null or not cursor.has_center_interaction_prompt():
		push_error("action prompt preview: centered cursor prompt missing")
		get_tree().quit(1)
		return
	print("action prompt preview: staged center morph %s -> %s" % [
		door.get_path(), door.get_interaction_prompt_data()
	])

	# Remove capture-only debug labels so the interaction treatment is legible.
	var debug := world.get_node_or_null(^"Perfomance&Debugging")
	if debug is Node3D:
		(debug as Node3D).visible = false
	var stats := world.get_node_or_null(^"StatsDisplay")
	if stats is CanvasItem:
		(stats as CanvasItem).visible = false
