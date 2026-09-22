class_name MaskedHandDrawnOutline
extends ColorRect

## Canvas Sobel + exact Henry ID mask.
##
## A secondary SubViewport shares the main World3D but its camera renders only
## Henry's dedicated render layer (16). With transparent_bg enabled, the
## viewport texture alpha becomes a pixel-accurate player silhouette.
## The Sobel pass simply skips those pixels.

@export_flags_3d_render var player_render_layer: int = 16
@export_range(0.0, 4.0, 0.25) var mask_dilate_px: float = 1.5

var _source_camera: Camera3D
var _mask_viewport: SubViewport
var _mask_camera: Camera3D
var _mask_environment: Environment
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

	_create_mask_viewport()
	_sync_mask_camera()
	set_process(true)


func _process(_delta: float) -> void:
	_sync_mask_camera()


func get_mask_texture() -> ViewportTexture:
	if _mask_viewport == null:
		return null
	return _mask_viewport.get_texture()


func _create_mask_viewport() -> void:
	_mask_viewport = SubViewport.new()
	_mask_viewport.name = "HenryIDMaskViewport"
	_mask_viewport.transparent_bg = true
	_mask_viewport.disable_2d = true
	_mask_viewport.disable_3d = false
	_mask_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_mask_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	_mask_viewport.world_3d = _source_camera.get_world_3d()
	add_child(_mask_viewport)

	_mask_camera = Camera3D.new()
	_mask_camera.name = "HenryIDMaskCamera"
	_mask_camera.cull_mask = player_render_layer
	_mask_viewport.add_child(_mask_camera)

	# Override the shared world's sky/fog for this camera only. The viewport
	# itself is transparent, so pixels with no Henry geometry stay alpha=0.
	_mask_environment = Environment.new()
	_mask_environment.background_mode = Environment.BG_COLOR
	_mask_environment.background_color = Color(0.0, 0.0, 0.0, 0.0)
	_mask_environment.background_energy_multiplier = 0.0
	_mask_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_mask_environment.ambient_light_color = Color.WHITE
	_mask_environment.ambient_light_energy = 1.0
	_mask_environment.fog_enabled = false
	_mask_environment.volumetric_fog_enabled = false
	_mask_camera.environment = _mask_environment

	_shader_material.set_shader_parameter("player_mask_texture", _mask_viewport.get_texture())
	_shader_material.set_shader_parameter("player_mask_dilate_px", mask_dilate_px)


func _sync_mask_camera() -> void:
	if _source_camera == null or _mask_camera == null or _mask_viewport == null:
		return

	var source_viewport := _source_camera.get_viewport()
	if source_viewport == null:
		return

	var visible_size := source_viewport.get_visible_rect().size
	var viewport_size := Vector2i(
		maxi(int(round(visible_size.x)), 1),
		maxi(int(round(visible_size.y)), 1)
	)

	if _mask_viewport.size != viewport_size:
		_mask_viewport.size = viewport_size
		_shader_material.set_shader_parameter(
			"player_mask_texel_size",
			Vector2(1.0 / float(viewport_size.x), 1.0 / float(viewport_size.y))
		)

	_mask_camera.global_transform = _source_camera.global_transform
	_mask_camera.projection = _source_camera.projection
	_mask_camera.keep_aspect = _source_camera.keep_aspect
	_mask_camera.fov = _source_camera.fov
	_mask_camera.size = _source_camera.size
	_mask_camera.frustum_offset = _source_camera.frustum_offset
	_mask_camera.near = _source_camera.near
	_mask_camera.far = _source_camera.far
	_mask_camera.h_offset = _source_camera.h_offset
	_mask_camera.v_offset = _source_camera.v_offset
	_mask_camera.current = true
