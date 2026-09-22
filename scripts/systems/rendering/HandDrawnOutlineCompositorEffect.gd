@tool
class_name HandDrawnOutlineCompositorEffect
extends CompositorEffect

const SHADER_PATH: String = "res://shaders/postprocess/hand_drawn_outline_compositor.glsl"

@export var edge_color: Color = Color(0.012, 0.016, 0.022, 1.0)
@export_range(0.0, 1.0, 0.01) var edge_opacity: float = 0.58
@export_range(0.5, 3.0, 0.05) var edge_width_px: float = 1.05
@export_range(0.001, 0.25, 0.001) var depth_threshold: float = 0.018
@export_range(0.005, 0.6, 0.005) var normal_threshold: float = 0.085
@export_range(0.0, 1.0, 0.05) var jitter_amount_px: float = 0.30
@export_range(0.0, 100.0, 0.5) var distance_fade_start: float = 18.0
@export_range(1.0, 200.0, 0.5) var distance_fade_end: float = 60.0

var _rd: RenderingDevice
var _shader: RID
var _pipeline: RID
var _nearest_sampler: RID


func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	access_resolved_color = true
	access_resolved_depth = true
	needs_normal_roughness = true

	_rd = RenderingServer.get_rendering_device()
	if _rd != null:
		RenderingServer.call_on_render_thread(_initialize_compute)


func _notification(what: int) -> void:
	if what != NOTIFICATION_PREDELETE or _rd == null:
		return

	if _shader.is_valid():
		_rd.free_rid(_shader)
		_shader = RID()

	if _nearest_sampler.is_valid():
		_rd.free_rid(_nearest_sampler)
		_nearest_sampler = RID()


#region Rendering thread
func _initialize_compute() -> void:
	_rd = RenderingServer.get_rendering_device()
	if _rd == null:
		return

	var shader_file := load(SHADER_PATH) as RDShaderFile
	if shader_file == null:
		push_error("HandDrawnOutlineCompositorEffect: compute shader failed to load.")
		return

	var spirv: RDShaderSPIRV = shader_file.get_spirv()
	if spirv == null:
		push_error("HandDrawnOutlineCompositorEffect: shader has no SPIR-V.")
		return

	_shader = _rd.shader_create_from_spirv(spirv)
	if not _shader.is_valid():
		push_error("HandDrawnOutlineCompositorEffect: shader RID is invalid.")
		return

	_pipeline = _rd.compute_pipeline_create(_shader)

	var sampler_state := RDSamplerState.new()
	sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	sampler_state.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	sampler_state.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	_nearest_sampler = _rd.sampler_create(sampler_state)


func _render_callback(
	p_effect_callback_type: EffectCallbackType,
	p_render_data: RenderData
) -> void:
	if (
		_rd == null
		or p_effect_callback_type != EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
		or not _pipeline.is_valid()
		or not _nearest_sampler.is_valid()
	):
		return

	var render_scene_buffers := p_render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	var scene_data := p_render_data.get_render_scene_data()
	if render_scene_buffers == null or scene_data == null:
		return

	if not render_scene_buffers.has_texture(&"forward_clustered", &"normal_roughness"):
		return

	var size: Vector2i = render_scene_buffers.get_internal_size()
	if size.x <= 0 or size.y <= 0:
		return

	var scene_data_buffer: RID = scene_data.get_uniform_buffer()
	if not scene_data_buffer.is_valid():
		return

	var normal_context: StringName = &"forward_clustered"
	var normal_name: StringName = &"normal_roughness"

	@warning_ignore("integer_division")
	var x_groups: int = (size.x - 1) / 8 + 1
	@warning_ignore("integer_division")
	var y_groups: int = (size.y - 1) / 8 + 1

	var view_count: int = render_scene_buffers.get_view_count()
	for view: int in range(view_count):
		var color_image: RID = render_scene_buffers.get_color_layer(view)
		var depth_image: RID = render_scene_buffers.get_depth_layer(view)
		var normal_image: RID = render_scene_buffers.get_texture_slice(
			normal_context,
			normal_name,
			view,
			0,
			1,
			1
		)

		if (
			not color_image.is_valid()
			or not depth_image.is_valid()
			or not normal_image.is_valid()
		):
			continue

		var scene_uniform := RDUniform.new()
		scene_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
		scene_uniform.binding = 0
		scene_uniform.add_id(scene_data_buffer)

		var color_uniform := RDUniform.new()
		color_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		color_uniform.binding = 1
		color_uniform.add_id(color_image)

		var depth_uniform := RDUniform.new()
		depth_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		depth_uniform.binding = 2
		depth_uniform.add_id(_nearest_sampler)
		depth_uniform.add_id(depth_image)

		var normal_uniform := RDUniform.new()
		normal_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		normal_uniform.binding = 3
		normal_uniform.add_id(_nearest_sampler)
		normal_uniform.add_id(normal_image)

		var uniform_set: RID = UniformSetCacheRD.get_cache(
			_shader,
			0,
			[scene_uniform, color_uniform, depth_uniform, normal_uniform]
		)
		if not uniform_set.is_valid():
			continue

		var push_constant := PackedFloat32Array([
			float(size.x),
			float(size.y),
			float(view),
			edge_width_px,
			edge_opacity,
			depth_threshold,
			normal_threshold,
			jitter_amount_px,
			distance_fade_start,
			maxf(distance_fade_end, distance_fade_start + 0.5),
			0.0,
			0.0,
			edge_color.r,
			edge_color.g,
			edge_color.b,
			edge_color.a,
		])

		var compute_list: int = _rd.compute_list_begin()
		_rd.compute_list_bind_compute_pipeline(compute_list, _pipeline)
		_rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
		_rd.compute_list_set_push_constant(
			compute_list,
			push_constant.to_byte_array(),
			push_constant.size() * 4
		)
		_rd.compute_list_dispatch(compute_list, x_groups, y_groups, 1)
		_rd.compute_list_end()
#endregion
