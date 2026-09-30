#include "res://shaders/environment/stylized_shadow.gdshaderinc"

uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.9;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform bool use_vertex_color = false;
uniform bool use_albedo_texture = false;
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_normal_texture = false;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float normal_scale : hint_range(-16.0, 16.0) = 1.0;
uniform vec2 uv_scale = vec2(1.0);
uniform vec2 uv_offset = vec2(0.0);
uniform vec3 emission_color : source_color = vec3(0.0);
uniform float emission_energy : hint_range(0.0, 16.0) = 0.0;
// Historical parameter name retained so converted shelter materials can opt out.
uniform bool stylized_shadow_warp_enabled = true;

varying vec3 stylized_world_pos;

void vertex() {
	stylized_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (stylized_shadow_warp_enabled) {
		LIGHT_VERTEX = VERTEX + HFN_STYLIZED_SHADOW_WARP(stylized_world_pos, VIEW_MATRIX);
	}
	vec2 uv = UV * uv_scale + uv_offset;
	vec4 base = albedo_color;
	if (use_vertex_color) {
		base *= COLOR;
	}
	if (use_albedo_texture) {
		base *= texture(albedo_texture, uv);
	}
	ALBEDO = base.rgb;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	if (use_normal_texture) {
		NORMAL_MAP = texture(normal_texture, uv).rgb;
		NORMAL_MAP_DEPTH = normal_scale;
	}
	EMISSION = emission_color * emission_energy;
}

void light() {
	float ndotl = max(dot(NORMAL, LIGHT), 0.0);
	float attenuation = hfn_stylized_shadow_attenuation(
		ATTENUATION,
		stylized_world_pos,
		LIGHT_IS_DIRECTIONAL,
		HFN_LIGHT_INDEX,
		VIEW_MATRIX,
		stylized_shadow_warp_enabled
	);
	DIFFUSE_LIGHT += ndotl * attenuation * LIGHT_COLOR / PI;

	// Cheap restrained specular keeps metal/glass-adjacent props readable
	// without reintroducing the built-in PBR path that bypasses our light().
	vec3 half_dir = normalize(LIGHT + VIEW);
	float spec_power = mix(128.0, 4.0, roughness);
	float spec = pow(max(dot(NORMAL, half_dir), 0.0), spec_power);
	float spec_gain = mix(0.05, 0.24, metallic) * (1.0 - roughness);
	SPECULAR_LIGHT += spec * spec_gain * attenuation * LIGHT_COLOR;
}
