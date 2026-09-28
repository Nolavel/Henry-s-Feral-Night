shader_type particles;
render_mode keep_data, collision_use_scale;

#include "res://shaders/environment/weather/snow_door_barrier.gdshaderinc"

uniform vec3 emission_box_extents = vec3(0.1);
uniform float speed_min = 0.35;
uniform float speed_max = 0.7;

float draft_rand(inout uint seed) {
	seed = seed * uint(1664525) + uint(1013904223);
	return float(seed & uint(65535)) / 65535.0;
}

void start() {
	uint seed = NUMBER + RANDOM_SEED;
	vec3 offset = vec3(draft_rand(seed), draft_rand(seed), draft_rand(seed)) * 2.0 - 1.0;
	TRANSFORM = EMISSION_TRANSFORM;
	TRANSFORM[3].xyz = (EMISSION_TRANSFORM * vec4(offset * emission_box_extents, 1.0)).xyz;
	float size = mix(0.65, 1.1, draft_rand(seed));
	TRANSFORM[0].xyz *= size;
	TRANSFORM[1].xyz *= size;
	TRANSFORM[2].xyz *= size;
	vec3 direction = vec3((draft_rand(seed) - 0.5) * 0.1, -0.1, 1.0);
	VELOCITY = (EMISSION_TRANSFORM * vec4(direction * mix(speed_min, speed_max, draft_rand(seed)), 0.0)).xyz;
	USERDATA1 = vec4(0.0);
	USERDATA2 = vec4(TRANSFORM[3].xyz, 1.0);
	COLOR = vec4(0.95, 0.97, 1.0, 0.75);
}

void process() {
	if (COLLIDED || snow_door_hit(USERDATA2.xyz, TRANSFORM[3].xyz)
		|| snow_door_hit(TRANSFORM[3].xyz, TRANSFORM[3].xyz + VELOCITY * DELTA)) {
		ACTIVE = false;
	}
	USERDATA2 = vec4(TRANSFORM[3].xyz, 1.0);
	USERDATA1.x += DELTA;
	VELOCITY.y -= 1.2 * DELTA;
	COLOR.a = 0.75 * (1.0 - smoothstep(0.7, 1.0, USERDATA1.x / LIFETIME));
}
