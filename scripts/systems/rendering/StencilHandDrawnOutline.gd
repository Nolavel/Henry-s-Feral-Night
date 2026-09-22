class_name StencilHandDrawnOutline
extends MeshInstance3D

const STENCIL_WRITER_SHADER: Shader = preload(
	"res://shaders/postprocess/henry_stencil_writer.gdshader"
)

var _camera: Camera3D
var _player: Node
var _writer_material: ShaderMaterial
var _original_overlays: Dictionary = {}


func _ready() -> void:
	_camera = get_parent() as Camera3D
	if _camera == null:
		push_error("StencilHandDrawnOutline must be a child of PlayerCamera.")
		visible = false
		return

	_player = _camera.get("player") as Node
	if _player == null:
		call_deferred("_bind_player_stencil")
	else:
		_bind_player_stencil()


func _exit_tree() -> void:
	_restore_player_overlays()


func _bind_player_stencil() -> void:
	if _player == null:
		_player = _camera.get("player") as Node
	if _player == null:
		push_warning("StencilHandDrawnOutline: Player is not assigned.")
		return

	_writer_material = ShaderMaterial.new()
	_writer_material.shader = STENCIL_WRITER_SHADER
	_writer_material.render_priority = -127

	_apply_writer_recursive(_player)


func _apply_writer_recursive(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		_original_overlays[mesh_instance] = mesh_instance.material_overlay
		mesh_instance.material_overlay = _writer_material

	for child: Node in node.get_children():
		_apply_writer_recursive(child)


func _restore_player_overlays() -> void:
	for mesh_instance_variant: Variant in _original_overlays.keys():
		var mesh_instance := mesh_instance_variant as MeshInstance3D
		if is_instance_valid(mesh_instance):
			mesh_instance.material_overlay = _original_overlays[mesh_instance_variant] as Material
	_original_overlays.clear()
