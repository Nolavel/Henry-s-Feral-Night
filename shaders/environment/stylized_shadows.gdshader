shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

// HFN stock-Godot adaptation of "Stylized shadows, not a post processing"
// by ShaderError.
// Source: https://godotshaders.com/shader/stylized-shadows-not-a-post-processing/
// Original shader code is CC0.
//
// The original sample calls a custom sample_directional_shadow() built-in and
// therefore requires a modified Godot shader pipeline. This version stays on
// stock Godot: ATTENUATION already contains the real shadow-map result, so two
// triplanar noise bands perturb the shadow transition inside light().

uniform sampler2D noise_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;

uniform bool use_albedo_texture = false;
uniform vec4 albedo_tint : source_color = vec4(0.64, 0.68, 0.72, 1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.92;

uniform float noise_strength_1 : hint_range(0.0, 1.0) = 0.18;
uniform float noise_strength_2 : hint_range(0.0, 1.0) = 0.08;
uniform vec3 uv_scale_1 = vec3(0.42);
uniform vec3 uv_offset_1 = vec3(0.0);
uniform vec3 uv_scale_2 = vec3(1.35);
uniform vec3 uv_offset_2 = vec3(11.7, -4.3, 7.1);

uniform bool use_world = true;
uniform float shadow_strength : hint_range(0.0, 1.0) = 0.95;
uniform float shadow_threshold : hint_range(0.0, 1.0) = 0.52;
uniform float shadow_softness : hint_range(0.001, 0.35) = 0.035;
uniform float shadow_floor : hint_range(0.0, 0.5) = 0.035;
uniform float shadow_pattern_light : hint_range(0.0, 0.5) = 0.17;
uniform float shadow_pattern_threshold : hint_range(0.0, 1.0) = 0.52;

varying vec3 sample_position;
varying vec3 sample_normal;
varying float shadow_noise;


float triplanar_noise(sampler2D tex, vec3 p, vec3 n) {
	vec3 weight = abs(n);
	weight = max(weight, vec3(0.0001));
	weight /= weight.x + weight.y + weight.z;

	float x = texture(tex, p.yz).r;
	float y = texture(tex, p.xz).r;
	float z = texture(tex, p.xy).r;
	return x * weight.x + y * weight.y + z * weight.z;
}


void vertex() {
	if (use_world) {
		sample_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		sample_normal = normalize(mat3(MODEL_MATRIX) * NORMAL);
	} else {
		sample_position = VERTEX;
		sample_normal = NORMAL;
	}
}


void fragment() {
	float n1 = triplanar_noise(
		noise_texture,
		sample_position * uv_scale_1 + uv_offset_1,
		sample_normal
	);
	float n2 = triplanar_noise(
		noise_texture,
		sample_position * uv_scale_2 + uv_offset_2,
		sample_normal
	);

	shadow_noise =
		(n1 - 0.5) * noise_strength_1
		+ (n2 - 0.5) * noise_strength_2;

	vec4 base = albedo_tint;
	if (use_albedo_texture) {
		base *= texture(albedo_texture, UV);
	}

	ALBEDO = base.rgb;
	ROUGHNESS = roughness;
	METALLIC = 0.0;
	SPECULAR = 0.0;
}


void light() {
	float ndotl = max(dot(NORMAL, LIGHT), 0.0);

	if (LIGHT_IS_DIRECTIONAL) {
		float noisy_shadow_sample = clamp(ATTENUATION + shadow_noise, 0.0, 1.0);
		float stylized_edge = smoothstep(
			shadow_threshold - shadow_softness,
			shadow_threshold + shadow_softness,
			noisy_shadow_sample
		);

		float pattern_sample = clamp(0.5 + shadow_noise * 2.8, 0.0, 1.0);
		float graphic_pattern = step(shadow_pattern_threshold, pattern_sample);
		float shadow_fill = mix(shadow_floor, shadow_pattern_light, graphic_pattern);
		float stylized_shadow = mix(shadow_fill, 1.0, stylized_edge);

		// Keep the graphic pattern strictly inside a real cast shadow.
		// Soft shadow-map filtering can return values just below 1.0 even on lit
		// pixels, so a 0.999 cutoff leaks noise onto the white receiver.
		float is_shadowed = 1.0 - smoothstep(0.82, 0.96, ATTENUATION);
		float shadow_term = mix(ATTENUATION, stylized_shadow, shadow_strength * is_shadowed);

		DIFFUSE_LIGHT += ndotl * shadow_term * LIGHT_COLOR / PI;
	} else {
		DIFFUSE_LIGHT += ndotl * ATTENUATION * LIGHT_COLOR / PI;
	}
}
