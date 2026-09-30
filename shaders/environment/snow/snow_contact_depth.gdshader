shader_type spatial;
render_mode unshaded, fog_disabled, depth_test_disabled, depth_draw_never, cull_disabled, blend_mix, shadows_disabled;

// Full-screen quad for the upward snow contact camera. Writes the lowest world
// height of anything on the contact layer, minus base_y; 1000 where empty.
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform float base_y = 0.0;

void vertex() {
	POSITION = vec4(VERTEX.xy * 2.0, 0.0, 1.0);
}

void fragment() {
	float depth = texture(depth_tex, SCREEN_UV).r;
	float height = 1000.0;
	if (depth > 0.000001) {
		vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
		view.xyz /= view.w;
		vec4 world = INV_VIEW_MATRIX * vec4(view.xyz, 1.0);
		height = world.y - base_y;
	}
	ALBEDO = vec3(height, 0.0, 0.0);
	ALPHA = 1.0;
}
