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
		vec3 wind = vec3(wind_speed.x, 0.0, wind_speed.y) * TIME * 0.1;
		vec3 tiling = vec3(noise_tiling.x, 1.0, noise_tiling.y) * 0.2;
		vec3 cloud_position = EYEDIR * t * tiling + wind;

		float cloud_height = sample_cloud_height(cloud_position.xz);
		cloud_position += EYEDIR * cloud_height * cloud_depth * 0.1;
		cloud_height = sample_cloud_height(cloud_position.xz);

		float view_up = clamp(dot(vec3(0.0, 1.0, 0.0), EYEDIR), 0.0, 1.0);
		float transmission = beer_law(cloud_density, 1.0 - cloud_height * view_up);
		upper_sky += light_color * transmission;
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
