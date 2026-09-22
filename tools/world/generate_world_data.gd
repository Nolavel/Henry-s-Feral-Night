extends SceneTree

## Reads the authored island scene and writes data/world_data.tres. The scene's
## Area3D nodes stay the source of truth; nothing here is hand-written.
##
## Run: godot --headless --script tools/world/generate_world_data.gd

const SOURCE_SCENE: String = "res://experimental_location/scenes/Graciosa_Island_Terrain.tscn"
const OUTPUT_PATH: String = "res://data/world_data.tres"
const STREAM_ROOT_NAME: String = "WorldStreamManager"
const CONTENT_DIR: String = "res://scenes/game"
## Both spellings: the authored names use a Cyrillic С homoglyph in "Сhunk_".
const CHUNK_PREFIXES: Array[String] = ["Chunk_", "Сhunk_"]
## Fallback radius when a chunk carries no polygon to measure.
const DEFAULT_RADIUS: float = 120.0

var _content_scenes: Dictionary = {}


## Nodes added during _initialize() are not in the tree yet, so global_position
## is meaningless there. Everything runs from the first frame instead.
func _process(_delta: float) -> bool:
	_generate()
	return true


func _generate() -> void:
	var packed := load(SOURCE_SCENE) as PackedScene
	if packed == null:
		push_error("generate_world_data: cannot load %s" % SOURCE_SCENE)
		quit(1)
		return
	var scene: Node = packed.instantiate()
	root.add_child(scene)

	_index_content_scenes(CONTENT_DIR)

	var data := WorldData.new()
	data.source_scene_path = SOURCE_SCENE
	var stream_root: Node = scene.get_node_or_null(STREAM_ROOT_NAME)
	if stream_root == null:
		push_error("generate_world_data: no %s in the scene" % STREAM_ROOT_NAME)
		quit(1)
		return
	_collect(stream_root, "", data)

	var spawner := scene.get_node_or_null("FirstSpawner") as Node3D
	if spawner != null:
		data.spawn_point = spawner.global_position

	data.chunks.sort_custom(func(a: ChunkData, b: ChunkData) -> bool: return a.id < b.id)
	var error: Error = ResourceSaver.save(data, OUTPUT_PATH)
	if error != OK:
		push_error("generate_world_data: save failed (%d)" % error)
		quit(1)
		return

	var missing: int = 0
	for chunk: ChunkData in data.chunks:
		if chunk.content_scene_path == "":
			missing += 1
			push_warning("generate_world_data: no content scene for '%s'" % chunk.id)
	print(
		"generate_world_data: wrote %d chunks to %s (%d without content)"
		% [data.chunks.size(), OUTPUT_PATH, missing]
	)
	quit(0)


## Walks the stream subtree, recording every chunk Area3D it finds.
func _collect(node: Node, location: String, data: WorldData) -> void:
	var current_location: String = location
	if location == "" and node.get_parent() != null \
			and node.get_parent().name == STREAM_ROOT_NAME:
		current_location = String(node.name)

	var area := node as Area3D
	if area != null and _is_chunk(String(area.name)):
		data.chunks.append(_build_chunk(area, current_location))

	for child: Node in node.get_children():
		_collect(child, current_location, data)


func _is_chunk(node_name: String) -> bool:
	for prefix: String in CHUNK_PREFIXES:
		if node_name.begins_with(prefix):
			return true
	return false


## Turns one authored Area3D into a ChunkData.
func _build_chunk(area: Area3D, location: String) -> ChunkData:
	var chunk := ChunkData.new()
	var bare: String = String(area.name)
	for prefix: String in CHUNK_PREFIXES:
		bare = bare.trim_prefix(prefix)
	chunk.id = StringName(_to_snake_case(bare))
	chunk.display_name = _read_label(area, bare)
	chunk.location = location
	chunk.position = area.global_position
	chunk.radius = _measure_radius(area)
	chunk.content_scene_path = String(_content_scenes.get(String(chunk.id), ""))
	return chunk


## Radius of the authored collision polygon, in world units.
func _measure_radius(area: Area3D) -> float:
	var widest: float = 0.0
	for child: Node in area.get_children():
		var shape := child as CollisionPolygon3D
		if shape == null:
			continue
		for point: Vector2 in shape.polygon:
			widest = maxf(widest, point.length())
	return widest if widest > 0.0 else DEFAULT_RADIUS


## Prefers the authored Label3D text over the node name.
func _read_label(area: Area3D, fallback: String) -> String:
	for child: Node in area.get_children():
		var label := child as Label3D
		if label != null and label.text.strip_edges() != "":
			return label.text.strip_edges()
	return fallback


## Indexes every chunk_*.tscn under the content directory by its bare id, so
## the mapping is a naming convention rather than a hardcoded table.
func _index_content_scenes(directory: String) -> void:
	var dir := DirAccess.open(directory)
	if dir == null:
		return
	for file_name: String in dir.get_files():
		var clean: String = file_name.trim_suffix(".remap")
		if not clean.ends_with(".tscn") or not clean.begins_with("chunk_"):
			continue
		_content_scenes[clean.trim_prefix("chunk_").trim_suffix(".tscn")] = \
			"%s/%s" % [directory, clean]
	for sub_dir: String in dir.get_directories():
		_index_content_scenes("%s/%s" % [directory, sub_dir])


## PascalCase or spaced names to snake_case ids.
func _to_snake_case(value: String) -> String:
	var out: String = ""
	for i: int in range(value.length()):
		var character: String = value[i]
		if character == " " or character == "-" or character == "'":
			continue
		if character == character.to_upper() and character != character.to_lower() and i > 0:
			out += "_"
		out += character.to_lower()
	return out
