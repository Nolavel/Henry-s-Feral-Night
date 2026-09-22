shader_type canvas_item;
render_mode unshaded;

// Readable production Sobel. Henry exclusion comes from a separate render pass
// (player_mask_texture), not from a guessed 2D shape.

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform sampler2D player_mask_texture : repeat_disable, filter_nearest;

uniform vec4 edge_color : source_color = vec4(0.006, 0.008, 0.012, 1.0);
uniform float edge_opacity : hint_range(0.0, 1.0) = 0.76;
uniform float edge_width_px : hint_range(0.5, 4.0, 0.1) = 1.35;
uniform float edge_threshold : hint_range(0.001, 0.5, 0.001) = 0.018;
uniform float jitter_amount_px : hint_range(0.0, 2.0, 0.05) = 0.30;

uniform vec2 player_mask_texel_size = vec2(0.00078125, 0.00138889);
uniform float player_mask_dilate_px : hint_range(0.0, 4.0, 0.25) = 1.5;


float luma(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}


float hand_offset(float y_px) {
	float broad = sin(y_px * 0.043) * 0.55;
	float fine = sin(y_px * 0.131 + 1.7) * 0.25;
	return (broad + fine) * jitter_amount_px;
}


float henry_mask(vec2 uv) {
	vec2 t = player_mask_texel_size * player_mask_dilate_px;
	float a = texture(player_mask_texture, uv).a;
	a = max(a, texture(player_mask_texture, uv + vec2( t.x, 0.0)).a);
	a = max(a, texture(player_mask_texture, uv + vec2(-t.x, 0.0)).a);
	a = max(a, texture(player_mask_texture, uv + vec2(0.0,  t.y)).a);
	a = max(a, texture(player_mask_texture, uv + vec2(0.0, -t.y)).a);
	a = max(a, texture(player_mask_texture, uv + vec2( t.x,  t.y)).a);
	a = max(a, texture(player_mask_texture, uv + vec2(-t.x,  t.y)).a);
	a = max(a, texture(player_mask_texture, uv + vec2( t.x, -t.y)).a);
	a = max(a, texture(player_mask_texture, uv + vec2(-t.x, -t.y)).a);
	return smoothstep(0.02, 0.20, a);
}


void fragment() {
	vec2 base_uv = SCREEN_UV;
	vec2 px = SCREEN_PIXEL_SIZE * edge_width_px;

	float y_px = base_uv.y / max(SCREEN_PIXEL_SIZE.y, 0.000001);
	vec2 jitter = vec2(hand_offset(y_px) * SCREEN_PIXEL_SIZE.x, 0.0);
	vec2 uv = base_uv + jitter;

	float s00 = luma(texture(screen_texture, uv + vec2(-px.x, -px.y)).rgb);
	float s10 = luma(texture(screen_texture, uv + vec2( 0.0, -px.y)).rgb);
	float s20 = luma(texture(screen_texture, uv + vec2( px.x, -px.y)).rgb);
	float s01 = luma(texture(screen_texture, uv + vec2(-px.x,  0.0)).rgb);
	float s21 = luma(texture(screen_texture, uv + vec2( px.x,  0.0)).rgb);
	float s02 = luma(texture(screen_texture, uv + vec2(-px.x,  px.y)).rgb);
	float s12 = luma(texture(screen_texture, uv + vec2( 0.0,  px.y)).rgb);
	float s22 = luma(texture(screen_texture, uv + vec2( px.x,  px.y)).rgb);

	float gx = s20 + 2.0 * s21 + s22 - s00 - 2.0 * s01 - s02;
	float gy = s00 + 2.0 * s10 + s20 - s02 - 2.0 * s12 - s22;
	float magnitude = length(vec2(gx, gy));
	float edge = smoothstep(edge_threshold, edge_threshold * 3.5, magnitude);

	// Exact per-pixel exclusion from the ID render pass.
	edge *= 1.0 - henry_mask(base_uv);

	vec3 scene_color = texture(screen_texture, base_uv).rgb;
	COLOR = vec4(mix(scene_color, edge_color.rgb, edge * edge_opacity), 1.0);
}
