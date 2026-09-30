shader_type canvas_item;
render_mode blend_disabled;

// Persistent packed-snow field, ping-ponged between two viewports.
// R: metres packed below the settled top. Fills back in with snowfall.
uniform sampler2D previous : filter_nearest, repeat_disable;
// Packing restored from stored tiles, already filled in for their age; read where
// the window has just moved onto ground the previous frame did not cover.
uniform sampler2D restore : filter_linear, repeat_disable;
uniform sampler2D contact_tex : filter_nearest, repeat_disable;
// Settled field: R snow top (world y), G depth, B cut away.
uniform sampler2D field : filter_linear, repeat_disable;
uniform float base_y = 0.0;
// UV offset applied once when the window moves.
uniform vec2 shift_uv = vec2(0.0);
// Share of the packing that fills back in this frame.
uniform float fill = 0.0;
// Share of the settled depth a foot or body can pack down.
uniform float max_pack = 0.85;
// A print's walls shedding into it this frame: uv centre, uv radius, fill share.
uniform vec4 collapse = vec4(0.0);

float lump_noise(vec2 p) {
	return fract(sin(dot(floor(p), vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	vec2 from = uv + shift_uv;
	float packed = texture(restore, uv).r;
	if (from.x >= 0.0 && from.y >= 0.0 && from.x <= 1.0 && from.y <= 1.0) {
		packed = texture(previous, from).r;
	}
	packed *= 1.0 - fill;
	// Fallen clumps raise the floor in lumps, most near the wall they broke from.
	if (collapse.w > 0.0) {
		float r = distance(uv, collapse.xy) / max(collapse.z, 1e-6);
		if (r < 1.0) {
			float lumps = lump_noise(uv * 1024.0 / 3.0);
			packed *= 1.0 - collapse.w * (0.4 + 0.6 * lumps) * smoothstep(0.0, 1.0, r + 0.3);
		}
	}
	vec3 settled = texture(field, uv).rgb;
	// B below 0.5 is softness (x0.49): wind crust holds a foot, powder lets it sink.
	float give = settled.g * max_pack * clamp(settled.b / 0.49, 0.0, 1.0);
	packed = min(packed, give);
	// The contact camera looks up, so its image runs +x east and down-screen north.
	float contact = texture(contact_tex, vec2(uv.x, 1.0 - uv.y)).r + base_y;
	float into = settled.r - contact;
	if (settled.b < 0.5 && into > 0.0 && contact > settled.r - settled.g - 0.3) {
		packed = max(packed, min(into, give));
	}
	COLOR = vec4(packed, 0.0, 0.0, 1.0);
}
