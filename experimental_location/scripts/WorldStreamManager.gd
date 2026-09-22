extends Node3D

const LOCATION_DATA_PATH := "res://locations_data.json"

const LOCATION_AREAS := {
	"Silvan Heights": "Silvan Heights/Loc_SilvanHeights",
	"Palawan Cove": "Palawan Cove/Loc_PalawanCove",
	"Fort Meridian": "Fort Meridian/Loc_FortMeridian",
	"Verdant Ruins": "Verdant Ruins/Loc_VerdantRuins",
	"Harborlight District": "Harborlight District/Loc_HarborlightDistrict",
}

const CHUNK_DEFINITIONS := {
	"East Point Redoubt": {
		"area": "Fort Meridian/FM_Сhunks/Сhunk_EastPointRedoubt",
		"scene": "res://scenes/game/Сhunks/chunk_east_point_redoubt.tscn",
	},
	"Alata Battery": {
		"area": "Fort Meridian/FM_Сhunks/Сhunk_AlataBattery",
		"scene": "res://scenes/game/Сhunks/chunk_alata_battery.tscn",
	},
	"Guards Beach": {
		"area": "Fort Meridian/FM_Сhunks/Сhunk_GuardsBeach",
		"scene": "res://scenes/game/Сhunks/chunk_guards_beach.tscn",
	},
	"Gateway Cove": {
		"area": "Fort Meridian/FM_Сhunks/Сhunk_GatewayCove",
		"scene": "res://scenes/game/Сhunks/chunk_gateway_cove.tscn",
	},
	"Echo Glade": {
		"area": "Fort Meridian/FM_Сhunks/Сhunk_EchoGlade",
		"scene": "res://scenes/game/Сhunks/chunk_echo_glade.tscn",
	},
	"The Waiting Hill": {
		"area": "Fort Meridian/FM_Сhunks/Сhunk_TheWaitingHill",
		"scene": "res://scenes/game/Сhunks/chunk_the_waiting_hill.tscn",
	},
	"The Patrol Trail": {
		"area": "Fort Meridian/FM_Сhunks/Сhunk_ThePatrolTrail",
		"scene": "res://scenes/game/Сhunks/chunk_the_patrol_trail.tscn",
	},
	"Radio Shadow": {
		"area": "Fort Meridian/FM_Сhunks/Сhunk_RadioShadow",
		"scene": "res://scenes/game/Сhunks/chunk_radio_shadow.tscn",
	},
	"The Pit Descent": {
		"area": "Fort Meridian/FM_Сhunks/Сhunk_ThePitDescent",
		"scene": "res://scenes/game/Сhunks/chunk_the_pit_descent.tscn",
	},
}

@export_group("Streaming")
@export_range(50.0, 1000.0, 10.0) var preload_distance: float = 360.0
@export_range(25.0, 900.0, 10.0) var activate_distance: float = 220.0
@export_range(100.0, 1500.0, 10.0) var unload_distance: float = 480.0
@export_range(0.0, 30.0, 0.5) var unload_delay: float = 4.0
@export_range(0.05, 2.0, 0.05) var stream_check_interval: float = 0.20

@export_group("Debug")
@export var debug_info: bool = false
@export var recalculate_locations: bool = false

@onready var player: Node3D = get_node_or_null("../Player") as Node3D
@onready var debug_node: Node3D = get_node_or_null("../Perfomance&Debugging") as Node3D
@onready var debug_label_loc: RichTextLabel = get_node_or_null("../Perfomance&Debugging/debug_label_loc_pos_player") as RichTextLabel
@onready var debug_label_loc_info: RichTextLabel = get_node_or_null("../Perfomance&Debugging/debug_label_loc_info") as RichTextLabel
@onready var debug_label_chunk_info: RichTextLabel = get_node_or_null("../Perfomance&Debugging/debug_label_chunk_info") as RichTextLabel

var active_locations: Array[String] = []
var active_chunks: Array[String] = []
var locations_data: Dictionary = {}

var _debug_lines: Array[String] = []
var _debug_chunk_lines: Array[String] = []
var _chunk_areas: Dictionary = {}
var _loading_paths: Dictionary = {}
var _ready_resources: Dictionary = {}
var _loaded_chunk_nodes: Dictionary = {}
var _activation_requested: Dictionary = {}
var _unload_deadlines_msec: Dictionary = {}
var _stream_accumulator: float = 0.0


func _ready() -> void:
	_cache_chunk_areas()
	_set_debug_enabled(debug_info)

	if recalculate_locations:
		collect_and_save_location_data()
	else:
		load_location_data_from_json()

	if not is_instance_valid(player):
		push_warning("WorldStreamManager: ../Player not found; streaming is disabled.")
		set_process(false)
		return

	_evaluate_streaming()


func _process(delta: float) -> void:
	_poll_chunk_loading()

	_stream_accumulator += delta
	if _stream_accumulator < stream_check_interval:
		return

	_stream_accumulator = 0.0
	_evaluate_streaming()


func _cache_chunk_areas() -> void:
	_chunk_areas.clear()

	for chunk_name in CHUNK_DEFINITIONS:
		var definition: Dictionary = CHUNK_DEFINITIONS[chunk_name]
		var area: Area3D = get_node_or_null(String(definition["area"])) as Area3D
		if area == null:
			push_warning("WorldStreamManager: chunk area not found for %s" % chunk_name)
			continue
		_chunk_areas[chunk_name] = area


func _evaluate_streaming() -> void:
	var now_msec: int = Time.get_ticks_msec()

	for chunk_name in CHUNK_DEFINITIONS:
		var distance: float = _distance_to_chunk(chunk_name)
		if is_inf(distance):
			continue

		if distance <= preload_distance:
			_request_chunk_preload(chunk_name)

		if distance <= activate_distance:
			_activation_requested[chunk_name] = true
			_try_activate_chunk(chunk_name)

		if distance < unload_distance:
			_unload_deadlines_msec.erase(chunk_name)
			continue

		if active_chunks.has(chunk_name):
			continue

		var has_memory: bool = (
			_loaded_chunk_nodes.has(chunk_name)
			or _ready_resources.has(chunk_name)
			or _loading_paths.has(chunk_name)
		)
		if not has_memory:
			continue

		if not _unload_deadlines_msec.has(chunk_name):
			_unload_deadlines_msec[chunk_name] = now_msec + int(unload_delay * 1000.0)
		elif now_msec >= int(_unload_deadlines_msec[chunk_name]):
			_release_chunk(chunk_name)


func _request_chunk_preload(chunk_name: String) -> void:
	if _loaded_chunk_nodes.has(chunk_name) or _ready_resources.has(chunk_name) or _loading_paths.has(chunk_name):
		return

	if not CHUNK_DEFINITIONS.has(chunk_name):
		push_warning("WorldStreamManager: unknown chunk %s" % chunk_name)
		return

	var definition: Dictionary = CHUNK_DEFINITIONS[chunk_name]
	var path: String = String(definition["scene"])
	var error: int = ResourceLoader.load_threaded_request(path, "PackedScene", true)

	if error != OK:
		push_warning("WorldStreamManager: failed to start loading %s (%s), error %d" % [chunk_name, path, error])
		return

	_loading_paths[chunk_name] = path
	_debug_chunk("PRELOAD  %s" % chunk_name)


func _poll_chunk_loading() -> void:
	for chunk_name in _loading_paths.keys():
		var path: String = String(_loading_paths[chunk_name])
		var status: int = ResourceLoader.load_threaded_get_status(path)

		match status:
			ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				continue

			ResourceLoader.THREAD_LOAD_LOADED:
				var resource: Resource = ResourceLoader.load_threaded_get(path)
				_loading_paths.erase(chunk_name)

				if not (resource is PackedScene):
					push_warning("WorldStreamManager: %s did not load as PackedScene." % chunk_name)
					continue

				if _distance_to_chunk(chunk_name) >= unload_distance and not active_chunks.has(chunk_name):
					# Player left while the background request was running. Drop our reference.
					continue

				_ready_resources[chunk_name] = resource
				_debug_chunk("READY    %s" % chunk_name)
				_try_activate_chunk(chunk_name)

			ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				_loading_paths.erase(chunk_name)
				push_warning("WorldStreamManager: failed loading chunk %s" % chunk_name)


func _try_activate_chunk(chunk_name: String) -> void:
	if _loaded_chunk_nodes.has(chunk_name):
		return

	if not bool(_activation_requested.get(chunk_name, false)):
		return

	if not _ready_resources.has(chunk_name):
		_request_chunk_preload(chunk_name)
		return

	var scene: PackedScene = _ready_resources[chunk_name] as PackedScene
	if scene == null:
		_ready_resources.erase(chunk_name)
		return

	var area: Area3D = _chunk_areas.get(chunk_name) as Area3D
	if area == null:
		return

	var instance: Node = scene.instantiate()
	var parent_location: Node = area.get_parent().get_parent()
	parent_location.add_child(instance)

	if instance is Node3D:
		(instance as Node3D).global_position = area.global_position

	_loaded_chunk_nodes[chunk_name] = instance
	_ready_resources.erase(chunk_name)
	_unload_deadlines_msec.erase(chunk_name)
	_debug_chunk("ACTIVE   %s" % chunk_name)


func _release_chunk(chunk_name: String) -> void:
	if active_chunks.has(chunk_name):
		return

	if _loaded_chunk_nodes.has(chunk_name):
		var node: Node = _loaded_chunk_nodes[chunk_name] as Node
		if is_instance_valid(node):
			node.queue_free()

	_loaded_chunk_nodes.erase(chunk_name)
	_ready_resources.erase(chunk_name)
	_activation_requested.erase(chunk_name)
	_unload_deadlines_msec.erase(chunk_name)

	# A threaded request cannot be cancelled safely here. If one is still running,
	# _poll_chunk_loading() will discard it once it completes and sees the player is far away.
	_debug_chunk("UNLOAD   %s" % chunk_name)


func _distance_to_chunk(chunk_name: String) -> float:
	if not is_instance_valid(player):
		return INF

	var area: Area3D = _chunk_areas.get(chunk_name) as Area3D
	if area == null:
		return INF

	return player.global_position.distance_to(area.global_position)


func _on_chunk_entered(body: Node3D, chunk_name: String) -> void:
	if body != player:
		return

	if not active_chunks.has(chunk_name):
		active_chunks.append(chunk_name)

	_activation_requested[chunk_name] = true
	_unload_deadlines_msec.erase(chunk_name)
	_request_chunk_preload(chunk_name)
	_try_activate_chunk(chunk_name)
	_debug_chunk("ENTER    %s" % chunk_name)


func _on_chunk_exited(body: Node3D, chunk_name: String) -> void:
	if body != player:
		return

	active_chunks.erase(chunk_name)
	_unload_deadlines_msec[chunk_name] = Time.get_ticks_msec() + int(unload_delay * 1000.0)
	_debug_chunk("EXIT     %s" % chunk_name)


func load_location_data_from_json() -> void:
	var file := FileAccess.open(LOCATION_DATA_PATH, FileAccess.READ)
	if file == null:
		_collect_location_data()
		return

	var json := JSON.new()
	if json.parse(file.get_as_text()) == OK and json.data is Dictionary:
		locations_data = json.data
	elif debug_info:
		push_warning("WorldStreamManager: locations_data.json is invalid; recalculating in memory.")
		_collect_location_data()


func collect_and_save_location_data() -> void:
	_collect_location_data()

	var file := FileAccess.open(LOCATION_DATA_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("WorldStreamManager: cannot write %s" % LOCATION_DATA_PATH)
		return

	file.store_string(JSON.stringify(locations_data, "\t"))


func _collect_location_data() -> void:
	locations_data.clear()

	for location_name in LOCATION_AREAS:
		var area: Area3D = get_node_or_null(String(LOCATION_AREAS[location_name])) as Area3D
		if area == null:
			continue

		var polygon: CollisionPolygon3D = _find_collision_polygon(area)
		if polygon == null or polygon.polygon.is_empty():
			continue

		var aabb: AABB = _calculate_polygon_aabb(polygon)
		var actual_area: float = _polygon_area(polygon.polygon)
		var debug_color := Color.WHITE
		if polygon.has_meta("debug_color"):
			debug_color = polygon.get_meta("debug_color")

		locations_data[location_name] = {
			"position": {
				"x": area.global_position.x,
				"y": area.global_position.y,
				"z": area.global_position.z,
			},
			"polygon_depth": polygon.depth,
			"aabb_size": {
				"x": aabb.size.x,
				"y": aabb.size.y,
				"z": aabb.size.z,
			},
			"area_sq_m": actual_area,
			"hectares": actual_area / 10000.0,
			"debug_color": {
				"r": debug_color.r,
				"g": debug_color.g,
				"b": debug_color.b,
				"a": debug_color.a,
			},
		}


func _polygon_area(vertices: PackedVector2Array) -> float:
	if vertices.size() < 3:
		return 0.0

	var twice_area: float = 0.0
	for index in range(vertices.size()):
		var current: Vector2 = vertices[index]
		var next: Vector2 = vertices[(index + 1) % vertices.size()]
		twice_area += current.x * next.y - next.x * current.y

	return absf(twice_area) * 0.5


func _calculate_polygon_aabb(polygon_node: CollisionPolygon3D) -> AABB:
	var vertices: PackedVector2Array = polygon_node.polygon
	if vertices.is_empty():
		return AABB()

	var min_point: Vector2 = vertices[0]
	var max_point: Vector2 = vertices[0]

	for index in range(1, vertices.size()):
		var vertex: Vector2 = vertices[index]
		min_point.x = minf(min_point.x, vertex.x)
		min_point.y = minf(min_point.y, vertex.y)
		max_point.x = maxf(max_point.x, vertex.x)
		max_point.y = maxf(max_point.y, vertex.y)

	var half_depth: float = polygon_node.depth * 0.5
	var min_3d := Vector3(min_point.x, min_point.y, -half_depth)
	var max_3d := Vector3(max_point.x, max_point.y, half_depth)
	return AABB(min_3d, max_3d - min_3d)


func _find_collision_polygon(node: Node) -> CollisionPolygon3D:
	for child in node.get_children():
		if child is CollisionPolygon3D:
			return child as CollisionPolygon3D
	return null


func _set_debug_enabled(enabled: bool) -> void:
	if is_instance_valid(debug_node):
		debug_node.visible = enabled
	_set_label3d_visibility_recursive(self, enabled)


func _set_label3d_visibility_recursive(node: Node, enabled: bool) -> void:
	for child in node.get_children():
		if child is Label3D:
			(child as Label3D).visible = enabled
		_set_label3d_visibility_recursive(child, enabled)


func _debug_location(message: String) -> void:
	if not debug_info or debug_label_loc == null:
		return
	_debug_lines.append(message)
	if _debug_lines.size() > 2:
		_debug_lines.pop_front()
	debug_label_loc.text = "\n".join(_debug_lines)


func _debug_chunk(message: String) -> void:
	if not debug_info or debug_label_chunk_info == null:
		return
	_debug_chunk_lines.append(message)
	if _debug_chunk_lines.size() > 3:
		_debug_chunk_lines.pop_front()
	debug_label_chunk_info.text = "\n".join(_debug_chunk_lines)


func _location_entered(body: Node3D, location_name: String) -> void:
	if body != player:
		return
	if not active_locations.has(location_name):
		active_locations.append(location_name)
	_debug_location("ENTER  %s" % location_name)
	_update_location_info(location_name)


func _location_exited(body: Node3D, location_name: String) -> void:
	if body != player:
		return
	active_locations.erase(location_name)
	_debug_location("EXIT   %s" % location_name)
	if active_locations.is_empty():
		if debug_label_loc_info != null:
			debug_label_loc_info.text = ""
	else:
		_update_location_info(active_locations.back())


func _update_location_info(location_name: String) -> void:
	if not debug_info or debug_label_loc_info == null or not locations_data.has(location_name):
		return

	var data: Dictionary = locations_data[location_name]
	var position_data: Dictionary = data["position"]
	debug_label_loc_info.text = (
		"[color=yellow]%s[/color]\n"
		+ "Position: (%.1f, %.1f, %.1f)\n"
		+ "Area: %.1f m² / %.2f ha"
	) % [
		location_name,
		float(position_data["x"]),
		float(position_data["y"]),
		float(position_data["z"]),
		float(data["area_sq_m"]),
		float(data["hectares"]),
	]


# Scene signal compatibility. These stay tiny; streaming logic lives above.
func _on_loc_fort_meridian_body_entered(body: Node3D) -> void:
	_location_entered(body, "Fort Meridian")

func _on_loc_fort_meridian_body_exited(body: Node3D) -> void:
	_location_exited(body, "Fort Meridian")

func _on_loc_verdant_ruins_body_entered(body: Node3D) -> void:
	_location_entered(body, "Verdant Ruins")

func _on_loc_verdant_ruins_body_exited(body: Node3D) -> void:
	_location_exited(body, "Verdant Ruins")

func _on_loc_harborlight_district_body_entered(body: Node3D) -> void:
	_location_entered(body, "Harborlight District")

func _on_loc_harborlight_district_body_exited(body: Node3D) -> void:
	_location_exited(body, "Harborlight District")

func _on_loc_silvan_heights_body_entered(body: Node3D) -> void:
	_location_entered(body, "Silvan Heights")

func _on_loc_silvan_heights_body_exited(body: Node3D) -> void:
	_location_exited(body, "Silvan Heights")

func _on_loc_palawan_cove_body_entered(body: Node3D) -> void:
	_location_entered(body, "Palawan Cove")

func _on_loc_palawan_cove_body_exited(body: Node3D) -> void:
	_location_exited(body, "Palawan Cove")

func _on_chunk_east_point_redoubt_body_entered(body: Node3D) -> void:
	_on_chunk_entered(body, "East Point Redoubt")

func _on_chunk_east_point_redoubt_body_exited(body: Node3D) -> void:
	_on_chunk_exited(body, "East Point Redoubt")

func _on_chunk_alata_battery_body_entered(body: Node3D) -> void:
	_on_chunk_entered(body, "Alata Battery")

func _on_chunk_alata_battery_body_exited(body: Node3D) -> void:
	_on_chunk_exited(body, "Alata Battery")

func _on_chunk_guards_beach_body_entered(body: Node3D) -> void:
	_on_chunk_entered(body, "Guards Beach")

func _on_chunk_guards_beach_body_exited(body: Node3D) -> void:
	_on_chunk_exited(body, "Guards Beach")

func _on_chunk_gateway_cove_body_entered(body: Node3D) -> void:
	_on_chunk_entered(body, "Gateway Cove")

func _on_chunk_gateway_cove_body_exited(body: Node3D) -> void:
	_on_chunk_exited(body, "Gateway Cove")

func _on_chunk_echo_glade_body_entered(body: Node3D) -> void:
	_on_chunk_entered(body, "Echo Glade")

func _on_chunk_echo_glade_body_exited(body: Node3D) -> void:
	_on_chunk_exited(body, "Echo Glade")

func _on_chunk_the_waiting_hill_body_entered(body: Node3D) -> void:
	_on_chunk_entered(body, "The Waiting Hill")

func _on_chunk_the_waiting_hill_body_exited(body: Node3D) -> void:
	_on_chunk_exited(body, "The Waiting Hill")

func _on_chunk_the_patrol_trail_body_entered(body: Node3D) -> void:
	_on_chunk_entered(body, "The Patrol Trail")

func _on_chunk_the_patrol_trail_body_exited(body: Node3D) -> void:
	_on_chunk_exited(body, "The Patrol Trail")

func _on_chunk_radio_shadow_body_entered(body: Node3D) -> void:
	_on_chunk_entered(body, "Radio Shadow")

func _on_chunk_radio_shadow_body_exited(body: Node3D) -> void:
	_on_chunk_exited(body, "Radio Shadow")

func _on_chunk_the_pit_descent_body_entered(body: Node3D) -> void:
	_on_chunk_entered(body, "The Pit Descent")

func _on_chunk_the_pit_descent_body_exited(body: Node3D) -> void:
	_on_chunk_exited(body, "The Pit Descent")
