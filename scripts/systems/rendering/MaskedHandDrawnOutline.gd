class_name MaskedHandDrawnOutline
extends ColorRect

## Readable production-preview Sobel with an exact screen-space exclusion box
## derived from Henry's visible MeshInstance3D bounds.
##
## The outline remains the same selected production-preview look on the world
## and props. Only the projected player bounds bypass the post-process.

@export_range(0.0, 24.0, 0.5) var mask_padding_px: float = 5.0
@export_range(0.0, 0.25, 0.01) var mask_feather: float = 0.08

var _source_camera: Camera3D
var _player: Node3D
var _shader_material: ShaderMaterial


func _ready() -> void:
	_source_camera = get_parent() as Camera3D
	_shader_material = material as ShaderMaterial

	if _source_camera == null:
		push_error("MaskedHandDrawnOutline must be a child of PlayerCamera.")
		visible = false
		return

	if _shader_material == null:
		push_error("MaskedHandDrawnOutline requires a ShaderMaterial.")
		visible = false
		return

	_player = _source_camera.get("player") as Node3D
	set_process(true)
	_update_player_mask()


func _process(_delta: float) -> void:
	if _source_camera == null or _shader_material == null:
		return

	if not is_instance_valid(_player):
		_player = _source_camera.get("player") as Node3D

	_update_player_mask()


func _update_player_mask() -> void:
	if not is_instance_valid(_player):
		_disable_mask()
		return

	var viewport := _source_camera.get_viewport()
	if viewport == null:
		_disable_mask()
		return

	var viewport_size := Vector2(viewport.get_visible_rect().size)
	if viewport_size.x <= 1.0 or viewport_size.y <= 1.0:
		_disable_mask()
		return

	var screen_min := Vector2(1.0e20, 1.0e20)
	var screen_max := Vector2(-1.0e20, -1.0e20)
	var found_mesh := false

	var meshes: Array[MeshInstance3D] = []
	_collect_visible_meshes(_player, meshes)

	for mesh_instance: MeshInstance3D in meshes:
		if mesh_instance.mesh == null:
			continue

		var local_aabb: AABB = mesh_instance.get_aabb()
		for endpoint_index: int in range(8):
			var world_point: Vector3 = mesh_instance.global_transform * local_aabb.get_endpoint(endpoint_index)
			if _source_camera.is_position_behind(world_point):
				continue

			var screen_point: Vector2 = _source_camera.unproject_position(world_point)
			screen_min.x = minf(screen_min.x, screen_point.x)
			screen_min.y = minf(screen_min.y, screen_point.y)
			screen_max.x = maxf(screen_max.x, screen_point.x)
			screen_max.y = maxf(screen_max.y, screen_point.y)
			found_mesh = true

	if not found_mesh:
		_disable_mask()
		return

	screen_min -= Vector2.ONE * mask_padding_px
	screen_max += Vector2.ONE * mask_padding_px

	var min_uv := Vector2(
		clampf(screen_min.x / viewport_size.x, 0.0, 1.0),
		clampf(screen_min.y / viewport_size.y, 0.0, 1.0)
	)
	var max_uv := Vector2(
		clampf(screen_max.x / viewport_size.x, 0.0, 1.0),
		clampf(screen_max.y / viewport_size.y, 0.0, 1.0)
	)

	if min_uv.x >= max_uv.x or min_uv.y >= max_uv.y:
		_disable_mask()
		return

	_shader_material.set_shader_parameter("player_mask_enabled", 1.0)
	_shader_material.set_shader_parameter("player_mask_min", min_uv)
	_shader_material.set_shader_parameter("player_mask_max", max_uv)
	_shader_material.set_shader_parameter("player_mask_feather", mask_feather)


func _collect_visible_meshes(node: Node, result: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.visible and mesh_instance.is_visible_in_tree():
			result.append(mesh_instance)

	for child: Node in node.get_children():
		_collect_visible_meshes(child, result)


func _disable_mask() -> void:
	if _shader_material != null:
		_shader_material.set_shader_parameter("player_mask_enabled", 0.0)
