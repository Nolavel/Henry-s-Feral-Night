shader_type spatial;
render_mode cull_back, depth_draw_opaque;

// Chunk-wide settled snow: a terrain-height grid lifted by the same depth as
// Henry's window (snow_base_depth), city wind factor in UV.x. Ridges shade per
// pixel, so they read on a coarse grid. See docs/technical/SNOW_COVER.md.
#include "res://shaders/environment/snow/snow_surface.gdshaderinc"

// xy: window min corner, z: window size, w: 1 when the window is live.
global uniform vec4 snow_window;
uniform vec3 fresh_color : source_color = vec3(0.8, 0.83, 0.88);

varying vec3 v_world;
varying vec3 v_ground_normal;
varying float v_city;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_city = UV.x;
	v_ground_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	VERTEX.y += snow_base_depth(world.xz, v_city);
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 in_window = (v_world.xz - snow_window.xy) / max(snow_window.z, 0.001);
	bool inside = snow_window.w > 0.5 && all(greaterThan(in_window, vec2(0.0))) && all(lessThan(in_window, vec2(1.0)));
	float depth = snow_base_depth(v_world.xz, v_city);
	if (inside || depth < 0.012) {
		discard;
	}
	// Ridge slope from the depth function itself, not the 2 m mesh.
	float e = 0.08;
	float gx = (snow_base_depth(v_world.xz + vec2(e, 0.0), v_city) - snow_base_depth(v_world.xz - vec2(e, 0.0), v_city)) / (2.0 * e);
	float gz = (snow_base_depth(v_world.xz + vec2(0.0, e), v_city) - snow_base_depth(v_world.xz - vec2(0.0, e), v_city)) / (2.0 * e);
	vec3 n = normalize(normalize(v_ground_normal) - vec3(gx, 0.0, gz));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	vec3 color = fresh_color * (1.0 - snow_breakup(v_world, 5.0) * 0.03);
	color *= mix(1.0, 1.03, smoothstep(0.1, 0.4, depth));
	ALBEDO = snow_thin_tint(color, depth);
	ROUGHNESS = 0.85;
}
