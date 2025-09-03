shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix;

uniform vec4 particle_color : source_color = vec4(0.3, 0.3, 0.3, 0.7);  // Серый цвет по умолчанию

// Параметры частиц - ТВОИ ОРИГИНАЛЬНЫЕ
uniform int particle_count : hint_range(1, 40) = 20;
uniform float particle_speed : hint_range(0.05, 3.0) = 1.5;
uniform float particle_size : hint_range(0.01, 0.15) = 0.05;
uniform float particle_lifetime : hint_range(0.5, 4.0) = 2.0;

// ТОЛЬКО ДОБАВЛЯЕМ ЭТО ДЛЯ КОНТРОЛЯ РАЗБРОСА
uniform float spread_angle : hint_range(0.0, 3.14159) = 3.14159;

// Псевдослучай - ТВОЯ ОРИГИНАЛЬНАЯ ФУНКЦИЯ
float rand(vec2 co) {
    return fract(sin(dot(co.xy, vec2(12.9898,78.233))) * 43758.5453);
}

// ТВОЯ ОРИГИНАЛЬНАЯ ФУНКЦИЯ + только используем spread_angle вместо 3.14159
float generate_particle(vec2 uv, float particle_id, float time) {
    float spawn_time = particle_id * 0.3;
    float life = mod(time + spawn_time, particle_lifetime) / particle_lifetime;
    if (life <= 0.0 || life >= 1.0) return 0.0;

    // стартовая позиция внизу
    float start_x = (rand(vec2(particle_id, 1.0)) - 0.5) * 1.6;
    float start_y = 0.0;

    // ТВОЯ ЛОГИКА, но вместо 3.14159 используем spread_angle
    float angle = rand(vec2(particle_id, 2.0)) * spread_angle - (spread_angle * 0.5);
    vec2 direction = vec2(sin(angle), cos(angle));

    // позиция частицы
    vec2 particle_pos = vec2(start_x, start_y) + direction * life * particle_speed;

    // «рваная форма» — добавляем шум к радиусу
    float dist = length(uv - particle_pos);
    float noise = rand(uv * particle_id * 10.0 + time);
    float shape = smoothstep(particle_size * (1.0 + noise), 0.0, dist);

    // плавное затухание по времени
    float alpha = (1.0 - life) * (1.0 - life);
    return shape * alpha;
}

void fragment() {
    vec2 uv = UV * 2.0 - 1.0;
    float particles = 0.0;

    for (int i = 0; i < particle_count; i++) {
        particles += generate_particle(uv, float(i), TIME);
    }

    particles = clamp(particles, 0.0, 1.0);
    vec4 final_color = vec4(particle_color.rgb, particle_color.a * particles);
    ALBEDO = final_color.rgb;
    ALPHA = final_color.a;
}