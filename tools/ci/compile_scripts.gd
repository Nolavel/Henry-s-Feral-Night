extends SceneTree

## Compiles every project GDScript and fails on the first that does not parse.
## Import alone never parses scripts, so a broken orphan would pass CI.

const SKIP: Array[String] = ["res://.godot", "res://addons"]


func _initialize() -> void:
	var failed: PackedStringArray = []
	var count: int = 0
	for path: String in _scripts("res://"):
		if path == get_script().resource_path:
			continue  # reloading the running script hangs
		count += 1
		var script := ResourceLoader.load(path, "GDScript", ResourceLoader.CACHE_MODE_IGNORE) as GDScript
		if script == null or not script.can_instantiate():
			failed.append(path)
	if failed.is_empty():
		print("compile scripts: %d clean" % count)
		quit(0)
		return
	for path: String in failed:
		push_error("compile scripts: %s does not compile" % path)
	quit(1)


func _scripts(dir_path: String) -> PackedStringArray:
	var out: PackedStringArray = []
	if SKIP.has(dir_path.trim_suffix("/")) or FileAccess.file_exists(dir_path.path_join(".gdignore")):
		return out
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for file: String in dir.get_files():
		if file.ends_with(".gd"):
			out.append(dir_path.path_join(file))
	for sub: String in dir.get_directories():
		out.append_array(_scripts(dir_path.path_join(sub)))
	return out
