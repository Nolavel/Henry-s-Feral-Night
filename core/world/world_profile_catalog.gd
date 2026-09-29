class_name WorldProfileCatalog
extends RefCounted

## Central lookup for world datasets. Selection stays out of gameplay
## systems so adding another island does not add per-world match arms.

const DEFAULT_PROFILE_ID: StringName = &"graciosa"
const PROFILE_DIR: String = "res://data/world_profiles"
const ENV_NAME: String = "HFN_WORLD"


static func requested_id() -> StringName:
	var requested: String = OS.get_environment(ENV_NAME).strip_edges()
	return DEFAULT_PROFILE_ID if requested.is_empty() else StringName(requested)


static func profile_path(id: StringName) -> String:
	return "%s/%s.tres" % [PROFILE_DIR, String(id)]


static func load_profile(id: StringName) -> WorldProfile:
	var path: String = profile_path(id)
	if not ResourceLoader.exists(path):
		push_error("WorldProfileCatalog: unknown world profile %s (%s)" % [id, path])
		return null
	var profile := load(path) as WorldProfile
	if profile == null:
		push_error("WorldProfileCatalog: cannot load %s" % path)
		return null
	return profile


static func load_selected() -> WorldProfile:
	return load_profile(requested_id())
