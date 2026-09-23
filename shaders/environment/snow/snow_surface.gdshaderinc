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

// How close a point on a box is to its edges and base, 0 mid-face to 1 on an
// edge. Rime needs something to grow from; it starts at corners, not mid-wall.
float box_edge_factor(vec3 local_pos, vec3 half_extents, float edge_width, float base_height) {
	vec3 d = max(half_extents - abs(local_pos), vec3(0.0));
	float lo = min(d.x, min(d.y, d.z));
	float hi = max(d.x, max(d.y, d.z));
	float to_edge = d.x + d.y + d.z - lo - hi;
	float edge = 1.0 - smoothstep(0.0, edge_width, to_edge);
	float base = 1.0 - smoothstep(0.0, base_height, local_pos.y + half_extents.y);
	return max(edge, base * 0.85);
}

// Rime on steep faces, growing inward from edges as frost_amount rises. `edge`
// is 1 on edges, corners and cavities; noise only breaks up the growth front.
float frost_weight(vec3 world_normal, vec3 world_pos, float edge) {
	float up = abs(dot(normalize(world_normal), vec3(0.0, 1.0, 0.0)));
	float steep = smoothstep(0.25, 0.85, 1.0 - up);
	vec2 wall_plane = vec2(world_pos.x + world_pos.z, world_pos.y);
	float grain = snow_noise(wall_plane * 7.0) * 0.6 + snow_noise(wall_plane * 19.0 + 3.0) * 0.4;
	float reach = clamp(frost_amount, 0.0, 1.0);
	float front = edge + (grain - 0.5) * 0.35;
	float threshold = 1.0 - reach * 1.3;
	return steep * smoothstep(threshold, threshold + 0.2, front);
}
