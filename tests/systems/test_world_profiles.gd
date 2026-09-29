extends SceneTree

## Dataset profiles retain the Graciosa default and gate Key West runtime
## readiness on real terrain files rather than configured paths alone.

var _failures: int = 0
var _ran: bool = false


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_run()
	return false


func _run() -> void:
	var graciosa: WorldProfile = WorldProfileCatalog.load_profile(&"graciosa")
	_check(graciosa != null, "Graciosa profile does not load")
	if graciosa != null:
		_check(graciosa.id == &"graciosa", "wrong Graciosa id")
		_check(graciosa.terrain_image_path == IslandHeightmap.DEFAULT_IMAGE, "Graciosa image path changed")
		_check(graciosa.terrain_meta_path == IslandHeightmap.DEFAULT_META, "Graciosa metadata path changed")
		_check(graciosa.world_data_path == StreamingSystem.DEFAULT_WORLD_DATA, "Graciosa world data path changed")
		_check(graciosa.is_runtime_ready(), "existing Graciosa profile is not runtime-ready")

	var key_west: WorldProfile = WorldProfileCatalog.load_profile(&"key_west_test")
	_check(key_west != null, "Key West profile does not load")
	if key_west != null:
		_check(key_west.experimental, "Key West profile is not marked experimental")
		_check(key_west.terrain_is_configured(), "Key West terrain paths are not configured")
		_check(key_west.terrain_image_path != IslandHeightmap.DEFAULT_IMAGE, "Key West reuses the Graciosa image")
		_check(key_west.terrain_meta_path != IslandHeightmap.DEFAULT_META, "Key West reuses the Graciosa metadata")
		_check(key_west.content_scene_exists(), "Key West content scene does not exist")
		if key_west.terrain_files_exist():
			_check(key_west.is_runtime_ready(), "Key West with imported NOAA terrain is not runtime-ready")
		else:
			_check(not key_west.is_runtime_ready(), "Key West became runtime-ready without NOAA terrain")

	var missing_terrain := WorldProfile.new()
	missing_terrain.id = &"missing_terrain"
	missing_terrain.terrain_image_path = "res://tests/missing_noaa_terrain.png"
	missing_terrain.terrain_meta_path = "res://tests/missing_noaa_terrain.json"
	_check(not missing_terrain.is_runtime_ready(), "configured missing terrain must not be runtime-ready")

	var terrain := IslandTerrain.new()
	_check(terrain.heightmap_image_path == IslandHeightmap.DEFAULT_IMAGE, "IslandTerrain no longer defaults to Graciosa image")
	_check(terrain.heightmap_meta_path == IslandHeightmap.DEFAULT_META, "IslandTerrain no longer defaults to Graciosa metadata")
	terrain.free()

	if _failures > 0:
		push_error("world profiles: %d check(s) failed" % _failures)
		quit(1)
		return
	print("world profiles: all checks passed")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("world profiles: %s" % message)
