// Shared snow and rime response for any spatial material, terrain-agnostic.
// Globals written by SnowPresentationSystem; see docs/technical/SNOW_COVER.md.

global uniform float snow_cover;
global uniform float frost_amount;

// Cheap world-space value noise, so no texture is required to break up edges.
float snow_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float snow_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(snow_hash(i), snow_hash(i + vec2(1.0, 0.0)), u.x),
		mix(snow_hash(i + vec2(0.0, 1.0)), snow_hash(i + vec2(1.0, 1.0)), u.x),
		u.y
	);
}

// Two octaves of noise over a world XZ position, 0..1.
float snow_breakup(vec3 world_pos, float scale) {
	vec2 p = world_pos.xz * scale;
	return snow_noise(p) * 0.65 + snow_noise(p * 3.1 + 17.0) * 0.35;
}

// Settled snow on up-facing surfaces. More cover reaches steeper slopes.
float snow_weight(vec3 world_normal, vec3 world_pos, float softness) {
	float up = dot(normalize(world_normal), vec3(0.0, 1.0, 0.0));
	float threshold = mix(0.97, 0.35, clamp(snow_cover, 0.0, 1.0));
	float jitter = (snow_breakup(world_pos, 1.7) - 0.5) * 0.25;
	return smoothstep(threshold - softness, threshold + softness, up + jitter);
}

// Rime on steep and vertical faces, patchy, grown by cold outdoor air.
float frost_weight(vec3 world_normal, vec3 world_pos) {
	float up = abs(dot(normalize(world_normal), vec3(0.0, 1.0, 0.0)));
	float steep = smoothstep(0.25, 0.85, 1.0 - up);
	// Sampled in the wall's own plane; XZ noise would streak on vertical faces.
	vec2 wall_plane = vec2(world_pos.x + world_pos.z, world_pos.y) * 2.3;
	float patches = smoothstep(
		0.35, 0.75, snow_noise(wall_plane) * 0.65 + snow_noise(wall_plane * 3.1 + 5.0) * 0.35
	);
	return clamp(frost_amount, 0.0, 1.0) * steep * mix(0.35, 1.0, patches);
}
