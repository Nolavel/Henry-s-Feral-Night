class_name WorldData
extends Resource

## The declarative content list the streaming pipeline consumes. Editing world
## layout means editing this data, not code.
##
## Regenerate with:
##   godot --headless --script tools/world/generate_world_data.gd

## Every streamed chunk on the island.
@export var chunks: Array[ChunkData] = []
## Where the player starts, when the scene does not carry its own marker.
@export var spawn_point: Vector3 = Vector3.ZERO
## Scene this data was generated from, for regeneration and for diffing.
@export var source_scene_path: String = ""


## The chunk with this id, or null.
func find_chunk(id: StringName) -> ChunkData:
	for chunk: ChunkData in chunks:
		if chunk != null and chunk.id == id:
			return chunk
	return null


## Only the chunks that carry enough data to stream.
func get_streamable_chunks() -> Array[ChunkData]:
	var streamable: Array[ChunkData] = []
	for chunk: ChunkData in chunks:
		if chunk != null and chunk.is_streamable():
			streamable.append(chunk)
	return streamable
