extends SceneTree
## Checks the patched bindings and deep copies without saving terrain data.

var _failures: int = 0


func _initialize() -> void:
	for type_name: StringName in [&"Terrain3DMeshAsset", &"Terrain3DTextureAsset"]:
		var asset: Resource = ClassDB.instantiate(type_name) as Resource
		if asset == null:
			_check(false, "Cannot instantiate %s" % type_name)
			continue
		asset.set("name", "Terrain compatibility probe")
		_check(asset.has_method("get_asset_name"), "%s getter missing" % type_name)
		_check(asset.has_method("set_asset_name"), "%s setter missing" % type_name)
		if asset.has_method("get_asset_name") and asset.has_method("set_asset_name"):
			_check(asset.call("get_asset_name") == "Terrain compatibility probe", "Name property getter mismatch")
			asset.call("set_asset_name", "Renamed probe")
			_check(asset.get("name") == "Renamed probe", "Name property setter mismatch")

	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	var directory: String = arguments[0] if not arguments.is_empty() else "res://experimental_location/Graciosa/terrain_graciosa"
	var count: int = 0
	for file_name: String in DirAccess.get_files_at(directory):
		if not file_name.ends_with(".res"):
			continue
		var region: Resource = load(directory.path_join(file_name)) as Resource
		if region == null or region.get_class() != "Terrain3DRegion":
			_check(false, "Cannot load %s" % file_name)
			continue
		var copied: Resource = region.duplicate(true)
		if copied == null:
			_check(false, "Cannot duplicate %s" % file_name)
			continue
		_check(copied.get("location") == region.get("location"), "Region location changed")
		_check(copied.get("region_size") == region.get("region_size"), "Region size changed")
		for map_name: StringName in [&"height_map", &"control_map", &"color_map"]:
			var original_map: Image = region.get(map_name) as Image
			var copied_map: Image = copied.get(map_name) as Image
			if original_map == null or copied_map == null:
				_check(false, "Missing %s in %s" % [map_name, file_name])
				continue
			_check(original_map != copied_map, "Deep copy shares an image")
			_check(original_map.get_size() == copied_map.get_size(), "Image size changed")
			_check(original_map.get_format() == copied_map.get_format(), "Image format changed")
			_check(original_map.get_data() == copied_map.get_data(), "Image data changed")
		var original_instances: Dictionary = region.get("instances")
		var copied_instances: Dictionary = copied.get("instances")
		copied_instances[&"hfn_probe"] = true
		_check(not original_instances.has(&"hfn_probe"), "Deep copy shares its instance dictionary")
		count += 1
		print("TERRAIN_REGION_OK=", file_name)
	_check(count == 5, "Expected five Graciosa regions, loaded %d" % count)
	print("TERRAIN_COMPATIBILITY_FAILURES=", _failures)
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
