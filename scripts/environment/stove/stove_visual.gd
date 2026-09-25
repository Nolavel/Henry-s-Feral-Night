class_name StoveVisual
extends Node3D

## A cast-iron wood stove around a HeatSource (the parent): legs, ash pan with a
## draught vent, a firebox with one log per fuel unit left, a slotted door that
## glows, a cooktop and a flue. Front is +X, where the feed prompt stands.

## Logs the firebox shows at most; one per fuel unit of hours left.
const MAX_LOGS: int = 4
const SIZE: Vector3 = Vector3(0.62, 0.0, 0.7)  # footprint depth (X) and width (Z)
const LEG_H: float = 0.14
const ASH_H: float = 0.12
const BOX_H: float = 0.5
const WALL: float = 0.03
const DOOR_W: float = 0.44
const DOOR_H: float = 0.34
const FLUE_H: float = 1.7

@export var source: HeatSource

var _iron: StandardMaterial3D
var _embers: StandardMaterial3D
var _logs: Array[Node3D] = []
var _glow: OmniLight3D
var _flicker_t: float = 0.0


func _ready() -> void:
	if source == null:
		source = get_parent() as HeatSource
	_build()
	if source != null:
		source.fuel_changed.connect(func(_f: float) -> void: _refresh())
		source.burning_changed.connect(func(_b: bool) -> void: _refresh())
	_refresh()


func get_visible_log_count() -> int:
	var count: int = 0
	for log_node: Node3D in _logs:
		if log_node.visible:
			count += 1
	return count


func is_glowing() -> bool:
	return _glow != null and _glow.visible


func _process(delta: float) -> void:
	if not is_glowing():
		return
	_flicker_t += delta
	var flicker: float = 0.8 + 0.2 * sin(_flicker_t * 7.3) * sin(_flicker_t * 3.1 + 1.7)
	_glow.light_energy = 1.4 * flicker
	_embers.emission_energy_multiplier = 2.2 * flicker
	if source != null and source.flame_light != null and source.flame_light.visible:
		source.flame_light.light_energy = 2.5 * (0.85 + 0.15 * flicker)


func _refresh() -> void:
	var burning: bool = source != null and source.is_burning()
	var units: int = 0
	if source != null and source.hours_per_fuel_unit > 0.0:
		units = ceili(source.get_remaining_hours() / source.hours_per_fuel_unit - 0.001)
	for i: int in range(_logs.size()):
		_logs[i].visible = i < clampi(units, 0, MAX_LOGS)
	_glow.visible = burning
	_embers.emission_enabled = burning
	_embers.albedo_color = Color(0.9, 0.35, 0.1) if burning else Color(0.18, 0.17, 0.16)


func _build() -> void:
	_iron = _material(Color(0.13, 0.13, 0.14), 0.75, 0.6)
	_embers = _material(Color(0.9, 0.35, 0.1), 0.9, 0.0)
	_embers.emission = Color(1.0, 0.42, 0.12)
	var hx: float = SIZE.x * 0.5
	var hz: float = SIZE.z * 0.5
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_box(Vector3(0.05, LEG_H, 0.05), Vector3(sx * (hx - 0.05), LEG_H * 0.5, sz * (hz - 0.05)), _iron)
	## Ash pan: a drawer under the firebox with the draught vent in front.
	var ash_y: float = LEG_H + ASH_H * 0.5
	_box(Vector3(SIZE.x, ASH_H, SIZE.z), Vector3(0.0, ash_y, 0.0), _iron)
	for i: int in range(3):
		_box(Vector3(0.01, 0.025, 0.09), Vector3(hx + 0.004, ash_y, (i - 1) * 0.12), _material(Color(0.03, 0.03, 0.03), 1.0, 0.0))
	_box(Vector3(0.03, 0.02, 0.14), Vector3(hx + 0.02, ash_y - 0.035, 0.0), _iron)  # drawer pull
	## Firebox: floor, back, sides, a front frame around the door opening, cooktop.
	var floor_y: float = LEG_H + ASH_H
	var top_y: float = floor_y + BOX_H
	var mid_y: float = floor_y + BOX_H * 0.5
	_box(Vector3(SIZE.x, WALL, SIZE.z), Vector3(0.0, floor_y + WALL * 0.5, 0.0), _iron)
	_box(Vector3(WALL, BOX_H, SIZE.z), Vector3(-hx + WALL * 0.5, mid_y, 0.0), _iron)
	for sz: float in [-1.0, 1.0]:
		_box(Vector3(SIZE.x, BOX_H, WALL), Vector3(0.0, mid_y, sz * (hz - WALL * 0.5)), _iron)
	var post: float = (SIZE.z - DOOR_W) * 0.5
	for sz: float in [-1.0, 1.0]:
		_box(Vector3(WALL, BOX_H, post), Vector3(hx - WALL * 0.5, mid_y, sz * (hz - post * 0.5)), _iron)
	var sill: float = (BOX_H - DOOR_H) * 0.5
	_box(Vector3(WALL, sill, DOOR_W), Vector3(hx - WALL * 0.5, floor_y + sill * 0.5, 0.0), _iron)
	_box(Vector3(WALL, sill, DOOR_W), Vector3(hx - WALL * 0.5, top_y - sill * 0.5, 0.0), _iron)
	_box(Vector3(SIZE.x + 0.06, 0.03, SIZE.z + 0.06), Vector3(0.0, top_y + 0.015, 0.0), _iron)
	_cylinder(0.11, 0.012, Vector3(0.05, top_y + 0.036, -0.14), _material(Color(0.2, 0.2, 0.21), 0.6, 0.7))  # cooking ring
	## Ember bed and logs inside: one log per fuel unit, stacked two by two.
	_box(Vector3(SIZE.x - 0.12, 0.02, SIZE.z - 0.12), Vector3(0.0, floor_y + WALL + 0.01, 0.0), _embers)
	var bark := _material(Color(0.3, 0.2, 0.12), 0.95, 0.0)
	for i: int in range(MAX_LOGS):
		var layer: int = i / 2
		var side: float = -1.0 if i % 2 == 0 else 1.0
		var log_node := _cylinder(0.05, SIZE.z - 0.16,
			Vector3(side * 0.09 - 0.04, floor_y + WALL + 0.06 + layer * 0.09, 0.0), bark)
		log_node.rotation = Vector3(PI * 0.5, 0.0, 0.0)  # lying front-to-back across the width
		_logs.append(log_node)
	_glow = OmniLight3D.new()
	_glow.light_color = Color(1.0, 0.5, 0.2)
	_glow.omni_range = 1.4
	_glow.position = Vector3(hx + 0.15, mid_y, 0.0)  # spills out through the door slots
	add_child(_glow)
	_build_door(Vector3(hx + 0.01, floor_y + sill, -DOOR_W * 0.5))
	## Flue: a collar on the cooktop at the back, a pipe to the roof.
	_cylinder(0.08, 0.06, Vector3(-hx + 0.15, top_y + 0.06, 0.0), _iron)
	_cylinder(0.065, FLUE_H, Vector3(-hx + 0.15, top_y + 0.06 + FLUE_H * 0.5, 0.0), _iron)


## A door hinged on its -Z edge: solid lower half, vertical bars above with gaps
## the fire shows through, and a knob.
func _build_door(hinge_at: Vector3) -> void:
	var hinge := Node3D.new()
	hinge.name = "DoorHinge"
	hinge.position = hinge_at
	add_child(hinge)
	var lower: float = DOOR_H * 0.45
	_box(Vector3(0.025, lower, DOOR_W), Vector3(0.0, lower * 0.5, DOOR_W * 0.5), _iron, hinge)
	_box(Vector3(0.025, 0.04, DOOR_W), Vector3(0.0, DOOR_H - 0.02, DOOR_W * 0.5), _iron, hinge)
	var bars: int = 6
	var bar_w: float = 0.035
	var gap_h: float = DOOR_H - lower - 0.04
	for i: int in range(bars):
		var z: float = bar_w * 0.5 + i * (DOOR_W - bar_w) / float(bars - 1)
		_box(Vector3(0.025, gap_h, bar_w), Vector3(0.0, lower + gap_h * 0.5, z), _iron, hinge)
	_cylinder(0.018, 0.04, Vector3(0.03, DOOR_H * 0.5, DOOR_W - 0.05), _material(Color(0.5, 0.45, 0.35), 0.5, 0.8), hinge)


func _box(size: Vector3, at: Vector3, material: Material, parent: Node3D = self) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = at
	parent.add_child(node)
	return node


func _cylinder(radius: float, height: float, at: Vector3, material: Material, parent: Node3D = self) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	mesh.material = material
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = at
	parent.add_child(node)
	return node


func _material(albedo: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = albedo
	material.roughness = roughness
	material.metallic = metallic
	return material
