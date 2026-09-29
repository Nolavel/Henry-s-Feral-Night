class_name WorldProfile
extends Resource

## One terrain/content dataset that HFN can select.
## This resource stores paths and provenance only; it owns no runtime state.

@export var id: StringName = &""
@export var display_name: String = ""

@export_group("Terrain")
@export_file("*.png") var terrain_image_path: String = ""
@export_file("*.json") var terrain_meta_path: String = ""

@export_group("Streaming")
@export_file("*.tres") var world_data_path: String = ""

@export_group("Provenance")
@export var experimental: bool = false
@export var source_note: String = ""
@export var source_manifest_path: String = ""


func terrain_is_configured() -> bool:
	return terrain_image_path != "" and terrain_meta_path != ""


func terrain_files_exist() -> bool:
	return (
		terrain_is_configured()
		and FileAccess.file_exists(terrain_image_path)
		and FileAccess.file_exists(terrain_meta_path)
	)


func world_data_exists() -> bool:
	return world_data_path != "" and ResourceLoader.exists(world_data_path)


func is_runtime_ready() -> bool:
	return id != &"" and terrain_files_exist() and world_data_exists()
