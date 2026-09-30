shader_type canvas_item;
render_mode blend_disabled;

// Shapes the packed-snow field into what is drawn: pit walls slope at the angle
// the snow can hold, then a small blur rounds texel edges. Stored packing erodes
// towards the same slope on its own (snow_accumulate), so the two converge.
// Pass 0 and 1 are a separable dilation by a slope cone along x then y; pass 2
// is a 5x5 Gaussian. R: metres packed, negative where displaced snow heaps.
uniform sampler2D source : filter_nearest, repeat_disable;
// Settled field: B below 0.5 is softness scaled by 0.49, above is cut away.
uniform sampler2D field : filter_linear, repeat_disable;
uniform int pass = 0;
// Metres a wall drops per texel of run: tan(slope) * texel size, powder and crust.
uniform float drop_powder = 0.021;
uniform float drop_crust = 0.14;
// Farthest a wall reaches, in texels.
uniform int reach = 24;

void fragment() {
	vec2 texel = 1.0 / vec2(textureSize(source, 0));
	float out_v = 0.0;
	if (pass < 2) {
		float b = texture(field, UV).b;
		float powder = b < 0.5 ? smoothstep(0.45, 0.95, b / 0.49) : 0.0;
		float drop = mix(drop_crust, drop_powder, powder);
		vec2 axis = pass == 0 ? vec2(texel.x, 0.0) : vec2(0.0, texel.y);
		out_v = texture(source, UV).r;
		for (int i = 1; i <= reach; i++) {
			float fall = drop * float(i);
			if (fall > 1.2) {
				break;
			}
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
