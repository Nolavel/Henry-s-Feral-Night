extends SceneTree

## Stage 0 of #138: profiles exist without changing the Graciosa default,
## and IslandTerrain exposes generic dataset paths while retaining old defaults.
## Run: godot --headless --script tests/systems/test_world_profiles.gd

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
	_check(key_west != null, "Key West placeholder profile does not load")
	if key_west != null:
		_check(key_west.experimental, "Key West placeholder is not marked experimental")
		_check(not key_west.terrain_is_configured(), "Key West placeholder must not fake terrain data")
		_check(not key_west.is_runtime_ready(), "Key West placeholder became runtime-ready before NOAA import")

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
