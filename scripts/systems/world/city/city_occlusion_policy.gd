class_name CityOcclusionPolicy
extends Node

## Runtime occlusion culling for dense streamed city chunks.
##
## The existing Ring0Massing already stores one cheap box proxy transform per
## building. When exact BuildingDetail streams in, combine the useful large
## proxies into one ArrayOccluder3D. The occluder lives under BuildingDetail,
## so it follows the existing HLOD visibility/lifetime and disappears when the
## detail chunk unloads.
##
## Keep this conservative: open/sparse chunks do not get an occluder, small
## props never participate, and proxy boxes are inset so they remain inside the
## visible building silhouette instead of causing false occlusion around edges.

const DETAIL_NODE_NAME: StringName = &"BuildingDetail"
const OCCLUDER_NODE_NAME: StringName = &"BuildingOccluder"

## CPU occlusion has a fixed cost. Only dense chunks are worth rasterizing.
const MIN_BUILDING_BOXES_PER_CHUNK: int = 10
## Ignore sheds and tiny helper boxes; they rarely hide enough geometry.
const MIN_HORIZONTAL_SIZE_M: float = 4.0
const MIN_HEIGHT_M: float = 3.0
## Ring0 proxies are bounding boxes. Shrink them to reduce false-positive culls.
const HORIZONTAL_INSET: float = 0.78
const VERTICAL_INSET: float = 0.90

const BOX_TRIANGLES: Array[int] = [
	0, 2, 1, 0, 3, 2,
	4, 5, 6, 4, 6, 7,
	0, 4, 7, 0, 7, 3,
	1, 2, 6, 1, 6, 5,
	0, 1, 5, 0, 5, 4,
	3, 7, 6, 3, 6, 2,
]


func _ready() -> void:
	## Godot supports toggling occlusion culling directly on the root viewport.
	## This keeps the production switch beside the policy that owns the actual
	## occluders instead of enabling CPU occlusion globally with no geometry.
	var root := get_tree().root
	if root != null:
		root.use_occlusion_culling = true

	var tree := get_tree()
	if not tree.node_added.is_connected(_on_node_added):
		tree.node_added.connect(_on_node_added)
	call_deferred(&"_apply_existing")


func _exit_tree() -> void:
	var tree := get_tree()
	if tree != null and tree.node_added.is_connected(_on_node_added):
		tree.node_added.disconnect(_on_node_added)


func _apply_existing() -> void:
	var root: Node = get_tree().current_scene
	if root == null:
		root = get_tree().root
	_apply_recursive(root)


func _apply_recursive(node: Node) -> void:
	if node is Node3D and node.name == DETAIL_NODE_NAME:
		_install_for_detail(node as Node3D)
	for child: Node in node.get_children():
		_apply_recursive(child)


func _on_node_added(node: Node) -> void:
	if node is Node3D and node.name == DETAIL_NODE_NAME:
		call_deferred(&"_install_for_detail", node as Node3D)


func _install_for_detail(detail: Node3D) -> void:
	if not is_instance_valid(detail) or not detail.is_inside_tree():
		return
	if detail.get_node_or_null("BuildingOccluder") != null:
		return
	var chunk := detail.get_parent()
	if chunk == null:
		return
	var massing := chunk.get_node_or_null("Ring0Massing") as MultiMeshInstance3D
	if massing == null or massing.multimesh == null:
		return

	var multimesh := massing.multimesh
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var useful_boxes: int = 0

	for i: int in range(multimesh.instance_count):
		var xf: Transform3D = multimesh.get_instance_transform(i)
		var size_x: float = xf.basis.x.length()
		var size_y: float = xf.basis.y.length()
		var size_z: float = xf.basis.z.length()
		if size_x < MIN_HORIZONTAL_SIZE_M or size_z < MIN_HORIZONTAL_SIZE_M or size_y < MIN_HEIGHT_M:
			continue

		var hx: float = 0.5 * HORIZONTAL_INSET
		var hy: float = 0.5 * VERTICAL_INSET
		var hz: float = 0.5 * HORIZONTAL_INSET
		var base: int = vertices.size()
		vertices.append_array(PackedVector3Array([
			xf * Vector3(-hx, -hy, -hz),
			xf * Vector3(hx, -hy, -hz),
			xf * Vector3(hx, hy, -hz),
			xf * Vector3(-hx, hy, -hz),
			xf * Vector3(-hx, -hy, hz),
			xf * Vector3(hx, -hy, hz),
			xf * Vector3(hx, hy, hz),
			xf * Vector3(-hx, hy, hz),
		]))
		for triangle_index: int in BOX_TRIANGLES:
			indices.append(base + triangle_index)
		useful_boxes += 1

	if useful_boxes < MIN_BUILDING_BOXES_PER_CHUNK:
		return

	var shape := ArrayOccluder3D.new()
	shape.set_arrays(vertices, indices)
	var occluder := OccluderInstance3D.new()
	occluder.name = OCCLUDER_NODE_NAME
	occluder.occluder = shape
	detail.add_child(occluder)
