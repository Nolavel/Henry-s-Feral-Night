extends SceneTree

## Covers the Key West city mesh rules from the #138 audit: footprints face out
## whatever their OSM winding, roofs follow the footprint, gables are closed.
## Run: godot --headless --script tests/systems/test_city_meshes.gd

var _failures: int = 0


func _process(_delta: float) -> bool:
	_run()
	return true


func _run() -> void:
	_test_winding_is_normalised()
	_test_triangles_face_where_asked()
	_test_rectangles_get_a_box_and_odd_lots_do_not()
	_test_gables_are_closed()
	_test_barriers_pick_their_material()
	if _failures > 0:
		push_error("city meshes: %d check(s) failed" % _failures)
		quit(1)
		return
	print("city meshes: all checks passed")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("city meshes: %s" % message)


func _square(clockwise: bool) -> Array:
	var points: Array = [[0.0, 0.0], [6.0, 0.0], [6.0, 4.0], [0.0, 4.0]]
	if clockwise:
		points.reverse()
	return points


func _test_winding_is_normalised() -> void:
	for clockwise: bool in [false, true]:
		var polygon: PackedVector2Array = KeyWestCityVisuals.normalized_footprint(_square(clockwise))
		_check(KeyWestCityVisuals.signed_area(polygon) > 0.0, "footprint winding was not normalised")
		## Positive area: the outward side of edge a→b is (dz, -dx), away from the centre.
		var centre := Vector2(3.0, 2.0)
		for i: int in range(polygon.size()):
			var a: Vector2 = polygon[i]
			var b: Vector2 = polygon[(i + 1) % polygon.size()]
			var edge: Vector2 = b - a
			var out := Vector2(edge.y, -edge.x)
			_check(out.dot((a + b) * 0.5 - centre) > 0.0, "a wall would face into its building")


func _test_triangles_face_where_asked() -> void:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var i := PackedInt32Array()
	KeyWestCityVisuals.emit_tri(v, n, c, i, Vector3.ZERO, Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3.UP, Color.WHITE)
	KeyWestCityVisuals.emit_tri(v, n, c, i, Vector3.ZERO, Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3.UP, Color.WHITE)
	for t: int in range(0, i.size(), 3):
		var normal: Vector3 = (v[i[t + 1]] - v[i[t]]).cross(v[i[t + 2]] - v[i[t]])
		## Front faces wind clockwise: (b-a)×(c-a) points away from the viewer above.
		_check(normal.y < 0.0, "a roof triangle faces down")


func _test_rectangles_get_a_box_and_odd_lots_do_not() -> void:
	var box: Dictionary = KeyWestCityVisuals.footprint_box(KeyWestCityVisuals.normalized_footprint(_square(true)))
	_check(not box.is_empty(), "a rectangle got no roof box")
	if not box.is_empty():
		_check(is_equal_approx(float(box["width"]) * float(box["depth"]), 24.0), "roof box does not match the footprint")
		_check((box["center"] as Vector2).is_equal_approx(Vector2(3, 2)), "roof box is off the footprint centre")
	var ell: Array = [[0, 0], [8, 0], [8, 3], [3, 3], [3, 8], [0, 8]]
	_check(KeyWestCityVisuals.footprint_box(KeyWestCityVisuals.normalized_footprint(ell)).is_empty(), "an L-shaped lot got a pitched-roof box")


func _test_gables_are_closed() -> void:
	var building: Dictionary = {
		"osm_id": "test/1", "footprint": _square(false), "height": 4.0,
		"metadata": {"building": "house"}, "proxy": {},
	}
	var enrichment: Dictionary = {"building_attrs": {"test/1": {"roof_shape": "gabled"}}}
	var terrain := IslandTerrain.new()
	var mesh: ArrayMesh = KeyWestCityVisuals.build_roof_mesh([building], [0], terrain, enrichment, null)
	terrain.free()
	_check(mesh != null, "a gabled house got no roof")
	if mesh == null:
		return
	var faces: PackedVector3Array = mesh.get_faces()
	var vertical: int = 0
	for t: int in range(0, faces.size(), 3):
		var normal: Vector3 = (faces[t + 1] - faces[t]).cross(faces[t + 2] - faces[t]).normalized()
		if absf(normal.y) < 0.01:
			vertical += 1
	_check(faces.size() / 3 == 6, "a gable roof should be 4 slopes and 2 ends, got %d triangles" % (faces.size() / 3))
	_check(vertical == 2, "a gable roof is open at its ends")
	var up: int = 0
	for t: int in range(0, faces.size(), 3):
		if (faces[t + 1] - faces[t]).cross(faces[t + 2] - faces[t]).normalized().y < -0.2:
			up += 1
	_check(up == 4, "a gable roof does not cover both sides, %d slope triangles" % up)


func _test_barriers_pick_their_material() -> void:
	_check(KeyWestCityVisuals.barrier_style("barrier:fence", {"material": "wood"}) == "wood", "a wooden fence is not wood")
	_check(KeyWestCityVisuals.barrier_style("barrier:fence", {"fence_type": "metal_bars"}) == "metal", "metal bars are not metal")
	_check(KeyWestCityVisuals.barrier_style("barrier:fence", {}) == "chain_link", "an untagged fence is not chain link")
	_check(KeyWestCityVisuals.barrier_style("barrier:wall", {}) == "wall", "a wall is not masonry")
	_check(KeyWestCityVisuals.barrier_style("barrier:hedge", {}) == "hedge", "a hedge is not a hedge")
