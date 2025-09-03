
shader_type canvas_item;

// === 3D PERSPECTIVE UNIFORMS ===
uniform float fov : hint_range(1.0, 179.0) = 90.0;
uniform bool cull_back = true;
uniform float y_rot : hint_range(-180.0, 180.0) = 0.0;
uniform float x_rot : hint_range(-180.0, 180.0) = 0.0;
uniform float inset : hint_range(0.0, 1.0) = 0.0;
uniform bool use_rect_size = false;
uniform vec2 rect_size = vec2(100.0, 100.0);

// === BURN/DISSOLVE UNIFORMS ===
uniform float progress : hint_range(-1.5, 1.5) = -1.5;
uniform float noiseForce : hint_range(0.0, 1.0) = 0.4;
uniform sampler2D noiseTexture;
uniform vec4 burnColor : source_color = vec4(1.0, 0.5, 0.0, 1.0);
uniform float borderWidth : hint_range(0.0, 0.5) = 0.1;
uniform float direction : hint_range(0.0, 360.0) = 180.0;

// === CONTROL UNIFORMS ===
uniform bool enable_3d_effect = true;
uniform bool enable_burn_effect = false;

varying vec2 o;
varying vec3 p;

vec2 degreesToPerpendicular(){
	return vec2(cos(radians(direction)), -sin(radians(direction)));
}

void vertex(){
	if (enable_3d_effect) {
		// === 3D PERSPECTIVE VERTEX PROCESSING ===
		float y_rad = y_rot * PI / 180.0;
		float x_rad = x_rot * PI / 180.0;

		float sin_b = sin(y_rad);
		float cos_b = cos(y_rad);
		float sin_c = sin(x_rad);
		float cos_c = cos(x_rad);

		mat3 inv_rot_mat = mat3(
			vec3(cos_b, 0.0, -sin_b),
			vec3(sin_b * sin_c, cos_c, cos_b * sin_c),
			vec3(sin_b * cos_c, -sin_c, cos_b * cos_c)
		);

		float t = tan(fov * PI / 360.0);
		p = inv_rot_mat * vec3((UV - 0.5), 0.5 / t);
		float v = (0.5 / t) + 0.5;
		p.xy *= v * inv_rot_mat[2].z;
		o = v * inv_rot_mat[2].xy;

		if (use_rect_size) {
			VERTEX += (UV - 0.5) * rect_size * t * (1.0 - inset);
		} else {
			VERTEX += (UV - 0.5) / TEXTURE_PIXEL_SIZE * t * (1.0 - inset);
		}
	} else {
		// === STANDARD VERTEX PROCESSING ===
		o = vec2(0.0);
		p = vec3(UV - 0.5, 1.0);
	}
}

void fragment(){
	vec2 final_uv = UV;

	if (enable_3d_effect) {
		// === 3D PERSPECTIVE FRAGMENT PROCESSING ===
		if (cull_back && p.z <= 0.0) {
			discard;
		}

		vec2 perspective_uv = (p.xy / p.z) - o;

		if (abs(perspective_uv.x) > 0.5 || abs(perspective_uv.y) > 0.5) {
			discard;
		}

		final_uv = perspective_uv + 0.5;
	}

	// Получаем цвет текстуры
	vec4 tex_color = texture(TEXTURE, final_uv);

	if (enable_burn_effect && tex_color.a > 0.0) {
		// === ИСПРАВЛЕННЫЙ BURN ЭФФЕКТ ===

		// Нормализованные UV от -1 до 1
		vec2 normUV = final_uv * 2.0 - 1.0;

		// Получаем направление burn
		vec2 burn_direction = degreesToPerpendicular();

		// Базовый градиент по направлению
		float base_gradient = dot(normUV, burn_direction);

		// Добавляем шум
		float noise_sample = texture(noiseTexture, final_uv).r;
		float noise_offset = (noise_sample - 0.5) * noiseForce;

		// ИСПРАВЛЕННАЯ ФОРМУЛА: более простая и работающая
		float burn_threshold = base_gradient + noise_offset;

		// Главная проверка burn
		if (burn_threshold < progress) {
			// Этот пиксель должен быть сожжен
			discard;
		}

		// Проверяем границу огня
		float border_distance = burn_threshold - progress;
		if (border_distance < borderWidth) {
			// Мы на границе - смешиваем с цветом огня
			float border_factor = border_distance / borderWidth;
			border_factor = clamp(border_factor, 0.0, 1.0);

			// Плавный переход к цвету огня
			tex_color.rgb = mix(burnColor.rgb, tex_color.rgb, border_factor);

			// Добавляем яркость на границе
			tex_color.rgb += burnColor.rgb * (1.0 - border_factor) * 0.5;
		}
	}

	COLOR = tex_color;
}