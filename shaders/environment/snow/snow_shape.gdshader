shader_type canvas_item;
render_mode blend_disabled;

// Shapes the packed-snow field into what is drawn: pit walls slope at the angle
// of repose, then a small blur rounds texel edges. Stored packing is untouched.
// Pass 0 and 1 are a separable dilation by a repose cone along x then y; pass 2
// is a 5x5 Gaussian. R: metres packed.
uniform sampler2D source : filter_nearest, repeat_disable;
uniform int pass = 0;
// Metres a wall drops per texel of run: tan(repose) * texel size.
uniform float drop_per_texel = 0.021;
// Farthest a wall reaches, in texels.
uniform int reach = 24;

void fragment() {
	vec2 texel = 1.0 / vec2(textureSize(source, 0));
	float out_v = 0.0;
	if (pass < 2) {
		vec2 axis = pass == 0 ? vec2(texel.x, 0.0) : vec2(0.0, texel.y);
		out_v = texture(source, UV).r;
		for (int i = 1; i <= reach; i++) {
			float fall = drop_per_texel * float(i);
			out_v = max(out_v, texture(source, UV + axis * float(i)).r - fall);
			out_v = max(out_v, texture(source, UV - axis * float(i)).r - fall);
		}
	} else {
		float weights[3] = float[3](0.375, 0.25, 0.0625);
		for (int y = -2; y <= 2; y++) {
			for (int x = -2; x <= 2; x++) {
				out_v += texture(source, UV + vec2(float(x), float(y)) * texel).r
					* weights[abs(x)] * weights[abs(y)];
			}
		}
	}
	COLOR = vec4(out_v, 0.0, 0.0, 1.0);
}
