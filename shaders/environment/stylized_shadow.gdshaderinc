// Hoarbound shared stylized-shadow lighting contract.
//
// Directional shadows use two stages:
// 1) seamless world-space texture noise offsets LIGHT_VERTEX before Godot's
//    physical shadow lookup;
// 2) that directional shadow receives a solid ink core and a hard,
//    noise-broken perimeter.
//
// Omni/Spot keep physical ATTENUATION untouched. For local lights ATTENUATION
// also carries distance falloff, so 1-ATTENUATION must not be treated as a
// shadow mask.

global uniform float stylized_shadow_strength;
global uniform float stylized_shadow_local_strength; // retained for settings compatibility
global uniform float stylized_shadow_floor;
global uniform float stylized_shadow_edge_light;
global uniform float stylized_shadow_threshold;
global uniform float stylized_shadow_break_softness;
global uniform float stylized_shadow_macro_scale;
global uniform float stylized_shadow_detail_scale;
global uniform float stylized_shadow_detail_amount;
global uniform sampler2D stylized_shadow_noise_texture;
global uniform float stylized_shadow_warp_m;
global uniform float stylized_shadow_texture_scale;
global uniform float stylized_shadow_texture_detail_scale;
global uniform float stylized_shadow_texture_detail_mix;

float hfn_shadow_tex(vec2 uv) {
	return texture(stylized_shadow_noise_texture, uv).r;
}

float hfn_shadow_world_noise(vec3 world_pos, float scale) {
	vec3 p = world_pos * max(scale, 0.0001);
	float xz = hfn_shadow_tex(p.xz);
	float xy = hfn_shadow_tex(p.xy + vec2(0.371, 0.113));
	float yz = hfn_shadow_tex(p.yz + vec2(0.719, 0.427));
	return xz * 0.50 + xy * 0.25 + yz * 0.25;
}

vec3 hfn_stylized_shadow_world_warp(vec3 world_pos) {
	float strength = clamp(stylized_shadow_strength, 0.0, 1.0);
	if (strength <= 0.0001 || stylized_shadow_warp_m <= 0.0001) {
		return vec3(0.0);
	}
	float macro_a = hfn_shadow_world_noise(
		world_pos + vec3(17.3, 0.0, -6.1), stylized_shadow_texture_scale
	);
	float macro_b = hfn_shadow_world_noise(
		world_pos + vec3(-9.7, 3.1, 13.9), stylized_shadow_texture_scale
	);
	float detail_a = hfn_shadow_world_noise(
		world_pos + vec3(2.6, -7.2, 5.8), stylized_shadow_texture_detail_scale
	);
	float detail_b = hfn_shadow_world_noise(
		world_pos + vec3(-4.4, 8.3, -12.7), stylized_shadow_texture_detail_scale
	);
	vec2 macro = vec2(macro_a, macro_b) * 2.0 - 1.0;
	vec2 detail = vec2(detail_a, detail_b) * 2.0 - 1.0;
	vec2 warp = mix(
		macro, detail, clamp(stylized_shadow_texture_detail_mix, 0.0, 1.0)
	);
	float amplitude = mix(
		0.38,
		1.0,
		hfn_shadow_world_noise(
			world_pos + vec3(31.0, -11.0, 7.0),
			stylized_shadow_texture_scale * 0.47
		)
	);
	return vec3(warp.x, 0.0, warp.y)
		* stylized_shadow_warp_m
		* amplitude
		* strength;
}

vec3 hfn_stylized_shadow_view_warp(vec3 world_pos, mat4 view_matrix) {
	return (view_matrix * vec4(hfn_stylized_shadow_world_warp(world_pos), 0.0)).xyz;
}

float hfn_stylized_shadow_attenuation(
	float physical_attenuation,
	vec3 world_pos,
	bool directional
) {
	float base = clamp(physical_attenuation, 0.0, 1.0);
	if (!directional) {
		return base;
	}

	float physical_shadow = 1.0 - base;
	float macro = hfn_shadow_world_noise(world_pos, stylized_shadow_macro_scale);
	float detail = hfn_shadow_world_noise(
		world_pos + vec3(11.7, -4.3, 7.1), stylized_shadow_detail_scale
	);

	float solid_core = smoothstep(0.48, 0.68, physical_shadow);
	float perimeter_gate =
		smoothstep(0.10, 0.22, physical_shadow)
		* (1.0 - smoothstep(0.50, 0.72, physical_shadow));

	float edge_field =
		physical_shadow * 0.56
		+ macro * 0.78
		+ (detail - 0.5) * 0.10 * stylized_shadow_detail_amount;
	float soft_edge = smoothstep(
		stylized_shadow_threshold - stylized_shadow_break_softness,
		stylized_shadow_threshold + stylized_shadow_break_softness,
		edge_field
	);
	float hard_edge = step(stylized_shadow_threshold, edge_field);
	float ragged_edge = mix(soft_edge, hard_edge, 0.72);

	float ink_mask = clamp(max(solid_core, ragged_edge * perimeter_gate), 0.0, 1.0);
	float edge_darkness = mix(
		stylized_shadow_edge_light,
		stylized_shadow_floor,
		smoothstep(0.42, 0.72, macro)
	);
	float ink_darkness = mix(edge_darkness, stylized_shadow_floor, solid_core);
	float stylized = mix(1.0, ink_darkness, ink_mask);
	return mix(base, stylized, clamp(stylized_shadow_strength, 0.0, 1.0));
}
