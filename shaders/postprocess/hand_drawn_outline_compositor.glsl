#[compute]
#version 450

#define MAX_VIEWS 2
#include "godot/scene_data_inc.glsl"

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0, std140) uniform SceneDataBlock {
	SceneData data;
	SceneData prev_data;
} scene_data_block;

layout(rgba16f, set = 0, binding = 1) uniform image2D color_image;
layout(set = 0, binding = 2) uniform sampler2D depth_texture;
layout(set = 0, binding = 3) uniform sampler2D normal_roughness_texture;

layout(push_constant, std430) uniform Params {
	vec2 raster_size;
	float view;
	float edge_width_px;

	float edge_opacity;
	float depth_threshold;
	float normal_threshold;
	float jitter_amount_px;

	float distance_fade_start;
	float distance_fade_end;
	float wide_normal_radius_px;
	float curvature_boost;

	vec4 edge_color;
} params;


vec2 clamp_uv(vec2 uv) {
	vec2 px = 1.0 / params.raster_size;
	return clamp(uv, px * 0.5, vec2(1.0) - px * 0.5);
}


mat4 get_inv_projection() {
	int view_index = int(params.view);
	if (view_index > 0) {
		return scene_data_block.data.inv_projection_matrix_view[view_index];
	}
	return scene_data_block.data.inv_projection_matrix;
}


float view_depth(vec2 uv) {
	float raw_depth = texture(depth_texture, clamp_uv(uv)).r;
	if (raw_depth <= 0.000001) {
		return 100000.0;
	}

	vec3 ndc = vec3(clamp_uv(uv) * 2.0 - 1.0, raw_depth);
	vec4 view_pos = get_inv_projection() * vec4(ndc, 1.0);
	float safe_w = abs(view_pos.w) < 0.000001 ? 0.000001 : view_pos.w;
	return max(-view_pos.z / safe_w, 0.0);
}


vec3 view_normal(vec2 uv) {
	vec4 packed = texture(normal_roughness_texture, clamp_uv(uv));
	return normalize(packed.xyz * 2.0 - 1.0);
}


float row_jitter(float y_px) {
	float broad = sin(y_px * 0.043) * 0.55;
	float fine = sin(y_px * 0.131 + 1.7) * 0.25;
	return (broad + fine) * params.jitter_amount_px;
}


void main() {
	ivec2 pixel = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = ivec2(params.raster_size);
	if (pixel.x >= size.x || pixel.y >= size.y) {
		return;
	}

	vec2 uv = (vec2(pixel) + vec2(0.5)) / params.raster_size;
	float raw_center = texture(depth_texture, uv).r;

	// Draw only on geometry pixels. Sky is never darkened by the outline pass.
	if (raw_center <= 0.000001) {
		return;
	}

	vec2 texel = 1.0 / params.raster_size;
	float width_px = max(params.edge_width_px, 0.5);
	vec2 step_uv = texel * width_px;
	vec2 jitter_uv = vec2(row_jitter(float(pixel.y)) * texel.x, 0.0);
	vec2 c = uv + jitter_uv;

	float d0 = view_depth(c + vec2(-step_uv.x, -step_uv.y));
	float d1 = view_depth(c + vec2( 0.0,       -step_uv.y));
	float d2 = view_depth(c + vec2( step_uv.x, -step_uv.y));
	float d3 = view_depth(c + vec2(-step_uv.x,  0.0));
	float d4 = view_depth(c);
	float d5 = view_depth(c + vec2( step_uv.x,  0.0));
	float d6 = view_depth(c + vec2(-step_uv.x,  step_uv.y));
	float d7 = view_depth(c + vec2( 0.0,        step_uv.y));
	float d8 = view_depth(c + vec2( step_uv.x,  step_uv.y));

	float gx = d2 + 2.0 * d5 + d8 - d0 - 2.0 * d3 - d6;
	float gy = d0 + 2.0 * d1 + d2 - d6 - 2.0 * d7 - d8;
	float relative_depth_edge = length(vec2(gx, gy)) / max(d4, 0.35);
	float depth_edge = smoothstep(
		params.depth_threshold,
		params.depth_threshold * 2.25,
		relative_depth_edge
	);

	vec3 nc = view_normal(c);

	// Local normal change catches creases and bevels. Use vector distance rather
	// than 1-dot so shallow angular changes are not quadratically suppressed.
	float local_normal_delta = 0.0;
	local_normal_delta = max(local_normal_delta, length(nc - view_normal(c + vec2( step_uv.x, 0.0))));
	local_normal_delta = max(local_normal_delta, length(nc - view_normal(c + vec2(-step_uv.x, 0.0))));
	local_normal_delta = max(local_normal_delta, length(nc - view_normal(c + vec2(0.0,  step_uv.y))));
	local_normal_delta = max(local_normal_delta, length(nc - view_normal(c + vec2(0.0, -step_uv.y))));

	float local_normal_edge = smoothstep(
		params.normal_threshold,
		params.normal_threshold * 2.0,
		local_normal_delta
	);

	// A wider radius reads gradual curvature on cylinders, rounded props and
	// character volumes without adding edges to truly flat surfaces.
	vec2 wide_step = texel * max(params.wide_normal_radius_px, width_px);
	float wide_normal_delta = 0.0;
	wide_normal_delta = max(wide_normal_delta, length(nc - view_normal(c + vec2( wide_step.x, 0.0))));
	wide_normal_delta = max(wide_normal_delta, length(nc - view_normal(c + vec2(-wide_step.x, 0.0))));
	wide_normal_delta = max(wide_normal_delta, length(nc - view_normal(c + vec2(0.0,  wide_step.y))));
	wide_normal_delta = max(wide_normal_delta, length(nc - view_normal(c + vec2(0.0, -wide_step.y))));
	wide_normal_delta = max(wide_normal_delta, length(nc - view_normal(c + vec2( wide_step.x,  wide_step.y))));
	wide_normal_delta = max(wide_normal_delta, length(nc - view_normal(c + vec2(-wide_step.x,  wide_step.y))));
	wide_normal_delta = max(wide_normal_delta, length(nc - view_normal(c + vec2( wide_step.x, -wide_step.y))));
	wide_normal_delta = max(wide_normal_delta, length(nc - view_normal(c + vec2(-wide_step.x, -wide_step.y))));

	float wide_normal_edge = smoothstep(
		params.normal_threshold * 0.70,
		params.normal_threshold * 1.65,
		wide_normal_delta
	) * params.curvature_boost;

	float normal_edge = max(local_normal_edge, wide_normal_edge);

	float edge = max(depth_edge, normal_edge);
	float distance_fade = 1.0 - smoothstep(
		params.distance_fade_start,
		params.distance_fade_end,
		d4
	);
	edge *= distance_fade * params.edge_opacity;

	if (edge <= 0.001) {
		return;
	}

	vec4 color = imageLoad(color_image, pixel);
	color.rgb = mix(color.rgb, params.edge_color.rgb, clamp(edge, 0.0, 1.0));
	imageStore(color_image, pixel, color);
}
