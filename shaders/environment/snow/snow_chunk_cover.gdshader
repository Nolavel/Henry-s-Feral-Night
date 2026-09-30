shader_type spatial;
render_mode cull_back, depth_draw_opaque;

// Chunk-wide settled snow: terrain-height grid lifted by the city wind factor
// (UV.x). Hidden inside Henry's detailed window. See docs/technical/SNOW_COVER.md.
#include "res://shaders/environment/snow/snow_surface.gdshaderinc"

global uniform float snow_settled_depth;
// xy: window min corner, z: window size, w: 1 when the window is live.
global uniform vec4 snow_window;
uniform vec3 fresh_color : source_color = vec3(0.8, 0.83, 0.88);

varying vec3 v_world;
varying float v_depth;

void vertex() {
	v_depth = snow_settled_depth * UV.x;
	VERTEX.y += v_depth;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 in_window = (v_world.xz - snow_window.xy) / max(snow_window.z, 0.001);
	bool inside = snow_window.w > 0.5 && all(greaterThan(in_window, vec2(0.0))) && all(lessThan(in_window, vec2(1.0)));
	if (inside || v_depth < 0.012) {
		discard;
	}
	vec3 n = normalize(cross(dFdy(v_world), dFdx(v_world)));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	vec3 color = fresh_color * (1.0 - snow_breakup(v_world, 5.0) * 0.03);
	ALBEDO = color * mix(1.0, 1.03, smoothstep(0.1, 0.4, v_depth));
	ROUGHNESS = 0.85;
}
