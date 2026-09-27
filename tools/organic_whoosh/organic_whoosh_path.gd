@tool
class_name OrganicWhooshPath
extends Path3D

## Editor draft of a Disney-style organic wind whoosh.
## Builds a Curve3D from cubic Bezier points: straight entry with a slight
## dive, an elliptical loop that does not close like a compass circle, then
## an early peel-off exit. Path3D is the spine of the gesture only — volume
## (particles, forces) is a separate layer and is intentionally not wired here.
##
## Usage: add this node in the editor, tune Shape exports, the curve rebuilds.
## Hand-edit curve points afterward if needed; turn off auto_rebuild first.
## Not a runtime weather driver.

@export_group("Shape")
## Overall length along the primary wind axis (local +X).
@export_range(2.0, 40.0, 0.1) var length: float = 12.0:
	set(value):
		length = maxf(value, 2.0)
		_request_rebuild()

## Peak height of the loop above the baseline (local +Y).
@export_range(0.2, 8.0, 0.05) var height: float = 1.8:
	set(value):
		height = maxf(value, 0.2)
		_request_rebuild()

## Nominal loop size before ellipse stretch.
@export_range(0.2, 6.0, 0.05) var loop_radius: float = 1.4:
	set(value):
		loop_radius = maxf(value, 0.2)
		_request_rebuild()

## Horizontal stretch of the loop (>1 wider than tall).
@export_range(0.6, 2.5, 0.05) var ellipse_ratio: float = 1.25:
	set(value):
		ellipse_ratio = clampf(value, 0.6, 2.5)
		_request_rebuild()

## How far the entry dips before climbing into the loop.
@export_range(0.0, 1.5, 0.05) var dive: float = 0.3:
	set(value):
		dive = maxf(value, 0.0)
		_request_rebuild()

## 0 = exit near full loop closure; 1 = peel off much earlier.
@export_range(0.0, 1.0, 0.05) var early_exit: float = 0.55:
	set(value):
		early_exit = clampf(value, 0.0, 1.0)
		_request_rebuild()

## Sideways sway on the loop (local Z) so the path is not planar.
@export_range(0.0, 2.0, 0.05) var lateral_sway: float = 0.35:
	set(value):
		lateral_sway = maxf(value, 0.0)
		_request_rebuild()

## Curve bake density for PathFollow / sampling.
@export_range(0.05, 0.5, 0.01) var curve_bake_interval: float = 0.12:
	set(value):
		curve_bake_interval = clampf(value, 0.05, 0.5)
		_request_rebuild()

@export_group("Editor")
## Rebuild the curve when Shape exports change.
@export var auto_rebuild: bool = true
## Draw a thin ribbon mesh in the editor so the gesture reads without relying
## only on the Path3D debug draw.
@export var show_preview_mesh: bool = true:
	set(value):
		show_preview_mesh = value
		_update_preview_mesh()

@export var preview_color: Color = Color(0.95, 0.93, 0.89, 0.92):
	set(value):
		preview_color = value
		_update_preview_mesh()

## Ribbon half-width in meters.
@export_range(0.01, 0.25, 0.005) var preview_half_width: float = 0.04:
	set(value):
		preview_half_width = clampf(value, 0.01, 0.25)
		_update_preview_mesh()

## Toggle true in the inspector to force a rebuild once.
@export var rebuild_now: bool = false:
	set(value):
		if value:
			rebuild_curve()
		rebuild_now = false

const _PREVIEW_NAME := "_WhooshPreview"

var _rebuild_queued: bool = false


func _ready() -> void:
	if Engine.is_editor_hint():
		rebuild_curve()
	else:
		## Runtime: keep whatever curve is serialized; hide editor-only mesh.
		_clear_preview_mesh()


func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	if _rebuild_queued:
		_rebuild_queued = false
		rebuild_curve()


## Regenerates `curve` from the Shape exports.
func rebuild_curve() -> void:
	var c := Curve3D.new()
	c.bake_interval = curve_bake_interval

	var rx: float = loop_radius * ellipse_ratio
	var ry: float = loop_radius
	var mid_x: float = length * 0.42
	var base_y: float = 0.0
	var exit_angle: float = lerpf(TAU * 0.92, TAU * 0.55, early_exit)

	## 0 — entry far left, handles point downstream.
	var p0 := Vector3(0.0, base_y + 0.05, 0.0)
	var p0_out := Vector3(length * 0.12, 0.0, 0.0)

	## 1 — dive before the loop (slight undershoot).
	var p1 := Vector3(mid_x - rx * 0.95, base_y - dive, lateral_sway * 0.15)
	var p1_in := Vector3(-rx * 0.45, dive * 0.2, 0.0)
	var p1_out := Vector3(rx * 0.35, -dive * 0.15, lateral_sway * 0.2)

	## 2 — climb into the upper part of the elliptical loop.
	var p2 := Vector3(mid_x + rx * 0.15, base_y + ry * 1.05, lateral_sway)
	var p2_in := Vector3(-rx * 0.55, ry * 0.15, lateral_sway * 0.1)
	var p2_out := Vector3(rx * 0.5, -ry * 0.05, -lateral_sway * 0.15)

	## 3 — early exit: peel off before a full compass closure.
	var ex: float = cos(exit_angle)
	var ey: float = sin(exit_angle)
	var p3 := Vector3(mid_x + rx * ex * 0.85, base_y + ry * maxf(ey, 0.15), -lateral_sway * 0.4)
	var p3_in := Vector3(-rx * 0.25 * ey, ry * 0.35 * ex, 0.0)
	var p3_out := Vector3(length * 0.08, -ry * 0.1, 0.0)

	## 4 — far exit, almost straight again.
	var p4 := Vector3(length, base_y + 0.08, lateral_sway * 0.1)
	var p4_in := Vector3(-length * 0.1, 0.0, 0.0)

	c.add_point(p0, Vector3.ZERO, p0_out)
	c.add_point(p1, p1_in, p1_out)
	c.add_point(p2, p2_in, p2_out)
	c.add_point(p3, p3_in, p3_out)
	c.add_point(p4, p4_in, Vector3.ZERO)

	curve = c
	_update_preview_mesh()


func _request_rebuild() -> void:
	if not auto_rebuild:
		return
	if not is_inside_tree():
		return
	if Engine.is_editor_hint():
		_rebuild_queued = true
	else:
		rebuild_curve()


func _update_preview_mesh() -> void:
	if not Engine.is_editor_hint():
		_clear_preview_mesh()
		return
	if not show_preview_mesh or curve == null or curve.point_count < 2:
		_clear_preview_mesh()
		return

	var mesh_instance := get_node_or_null(_PREVIEW_NAME) as MeshInstance3D
	if mesh_instance == null:
		mesh_instance = MeshInstance3D.new()
		mesh_instance.name = _PREVIEW_NAME
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mesh_instance)
		mesh_instance.owner = owner if owner != null else self

	mesh_instance.mesh = _build_ribbon_mesh()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = preview_color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh_instance.material_override = mat


func _clear_preview_mesh() -> void:
	var existing := get_node_or_null(_PREVIEW_NAME)
	if existing != null:
		existing.queue_free()


func _build_ribbon_mesh() -> ArrayMesh:
	var c := curve
	var total: float = c.get_baked_length()
	if total <= 0.001:
		return ArrayMesh.new()

	var step: float = maxf(c.bake_interval, 0.08)
	var offsets: PackedFloat32Array = PackedFloat32Array()
	var o: float = 0.0
	while o <= total:
		offsets.append(o)
		o += step
	if offsets[offsets.size() - 1] < total:
		offsets.append(total)

	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var colors := PackedColorArray()

	for i in offsets.size():
		var tf: Transform3D = c.sample_baked_with_rotation(offsets[i], true, false)
		var origin: Vector3 = tf.origin
		var side: Vector3 = tf.basis.x.normalized() * preview_half_width
		var up: Vector3 = tf.basis.y.normalized()
		verts.append(origin - side)
		verts.append(origin + side)
		norms.append(up)
		norms.append(up)
		colors.append(preview_color)
		colors.append(preview_color)

	var indices := PackedInt32Array()
	for i in range(offsets.size() - 1):
		var a: int = i * 2
		indices.append_array([a, a + 1, a + 2, a + 1, a + 3, a + 2])

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
