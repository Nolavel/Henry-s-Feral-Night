// Swept contacts prevent a fast flake from stepping through a thin moving leaf.
uniform bool snow_door_enabled = false;
uniform mat4 snow_leaf_inverse;
uniform vec3 snow_leaf_min;
uniform vec3 snow_leaf_max;
uniform mat4 snow_frame_inverse;
uniform vec2 snow_opening_size = vec2(1.5, 2.25);

bool snow_segment_box(vec3 a, vec3 b, vec3 lo, vec3 hi) {
	vec3 d = b - a;
	float near_t = 0.0;
	float far_t = 1.0;
	for (int axis = 0; axis < 3; axis++) {
		if (abs(d[axis]) < 0.000001) {
			if (a[axis] < lo[axis] || a[axis] > hi[axis]) { return false; }
		} else {
			float first = (lo[axis] - a[axis]) / d[axis];
			float last = (hi[axis] - a[axis]) / d[axis];
			near_t = max(near_t, min(first, last));
			far_t = min(far_t, max(first, last));
			if (near_t > far_t) { return false; }
		}
	}
	return true;
}

bool snow_door_hit(vec3 from, vec3 to) {
	if (!snow_door_enabled) { return false; }
	vec3 a = (snow_leaf_inverse * vec4(from, 1.0)).xyz;
	vec3 b = (snow_leaf_inverse * vec4(to, 1.0)).xyz;
	if (snow_segment_box(a, b, snow_leaf_min, snow_leaf_max)) { return true; }
	a = (snow_frame_inverse * vec4(from, 1.0)).xyz;
	b = (snow_frame_inverse * vec4(to, 1.0)).xyz;
	vec2 half_size = snow_opening_size * 0.5;
	return snow_segment_box(a, b, vec3(-half_size.x - 0.12, -half_size.y, -0.1), vec3(-half_size.x, half_size.y + 0.12, 0.1))
		|| snow_segment_box(a, b, vec3(half_size.x, -half_size.y, -0.1), vec3(half_size.x + 0.12, half_size.y + 0.12, 0.1))
		|| snow_segment_box(a, b, vec3(-half_size.x, half_size.y, -0.1), vec3(half_size.x, half_size.y + 0.12, 0.1));
}
