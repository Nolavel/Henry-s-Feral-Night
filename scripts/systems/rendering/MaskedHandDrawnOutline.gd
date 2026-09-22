class_name MaskedHandDrawnOutline
extends ColorRect

## Readable production-preview Sobel with a soft screen-space exclusion mask
## around Henry. This keeps the selected visual style on world/props while
## preserving Henry's original shading without a second 3D render.

@export_range(1.0, 4.0, 0.05) var player_height_m: float = 2.05
@export_range(1.0, 2.0, 0.05) var mask_scale: float = 1.22
@export_range(0.2, 1.0, 0.05) var mask_width_to_height: float = 0.46

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
		_shader_material.set_shader_parameter("player_mask_enabled", 0.0)
		return

	var viewport := _source_camera.get_viewport()
	if viewport == null:
		_shader_material.set_shader_parameter("player_mask_enabled", 0.0)
		return

	var viewport_size := Vector2(viewport.get_visible_rect().size)
	if viewport_size.x <= 1.0 or viewport_size.y <= 1.0:
		_shader_material.set_shader_parameter("player_mask_enabled", 0.0)
		return

	var feet: Vector3 = _player.global_position
	var head: Vector3 = feet + Vector3.UP * player_height_m
	var center_3d: Vector3 = feet + Vector3.UP * (player_height_m * 0.52)

	if _source_camera.is_position_behind(center_3d):
		_shader_material.set_shader_parameter("player_mask_enabled", 0.0)
		return

	var feet_px: Vector2 = _source_camera.unproject_position(feet)
	var head_px: Vector2 = _source_camera.unproject_position(head)
	var center_px: Vector2 = _source_camera.unproject_position(center_3d)

	var height_px: float = maxf(absf(feet_px.y - head_px.y), 8.0)
	var radius_y_px: float = height_px * 0.5 * mask_scale
	var radius_x_px: float = radius_y_px * mask_width_to_height

	var center_uv := Vector2(
		center_px.x / viewport_size.x,
		center_px.y / viewport_size.y
	)
	var radius_uv := Vector2(
		radius_x_px / viewport_size.x,
		radius_y_px / viewport_size.y
	)

	_shader_material.set_shader_parameter("player_mask_enabled", 1.0)
	_shader_material.set_shader_parameter("player_mask_center", center_uv)
	_shader_material.set_shader_parameter("player_mask_radius", radius_uv)
