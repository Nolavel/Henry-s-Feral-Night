extends SceneTree

## Covers the data-driven streaming pipeline: the generated data, the cell
## state machine, hysteresis, the budgets, and rollback without instantiating.
## Run: godot --headless --script tests/systems/test_streaming.gd

const WORLD_DATA: String = "res://data/world_data.tres"

var _failures: int = 0


## The pipeline instantiates scenes, which only works from inside the tree.
func _process(_delta: float) -> bool:
	_run()
	return true


func _run() -> void:
	_test_generated_data_is_usable()
	_test_chunks_load_when_the_player_approaches()
	_test_hysteresis_keeps_a_boundary_chunk_loaded()
	_test_instantiation_budget_is_respected()
	_test_leaving_early_rolls_back_without_instantiating()
	_test_reset_clears_everything()
	if _failures > 0:
		push_error("streaming: %d check(s) failed" % _failures)
		quit(1)
		return
	print("streaming: all checks passed")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("streaming: %s" % message)


func _dispose(node: Node) -> void:
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	node.free()


func _make_system() -> Dictionary:
	var container := Node3D.new()
	root.add_child(container)
	var player := Node3D.new()
	root.add_child(player)
	var system := StreamingSystem.new()
	root.add_child(system)
	system.initialize(container, player)
	return {"system": system, "container": container, "player": player}


func _dispose_rig(rig: Dictionary) -> void:
	(rig["system"] as StreamingSystem).reset()
	for key: String in ["system", "player", "container"]:
		_dispose(rig[key])


## Pumps until every load settles, with a bound so a stall fails rather than hangs.
func _settle(system: StreamingSystem, iterations: int = 400) -> void:
	for i: int in range(iterations):
		system.pump()


func _first_chunk() -> ChunkData:
	var data := load(WORLD_DATA) as WorldData
	return data.get_streamable_chunks()[0]


func _test_generated_data_is_usable() -> void:
	var data := load(WORLD_DATA) as WorldData
	_check(data != null, "world_data.tres did not load as WorldData")
	if data == null:
		return
	var streamable: Array[ChunkData] = data.get_streamable_chunks()
	_check(streamable.size() >= 9, "expected at least 9 chunks, got %d" % streamable.size())

	var seen: Dictionary = {}
	for chunk: ChunkData in streamable:
		_check(chunk.id != &"", "a chunk has no id")
		_check(not seen.has(chunk.id), "duplicate chunk id '%s'" % chunk.id)
		seen[chunk.id] = true
		_check(chunk.radius > 0.0, "%s has a non-positive radius" % chunk.id)
		_check(
			ResourceLoader.exists(chunk.content_scene_path),
			"%s points at a missing scene: %s" % [chunk.id, chunk.content_scene_path]
		)
	_check(
		data.find_chunk(streamable[0].id) == streamable[0],
		"find_chunk did not return the chunk it was asked for"
	)
	_check(data.find_chunk(&"not_a_chunk") == null, "find_chunk invented a chunk")


func _test_chunks_load_when_the_player_approaches() -> void:
	var rig: Dictionary = _make_system()
	var system: StreamingSystem = rig["system"]
	var chunk: ChunkData = _first_chunk()

	system.scan(Vector3(100000.0, 0.0, 100000.0))
	_settle(system)
	_check(
		system.get_active_chunks().is_empty(),
		"chunks were active with the player on the other side of the world"
	)

	system.scan(chunk.position)
	_settle(system)
	_check(
		system.get_state(chunk.id) == StreamingSystem.CellState.ACTIVE,
		"standing on a chunk did not make it active (state %d)" % system.get_state(chunk.id)
	)
	_check(
		(rig["container"] as Node3D).get_child_count() > 1,
		"an active chunk put nothing into the stream container"
	)
	_dispose_rig(rig)


## Without the gap, a chunk on the boundary thrashes between states.
func _test_hysteresis_keeps_a_boundary_chunk_loaded() -> void:
	var rig: Dictionary = _make_system()
	var system: StreamingSystem = rig["system"]
	var chunk: ChunkData = _first_chunk()

	system.scan(chunk.position)
	_settle(system)
	_check(
		system.get_state(chunk.id) == StreamingSystem.CellState.ACTIVE,
		"the rig chunk did not become active"
	)

	## Just past the load band, but inside the hysteresis gap.
	var just_outside: float = chunk.radius + system.load_margin_m + 10.0
	system.scan(chunk.position + Vector3(just_outside, 0.0, 0.0))
	_settle(system)
	_check(
		system.get_state(chunk.id) == StreamingSystem.CellState.ACTIVE,
		"a chunk just past the load band unloaded; the hysteresis gap does nothing"
	)

	## Beyond the gap it must go.
	var far: float = chunk.radius + system.load_margin_m + system.unload_hysteresis_m + 50.0
	system.scan(chunk.position + Vector3(far, 0.0, 0.0))
	_settle(system)
	_check(
		system.get_state(chunk.id) == StreamingSystem.CellState.UNLOADED,
		"a chunk past the unload band stayed loaded"
	)
	_dispose_rig(rig)


## instantiate() is what costs a frame, so the budget must actually bind.
func _test_instantiation_budget_is_respected() -> void:
	var rig: Dictionary = _make_system()
	var system: StreamingSystem = rig["system"]
	system.instantiation_budget_per_frame = 1

	## Sit at the island's centre of mass so several chunks qualify at once.
	var data := load(WORLD_DATA) as WorldData
	var centre: Vector3 = Vector3.ZERO
	for chunk: ChunkData in data.get_streamable_chunks():
		centre += chunk.position
	centre /= float(data.get_streamable_chunks().size())

	system.scan(centre)
	for i: int in range(200):
		system.pump()
	var ready_now: int = 0
	for chunk: ChunkData in data.get_streamable_chunks():
		if system.get_state(chunk.id) == StreamingSystem.CellState.READY:
			ready_now += 1

	var before: int = system.get_active_chunks().size()
	if ready_now > 0:
		system.pump()
		_check(
			system.get_active_chunks().size() - before <= 1,
			"one pump activated more than the budget of one chunk"
		)
	_check(before > 0, "sitting in the middle of the island activated nothing")
	_dispose_rig(rig)


## Walking away mid-load must not leave an instance behind.
func _test_leaving_early_rolls_back_without_instantiating() -> void:
	var rig: Dictionary = _make_system()
	var system: StreamingSystem = rig["system"]
	var chunk: ChunkData = _first_chunk()

	system.scan(chunk.position)
	var far: float = chunk.radius + system.load_margin_m + system.unload_hysteresis_m + 200.0
	system.scan(chunk.position + Vector3(far, 0.0, 0.0))
	_settle(system)

	_check(
		system.get_state(chunk.id) == StreamingSystem.CellState.UNLOADED,
		"a chunk left behind did not return to UNLOADED"
	)
	_check(
		not system.get_active_chunks().has(chunk.id),
		"a chunk the player walked away from was instantiated anyway"
	)
	_dispose_rig(rig)


func _test_reset_clears_everything() -> void:
	var rig: Dictionary = _make_system()
	var system: StreamingSystem = rig["system"]
	var chunk: ChunkData = _first_chunk()

	system.scan(chunk.position)
	_settle(system)
	_check(not system.get_active_chunks().is_empty(), "nothing was active before reset")

	system.reset()
	_check(system.get_active_chunks().is_empty(), "reset left chunks active")
	_check(
		system.get_state(chunk.id) == StreamingSystem.CellState.UNLOADED,
		"reset left a chunk in a loaded state"
	)
	_dispose_rig(rig)
