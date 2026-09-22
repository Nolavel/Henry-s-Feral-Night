shader_type sky;

// Adapted for Henry's Feral Night from "Simple Overcast" by tentabrobpy.
// Original shader: https://godotshaders.com/shader/simple-overcast/
// Source code is published under CC0.

group_uniforms Sky;
uniform bool use_directional_light = true;
uniform vec4 sun_color : source_color = vec4(1.0);
uniform float sun_energy = 6.0;
uniform float directional_energy_scale = 5.0;
uniform vec4 cloud_color : source_color = vec4(0.30, 0.39, 0.48, 1.0);
uniform float cloud_density = 4.8;
uniform float cloud_depth = 2.0;
uniform float cloud_sag = 2.0;
uniform sampler2D noise_texture : filter_linear_mipmap, repeat_enable;
uniform vec2 noise_tiling = vec2(1.0);
uniform vec2 wind_speed = vec2(0.24, 0.08);

// Multi-layer angular parallax. Because a sky shader is infinitely distant,
// this is a layered directional parallax rather than world-position parallax.
uniform float parallax_strength : hint_range(0.0, 1.0) = 0.22;
uniform float parallax_layer_separation : hint_range(0.0, 1.0) = 0.35;
uniform float parallax_detail_weight : hint_range(0.0, 1.0) = 0.45;
uniform float parallax_mid_scale : hint_range(1.0, 4.0) = 1.65;
uniform float parallax_high_scale : hint_range(1.0, 6.0) = 2.55;
uniform float cloud_shape_contrast : hint_range(0.0, 1.0) = 0.52;
uniform float cloud_shadow_strength : hint_range(0.0, 1.0) = 0.34;
group_uniforms;

group_uniforms Ground;
uniform vec4 ground_bottom_color : source_color = vec4(0.22, 0.21, 0.20, 1.0);
uniform float ground_curve : hint_range(0.001, 1.0) = 0.04;
group_uniforms;

uniform float exposure : hint_range(0.0, 128.0) = 0.82;


float ray_plane_intersection(
	vec3 plane_origin,
	vec3 plane_normal,
	vec3 ray_origin,
	vec3 ray_direction
) {
	float denominator = dot(ray_direction, plane_normal);
	if (abs(denominator) < 0.0001) {
		return -1.0;
	}
	return dot(plane_origin - ray_origin, plane_normal) / denominator;
}


float sample_cloud_height(vec2 uv) {
	float value = texture(noise_texture, uv).r;
	return pow(clamp(value, 0.0, 1.0), max(cloud_sag, 0.001));
}


float sample_layered_clouds(
	vec2 base_uv,
	vec2 view_slant,
	vec2 wind_uv
) {
	float base = sample_cloud_height(base_uv + wind_uv);

	vec2 mid_offset =
		view_slant * parallax_strength * parallax_layer_separation
		+ wind_uv * 0.37
		+ vec2(13.71, -8.23);
	float middle = sample_cloud_height(
		base_uv * parallax_mid_scale + mid_offset
	);

	vec2 high_offset =
		view_slant * parallax_strength * parallax_layer_separation * 1.9
		+ wind_uv * 0.73
		+ vec2(-19.42, 15.31);
	float high = sample_cloud_height(
		base_uv * parallax_high_scale + high_offset
	);

	float layered = base;
	layered = mix(layered, max(base * 0.78, middle), parallax_detail_weight * 0.62);
	layered = mix(layered, clamp(layered * 0.86 + high * 0.22, 0.0, 1.0), parallax_detail_weight * 0.48);
	return clamp(layered, 0.0, 1.0);
}


float beer_law(float absorption, float distance_through_cloud) {
	return exp(-absorption * max(distance_through_cloud, 0.0));
}


vec3 get_light_color() {
	if (use_directional_light && LIGHT0_ENABLED) {
		float elevation = max(dot(LIGHT0_DIRECTION, vec3(0.0, 1.0, 0.0)), 0.0);
		return LIGHT0_COLOR * LIGHT0_ENERGY * elevation * directional_energy_scale;
	}
	return sun_color.rgb * sun_energy;
}


void sky() {
	vec3 light_color = get_light_color();
	vec3 upper_sky = cloud_color.rgb;

	float t = ray_plane_intersection(
		vec3(0.0, 1.0, 0.0),
		vec3(0.0, -1.0, 0.0),
		vec3(0.0),
		EYEDIR
	);

	if (t >= 0.0) {
		vec2 wind_uv = wind_speed * TIME * 0.1;
		vec3 tiling = vec3(noise_tiling.x, 1.0, noise_tiling.y) * 0.2;
		vec3 cloud_position = EYEDIR * t * tiling;

		float safe_up = max(EYEDIR.y, 0.08);
		vec2 view_slant = EYEDIR.xz / safe_up;

		float cloud_height = sample_layered_clouds(
			cloud_position.xz,
			view_slant,
			wind_uv
		);

		// Second depth sample: shifts the apparent cloud body along the ray and
		// strengthens the layered separation without adding another texture.
		vec3 depth_position = cloud_position
			+ EYEDIR * cloud_height * cloud_depth * 0.12;
		float depth_height = sample_layered_clouds(
			depth_position.xz,
			view_slant * 1.08,
			wind_uv * 1.05
		);
		cloud_height = mix(cloud_height, depth_height, 0.42);

		float view_up = clamp(dot(vec3(0.0, 1.0, 0.0), EYEDIR), 0.0, 1.0);
		float transmission = beer_law(
			cloud_density,
			1.0 - cloud_height * view_up
		);

		// Readable overcast volume: darker dense bodies, brighter thin edges.
		// This keeps parallax visible even when directional light is weak.
		float shape = smoothstep(0.18, 0.82, cloud_height);
		vec3 cloud_shadow = cloud_color.rgb * (1.0 - cloud_shadow_strength);
		vec3 cloud_lit = cloud_color.rgb * (1.0 + cloud_shape_contrast * 0.42);
		upper_sky = mix(cloud_lit, cloud_shadow, shape);

		float rim = pow(clamp(1.0 - abs(cloud_height - 0.48) * 2.0, 0.0, 1.0), 2.0);
		upper_sky += light_color * transmission * (0.42 + rim * 0.32);
	}

	vec3 horizon = cloud_color.rgb + light_color * beer_law(cloud_density, 1.0);
	float safe_curve = max(ground_curve, 0.001);
	float ground_mix = clamp(
		1.0 - pow(max(1.0 + EYEDIR.y, 0.0001), 1.0 / safe_curve),
		0.0,
		1.0
	);
	vec3 ground = mix(horizon, ground_bottom_color.rgb, ground_mix);

	COLOR = mix(ground, upper_sky, step(0.0, EYEDIR.y)) * exposure;
}
