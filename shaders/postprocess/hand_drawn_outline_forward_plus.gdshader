shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled;

// Henry's Feral Night Forward+ prototype.
//
// Artistic direction adapted from Cyprinodont's CC0 "Hand Drawn"
// depth-based Sobel outline on GodotShaders (2026-01-19).
// This implementation is intentionally different: Forward+ gives us a
// normal/roughness buffer, so we do not render a second ghost viewport and we
// do not detect lighting/shadow changes as geometry edges.

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
uniform sampler2D normal_roughness_texture : hint_normal_roughness_texture, repeat_disable, filter_nearest;

uniform vec4 edge_color : source_color = vec4(0.025, 0.032, 0.045, 1.0);
uniform float edge_opacity : hint_range(0.0, 1.0) = 0.82;
uniform float edge_width_px : hint_range(0.5, 3.0, 0.1) = 1.15;
uniform float depth_threshold : hint_range(0.001, 0.2, 0.001) = 0.004;
uniform float raw_depth_threshold : hint_range(0.00001, 0.02, 0.00001) = 0.00035;
uniform float normal_threshold : hint_range(0.01, 0.6, 0.01) = 0.035;
uniform float luminance_threshold : hint_range(0.001, 0.5, 0.001) = 0.025;
uniform float luminance_weight : hint_range(0.0, 1.0, 0.05) = 0.80;
uniform float jitter_amount_px : hint_range(0.0, 2.0, 0.05) = 0.35;
uniform float jitter_speed : hint_range(0.0, 4.0, 0.05) = 0.30;
uniform float distance_fade_start : hint_range(0.0, 100.0, 0.5) = 18.0;
uniform float distance_fade_end : hint_range(1.0, 200.0, 0.5) = 55.0;


void vertex() {
	// Full-screen post-process quad. Keeping Z at 1 and disabling depth testing
	// makes the material independent from the camera node transform.
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}


float linear_depth(vec2 uv) {
	float raw_depth = texture(depth_texture, uv).r;
	vec3 ndc = vec3(uv * 2.0 - 1.0, raw_depth);
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	float safe_w = abs(view.w) < 0.000001 ? (view.w < 0.0 ? -0.000001 : 0.000001) : view.w;
	view.xyz /= safe_w;
	return max(-view.z, 0.0);
}


vec3 decoded_normal(vec2 uv) {
	return normalize(texture(normal_roughness_texture, uv).xyz * 2.0 - 1.0);
}


float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 345.45));
	p += dot(p, p + 34.345);
	return fract(p.x * p.y);
}


float luminance(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}


void fragment() {
	vec3 scene_color = texture(screen_texture, SCREEN_UV).rgb;
	float raw_center = texture(depth_texture, SCREEN_UV).r;

	// Reverse-Z Forward+: sky/background depth is approximately zero.
	if (raw_center <= 0.000001) {
		ALBEDO = scene_color;
		return;
	}

	vec2 pixel = 1.0 / VIEWPORT_SIZE;
	float phase = TIME * jitter_speed;
	float band = floor(SCREEN_UV.y * VIEWPORT_SIZE.y / 7.0);
	float jitter_seed = hash21(vec2(band, floor(phase * 5.0)));
	float jitter_wave = sin(SCREEN_UV.y * VIEWPORT_SIZE.y * 0.055 + phase * 2.3);
	vec2 jitter = vec2(
		(jitter_seed - 0.5) + jitter_wave * 0.20,
		sin(SCREEN_UV.x * VIEWPORT_SIZE.x * 0.047 + phase) * 0.18
	) * pixel * jitter_amount_px;

	vec2 p = pixel * edge_width_px;
	vec2 uv = SCREEN_UV + jitter;

	float d0 = linear_depth(uv + vec2(-p.x, -p.y));
	float d1 = linear_depth(uv + vec2( 0.0, -p.y));
	float d2 = linear_depth(uv + vec2( p.x, -p.y));
	float d3 = linear_depth(uv + vec2(-p.x,  0.0));
	float d4 = linear_depth(uv);
	float d5 = linear_depth(uv + vec2( p.x,  0.0));
	float d6 = linear_depth(uv + vec2(-p.x,  p.y));
	float d7 = linear_depth(uv + vec2( 0.0,  p.y));
	float d8 = linear_depth(uv + vec2( p.x,  p.y));

	float gx = d2 + 2.0 * d5 + d8 - d0 - 2.0 * d3 - d6;
	float gy = d0 + 2.0 * d1 + d2 - d6 - 2.0 * d7 - d8;
	float relative_depth_edge = length(vec2(gx, gy)) / max(d4, 0.20);
	float depth_edge = smoothstep(depth_threshold, depth_threshold * 2.0, relative_depth_edge);

	// Reverse-Z raw depth is intentionally also sampled as a silhouette
	// fallback. This is insensitive to linear-depth reconstruction details and
	// makes object/background discontinuities reliable on Forward+.
	float raw_c = texture(depth_texture, uv).r;
	float raw_delta = 0.0;
	raw_delta = max(raw_delta, abs(texture(depth_texture, uv + vec2( p.x, 0.0)).r - raw_c));
	raw_delta = max(raw_delta, abs(texture(depth_texture, uv + vec2(-p.x, 0.0)).r - raw_c));
	raw_delta = max(raw_delta, abs(texture(depth_texture, uv + vec2(0.0,  p.y)).r - raw_c));
	raw_delta = max(raw_delta, abs(texture(depth_texture, uv + vec2(0.0, -p.y)).r - raw_c));
	float silhouette_edge = smoothstep(raw_depth_threshold, raw_depth_threshold * 5.0, raw_delta);

	vec3 nc = decoded_normal(uv);
	float normal_delta = 0.0;
	normal_delta = max(normal_delta, 1.0 - dot(nc, decoded_normal(uv + vec2( p.x, 0.0))));
	normal_delta = max(normal_delta, 1.0 - dot(nc, decoded_normal(uv + vec2(-p.x, 0.0))));
	normal_delta = max(normal_delta, 1.0 - dot(nc, decoded_normal(uv + vec2(0.0,  p.y))));
	normal_delta = max(normal_delta, 1.0 - dot(nc, decoded_normal(uv + vec2(0.0, -p.y))));
	float normal_edge = smoothstep(normal_threshold, normal_threshold * 2.0, normal_delta);

	// Screen-space Sobel fallback. Depth + normals remain the geometric signal,
	// while luminance makes the prototype readable even on software Vulkan
	// drivers where auxiliary buffers can be conservative.
	float l0 = luminance(texture(screen_texture, uv + vec2(-p.x, -p.y)).rgb);
	float l1 = luminance(texture(screen_texture, uv + vec2( 0.0, -p.y)).rgb);
	float l2 = luminance(texture(screen_texture, uv + vec2( p.x, -p.y)).rgb);
	float l3 = luminance(texture(screen_texture, uv + vec2(-p.x,  0.0)).rgb);
	float l5 = luminance(texture(screen_texture, uv + vec2( p.x,  0.0)).rgb);
	float l6 = luminance(texture(screen_texture, uv + vec2(-p.x,  p.y)).rgb);
	float l7 = luminance(texture(screen_texture, uv + vec2( 0.0,  p.y)).rgb);
	float l8 = luminance(texture(screen_texture, uv + vec2( p.x,  p.y)).rgb);
	float lgx = l2 + 2.0 * l5 + l8 - l0 - 2.0 * l3 - l6;
	float lgy = l0 + 2.0 * l1 + l2 - l6 - 2.0 * l7 - l8;
	float luminance_edge = smoothstep(
		luminance_threshold,
		luminance_threshold * 3.0,
		length(vec2(lgx, lgy))
	) * luminance_weight;

	float edge = max(max(max(depth_edge, silhouette_edge), normal_edge), luminance_edge);
	float distance_fade = 1.0 - smoothstep(distance_fade_start, distance_fade_end, d4);
	edge *= distance_fade * edge_opacity;

	ALBEDO = mix(scene_color, edge_color.rgb, edge);
}
