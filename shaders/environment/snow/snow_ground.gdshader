shader_type spatial;
render_mode cull_back, depth_draw_opaque;

// Local snow shell driven by SnowShell. See docs/technical/SNOW_COVER.md.
#include "res://shaders/environment/snow/snow_surface.gdshaderinc"

// R: packed-down share, G: raised crust share, B: fill clock at stamp.
uniform sampler2D print_field : filter_linear, repeat_disable;
// R: ground height, G: 1 where something stands on the ground.
uniform sampler2D ground_field : filter_linear, repeat_disable;
uniform vec2 origin = vec2(0.0);
uniform float window_m = 25.6;
uniform float depth_m = 0.14;
uniform float drift_m = 0.22;
uniform float lee_m = 0.3;
uniform vec2 wind_dir = vec2(0.0, -1.0);
uniform float fill_now = 0.0;
uniform vec3 fresh_color : source_color = vec3(0.78, 0.8, 0.85);
uniform vec3 packed_color : source_color = vec3(0.5, 0.56, 0.68);

varying vec3 v_world;
varying float v_obstacle;
varying float v_carve;
varying float v_rim;
varying float v_edge;
varying float v_relief;

// Ridges stretched along the wind; two offset layers overlap into stacked drifts.
float drift_shape(vec2 xz) {
	vec2 side = vec2(-wind_dir.y, wind_dir.x);
	vec2 p = vec2(dot(xz, wind_dir) * 0.16, dot(xz, side) * 0.55);
	float a = snow_noise(p) * 0.7 + snow_noise(p * 2.3 + 5.0) * 0.3;
	float b = snow_noise(p * 0.6 + vec2(11.0, 3.0));
	float ridge_a = smoothstep(0.35, 0.85, a);
	float ridge_b = smoothstep(0.45, 0.9, b) * 0.8;
	return max(ridge_a, ridge_b) + ridge_a * ridge_b * 0.4;
}

// Snow the wind drops behind obstacles upwind of here, and piles in front.
float lee_pile(vec2 uv) {
	float pile = 0.0;
	vec2 step_uv = wind_dir * 0.35 / window_m;
	for (int k = 1; k <= 8; k++) {
		float d = float(k);
		float behind = texture(ground_field, uv - step_uv * d).g;
		pile = max(pile, behind * smoothstep(0.0, 1.5, d) * (1.0 - d / 9.0));
	}
	float front = texture(ground_field, uv + step_uv).g * 0.6;
	return max(pile, front);
}

float print_mix(vec4 p) {
	return 1.0 - clamp(fill_now - p.b, 0.0, 1.0);
}

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 uv = (world.xz - origin) / window_m;
	vec2 ground = texture(ground_field, uv).rg;
	float cover = clamp(snow_cover, 0.0, 1.0);
	float settled = cover * depth_m * (0.85 + snow_noise(world.xz * 0.9) * 0.3);
	float drift = pow(cover, 1.5) * drift_m * drift_shape(world.xz);
	float lee = cover * lee_m * lee_pile(uv);
	float depth = settled + max(drift, lee) + min(drift, lee) * 0.3;
	v_relief = clamp((depth - settled) / max(drift_m * 0.6, 0.01), 0.0, 1.0);
	vec4 prints = texture(print_field, uv);
	float keep = print_mix(prints);
	v_carve = prints.r * keep;
	v_rim = prints.g * keep;
	vec2 to_edge = min(uv, 1.0 - uv) * window_m;
	v_edge = smoothstep(0.0, 2.5, min(to_edge.x, to_edge.y));
	depth = depth * (1.0 - v_carve + v_rim) * v_edge;
	v_obstacle = ground.g;
	VERTEX.y = ground.r + max(depth, 0.004) - MODEL_MATRIX[3].y;
	v_world = world;
	v_world.y = ground.r + depth;
}

void fragment() {
	vec2 uv = (v_world.xz - origin) / window_m;
	if (v_obstacle > 0.5 || snow_hash(floor(v_world.xz * 40.0)) > v_edge * 1.05) {
		discard;
	}
	// Print edges are finer than the mesh, so they come in through the normal.
	float texel = 1.0 / float(textureSize(print_field, 0).x);
	float h_l = dot(texture(print_field, uv - vec2(texel, 0.0)).rg, vec2(-1.0, 1.0));
	float h_r = dot(texture(print_field, uv + vec2(texel, 0.0)).rg, vec2(-1.0, 1.0));
	float h_d = dot(texture(print_field, uv - vec2(0.0, texel)).rg, vec2(-1.0, 1.0));
	float h_u = dot(texture(print_field, uv + vec2(0.0, texel)).rg, vec2(-1.0, 1.0));
	float local_depth = max(v_world.y - texture(ground_field, uv).r, 0.02);
	vec2 slope = vec2(h_r - h_l, h_u - h_d) * local_depth / (2.0 * texel * window_m);
	vec3 geo = normalize(cross(dFdy(v_world), dFdx(v_world)));
	vec3 n = normalize(geo + vec3(-slope.x, 0.0, -slope.y) * 0.8);
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);

	float packed = smoothstep(0.05, 0.6, v_carve);
	float crust = smoothstep(0.02, 0.2, v_rim);
	vec3 color = mix(fresh_color, packed_color, packed);
	color *= 1.0 + crust * 0.05 - snow_breakup(v_world, 5.0) * 0.05;
	// Troughs between drifts sit in soft shade, crests catch the light.
	color *= mix(0.78, 1.04, v_relief);
	ALBEDO = color;
	ROUGHNESS = mix(0.82, 0.6, packed);
	SPECULAR = 0.35;
	float glint = step(0.996, snow_hash(floor(v_world.xz * 140.0)));
	EMISSION = vec3(glint * 0.25 * (1.0 - packed));
}
