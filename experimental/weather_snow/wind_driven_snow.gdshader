// Experimental HFN snow adaptation of ProfesorShader's
// "Wind Driven Falling Particles" (CC0).
// Source: https://godotshaders.com/shader/wind-driven-falling-particles-leaves-petals-feathers/
//
// The original self-driven wind range/change and vortex are intentionally
// removed. WeatherController is the single source of wind direction/speed.

shader_type particles;
render_mode keep_data;

uniform vec4 color : source_color = vec4(0.94, 0.97, 1.0, 0.92);
uniform vec3 box_emit_size = vec3(22.0, 2.0, 16.0);
uniform vec3 wind_velocity = vec3(0.0);
uniform float fall_speed_min : hint_range(0.1, 5.0, 0.05) = 0.9;
uniform float fall_speed_max : hint_range(0.1, 5.0, 0.05) = 1.7;
uniform float turbulence_strength : hint_range(0.0, 4.0, 0.05) = 0.25;
uniform float drag : hint_range(0.1, 12.0, 0.1) = 3.2;
uniform float size_min : hint_range(0.1, 2.0, 0.05) = 0.55;
uniform float size_max : hint_range(0.1, 2.0, 0.05) = 1.25;
uniform float fade_from : hint_range(0.0, 1.0, 0.01) = 0.82;

uint hfn_hash(uint x) {
	x = ((x >> uint(16)) ^ x) * uint(73244475);
	x = ((x >> uint(16)) ^ x) * uint(73244475);
	x = (x >> uint(16)) ^ x;
	return x;
}

float hfn_rand(inout uint seed) {
	int k;
	int s = int(seed);
	if (s == 0) {
		s = 305420679;
	}
	k = s / 127773;
	s = 16807 * (s - k * 127773) - 2836 * k;
	if (s < 0) {
		s += 2147483647;
	}
	seed = uint(s);
	return float(seed % uint(65536)) / 65535.0;
}

void start() {
	uint seed = hfn_hash(NUMBER + uint(1) + RANDOM_SEED);

	if (RESTART_ROT_SCALE) {
		float size = mix(size_min, size_max, hfn_rand(seed));
		TRANSFORM[0].xyz = vec3(size, 0.0, 0.0);
		TRANSFORM[1].xyz = vec3(0.0, size, 0.0);
		TRANSFORM[2].xyz = vec3(0.0, 0.0, size);
	}

	if (RESTART_POSITION) {
		vec3 p = vec3(
			(hfn_rand(seed) - 0.5) * box_emit_size.x,
			(hfn_rand(seed) - 0.5) * box_emit_size.y,
			(hfn_rand(seed) - 0.5) * box_emit_size.z
		);
		TRANSFORM[3].xyz = p;
		// With GPUParticles3D.local_coords = false, new particles are born in
		// the emitter's current world transform while older flakes stay behind.
		TRANSFORM = EMISSION_TRANSFORM * TRANSFORM;
	}

	if (RESTART_VELOCITY) {
		USERDATA1 = vec4(
			0.0,
			mix(fall_speed_min, fall_speed_max, hfn_rand(seed)),
			hfn_rand(seed) * TAU,
			hfn_rand(seed) * TAU
		);
		vec3 initial_flutter = vec3(
			(hfn_rand(seed) - 0.5) * 0.4,
			0.0,
			(hfn_rand(seed) - 0.5) * 0.4
		);
		VELOCITY = wind_velocity * 0.2 + initial_flutter;
		VELOCITY.y = -USERDATA1.y;
	}

	if (RESTART_COLOR) {
		COLOR = color;
	}
}

void process() {
	USERDATA1.x += DELTA;
	float normalized_age = clamp(USERDATA1.x / max(LIFETIME, 0.001), 0.0, 1.0);

	float flutter_x = sin(TIME * 2.3 + USERDATA1.z) * turbulence_strength;
	float flutter_z = cos(TIME * 1.9 + USERDATA1.w) * turbulence_strength;
	float flutter_y = sin(TIME * 2.7 + USERDATA1.z + USERDATA1.w)
		* turbulence_strength * 0.12;

	vec3 target_velocity = wind_velocity + vec3(
		flutter_x,
		-USERDATA1.y + flutter_y,
		flutter_z
	);
	float response = clamp(1.0 - exp(-drag * DELTA), 0.0, 1.0);
	VELOCITY = mix(VELOCITY, target_velocity, response);

	COLOR.a = color.a * (1.0 - smoothstep(fade_from, 1.0, normalized_age));
}
