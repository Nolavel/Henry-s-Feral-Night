shader_type spatial;
render_mode cull_back, depth_draw_opaque;

// Snow surface around Henry. Height comes from SnowField, packing from the
// contact accumulator. See docs/technical/SNOW_COVER.md.
#include "res://shaders/environment/snow/snow_surface.gdshaderinc"
#include "res://shaders/environment/stylized_shadow.gdshaderinc"

// R: snow top (world y), G: settled depth, B: 1 where cut away, A: city wind factor.
uniform sampler2D field : filter_linear, repeat_disable;
// R: metres packed down, walls shaped to the repose slope and softened.
uniform sampler2D packed_field : filter_linear, repeat_disable;
uniform vec2 origin = vec2(0.0);
uniform float window_m = 25.6;
uniform float packed_texel_m = 0.05;
// Matches island_terrain snow_color so the window edge does not read as a patch.
uniform vec3 fresh_color : source_color = vec3(0.8, 0.83, 0.88);
uniform vec3 packed_color : source_color = vec3(0.5, 0.56, 0.68);
// Print walls: light scatters deep into snow and comes back blue from a cut face.
uniform vec3 wall_color : source_color = vec3(0.56, 0.66, 0.82);
// How far a broken print edge wanders off the boot's outline, metres: crust
// snaps into jagged slabs, powder crumbles in finer bites.
uniform float jag_crust_m = 0.025;
uniform float jag_powder_m = 0.01;

varying vec3 v_world;
varying float v_packed;
varying float v_rim;
varying float v_cut;
varying float v_edge;
varying float v_depth;
varying float v_ground;
varying float v_city;
varying float v_crust;
varying vec2 v_jag;

float packed_at(vec2 uv) {
	return texture(packed_field, uv).r;
}

// UV offset that breaks a print's outline: two octaves of world noise, so the
// edge wanders like snapped snow instead of tracing the smooth sole.
vec2 edge_jag(vec2 xz, float crust) {
	vec2 a = vec2(snow_noise(xz * 9.0), snow_noise(xz * 9.0 + 31.7)) - 0.5;
	vec2 b = vec2(snow_noise(xz * 27.0 + 5.1), snow_noise(xz * 27.0 + 13.3)) - 0.5;
	return (a * 2.0 + b) * mix(jag_powder_m, jag_crust_m, crust) / window_m;
}

// Distance to the nearest cell border of a jittered grid (F2 - F1), for cracks.
float crack_distance(vec2 p) {
	vec2 cell = floor(p);
	float f1 = 8.0;
	float f2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 c = cell + vec2(float(x), float(y));
			vec2 site = c + vec2(snow_hash(c), snow_hash(c + 17.3));
			float d = distance(p, site);
			if (d < f1) {
				f2 = f1;
				f1 = d;
			} else if (d < f2) {
				f2 = d;
			}
		}
	}
	return f2 - f1;
}

// Steepest a trench wall stands, as rise over run (loose snow ~40 degrees).
uniform float repose_tan = 0.84;

// Pit slope from the smooth packed field, never steeper than repose: shading does
// not step with the mesh triangles.
vec2 packed_slope(vec2 uv) {
	float t = packed_texel_m * 1.5 / window_m;
	float gx = packed_at(uv + vec2(t, 0.0)) - packed_at(uv - vec2(t, 0.0));
	float gz = packed_at(uv + vec2(0.0, t)) - packed_at(uv - vec2(0.0, t));
	vec2 g = vec2(gx, gz) / (2.0 * packed_texel_m * 1.5);
	float len = length(g);
	return len > repose_tan ? g * (repose_tan / len) : g;
}

// Wind crust cracks into slabs that tilt up at a pit's edge. Displaced powder is
// stored in the packed field itself (negative), so only crust gets this lip.
float rim_at(vec2 uv, vec2 xz, float here, float crust) {
	float d = packed_texel_m * 2.5 / window_m;
	float around = 0.0;
	for (int i = 0; i < 8; i++) {
		float a = float(i) * 0.785398;
		around += max(packed_at(uv + vec2(cos(a), sin(a)) * d), 0.0);
		around += max(packed_at(uv + vec2(cos(a), sin(a)) * d * 0.5), 0.0) * 0.5;
	}
	around /= 12.0;
	float lip = max(around - max(here, 0.0) * 1.5, 0.0);
	float slab = 0.6 + 0.8 * snow_noise(xz * 6.0);
	return lip * mix(0.15, 0.6, crust) * slab;
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
	// Walls already slope as the snow holds and are softened (snow_shape passes);
	// the outline is broken up here, where it is drawn.
	v_crust = f.b < 0.5 ? 1.0 - smoothstep(0.45, 0.95, f.b / 0.49) : 0.0;
	v_jag = edge_jag(world.xz, v_crust);
	uv += v_jag;
	v_packed = packed_at(uv);
	// The floor of a print is lumpy: grains pack unevenly under a boot.
	v_packed += (snow_noise(world.xz * 9.0) - 0.5) * 0.02 * smoothstep(0.02, 0.06, v_packed);
	// Pushed-aside snow heaps in crumbs, not a smooth bead.
	v_packed -= snow_noise(world.xz * 16.0) * 0.012 * smoothstep(0.004, 0.03, -v_packed);
	v_rim = rim_at(uv, world.xz, v_packed, v_crust);
	v_cut = f.b;
	v_city = f.a;
	vec2 to_edge = min(uv - v_jag, 1.0 - uv + v_jag) * window_m;
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
	HFN_SHADOW_FRAGMENT(v_world);
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
	vec2 slope = packed_slope(uv + v_jag);
	float wall = smoothstep(0.35, 1.6, length(slope)) * v_edge;
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
	// Crust breaks along cracks that run out from a print's lip into the slab.
	float lip = smoothstep(0.003, 0.02, v_rim) + wall * 0.5 * (1.0 - smoothstep(0.02, 0.06, v_packed));
	float crack = (1.0 - smoothstep(0.015, 0.05, crack_distance(v_world.xz * 14.0))) * clamp(lip, 0.0, 1.0) * v_crust;
	n = normalize(n + vec3(snow_noise(v_world.xz * 40.0) - 0.5, 0.0, snow_noise(v_world.xz * 40.0 + 7.0) - 0.5) * crack * 0.6);
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);

	float packed = smoothstep(0.01, 0.08, v_packed);
	float crust = smoothstep(0.005, 0.04, v_rim);
	vec3 color = mix(fresh_color, packed_color, packed);
	float heap = smoothstep(0.004, 0.03, -v_packed);
	color *= 1.0 + crust * 0.06 + heap * 0.04 - snow_breakup(v_world, 5.0) * 0.03;
	// Deep drifts read a touch brighter on the crest; shallow cover equals the terrain.
	color *= mix(1.0, 1.03, smoothstep(0.1, 0.4, v_depth));
	// Cut walls show blue and the layers of past snowfalls; cracks read as dark seams.
	float below = settled_top(v_world.xz) - v_world.y;
	float strata = 0.94 + 0.06 * sin(below * 110.0 + snow_noise(v_world.xz * 4.0) * 6.0);
	color = mix(color, wall_color * strata, wall * 0.5);
	color *= 1.0 - crack * 0.22;
	ALBEDO = snow_thin_tint(snow_wind_tint(color, v_city), v_depth);
	ROUGHNESS = mix(0.85, 0.6, packed);
	// Freshly broken grains at a print's edge sparkle more than the settled top.
	float glint = step(mix(0.996, 0.985, wall), snow_hash(floor(v_world.xz * 140.0)));
	EMISSION = vec3(glint * 0.25 * (1.0 - packed * (1.0 - wall)));
}


void light() {
	float ndotl = max(dot(NORMAL, LIGHT), 0.0);
	float attenuation = hfn_stylized_shadow(ATTENUATION, LIGHT_IS_DIRECTIONAL);
	DIFFUSE_LIGHT += ndotl * attenuation * LIGHT_COLOR / PI;
}
