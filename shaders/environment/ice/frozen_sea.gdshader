shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

#include "res://shaders/environment/stylized_shadow.gdshaderinc"

uniform sampler2D ocean_mask : filter_nearest, repeat_disable;
uniform vec2 world_origin;
uniform vec2 world_size;
varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = (world_pos.xz - world_origin) / world_size;
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		discard;
	}
	if (texture(ocean_mask, uv).r < 0.5) {
		discard;
	}
	ALBEDO = vec3(0.38, 0.46, 0.54);
	ROUGHNESS = 0.38;
	METALLIC = 0.05;
}

void light() {
	float ndotl = max(dot(NORMAL, LIGHT), 0.0);
	float attenuation = hfn_stylized_shadow_attenuation(
		ATTENUATION,
		world_pos,
		LIGHT_IS_DIRECTIONAL,
		LIGHT_INDEX,
		VIEW_MATRIX,
		true
	);
	DIFFUSE_LIGHT += ndotl * attenuation * LIGHT_COLOR / PI;
}
