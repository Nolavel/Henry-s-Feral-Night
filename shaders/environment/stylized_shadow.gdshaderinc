// Hoarbound stylized directional-shadow contract.
//
// REQUIRES the HFN-patched Godot 4.8-dev6 editor. The engine patch exposes:
//   uint LIGHT_INDEX
//   float sample_directional_shadow(uint light_index, vec3 view_space_vertex)
//
// Unlike the old LIGHT_VERTEX approximation, this path performs two independent
// directional shadow-map lookups at noise-offset positions. Omni/Spot lights
// remain on Godot's untouched physical ATTENUATION path.

global uniform float stylized_shadow_strength;
global uniform float stylized_shadow_local_strength; // kept for settings/save compatibility
global uniform float stylized_shadow_floor;
global uniform float stylized_shadow_edge_light;
global uniform float stylized_shadow_threshold;
global uniform float stylized_shadow_break_softness;
global uniform float stylized_shadow_macro_scale;
global uniform float stylized_shadow_detail_scale;
global uniform float stylized_shadow_detail_amount;

const float HFN_SHADOW_OFFSET_1_M = 0.42;
const float HFN_SHADOW_OFFSET_2_M = 0.14;


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
