extends SceneTree

## Builds the First Exit greybox from data/world/first_exit_layout.json onto the
## island heightmap, saves it as a scene and writes every resolved footprint.
## Run: godot --headless --script res://tools/world/build_first_exit_blockout.gd

const LAYOUT: String = "res://data/world/first_exit_layout.json"
const OUT_SCENE: String = "res://scenes/world/first_exit/first_exit_blockout.tscn"
const OUT_RESOLVED: String = "res://docs/world/first_exit_resolved.json"
## Slabs and walls reach this far below the lowest ground under them.
const SINK_M: float = 1.0
const SHOULDER_M: float = 1.0
const DITCH_M: float = 1.2
## Length of one road piece; short enough to follow the ground.
const ROAD_STEP_M: float = 3.0
const INTERACTIVE_SCENE: String = "res://scenes/environment/interactive/InteractiveArea.tscn"
const ZONE_SCRIPT: String = "res://scripts/systems/survival/thermal_zone.gd"
const BREACH_SCRIPT: String = "res://scripts/systems/survival/shelter_breach.gd"
const BOARD_SCRIPT: String = "res://scripts/environment/interactive/breach_board_up.gd"
const HEAT_SCRIPT: String = "res://scripts/systems/survival/heat_source.gd"
const FEED_SCRIPT: String = "res://scripts/environment/interactive/heat_source_feed.gd"
const CABINET_SCRIPT: String = "res://scripts/environment/interactive/cabinet.gd"
const PICKUP_SCRIPT: String = "res://scripts/environment/interactive/item_pickup.gd"
## House openings shared by the walls and the breaches: [x, width, is_door].
const WINDOW_GAPS: Array = [[-0.25, 2.0], [0.3, 1.6]]

var _heights: IslandHeightmap
var _root: Node3D
var _roads: Dictionary = {}
## Built anchors by layout id, for pickups placed relative to them.
var _anchors: Dictionary = {}
var _resolved: Array = []
var _rng := RandomNumberGenerator.new()
var _concrete := StandardMaterial3D.new()
var _wood := StandardMaterial3D.new()
var _palm := StandardMaterial3D.new()
var _dark := StandardMaterial3D.new()
var _asphalt := StandardMaterial3D.new()
var _gravel := StandardMaterial3D.new()
var _board := StandardMaterial3D.new()
var _metal := StandardMaterial3D.new()
var _paint := StandardMaterial3D.new()
var _rust := StandardMaterial3D.new()
## Identical pieces share one mesh and one shape, keyed by size and material.
var _meshes: Dictionary = {}
var _shapes: Dictionary = {}


func _initialize() -> void:
	_heights = IslandHeightmap.load_default()
	_setup_materials()
	_rng.seed = 20260924
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	_root = Node3D.new()
	_root.name = "FirstExitBlockout"
	for road: Dictionary in layout.get("roads", []):
		_roads[road["id"]] = road
		_build_road(road)
	for lamps: Dictionary in layout.get("street_lamps", []):
		_build_lamps(lamps)
	for lot: Dictionary in layout.get("lots", []):
		_build_lot(lot)
	for s: Dictionary in layout["structures"]:
		_build_structure(s)
	for c: Dictionary in layout.get("clutter", []):
		_build_structure(c)
	for row: Dictionary in layout["palm_rows"]:
		_build_palm_row(row)
	if layout.has("verge_palms"):
		_build_verge_palms(layout["verge_palms"], layout.get("lots", []))
	for pickup: Dictionary in layout.get("pickups", []):
		_build_pickup(pickup)
	var spawn: Dictionary = layout["spawn"]
	var marker := Marker3D.new()
	marker.name = "SpawnPoint"
	marker.position = _ground(float(spawn["x"]), float(spawn["z"])) + Vector3.UP * 0.2
	marker.rotation.y = deg_to_rad(float(spawn["yaw_deg"]))
	_add(_root, marker)
	_drop_instanced_connections(_root)
	var packed := PackedScene.new()
	packed.pack(_root)
	var err: Error = ResourceSaver.save(packed, OUT_SCENE)
	var file := FileAccess.open(OUT_RESOLVED, FileAccess.WRITE)
	file.store_string(JSON.stringify({"spawn": spawn, "footprints": _resolved}, "\t"))
	file.close()
	print("first exit blockout: %d nodes, %d footprints -> %s (%s)" % [
		_count(_root), _resolved.size(), OUT_SCENE, error_string(err)])
	_root.free()
	quit(0 if err == OK else 1)


func _setup_materials() -> void:
	for pair: Array in [[_concrete, Color(0.62, 0.62, 0.6)], [_wood, Color(0.5, 0.48, 0.45)],
			[_palm, Color(0.36, 0.34, 0.31)], [_dark, Color(0.12, 0.12, 0.13)],
			[_asphalt, Color(0.2, 0.2, 0.21)], [_gravel, Color(0.44, 0.42, 0.39)],
			[_board, Color(0.58, 0.5, 0.4)], [_metal, Color(0.3, 0.32, 0.34)],
			[_paint, Color(0.52, 0.56, 0.6)], [_rust, Color(0.45, 0.33, 0.26)]]:
		var mat: StandardMaterial3D = pair[0]
		mat.albedo_color = pair[1]
		mat.roughness = 1.0


# --- Roads ------------------------------------------------------------------

## Carriageway in short pieces over a gravel bed, shoulders and ditches; some
## asphalt pieces are missing, so the broken surface shows the bed.
func _build_road(road: Dictionary) -> void:
	var node := Node3D.new()
	node.name = "Road_" + String(road["id"]).to_pascal_case()
	_add(_root, node)
	var width: float = float(road["width"])
	var pts: Array = road["points"]
	for i: int in range(pts.size() - 1):
		var a := Vector2(float(pts[i][0]), float(pts[i][1]))
		var b := Vector2(float(pts[i + 1][0]), float(pts[i + 1][1]))
		var n: int = maxi(1, int(ceil(a.distance_to(b) / ROAD_STEP_M)))
		for k: int in range(n):
			var p0: Vector2 = a.lerp(b, float(k) / float(n))
			var p1: Vector2 = a.lerp(b, float(k + 1) / float(n))
			var bed_w: float = width + SHOULDER_M * 2.0
			_road_piece(node, p0, p1, bed_w, 0.0, 0.3, _gravel, false)
			if _rng.randf() > 0.12:
				_road_piece(node, p0, p1, snappedf(width * _rng.randf_range(0.82, 1.0), 0.25), snappedf(_rng.randf_range(-0.3, 0.3), 0.1), 0.36, _asphalt, false)
			for side: float in [-1.0, 1.0]:
				_road_piece(node, p0, p1, DITCH_M, side * (bed_w + DITCH_M) * 0.5, 0.02, _dark, false)


## One flat piece from p0 to p1, pitched to the ground, offset sideways.
func _road_piece(parent: Node3D, p0: Vector2, p1: Vector2, width: float, lateral: float,
		lift: float, mat: Material, collide: bool) -> void:
	var dir: Vector2 = (p1 - p0).normalized()
	var normal := Vector2(-dir.y, dir.x)
	var q0: Vector2 = p0 + normal * lateral
	var q1: Vector2 = p1 + normal * lateral
	var y0: float = _ground(q0.x, q0.y).y
	var y1: float = _ground(q1.x, q1.y).y
	var length: float = q0.distance_to(q1)
	var piece: MeshInstance3D = _box(parent, Vector3((q0.x + q1.x) * 0.5, (y0 + y1) * 0.5 + lift - 0.2, (q0.y + q1.y) * 0.5),
		Vector3(width, 0.4, length + 0.2), mat, collide)
	piece.rotation = Vector3(-atan2(y1 - y0, length), atan2(dir.x, dir.y), 0.0)


## Position and tangent at distance s along a road; s < 0 means the far end.
func _road_frame(road_id: String, s: float) -> Dictionary:
	var pts: Array = _roads[road_id]["points"]
	var total: float = 0.0
	for i: int in range(pts.size() - 1):
		total += Vector2(float(pts[i][0]), float(pts[i][1])).distance_to(Vector2(float(pts[i + 1][0]), float(pts[i + 1][1])))
	var want: float = total if s < 0.0 else clampf(s, 0.0, total)
	var walked: float = 0.0
	for i: int in range(pts.size() - 1):
		var a := Vector2(float(pts[i][0]), float(pts[i][1]))
		var b := Vector2(float(pts[i + 1][0]), float(pts[i + 1][1]))
		var seg: float = a.distance_to(b)
		if walked + seg >= want or i == pts.size() - 2:
			var t: float = clampf((want - walked) / seg, 0.0, 1.0)
			return {"pos": a.lerp(b, t), "dir": (b - a).normalized(), "total": total}
		walked += seg
	return {"pos": Vector2.ZERO, "dir": Vector2.UP, "total": total}


## Unit normal on the named side: north/south by z, east/west by x.
func _side_normal(dir: Vector2, side: String) -> Vector2:
	var n := Vector2(-dir.y, dir.x)
	match side:
		"north":
			return n if n.y < 0.0 else -n
		"south":
			return n if n.y > 0.0 else -n
		"west":
			return n if n.x < 0.0 else -n
		_:
			return n if n.x > 0.0 else -n


func _edge_offset(road_id: String) -> float:
	return float(_roads[road_id]["width"]) * 0.5 + SHOULDER_M + DITCH_M


# --- Lamps ------------------------------------------------------------------

## Poles on the verge; a share lean, some lost their head, one lies in the ditch.
func _build_lamps(spec: Dictionary) -> void:
	var group := Node3D.new()
	group.name = "Lamps_" + String(spec["road"]).to_pascal_case()
	_add(_root, group)
	var s: float = float(spec["from_s"])
	var index: int = 0
	while s <= float(spec["to_s"]):
		var frame: Dictionary = _road_frame(spec["road"], s)
		var n: Vector2 = _side_normal(frame["dir"], spec["side"])
		var p: Vector2 = frame["pos"] + n * (_edge_offset(spec["road"]) - DITCH_M * 0.5)
		var lamp := Node3D.new()
		lamp.name = "Lamp"
		lamp.position = _ground(p.x, p.y)
		lamp.rotation.y = atan2(-n.x, -n.y)
		_add(group, lamp)
		var roll: float = _rng.randf()
		if index == 5:
			lamp.rotation.x = deg_to_rad(84.0)
		elif roll < 0.25:
			lamp.rotation.x = deg_to_rad(_rng.randf_range(12.0, 30.0)) * (1.0 if _rng.randf() < 0.5 else -1.0)
		_box(lamp, Vector3(0, 3.5 - SINK_M * 0.5, 0), Vector3(0.18, 7.0 + SINK_M, 0.18), _metal)
		if roll > 0.15 or index == 5:
			_box(lamp, Vector3(0, 6.9, 0.8), Vector3(0.1, 0.1, 1.6), _metal, false)
			_box(lamp, Vector3(0, 6.75, 1.55), Vector3(0.35, 0.18, 0.6), _metal, false)
		_resolved.append({"id": "lamp_%s_%d" % [spec["road"], index], "kind": "street_lamp",
			"x": snappedf(p.x, 0.1), "z": snappedf(p.y, 0.1)})
		s += float(spec["spacing"])
		index += 1


# --- Lots -------------------------------------------------------------------

## A house plot on the road: fence with a gate, driveway, house facing the road,
## optional shed and water tank, and the winter retrofits listed for it.
func _build_lot(lot: Dictionary) -> void:
	var frame: Dictionary = _road_frame(lot["road"], float(lot["s"]))
	var n: Vector2 = _side_normal(frame["dir"], lot["side"])
	var along: Vector2 = frame["dir"]
	var depth: float = float(lot["depth"])
	var width: float = float(lot["width"])
	var near: float = _edge_offset(lot["road"]) + 0.5
	var centre: Vector2 = frame["pos"] + n * (near + depth * 0.5)
	var yaw: float = atan2(-n.x, -n.y)
	var node := Node3D.new()
	node.name = String(lot["id"]).to_pascal_case()
	node.position = Vector3(centre.x, _footprint_min(centre.x, centre.y, width, depth, rad_to_deg(yaw)), centre.y)
	node.rotation.y = yaw
	node.set_meta(&"note", lot.get("note", ""))
	node.set_meta(&"depth", depth)
	_add(_root, node)
	_anchors[lot["id"]] = node
	## Local frame: +Z faces the road, the lot spans x ±width/2, z ±depth/2.
	var house: Array = lot["house"]
	var hw: float = float(house[0])
	var hd: float = float(house[1])
	var hh: float = float(house[2])
	var house_z: float = depth * 0.5 - float(lot["setback"]) - hd * 0.5 - 3.0
	var drive_x: float = width * 0.5 - 2.5
	_fence(node, width, depth, drive_x)
	_box(node, Vector3(drive_x, -0.15, (depth * 0.5 + house_z + hd * 0.5) * 0.5 + 1.0),
		Vector3(3.0, 0.4, depth * 0.5 - house_z - hd * 0.5 + 2.0 + near * 0.0), _gravel, false)
	_box(node, Vector3(drive_x, -0.15, depth * 0.5 + near * 0.5), Vector3(3.0, 0.4, near + 0.5), _gravel, false)
	var house_node := Node3D.new()
	house_node.name = "House"
	house_node.position = Vector3(-1.0, 0.0, house_z)
	_add(node, house_node)
	var state: String = lot.get("state", "kept")
	_bungalow(house_node, hw, hd, hh, state)
	for retrofit: String in lot.get("retrofits", []):
		_retrofit(house_node, retrofit, hw, hd, hh, node)
	if bool(lot.get("is_shelter", false)):
		_shelter_gameplay(house_node, hw, hd, hh)
	if bool(lot.get("outbuilding", false)):
		var shed := Node3D.new()
		shed.name = "Outbuilding"
		shed.position = Vector3(-width * 0.5 + 2.5, 0.0, -depth * 0.5 + 2.5)
		_add(node, shed)
		_room(shed, 3.0, 3.0, 2.4, 0.15, 0.9, [], _wood)
	if bool(lot.get("tank", true)):
		var tank := Node3D.new()
		tank.name = "WaterTank"
		tank.position = Vector3(hw * 0.5 + 1.2, 0.0, house_z - hd * 0.25)
		_add(node, tank)
		for leg: Vector2 in [Vector2(-0.6, -0.6), Vector2(0.6, -0.6), Vector2(-0.6, 0.6), Vector2(0.6, 0.6)]:
			_box(tank, Vector3(leg.x, 0.3, leg.y), Vector3(0.12, 1.6, 0.12), _wood, false)
		_cylinder(tank, Vector3(0, 2.1, 0), 0.9, 2.0, _metal)
	var door: Vector3 = node.transform * (house_node.position + Vector3(0, 0, hd * 0.5 + 3.0))
	_resolved.append({"id": lot["id"], "kind": "lot", "is_shelter": bool(lot.get("is_shelter", false)),
		"x": snappedf(centre.x, 0.1), "z": snappedf(centre.y, 0.1), "yaw_deg": snappedf(rad_to_deg(yaw), 0.1),
		"size": [width, depth], "house_front": [snappedf(door.x, 0.1), snappedf(door.z, 0.1)],
		"state": state, "retrofits": lot.get("retrofits", [])})


## Low picket fence around the plot with a gap for the driveway gate.
func _fence(node: Node3D, width: float, depth: float, gate_x: float) -> void:
	var fence := Node3D.new()
	fence.name = "Fence"
	_add(node, fence)
	var h: float = 1.0
	for side: float in [-1.0, 1.0]:
		_box(fence, Vector3(side * width * 0.5, h * 0.5 - 0.2, 0), Vector3(0.08, h + 0.4, depth), _wood)
	_box(fence, Vector3(0, h * 0.5 - 0.2, -depth * 0.5), Vector3(width, h + 0.4, 0.08), _wood)
	var left: float = gate_x - 1.8
	var right: float = gate_x + 1.8
	_box(fence, Vector3((-width * 0.5 + left) * 0.5, h * 0.5 - 0.2, depth * 0.5), Vector3(left + width * 0.5, h + 0.4, 0.08), _wood)
	if right < width * 0.5:
		_box(fence, Vector3((right + width * 0.5) * 0.5, h * 0.5 - 0.2, depth * 0.5), Vector3(width * 0.5 - right, h + 0.4, 0.08), _wood)
	for x: float in [left, right]:
		_box(fence, Vector3(x, 0.6, depth * 0.5), Vector3(0.2, 1.6, 0.2), _concrete)


func _retrofit(house: Node3D, kind: String, w: float, d: float, h: float, lot: Node3D) -> void:
	var floor_y: float = 0.8
	match kind:
		"boarded":
			for x: float in [-w * 0.25, w * 0.3]:
				for k: int in range(3):
					var plank: MeshInstance3D = _box(house, Vector3(x, floor_y + 1.1 + float(k) * 0.35, d * 0.5 + 0.14),
						Vector3(1.9, 0.18, 0.06), _board, false)
					plank.rotation.z = deg_to_rad(_rng.randf_range(-8.0, 8.0))
		"vestibule":
			_box(house, Vector3(-w * 0.5 + 0.05, floor_y + 1.2, d * 0.5 + 1.5), Vector3(0.12, 2.4, 3.0), _board)
			_box(house, Vector3(w * 0.5 - 0.05, floor_y + 1.2, d * 0.5 + 1.5), Vector3(0.12, 2.4, 3.0), _board)
			_box(house, Vector3(-w * 0.3, floor_y + 1.2, d * 0.5 + 3.0), Vector3(w * 0.4, 2.4, 0.12), _board)
			_box(house, Vector3(w * 0.3, floor_y + 1.2, d * 0.5 + 3.0), Vector3(w * 0.4, 2.4, 0.12), _board)
		"stovepipe":
			var pipe: MeshInstance3D = _cylinder(house, Vector3(-w * 0.5 - 0.35, floor_y + h * 0.5 + 0.8, -d * 0.2), 0.12, h + 1.6, _metal, false)
			_box(house, Vector3(-w * 0.5 - 0.2, floor_y + 1.0, -d * 0.2), Vector3(0.5, 0.12, 0.12), _metal, false)
			pipe.name = "StovePipe"
		"insulation":
			_box(house, Vector3(0, floor_y + h * 0.45, -d * 0.5 - 0.15), Vector3(w + 0.2, h * 0.9, 0.25), _board)
		"snow_fence":
			var fence := Node3D.new()
			fence.name = "SnowFence"
			fence.position = Vector3(0, 0, -float(lot.get_meta(&"depth", 24.0)) * 0.5 - 3.0)
			_add(lot, fence)
			for k: int in range(10):
				_box(fence, Vector3(-9.0 + float(k) * 2.0, 0.6, 0), Vector3(1.6, 1.4, 0.05), _board)


## Tropical house on piers: floor, veranda, walls with big openings, roof.
## "roofless" drops the roof, "collapsed" leaves only a corner of walls.
func _bungalow(node: Node3D, w: float, d: float, h: float, state: String = "kept") -> void:
	var floor_y: float = 0.8
	for px: float in [-w * 0.5 + 0.3, 0.0, w * 0.5 - 0.3]:
		for pz: float in [-d * 0.5 + 0.3, d * 0.5 - 0.3, d * 0.5 + 2.7]:
			_box(node, Vector3(px, (floor_y - SINK_M) * 0.5, pz), Vector3(0.3, floor_y + SINK_M, 0.3), _wood)
	_box(node, Vector3(0, floor_y, 0), Vector3(w, 0.2, d), _wood)
	_box(node, Vector3(0, floor_y, d * 0.5 + 1.5), Vector3(w, 0.15, 3.0), _wood)
	_box(node, Vector3(0, floor_y * 0.5, d * 0.5 + 3.4), Vector3(1.4, 0.25, 0.8), _wood)
	if state == "collapsed":
		_box(node, Vector3(-w * 0.5, floor_y + h * 0.3, -d * 0.25), Vector3(0.2, h * 0.6, d * 0.5), _wood)
		_box(node, Vector3(-w * 0.25, floor_y + h * 0.4, -d * 0.5), Vector3(w * 0.5, h * 0.8, 0.2), _wood)
		var slab: MeshInstance3D = _box(node, Vector3(w * 0.1, floor_y + 0.9, 0), Vector3(w * 0.8, 0.15, d * 0.7), _wood)
		slab.rotation.z = deg_to_rad(18.0)
		return
	var walls := Node3D.new()
	walls.name = "Walls"
	walls.position.y = floor_y
	_add(node, walls)
	var gaps: Array = []
	for gap: Array in WINDOW_GAPS:
		gaps.append([w * float(gap[0]), gap[1]])
	_room(walls, w, d, h - floor_y, 0.2, 1.1, gaps, _wood, false)
	if state == "roofless":
		_box(node, Vector3(w * 0.25, h + 0.3, -d * 0.3), Vector3(w * 0.5, 0.15, d * 0.4), _wood)
		return
	## Gable over the house, ridge along Z; the veranda gets its own low lean-to.
	var pitch: float = deg_to_rad(24.0)
	var half_span: float = (w * 0.5 + 0.5) / cos(pitch)
	for side: float in [-1.0, 1.0]:
		var slope: MeshInstance3D = _box(node, Vector3(side * (w * 0.25 + 0.25), h + 0.1 + tan(pitch) * (w * 0.25 + 0.25), 0),
			Vector3(half_span, 0.15, d + 0.8), _wood)
		slope.rotation.z = -side * pitch
	var lean: MeshInstance3D = _box(node, Vector3(0, h - 0.2, d * 0.5 + 1.6), Vector3(w + 0.6, 0.12, 3.4), _wood)
	lean.rotation.x = deg_to_rad(8.0)


# --- Shelter gameplay -------------------------------------------------------

## The working shelter from TestScene, fitted to the bungalow: an interior
## ThermalZone, one ShelterBreach per opening with a board-up prompt, and a
## stove that heats the zone. Sleep and save need nothing more.
func _shelter_gameplay(house: Node3D, w: float, d: float, h: float) -> void:
	var floor_y: float = 0.8
	var inner_h: float = h - floor_y
	var zone := Area3D.new()
	zone.name = "ShelterZone"
	zone.set_script(load(ZONE_SCRIPT))
	zone.set(&"temperature_offset_c", 8.0)
	zone.set(&"wind_exposure", 0.05)
	zone.set(&"is_interior", true)
	zone.set(&"max_heated_offset_c", 18.0)
	zone.position = Vector3(0.0, floor_y + inner_h * 0.5, 0.0)
	_add(house, zone)
	var zone_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(w - 0.4, inner_h, d - 0.4)
	zone_shape.shape = box
	_add(zone, zone_shape)
	## Openings: front door, then windows front and back. Severity by size.
	var openings: Array = [["Door", 0.0, 1.1, 1.0, 0.3, 1.0]]
	for i: int in range(WINDOW_GAPS.size()):
		var gap: Array = WINDOW_GAPS[i]
		var severity: float = 0.25 if float(gap[1]) >= 2.0 else 0.2
		openings.append(["FrontWindow%d" % (i + 1), w * float(gap[0]), float(gap[1]), 1.45, severity, 1.0])
		openings.append(["BackWindow%d" % (i + 1), w * float(gap[0]), float(gap[1]), 1.45, severity, -1.0])
	for opening: Array in openings:
		var side: float = opening[5]
		var breach := Node3D.new()
		breach.name = opening[0]
		breach.set_script(load(BREACH_SCRIPT))
		breach.set(&"severity", opening[4])
		breach.set(&"name_key", "BREACH_DOOR" if opening[0] == "Door" else "BREACH_WINDOW")
		## -Z of the breach points out of the house.
		breach.position = Vector3(float(opening[1]), float(opening[3]) + floor_y - zone.position.y, side * d * 0.5)
		breach.rotation.y = PI if side > 0.0 else 0.0
		_add(zone, breach)
		var boards := Node3D.new()
		boards.name = "Boards"
		boards.visible = false
		_add(breach, boards)
		var tall: float = 2.0 if opening[0] == "Door" else 1.1
		for k: int in range(3):
			var plank: MeshInstance3D = _box(boards, Vector3(0, -tall * 0.35 + float(k) * tall * 0.35, 0.12),
				Vector3(float(opening[2]) + 0.3, 0.2, 0.05), _board, false)
			plank.rotation.z = deg_to_rad(float(k - 1) * 6.0)
		breach.set(&"boarded_visual", boards)
		var prompt: Node3D = (load(INTERACTIVE_SCENE) as PackedScene).instantiate()
		prompt.name = "BoardUp"
		prompt.set_script(load(BOARD_SCRIPT))
		prompt.set(&"interactable_scene", null)
		prompt.position = Vector3(0.0, -0.4, 0.9)
		_add(breach, prompt)
		_prompt_shape(prompt, Vector3(float(opening[2]), 1.6, 1.2))
	var stove := Node3D.new()
	stove.name = "Stove"
	stove.set_script(load(HEAT_SCRIPT))
	stove.set(&"starts_burning", false)
	stove.position = Vector3(-w * 0.5 + 0.9, floor_y + 0.1 - zone.position.y, -d * 0.2)
	_add(zone, stove)
	stove.set(&"heats_zone", zone)
	_box(stove, Vector3(0, 0.45, 0), Vector3(0.8, 0.9, 0.8), _metal)
	var flame := OmniLight3D.new()
	flame.name = "Flame"
	flame.visible = false
	flame.light_color = Color(1.0, 0.55, 0.2)
	flame.light_energy = 2.5
	flame.omni_range = 6.0
	flame.position = Vector3(0, 1.1, 0)
	_add(stove, flame)
	stove.set(&"flame_light", flame)
	var feed: Node3D = (load(INTERACTIVE_SCENE) as PackedScene).instantiate()
	feed.name = "Feed"
	feed.set_script(load(FEED_SCRIPT))
	feed.set(&"interactable_scene", null)
	feed.position = Vector3(0.9, 0.0, 0.0)
	_add(stove, feed)
	_prompt_shape(feed, Vector3(1.2, 1.4, 1.4))
	_cabinet(zone, Vector3(w * 0.5 - 0.5, floor_y - zone.position.y, -d * 0.2))


## A low kitchen cabinet against the east wall, facing into the room, with a
## door on a real hinge on its left edge.
func _cabinet(parent: Node3D, pos: Vector3) -> void:
	var cab := Node3D.new()
	cab.name = "Cabinet"
	cab.position = pos
	cab.rotation.y = -PI * 0.5  # local +Z, the front, faces west into the room
	_add(parent, cab)
	var body: MeshInstance3D = _box(cab, Vector3(0.0, 0.45, -0.21), Vector3(0.8, 0.9, 0.03), _wood)
	_box(cab, Vector3(-0.385, 0.45, 0.0), Vector3(0.03, 0.9, 0.45), _wood)
	_box(cab, Vector3(0.385, 0.45, 0.0), Vector3(0.03, 0.9, 0.45), _wood)
	_box(cab, Vector3(0.0, 0.885, 0.0), Vector3(0.8, 0.03, 0.45), _wood)
	_box(cab, Vector3(0.0, 0.03, 0.0), Vector3(0.8, 0.06, 0.45), _wood)
	_box(cab, Vector3(0.0, 0.45, 0.0), Vector3(0.74, 0.02, 0.4), _wood, false)
	var hinge := Node3D.new()
	hinge.name = "DoorHinge"
	hinge.position = Vector3(-0.39, 0.45, 0.225)
	_add(cab, hinge)
	_box(hinge, Vector3(0.39, 0.0, 0.012), Vector3(0.78, 0.84, 0.025), _board, false)
	_box(hinge, Vector3(0.7, 0.05, 0.035), Vector3(0.03, 0.12, 0.03), _metal, false)
	var prompt: Node3D = (load(INTERACTIVE_SCENE) as PackedScene).instantiate()
	prompt.name = "Open"
	prompt.set_script(load(CABINET_SCRIPT))
	prompt.set(&"interactable_scene", null)
	prompt.set(&"door_hinge", hinge)
	prompt.set(&"interactive_mesh", body)
	prompt.position = Vector3(0.0, 0.0, 0.7)
	_add(cab, prompt)
	_prompt_shape(prompt, Vector3(1.0, 1.4, 1.0))


## Gives an instanced InteractiveArea its own box trigger.
func _prompt_shape(prompt: Node3D, size: Vector3) -> void:
	var box := BoxShape3D.new()
	box.size = size
	var col := prompt.get_node_or_null(^"CollisionShape3D") as CollisionShape3D
	if col != null:
		col.shape = box


## An item on the ground, relative to a built anchor or at world x, z.
func _build_pickup(spec: Dictionary) -> void:
	var world := Vector3.ZERO
	if spec.has("anchor"):
		var parts: PackedStringArray = String(spec["anchor"]).split("/", true, 1)
		var anchor: Node3D = _anchors.get(parts[0])
		if anchor == null:
			push_warning("pickup %s: no anchor %s" % [spec["id"], spec["anchor"]])
			return
		var local := Vector3(float(spec["local"][0]), float(spec["local"][1]), float(spec["local"][2]))
		var target: Node3D = anchor.get_node(parts[1]) as Node3D if parts.size() > 1 else anchor
		world = anchor.transform * (target.transform * local if target != anchor else local)
	else:
		world = _ground(float(spec["x"]), float(spec["z"]))
	if not bool(spec.get("keep_height", false)):
		world.y = _ground(world.x, world.z).y + 0.15
	var pickup: Node3D = (load(INTERACTIVE_SCENE) as PackedScene).instantiate()
	pickup.name = String(spec["id"]).to_pascal_case()
	pickup.set_script(load(PICKUP_SCRIPT))
	pickup.set(&"interactable_scene", null)
	pickup.set(&"item_id", StringName(spec["item_id"]))
	pickup.set(&"count", int(spec.get("count", 1)))
	pickup.position = world
	_add(_root, pickup)
	var sphere := SphereShape3D.new()
	sphere.radius = 0.6
	var col := pickup.get_node_or_null(^"CollisionShape3D") as CollisionShape3D
	if col != null:
		col.shape = sphere
	_resolved.append({"id": spec["id"], "kind": "pickup", "item_id": spec["item_id"], "count": int(spec.get("count", 1)),
		"x": snappedf(world.x, 0.1), "z": snappedf(world.z, 0.1)})


# --- Structures -------------------------------------------------------------

func _build_structure(s: Dictionary) -> void:
	var node := Node3D.new()
	node.name = String(s["id"]).to_pascal_case()
	var size: Array = s["size"]
	var w: float = float(size[0])
	var d: float = float(size[1])
	var h: float = float(size[2])
	var x: float
	var z: float
	var yaw_deg: float
	if s.has("road"):
		var frame: Dictionary = _road_frame(s["road"], float(s["s"]))
		if s["side"] == "end":
			x = frame["pos"].x
			z = frame["pos"].y
			yaw_deg = rad_to_deg(atan2(frame["dir"].x, frame["dir"].y))
		else:
			var n: Vector2 = _side_normal(frame["dir"], s["side"])
			var reach: float = float(s["lateral"]) if s.has("lateral") else _edge_offset(s["road"]) + float(s["offset"])
			var p: Vector2 = frame["pos"] + n * reach
			x = p.x
			z = p.y
			yaw_deg = rad_to_deg(atan2(-n.x, -n.y))
		yaw_deg += float(s.get("yaw_add", 0.0))
	else:
		x = float(s["x"])
		z = float(s["z"])
		yaw_deg = float(s["yaw_deg"])
	node.position = Vector3(x, _footprint_min(x, z, w, d, yaw_deg), z)
	node.rotation.y = deg_to_rad(yaw_deg)
	node.set_meta(&"note", s.get("note", ""))
	_add(_root, node)
	_anchors[s["id"]] = node
	_resolved.append({"id": s["id"], "kind": s["kind"], "x": snappedf(x, 0.1), "z": snappedf(z, 0.1),
		"yaw_deg": snappedf(yaw_deg, 0.1), "size": size})
	match String(s["kind"]):
		"bunker_portal":
			_bunker(node, w, d, h)
		"vent_stack":
			_cylinder(node, Vector3(0, h * 0.5, 0), w * 0.5, h + SINK_M, _concrete)
		"fort_ring":
			_ring(node, w * 0.5, h, 1.2, 14, 2, _concrete)
		"battery":
			_ring(node, w * 0.5, h, 1.4, 9, 0, _concrete, PI)
			_box(node, Vector3(0, -SINK_M * 0.5, 0), Vector3(w, SINK_M + 0.2, d), _concrete)
		"shed":
			_room(node, w, d, h, 0.25, 1.2, [], _wood)
		"water_tower":
			_water_tower(node, w, h)
		"chapel":
			_room(node, w, d, h, 0.5, 2.0, [], _concrete)
			_box(node, Vector3(0, h + 2.5, d * 0.5 - 1.0), Vector3(w * 0.5, 5.0, 1.2), _concrete)
		"bus_shelter":
			_box(node, Vector3(0, h * 0.5, -d * 0.5), Vector3(w, h, 0.15), _concrete)
			_box(node, Vector3(-w * 0.5, h * 0.5, 0), Vector3(0.15, h, d), _concrete)
			_box(node, Vector3(w * 0.5, h * 0.5, 0), Vector3(0.15, h, d), _concrete)
			_box(node, Vector3(0, h, 0), Vector3(w + 0.4, 0.15, d + 0.6), _concrete)
			_box(node, Vector3(w * 0.5 + 1.0, 1.4, d * 0.5), Vector3(0.1, 2.8, 0.1), _metal)
			_box(node, Vector3(w * 0.5 + 1.0, 2.7, d * 0.5), Vector3(0.6, 0.6, 0.05), _metal, false)
		"pier":
			_pier(node, w, d, h)
		"car", "pickup", "van", "bus":
			_vehicle(node, String(s["kind"]), s)
		"bin":
			_cylinder(node, Vector3(0, 0.45, 0), 0.35, 1.0, _metal)
		"dumpster":
			_box(node, Vector3(0, 0.55, 0), Vector3(w, 1.3, d), _rust)
			var lid: MeshInstance3D = _box(node, Vector3(0, 1.3, -d * 0.3), Vector3(w, 0.06, d * 0.6), _rust, false)
			lid.rotation.x = deg_to_rad(-35.0)
		_:
			_box(node, Vector3(0, h * 0.5, 0), Vector3(w, h, d), _concrete)


## A vehicle along local Z, front at +Z. "roll": "side" or "roof" overturns it,
## "sink" buries it in drift, "door_open" swings the driver's door.
func _vehicle(node: Node3D, kind: String, s: Dictionary) -> void:
	var body := Node3D.new()
	body.name = "Body"
	_add(node, body)
	var w: float = 1.8
	var h: float = 1.5
	var wheel_z: float = 1.4
	var mat: Material = _paint
	match kind:
		"car":
			_box(body, Vector3(0, 0.6, 0), Vector3(1.8, 0.7, 4.3), _paint)
			_box(body, Vector3(0, 1.25, -0.2), Vector3(1.6, 0.6, 2.2), _paint)
			_box(body, Vector3(0, 1.25, -0.2), Vector3(1.62, 0.35, 2.0), _dark, false)
		"pickup":
			mat = _rust
			w = 1.9
			h = 1.9
			wheel_z = 1.8
			_box(body, Vector3(0, 0.65, 0), Vector3(1.9, 0.8, 5.3), _rust)
			_box(body, Vector3(0, 1.45, 1.1), Vector3(1.8, 0.8, 1.8), _rust)
			_box(body, Vector3(0, 1.5, 1.1), Vector3(1.82, 0.4, 1.6), _dark, false)
			for side: float in [-1.0, 1.0]:
				_box(body, Vector3(side * 0.9, 1.3, -1.3), Vector3(0.08, 0.5, 2.6), _rust)
		"van":
			w = 2.0
			h = 2.2
			wheel_z = 1.7
			_box(body, Vector3(0, 1.2, 0), Vector3(2.0, 1.9, 5.0), _paint)
			_box(body, Vector3(0, 1.6, 2.2), Vector3(2.02, 0.6, 0.7), _dark, false)
		"bus":
			w = 2.5
			h = 3.1
			wheel_z = 3.6
			_box(body, Vector3(0, 1.7, 0), Vector3(2.5, 2.8, 11.0), _paint)
			_box(body, Vector3(0, 2.3, 0), Vector3(2.52, 0.9, 9.6), _dark, false)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var wheel: MeshInstance3D = _cylinder(body, Vector3(sx * (w * 0.5 - 0.05), 0.35, sz * wheel_z), 0.35, 0.28, _dark, false)
			wheel.rotation.z = PI * 0.5
	if bool(s.get("door_open", false)):
		var door: MeshInstance3D = _box(body, Vector3(w * 0.5 + 0.45, 0.9, 0.4), Vector3(0.08, 0.9, 1.1), mat)
		door.rotation.y = deg_to_rad(-55.0)
	match String(s.get("roll", "")):
		"side":
			body.rotation.z = PI * 0.5
			body.position = Vector3(h * 0.5, w * 0.5 - 0.3, 0)
		"roof":
			body.rotation.z = PI
			body.position.y = h
	body.position.y -= float(s.get("sink", 0.0))


## Blast door in a concrete face, set into an earth berm behind it.
func _bunker(node: Node3D, w: float, d: float, h: float) -> void:
	_box(node, Vector3(0, h * 0.5 - SINK_M * 0.5, 0), Vector3(w, h + SINK_M, d), _concrete)
	_box(node, Vector3(0, 1.3, d * 0.5 + 0.05), Vector3(2.6, 2.6, 0.2), _dark)
	_box(node, Vector3(-2.2, 1.6, d * 0.5 + 1.0), Vector3(0.6, 3.2, 2.0), _concrete)
	_box(node, Vector3(2.2, 1.6, d * 0.5 + 1.0), Vector3(0.6, 3.2, 2.0), _concrete)
	var berm: MeshInstance3D = _box(node, Vector3(0, h * 0.35, -d * 0.5 - 3.0), Vector3(w + 6.0, h, 8.0), _palm)
	berm.rotation.x = deg_to_rad(-18.0)


## Four walls with a door gap on +Z and optional window gaps [offset, width] on +Z/-Z.
func _room(node: Node3D, w: float, d: float, h: float, t: float, door_w: float,
		windows: Array, mat: Material, with_roof: bool = true) -> void:
	var base: float = 0.0 if node.name == "Walls" else -SINK_M
	var wall_h: float = h - base
	var cy: float = base + wall_h * 0.5
	_box(node, Vector3(-w * 0.5, cy, 0), Vector3(t, wall_h, d), mat)
	_box(node, Vector3(w * 0.5, cy, 0), Vector3(t, wall_h, d), mat)
	_wall_with_gaps(node, -d * 0.5, w, t, base, h, windows, mat)
	var front: Array = [[0.0, door_w, true]]
	for win: Array in windows:
		front.append([win[0], win[1], false])
	_wall_with_gaps(node, d * 0.5, w, t, base, h, front, mat)
	if with_roof:
		_box(node, Vector3(0, h, 0), Vector3(w + 0.4, 0.2, d + 0.4), mat)


## A wall along X at depth z, broken by gaps [centre, width, is_door].
func _wall_with_gaps(node: Node3D, z: float, w: float, t: float, base: float, h: float,
		gaps: Array, mat: Material) -> void:
	var cuts: Array = []
	for g: Array in gaps:
		cuts.append([float(g[0]) - float(g[1]) * 0.5, float(g[0]) + float(g[1]) * 0.5, g.size() > 2 and bool(g[2])])
	cuts.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var cursor: float = -w * 0.5
	for cut: Array in cuts:
		if cut[0] > cursor:
			_box(node, Vector3((cursor + cut[0]) * 0.5, (base + h) * 0.5, z), Vector3(cut[0] - cursor, h - base, t), mat)
		var sill: float = 0.0 if cut[2] else 0.9
		var head: float = 2.1 if cut[2] else 2.0
		if sill > base:
			_box(node, Vector3((cut[0] + cut[1]) * 0.5, (base + sill) * 0.5, z), Vector3(cut[1] - cut[0], sill - base, t), mat)
		if head < h:
			_box(node, Vector3((cut[0] + cut[1]) * 0.5, (head + h) * 0.5, z), Vector3(cut[1] - cut[0], h - head, t), mat)
		cursor = cut[1]
	if cursor < w * 0.5:
		_box(node, Vector3((cursor + w * 0.5) * 0.5, (base + h) * 0.5, z), Vector3(w * 0.5 - cursor, h - base, t), mat)


func _ring(node: Node3D, radius: float, h: float, t: float, segments: int, gaps: int,
		mat: Material, arc: float = TAU) -> void:
	var seg_len: float = arc * radius / float(segments) * 1.02
	for i: int in range(segments):
		if i < gaps:
			continue
		var a: float = -arc * 0.5 + arc * (float(i) + 0.5) / float(segments)
		var wall: MeshInstance3D = _box(node, Vector3(sin(a) * radius, (h - SINK_M) * 0.5, cos(a) * radius),
			Vector3(seg_len, h + SINK_M, t), mat)
		wall.rotation.y = a


func _water_tower(node: Node3D, w: float, h: float) -> void:
	var leg: float = w * 0.4
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_box(node, Vector3(sx * leg, (h - 4.0 - SINK_M) * 0.5, sz * leg), Vector3(0.35, h - 4.0 + SINK_M, 0.35), _concrete)
	_cylinder(node, Vector3(0, h - 2.0, 0), w * 0.55, 4.0, _concrete)
	_cylinder(node, Vector3(0, h + 0.3, 0), w * 0.3, 0.6, _concrete)


## Deck from the shore out over the sea on piles; +Z runs seaward.
func _pier(node: Node3D, w: float, d: float, h: float) -> void:
	_box(node, Vector3(0, h, d * 0.5), Vector3(w, 0.2, d), _wood)
	var n: int = int(d / 4.0)
	for i: int in range(n + 1):
		for sx: float in [-w * 0.5 + 0.2, w * 0.5 - 0.2]:
			_box(node, Vector3(sx, (h - 3.0) * 0.5, float(i) * 4.0), Vector3(0.3, h + 3.0, 0.3), _wood)


# --- Palms ------------------------------------------------------------------

func _build_palm_row(row: Dictionary) -> void:
	var a := Vector2(float(row["from"][0]), float(row["from"][1]))
	var b := Vector2(float(row["to"][0]), float(row["to"][1]))
	var n: int = maxi(1, int(a.distance_to(b) / float(row["spacing"])))
	var group := Node3D.new()
	group.name = "Palms_" + String(row["id"]).to_pascal_case()
	_add(_root, group)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(row["id"])
	for i: int in range(n + 1):
		var p: Vector2 = a.lerp(b, float(i) / float(n))
		p += Vector2(rng.randf_range(-3.0, 3.0), rng.randf_range(-3.0, 3.0))
		var lean: float = deg_to_rad(float(row["lean_to_deg"]) + rng.randf_range(-25.0, 25.0))
		_palm_tree(group, _ground(p.x, p.y), lean, snappedf(rng.randf_range(7.0, 11.0), 1.0), rng)


## Street palms on the verge between lots: the planted avenue of the old town.
func _build_verge_palms(spec: Dictionary, lots: Array) -> void:
	var group := Node3D.new()
	group.name = "Palms_Verge"
	_add(_root, group)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for lot: Dictionary in lots:
		if String(lot["road"]) != String(spec["road"]):
			continue
		var s: float = float(lot["s"]) + float(lot["width"]) * 0.5
		if s < float(spec["from_s"]) or s > float(spec["to_s"]) or rng.randf() < 0.3:
			continue
		var frame: Dictionary = _road_frame(spec["road"], s)
		var n: Vector2 = _side_normal(frame["dir"], lot["side"])
		var p: Vector2 = frame["pos"] + n * (_edge_offset(spec["road"]) + 0.4)
		_palm_tree(group, _ground(p.x, p.y), atan2(n.x, n.y) + rng.randf_range(-0.6, 0.6),
			snappedf(rng.randf_range(8.0, 11.0), 1.0), rng)


## Dead palm: a leaning, curving trunk of four segments and a drooped crown.
func _palm_tree(parent: Node3D, base: Vector3, lean_yaw: float, height: float, rng: RandomNumberGenerator) -> void:
	var tree := Node3D.new()
	tree.name = "Palm"
	tree.position = base
	tree.rotation.y = lean_yaw
	_add(parent, tree)
	var seg: float = height / 4.0
	var top := Vector3(0, -0.5, 0)
	var tilt: float = 0.0
	for i: int in range(4):
		tilt += deg_to_rad(rng.randf_range(3.0, 7.0))
		var dir := Vector3(0, cos(tilt), -sin(tilt))
		var mid: Vector3 = top + dir * seg * 0.5
		var trunk: MeshInstance3D = _cylinder(tree, mid, 0.22 - 0.03 * float(i), seg + 0.1, _palm, i == 0)
		trunk.rotation.x = -tilt
		top += dir * seg
	for k: int in range(6):
		var frond := Node3D.new()
		frond.position = top
		frond.rotation = Vector3(deg_to_rad(rng.randf_range(35.0, 70.0)), TAU * float(k) / 6.0, 0.0)
		_add(tree, frond)
		var leaf: MeshInstance3D = _box(frond, Vector3(0, 0, 1.4), Vector3(0.35, 0.04, 2.8), _palm, false)
		leaf.rotation.x = deg_to_rad(20.0)


# --- Primitives -------------------------------------------------------------

func _box(parent: Node3D, pos: Vector3, size: Vector3, mat: Material, collide: bool = true) -> MeshInstance3D:
	var key: String = "box%s%d" % [size.snappedf(0.01), mat.get_instance_id()]
	if not _meshes.has(key):
		var mesh := BoxMesh.new()
		mesh.size = size
		mesh.material = mat
		_meshes[key] = mesh
		var shape := BoxShape3D.new()
		shape.size = size
		_shapes[key] = shape
	var inst := MeshInstance3D.new()
	inst.mesh = _meshes[key]
	inst.position = pos
	_add(parent, inst)
	if collide:
		_add_body(inst, _shapes[key])
	return inst


func _cylinder(parent: Node3D, pos: Vector3, radius: float, height: float, mat: Material,
		collide: bool = true) -> MeshInstance3D:
	var key: String = "cyl%.2f_%.2f_%d" % [radius, height, mat.get_instance_id()]
	if not _meshes.has(key):
		var mesh := CylinderMesh.new()
		mesh.top_radius = radius
		mesh.bottom_radius = radius
		mesh.height = height
		mesh.radial_segments = 10
		mesh.material = mat
		_meshes[key] = mesh
		var shape := CylinderShape3D.new()
		shape.radius = radius
		shape.height = height
		_shapes[key] = shape
	var inst := MeshInstance3D.new()
	inst.mesh = _meshes[key]
	inst.position = pos
	_add(parent, inst)
	if collide:
		_add_body(inst, _shapes[key])
	return inst


func _add_body(inst: MeshInstance3D, shape: Shape3D) -> void:
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	col.shape = shape
	_add(inst, body)
	_add(body, col)


func _add(parent: Node, child: Node) -> void:
	parent.add_child(child, true)
	child.owner = _root


func _ground(x: float, z: float) -> Vector3:
	return Vector3(x, _heights.get_height(x, z), z)


## Lowest ground under a rotated footprint, so nothing floats.
func _footprint_min(x: float, z: float, w: float, d: float, yaw_deg: float) -> float:
	var yaw: float = deg_to_rad(yaw_deg)
	var lowest: float = INF
	for sx: float in [-0.5, 0.0, 0.5]:
		for sz: float in [-0.5, 0.0, 0.5]:
			var lx: float = sx * w
			var lz: float = sz * d
			var p := Vector2(x + lx * cos(yaw) + lz * sin(yaw), z - lx * sin(yaw) + lz * cos(yaw))
			lowest = minf(lowest, _ground(p.x, p.y).y)
	return lowest


## InteractiveArea.tscn wires its own body signals; packing would save them a
## second time on each instance, so they are dropped and the instance restores them.
func _drop_instanced_connections(node: Node) -> void:
	if node.scene_file_path == INTERACTIVE_SCENE:
		for signal_name: StringName in [&"body_entered", &"body_exited"]:
			for c: Dictionary in node.get_signal_connection_list(signal_name):
				node.disconnect(signal_name, c["callable"])
	for child: Node in node.get_children():
		_drop_instanced_connections(child)


func _count(node: Node) -> int:
	var total: int = 1
	for child: Node in node.get_children():
		total += _count(child)
	return total
