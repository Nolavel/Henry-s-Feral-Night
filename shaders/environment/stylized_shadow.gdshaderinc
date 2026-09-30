// Hoarbound stylized directional-shadow contract.
//
// Default path runs on stock Godot 4.8-dev6: the lookup moves through a
// LIGHT_VERTEX warp (HFN_STYLIZED_SHADOW_WARP) and ATTENUATION is torn into ink.
// Uncomment the define below only on the HFN-patched editor
// (docs/technical/CUSTOM_GODOT_SHADOW_SAMPLER.md) for two independent lookups.
// #define HFN_PATCHED_SHADOW_SAMPLER

global uniform float stylized_shadow_strength;
global uniform float stylized_shadow_local_strength; // kept for settings/save compatibility
global uniform float stylized_shadow_floor;
global uniform float stylized_shadow_edge_light;
global uniform float stylized_shadow_threshold;
global uniform float stylized_shadow_break_softness;
global uniform float stylized_shadow_macro_scale;
global uniform float stylized_shadow_detail_scale;
global uniform float stylized_shadow_detail_amount;


float hfn_shadow_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}


float hfn_shadow_value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float a = hfn_shadow_hash(i);
	float b = hfn_shadow_hash(i + vec2(1.0, 0.0));
	float c = hfn_shadow_hash(i + vec2(0.0, 1.0));
	float d = hfn_shadow_hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}


float hfn_shadow_world_noise(vec3 world_pos, float scale) {
	vec3 p = world_pos * max(scale, 0.0001);
	float xz = hfn_shadow_value_noise(p.xz);
	float xy = hfn_shadow_value_noise(p.xy + vec2(17.0, 3.0));
	float yz = hfn_shadow_value_noise(p.yz + vec2(-5.0, 23.0));
	return xz * 0.50 + xy * 0.25 + yz * 0.25;
}



#ifdef HFN_PATCHED_SHADOW_SAMPLER
#define HFN_LIGHT_INDEX LIGHT_INDEX
// The patched sampler moves each lookup itself: light() needs no warp.
#define HFN_STYLIZED_SHADOW_WARP(world_pos, view_matrix) vec3(0.0)

const float HFN_SHADOW_OFFSET_1_M = 0.42;
const float HFN_SHADOW_OFFSET_2_M = 0.14;


vec3 hfn_shadow_offset(vec3 world_pos, float scale, vec3 seed, float strength_m) {
	float nx = hfn_shadow_world_noise(world_pos + seed, scale);
	float ny = hfn_shadow_world_noise(world_pos + seed.yzx + vec3(9.0, -4.0, 13.0), scale * 1.17);
	float nz = hfn_shadow_world_noise(world_pos + seed.zxy + vec3(-7.0, 15.0, 2.0), scale * 0.91);
	return (vec3(nx, ny, nz) * 2.0 - 1.0) * strength_m;
}


float hfn_custom_directional_shadow(
	vec3 world_pos,
	uint light_index,
	mat4 view_matrix
) {
	vec3 world_1 = world_pos + hfn_shadow_offset(
		world_pos,
		stylized_shadow_macro_scale,
		vec3(11.7, -4.3, 7.1),
		HFN_SHADOW_OFFSET_1_M
	);
	vec3 world_2 = world_pos + hfn_shadow_offset(
		world_pos,
		stylized_shadow_detail_scale,
		vec3(-5.2, 19.1, -12.4),
		HFN_SHADOW_OFFSET_2_M
	);

	vec3 view_1 = (view_matrix * vec4(world_1, 1.0)).xyz;
	vec3 view_2 = (view_matrix * vec4(world_2, 1.0)).xyz;

	float shadow_1 = sample_directional_shadow(light_index, view_1);
	float shadow_2 = sample_directional_shadow(light_index, view_2);
	float sampled = mix(shadow_1, shadow_2, 0.5);

	// The double lookup creates the silhouette displacement. A second low-cost
	// mask crushes the transition into visible ink islands instead of a smooth
	// grey penumbra.
	float macro = hfn_shadow_world_noise(world_pos + vec3(31.0, -11.0, 7.0), stylized_shadow_macro_scale);
	float detail = hfn_shadow_world_noise(world_pos + vec3(-2.0, 8.0, 23.0), stylized_shadow_detail_scale);
	float cutoff = clamp(
		stylized_shadow_threshold
			+ (macro - 0.5) * 0.18
			+ (detail - 0.5) * 0.08 * stylized_shadow_detail_amount,
		0.28,
		0.72
	);
	float soft = smoothstep(
		cutoff - stylized_shadow_break_softness,
		cutoff + stylized_shadow_break_softness,
		sampled
	);
	float hard = step(cutoff, sampled);
	return mix(soft, hard, 0.78);
}


float hfn_stylized_shadow_attenuation(
	float physical_attenuation,
	vec3 world_pos,
	bool directional,
	uint light_index,
	mat4 view_matrix,
	bool enabled
) {
	float base = clamp(physical_attenuation, 0.0, 1.0);
	if (!enabled || !directional) {
		return base;
	}

	float torn_sample = hfn_custom_directional_shadow(world_pos, light_index, view_matrix);
	float physical_shadow = 1.0 - base;
	float solid_core = smoothstep(0.42, 0.72, physical_shadow);

	// Torn perimeter is dark but not as black as the fully occluded physical core.
	float torn_attenuation = mix(stylized_shadow_edge_light, 1.0, torn_sample);
	float stylized = mix(torn_attenuation, stylized_shadow_floor, solid_core);
	return mix(base, stylized, clamp(stylized_shadow_strength, 0.0, 1.0));
}

#else
#define HFN_LIGHT_INDEX 0u
#define HFN_STYLIZED_SHADOW_WARP(world_pos, view_matrix) hfn_stylized_shadow_view_warp(world_pos, view_matrix)

// Compile-time production constants. Keeping these out of Project Settings
// prevents an editor reload race where a new global uniform is referenced
// before Godot has registered it.
const float HFN_SHADOW_WARP_M = 0.28;
const float HFN_SHADOW_TEXTURE_SCALE = 0.12;
const float HFN_SHADOW_TEXTURE_DETAIL_SCALE = 0.45;
const float HFN_SHADOW_TEXTURE_DETAIL_MIX = 0.28;


vec3 hfn_stylized_shadow_world_warp(vec3 world_pos) {
	float strength = clamp(stylized_shadow_strength, 0.0, 1.0);
	if (strength <= 0.0001 || HFN_SHADOW_WARP_M <= 0.0001) {
		return vec3(0.0);
	}

	float macro_a = hfn_shadow_world_noise(
		world_pos + vec3(17.3, 0.0, -6.1),
		HFN_SHADOW_TEXTURE_SCALE
	);
	float macro_b = hfn_shadow_world_noise(
		world_pos + vec3(-9.7, 3.1, 13.9),
		HFN_SHADOW_TEXTURE_SCALE
	);
	float detail_a = hfn_shadow_world_noise(
		world_pos + vec3(2.6, -7.2, 5.8),
		HFN_SHADOW_TEXTURE_DETAIL_SCALE
	);
	float detail_b = hfn_shadow_world_noise(
		world_pos + vec3(-4.4, 8.3, -12.7),
		HFN_SHADOW_TEXTURE_DETAIL_SCALE
	);

	vec2 macro = vec2(macro_a, macro_b) * 2.0 - 1.0;
	vec2 detail = vec2(detail_a, detail_b) * 2.0 - 1.0;
	vec2 warp = mix(
		macro,
		detail,
		clamp(HFN_SHADOW_TEXTURE_DETAIL_MIX, 0.0, 1.0)
	);

	float amplitude_noise = hfn_shadow_world_noise(
		world_pos + vec3(31.0, -11.0, 7.0),
		HFN_SHADOW_TEXTURE_SCALE * 0.47
	);
	// Quantising part of the amplitude is intentional: broad regions shift by
	// noticeably different amounts instead of producing one smooth wavy edge.
	float island = mix(0.42, 1.0, step(0.48, amplitude_noise));
	float amplitude = mix(island, amplitude_noise, 0.22);

	return vec3(warp.x, 0.0, warp.y)
		* HFN_SHADOW_WARP_M
		* amplitude
		* strength;
}


vec3 hfn_stylized_shadow_view_warp(vec3 world_pos, mat4 view_matrix) {
	return (view_matrix * vec4(hfn_stylized_shadow_world_warp(world_pos), 0.0)).xyz;
}


float hfn_stylized_shadow_attenuation(
	float physical_attenuation,
	vec3 world_pos,
	bool directional,
	uint light_index,
	mat4 view_matrix,
	bool enabled
) {
	float base = clamp(physical_attenuation, 0.0, 1.0);
	if (!enabled) {
		return base;
	}

	// Local ATTENUATION also contains distance falloff. Keep it physical so
	// stove, flare and lamps are never interpreted as "more shadow" with range.
	if (!directional) {
		return base;
	}

	float physical_shadow = 1.0 - base;
	float macro = hfn_shadow_world_noise(world_pos, stylized_shadow_macro_scale);
	float detail = hfn_shadow_world_noise(
		world_pos + vec3(11.7, -4.3, 7.1),
		stylized_shadow_detail_scale
	);

	float solid_core = smoothstep(0.46, 0.64, physical_shadow);
	float perimeter_gate =
		smoothstep(0.07, 0.18, physical_shadow)
		* (1.0 - smoothstep(0.52, 0.76, physical_shadow));

	float edge_field =
		physical_shadow * 0.54
		+ macro * 0.72
		+ detail * 0.18 * stylized_shadow_detail_amount;

	float soft_edge = smoothstep(
		stylized_shadow_threshold - stylized_shadow_break_softness,
		stylized_shadow_threshold + stylized_shadow_break_softness,
		edge_field
	);
	float coarse_islands = step(0.52, macro * 0.78 + detail * 0.22);
	float hard_edge = step(stylized_shadow_threshold, edge_field) * coarse_islands;
	float ragged_edge = max(hard_edge, soft_edge * 0.24);

	float ink_mask = clamp(
		max(solid_core, ragged_edge * perimeter_gate),
		0.0,
		1.0
	);
	float edge_darkness = mix(
		stylized_shadow_edge_light,
		stylized_shadow_floor,
		step(0.58, macro)
	);
	float ink_darkness = mix(edge_darkness, stylized_shadow_floor, solid_core);
	float stylized = mix(1.0, ink_darkness, ink_mask);
	return mix(base, stylized, clamp(stylized_shadow_strength, 0.0, 1.0));
}
#endif
