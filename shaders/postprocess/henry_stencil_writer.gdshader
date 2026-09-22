shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;

// Exact Henry stencil writer.
// Transparent, colorless overlay so the original character shading is untouched.
stencil_mode write, compare_always, 1;

uniform float stencil_grow = 0.022;

void vertex() {
	// Slightly dilate the player stencil so Sobel samples immediately outside
	// Henry do not create a dark halo around his silhouette.
	VERTEX += NORMAL * stencil_grow;
}

void fragment() {
	ALBEDO = vec3(0.0);
	// Keep the pass in transparent rendering while remaining visually
	// imperceptible. The stencil write is the only intended result.
	ALPHA = 0.001;
}
