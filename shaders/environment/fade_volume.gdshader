shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;

// HFN adaptation of "Fade Volume" by dairycultist.
// Source: https://godotshaders.com/shader/fade-volume/
// Original shader code is CC0.
//
// Place this on a BoxMesh. x_len must match the box length on local X.
// The volume fades from transparent at local -X to fade_color at local +X.

uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;

uniform float x_len : hint_range(0.01, 50.0) = 6.0;
uniform float exponent : hint_range(0.05, 10.0) = 1.35;
uniform vec4 fade_color : source_color = vec4(0.0, 0.0, 0.0, 0.72);

varying vec3 pos_object;
varying vec3 cam_pos_object;


void vertex() {
	pos_object = VERTEX;

	vec3 cam_pos_world = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	cam_pos_object = (inverse(MODEL_MATRIX) * vec4(cam_pos_world, 1.0)).xyz;
}


float linearize_depth(float raw_depth, vec2 screen_uv, mat4 inv_proj_matrix) {
	vec3 ndc = vec3(screen_uv * 2.0 - 1.0, raw_depth);
	vec4 view = inv_proj_matrix * vec4(ndc, 1.0);
	view.xyz /= max(abs(view.w), 0.000001);
	return -view.z;
}


void fragment() {
	vec3 cam_dir_object = normalize(pos_object - cam_pos_object);

	float scene_depth = linearize_depth(
		texture(depth_texture, SCREEN_UV).x,
		SCREEN_UV,
		INV_PROJECTION_MATRIX
	);
	float volume_surface_depth = linearize_depth(
		FRAGCOORD.z,
		SCREEN_UV,
		INV_PROJECTION_MATRIX
	);

	float offset_into_fragment = max(scene_depth - volume_surface_depth, 0.0);
	vec3 position = pos_object + cam_dir_object * offset_into_fragment;

	float gradient = smoothstep(-x_len * 0.5, x_len * 0.5, position.x);
	float alpha = pow(clamp(gradient, 0.0, 1.0), exponent) * fade_color.a;

	ALBEDO = fade_color.rgb;
	ALPHA = alpha;
}
