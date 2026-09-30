// Hoarbound shared stylized-shadow lighting contract.
//
// Stock Godot only: ATTENUATION remains the physical shadow/falloff source.
// Directional lights may punch controlled holes through the shadow penumbra;
// local lights keep their distance falloff and receive a restrained ink breakup.

global uniform float stylized_shadow_strength;
global uniform float stylized_shadow_local_strength;
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

float hfn_shadow_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hfn_shadow_hash(i), hfn_shadow_hash(i + vec2(1.0, 0.0)), u.x),
		mix(hfn_shadow_hash(i + vec2(0.0, 1.0)), hfn_shadow_hash(i + vec2(1.0, 1.0)), u.x),
		u.y
	);
}

float hfn_shadow_world_noise(vec3 world_pos, float scale) {
	vec3 p = world_pos * scale;
	float xz = hfn_shadow_noise(p.xz);
	float xy = hfn_shadow_noise(p.xy + vec2(17.0, 3.0));
	float yz = hfn_shadow_noise(p.yz + vec2(-5.0, 23.0));
	return xz * 0.50 + xy * 0.25 + yz * 0.25;
}

float hfn_stylized_shadow_attenuation(
	float physical_attenuation,
	vec3 world_pos,
	bool directional
) {
	float base = clamp(physical_attenuation, 0.0, 1.0);
	float physical_shadow = 1.0 - base;
	float macro = hfn_shadow_world_noise(world_pos, stylized_shadow_macro_scale);
	float detail = hfn_shadow_world_noise(
		world_pos + vec3(11.7, -4.3, 7.1),
		stylized_shadow_detail_scale
	);

	float core_start = directional ? 0.48 : 0.72;
	float core_end = directional ? 0.68 : 0.94;
	float gate_end_start = directional ? 0.50 : 0.74;
	float gate_end = directional ? 0.72 : 0.96;

	float solid_core = smoothstep(core_start, core_end, physical_shadow);
	float perimeter_gate =
		smoothstep(0.10, 0.22, physical_shadow)
		* (1.0 - smoothstep(gate_end_start, gate_end, physical_shadow));

	float edge_field =
		physical_shadow * 0.56
		+ macro * 0.78
		+ (detail - 0.5) * 0.10 * stylized_shadow_detail_amount;
	float ragged_edge = smoothstep(
		stylized_shadow_threshold - stylized_shadow_break_softness,
		stylized_shadow_threshold + stylized_shadow_break_softness,
		edge_field
	);

	float ink_mask = clamp(max(solid_core, ragged_edge * perimeter_gate), 0.0, 1.0);
	float edge_darkness = mix(
		stylized_shadow_edge_light,
		stylized_shadow_floor,
		smoothstep(0.42, 0.72, macro)
	);
	float ink_darkness = mix(edge_darkness, stylized_shadow_floor, solid_core);

	if (directional) {
		// Directional light has no distance falloff: restoring 1.0 outside the
		// ink mask deliberately tears the shadow silhouette.
		float stylized = mix(1.0, ink_darkness, ink_mask);
		return mix(base, stylized, clamp(stylized_shadow_strength, 0.0, 1.0));
	}

	// ATTENUATION for Omni/Spot also contains distance falloff. Never brighten
	// above that physical value; only break/darken it gently.
	float local_ink = mix(base, base * ink_darkness, ink_mask);
	float local_strength = clamp(
		stylized_shadow_strength * stylized_shadow_local_strength,
		0.0,
		1.0
	);
	return mix(base, local_ink, local_strength);
}
