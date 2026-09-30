shader_type spatial;
render_mode cull_back, depth_draw_opaque;

// Snow surface around Henry. Height comes from SnowField, packing from the
// contact accumulator. See docs/technical/SNOW_COVER.md.
#include "res://shaders/environment/snow/snow_surface.gdshaderinc"
#include "res://shaders/environment/stylized_shadow.gdshaderinc"

// R: snow top (world y), G: settled depth, B: 1 where cut away, A: city wind factor.
uniform sampler2D field : filter_linear, repeat_disable;
// R: metres packed down.
uniform sampler2D packed_field : filter_linear, repeat_disable;
uniform vec2 origin = vec2(0.0);
uniform float window_m = 25.6;
uniform float packed_texel_m = 0.05;
// Matches island_terrain snow_color so the window edge does not read as a patch.
uniform vec3 fresh_color : source_color = vec3(0.8, 0.83, 0.88);
uniform vec3 packed_color : source_color = vec3(0.5, 0.56, 0.68);

varying vec3 v_world;
varying float v_packed;
varying float v_rim;
varying float v_cut;
varying float v_edge;
varying float v_depth;
varying float v_ground;
varying float v_city;

float packed_at(vec2 uv) {
	return texture(packed_field, uv).r;
}

// Snow pushed out of a pit piles on its edge; the crust breaks into slabs.
float rim_at(vec2 uv, vec2 xz, float here) {
	float d = packed_texel_m * 2.5 / window_m;
	float around = 0.0;
	for (int i = 0; i < 8; i++) {
		float a = float(i) * 0.785398;
		around += packed_at(uv + vec2(cos(a), sin(a)) * d);
		around += packed_at(uv + vec2(cos(a), sin(a)) * d * 0.5) * 0.5;
	}
	around /= 12.0;
	float lip = max(around - here * 1.5, 0.0);
	float slab = 0.6 + 0.8 * snow_noise(xz * 6.0);
	return lip * 0.6 * slab;
}

// Snow top before packing, eased onto the chunk-wide base toward the edge.
float settled_top(vec2 xz) {
	vec2 uv = (xz - origin) / window_m;
	vec4 f = texture(field, uv);
	vec2 to_edge = min(uv, 1.0 - uv) * window_m;
	float edge = smoothstep(0.0, 6.0, min(to_edge.x, to_edge.y));
	return f.r - f.g + mix(snow_base_depth(xz, f.a), f.g, edge);
}


void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 uv = (world.xz - origin) / window_m;
	vec4 f = texture(field, uv);
	v_packed = packed_at(uv);
	v_rim = rim_at(uv, world.xz, v_packed);
	v_cut = f.b;
	v_city = f.a;
	vec2 to_edge = min(uv, 1.0 - uv) * window_m;
	// Over the outer 6 m the detail fades out onto the chunk-wide base.
	v_edge = smoothstep(0.0, 6.0, min(to_edge.x, to_edge.y));
	float ground = f.r - f.g;
	v_ground = ground;
	// Toward the window edge the surface eases onto the chunk-wide snow (snow_chunk_cover).
	float base = snow_base_geom(f.a);
	v_depth = mix(snow_base_depth(world.xz, f.a), f.g, v_edge);
	float top = ground + mix(base, f.g - v_packed + v_rim, v_edge);
	VERTEX.y = max(top, ground + 0.004) - MODEL_MATRIX[3].y;
	v_world = vec3(world.x, top, world.z);
}

void fragment() {
	vec2 uv = (v_world.xz - origin) / window_m;
	float grain = snow_hash(floor(v_world.xz * 40.0));
	// Where snow thins to a skin it would z-fight the ground: let the ground show.
	// Where the ground under the snow jumps (a kerb, a wall foot) the mesh would
	// hang a curtain between levels: no snow surface is that steep.
	float ground_slope = fwidth(v_ground) / max(length(fwidth(v_world.xz)), 0.001);
	if (v_cut > 0.5 || v_depth < 0.012 + grain * 0.02 || ground_slope > 1.5) {
		discard;
	}
	// Pit walls are sharper than the mesh, so they also come in through the normal.
	float t = packed_texel_m / window_m;
	float gx = packed_at(uv + vec2(t, 0.0)) - packed_at(uv - vec2(t, 0.0));
	float gz = packed_at(uv + vec2(0.0, t)) - packed_at(uv - vec2(0.0, t));
	vec2 slope = vec2(gx, gz) / (2.0 * packed_texel_m);
	// Settled surface slope over ±0.4 m: the mesh facets at the 20 cm field texel
	// would band the ridges, so shade from the smoothed field instead.
	float e = 0.4;
	float sx = settled_top(v_world.xz + vec2(e, 0.0)) - settled_top(v_world.xz - vec2(e, 0.0));
	float sz = settled_top(v_world.xz + vec2(0.0, e)) - settled_top(v_world.xz - vec2(0.0, e));
	vec2 ripple = snow_ripple_slope(v_world.xz, v_city) * (1.0 - smoothstep(0.02, 0.08, v_packed));
	vec3 smooth_n = normalize(vec3(-sx / (2.0 * e) - ripple.x, 1.0, -sz / (2.0 * e) - ripple.y));
	// Near kerbs and walls the real mesh edge still matters.
	vec3 geo = normalize(cross(dFdy(v_world), dFdx(v_world)));
	vec3 n = normalize(mix(smooth_n, geo, smoothstep(0.6, 1.2, ground_slope)) + vec3(slope.x, 0.0, slope.y) * 0.6);
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);

	float packed = smoothstep(0.01, 0.08, v_packed);
	float crust = smoothstep(0.005, 0.04, v_rim);
	vec3 color = mix(fresh_color, packed_color, packed);
	color *= 1.0 + crust * 0.06 - snow_breakup(v_world, 5.0) * 0.03;
	// Deep drifts read a touch brighter on the crest; shallow cover equals the terrain.
	color *= mix(1.0, 1.03, smoothstep(0.1, 0.4, v_depth));
	ALBEDO = snow_thin_tint(snow_wind_tint(color, v_city), v_depth);
	ROUGHNESS = mix(0.85, 0.6, packed);
	float glint = step(0.996, snow_hash(floor(v_world.xz * 140.0)));
	EMISSION = vec3(glint * 0.25 * (1.0 - packed));
}


void light() {
	float ndotl = max(dot(NORMAL, LIGHT), 0.0);
	float attenuation = hfn_stylized_shadow_attenuation(
		ATTENUATION,
		v_world,
		LIGHT_IS_DIRECTIONAL
	);
	DIFFUSE_LIGHT += ndotl * attenuation * LIGHT_COLOR / PI;
}
