extends SceneTree

## Dumps the Graciosa heightfield and the scene's named markers for
## tools/world/island_report.py. Run headless; writes to user://island/.

const TERRAIN_DIR: String = "res://experimental_location/Graciosa/terrain_graciosa"
const SCENE: String = "res://experimental_location/scenes/Graciosa_Island_Terrain.tscn"
const OUT_DIR: String = "user://island"
## Sample spacing in metres; 2 m resolves a house footprint.
const STEP_M: float = 2.0


func _initialize() -> void:
	var terrain := Terrain3D.new()
	terrain.data_directory = TERRAIN_DIR
	root.add_child(terrain)
	await process_frame
	await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var bounds: Rect2 = _region_bounds(terrain)
	var cols: int = int(bounds.size.x / STEP_M)
	var rows: int = int(bounds.size.y / STEP_M)
	var heights := PackedFloat32Array()
	heights.resize(cols * rows)
	var data: Terrain3DData = terrain.data
	for r: int in range(rows):
		var z: float = bounds.position.y + (float(r) + 0.5) * STEP_M
		for c: int in range(cols):
			var x: float = bounds.position.x + (float(c) + 0.5) * STEP_M
			var h: float = data.get_height(Vector3(x, 0.0, z))
			heights[r * cols + c] = h if not is_nan(h) else -20.0
	var file := FileAccess.open(OUT_DIR + "/heights.f32", FileAccess.WRITE)
	file.store_buffer(heights.to_byte_array())
	file.close()
	var meta: Dictionary = {
		"origin_x": bounds.position.x, "origin_z": bounds.position.y,
		"step_m": STEP_M, "cols": cols, "rows": rows,
		"markers": _scene_markers(),
	}
	var json := FileAccess.open(OUT_DIR + "/meta.json", FileAccess.WRITE)
	json.store_string(JSON.stringify(meta, "\t"))
	json.close()
	print("island dump: %dx%d at %.1f m -> %s" % [cols, rows, STEP_M, ProjectSettings.globalize_path(OUT_DIR)])
	quit()


func _region_bounds(terrain: Terrain3D) -> Rect2:
	var size: float = float(terrain.region_size) * terrain.vertex_spacing
	var rect := Rect2()
	var first: bool = true
	for loc: Vector2i in terrain.data.get_region_locations():
		var cell := Rect2(Vector2(loc) * size, Vector2(size, size))
		rect = cell if first else rect.merge(cell)
		first = false
	return rect


## Named places from the scene, positions composed by hand: the scene is never
## added to the tree, so its World script does not boot.
func _scene_markers() -> Array:
	var scene: Node = (load(SCENE) as PackedScene).instantiate()
	var out: Array = []
	_collect(scene, Transform3D.IDENTITY, out)
	scene.free()
	return out


func _collect(node: Node, parent_xf: Transform3D, out: Array) -> void:
	var xf: Transform3D = parent_xf
	if node is Node3D:
		xf = parent_xf * (node as Node3D).transform
		if node is Marker3D or node.name == "Player" or node is Label3D:
			var p: Vector3 = xf.origin
			var label: String = (node as Label3D).text if node is Label3D else String(node.name)
			out.append({"name": label, "kind": node.get_class(), "x": p.x, "z": p.z})
	for child: Node in node.get_children():
		_collect(child, xf, out)
