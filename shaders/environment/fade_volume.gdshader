shader_type spatial;
render_mode unshaded, blend_mix, fog_disabled, depth_draw_never;

// "Fade Volume" by dairycultist (CC0):
// https://godotshaders.com/shader/fade-volume/
//
// Godot 4.8 adaptation preserving the reference's SIGNED local-X contract.
// The original shader advances an object-space ray by a view-space Z delta.
// For a shallow volume that can overshoot. Here the Z delta is divided by the
// view-ray cosine first, yielding the real distance along the ray.
// Contract stays identical to the reference: -X transparent, +X black.

uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
uniform float x_len : hint_range(0.01, 10.0) = 1.0;
uniform float y_len : hint_range(0.01, 10.0) = 1.0;
uniform float z_len : hint_range(0.01, 10.0) = 1.0;
uniform float exponent : hint_range(0.05, 10.0) = 1.0;
uniform float axis_sign : hint_range(-1.0, 1.0) = 1.0;
uniform vec4 fade_color : source_color = vec4(0.025, 0.035, 0.055, 0.58);
uniform float corner_radius : hint_range(0.0, 1.0) = 0.07;
uniform float edge_softness : hint_range(0.001, 0.5) = 0.025;

varying vec3 pos_object;
varying vec3 cam_pos_object;
varying vec3 surface_view;


void vertex() {
	pos_object = VERTEX;
	surface_view = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;

	vec3 cam_pos_world = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	cam_pos_object = (inverse(MODEL_MATRIX) * vec4(cam_pos_world, 1.0)).xyz;
}


float linearize_depth(float raw_depth, vec2 screen_uv, mat4 inv_proj_matrix) {
	vec3 ndc = vec3(screen_uv * 2.0 - 1.0, raw_depth);
	vec4 view = inv_proj_matrix * vec4(ndc, 1.0);
	float safe_w = abs(view.w) > 0.000001 ? view.w : 1.0;
	return -(view.z / safe_w);
}


float rounded_rect_mask(vec2 p, vec2 half_size, float radius, float softness) {
	float r = min(max(radius, 0.0), max(min(half_size.x, half_size.y) - 0.0001, 0.0));
	vec2 inner = max(half_size - vec2(r), vec2(0.0001));
	vec2 q = abs(p) - inner;
	float sd = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
	return 1.0 - smoothstep(-max(softness, 0.0001), 0.0, sd);
}


void fragment() {
	float raw_depth = textureLod(depth_texture, SCREEN_UV, 0.0).r;
	float scene_depth = linearize_depth(raw_depth, SCREEN_UV, INV_PROJECTION_MATRIX);
	float surface_depth = linearize_depth(FRAGCOORD.z, SCREEN_UV, INV_PROJECTION_MATRIX);
	float z_travel = max(scene_depth - surface_depth, 0.0);

	vec3 ray_view = normalize(surface_view);
	float ray_cosine = max(-ray_view.z, 0.0001);
	float ray_travel = z_travel / ray_cosine;

	vec3 ray_object = normalize(pos_object - cam_pos_object);
	vec3 scene_position_object = pos_object + ray_object * ray_travel;
	float signed_x = scene_position_object.x * axis_sign;

	float gradient = pow(
		clamp(smoothstep(-x_len * 0.5, x_len * 0.5, signed_x), 0.0, 1.0),
		exponent
	);
	float edge_mask = rounded_rect_mask(
		pos_object.yz,
		vec2(y_len, z_len) * 0.5,
		corner_radius,
		edge_softness
	);

	ALBEDO = fade_color.rgb;
	ALPHA = clamp(gradient * edge_mask * fade_color.a, 0.0, 1.0);
}
