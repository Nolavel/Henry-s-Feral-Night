shader_type canvas_item;

// =========================
// Градиентное исчезновение
// =========================
uniform float fade_start : hint_range(0.0, 1.0) = 0.75;     // Начало исчезновения
uniform float fade_end   : hint_range(0.0, 1.0) = 1.0;     // Конец исчезновения
uniform float fade_curve : hint_range(0.1, 4.0) = 0.55;     // Кривая фейда
uniform int   fade_direction : hint_range(0, 3) = 2;       // 0=Right, 1=Left, 2=Up, 3=Down

// Базовая подложка (если текстура имеет прозрачность)
uniform vec4 base_color : source_color = vec4(0.0, 0.0, 0.0, 0.0);

// =========================
/* Частицы, летящие в сторону градиента */
// =========================
uniform bool  enable_particles = true;
uniform int   particle_count   : hint_range(0, 64) = 20;
uniform float particle_speed   : hint_range(0.0, 1.0) = 0.25;   // скорость вдоль направления
uniform float particle_size    : hint_range(0.001, 0.08) = 0.08;
uniform float particle_softness: hint_range(0.0, 0.08) = 0.02;
uniform float particle_lifetime: hint_range(0.2, 6.0) = 2.5;
uniform vec4  particle_color   : source_color = vec4(0.85, 0.95, 0.4, 1.0);
uniform float particle_spread  : hint_range(0.0, 0.5) = 0.0;   // поперечный джиттер

// Управление полосой спавна (пучком)
uniform float particle_band_center : hint_range(0.0, 1.0) = 0.45; // центр полосы (0..1)
uniform float particle_band_width  : hint_range(0.0, 1.0) = 0.9; // ширина полосы (0..1)
uniform float particle_band_taper  : hint_range(0.0, 1.0) = 0.55; // сужение плотности к краям (0 — без)


// -------------------------
// Вспомогательные функции
// -------------------------
float rand(vec2 co) {
    return fract(sin(dot(co, vec2(12.9898, 78.233))) * 43758.5453);
}

// Направление градиента как вектор
vec2 gradient_dir() {
    if (fade_direction == 0) return vec2( 1.0,  0.0); // Right
    if (fade_direction == 1) return vec2(-1.0,  0.0); // Left
    if (fade_direction == 2) return vec2( 0.0, -1.0); // Up
    return vec2( 0.0,  1.0);                           // Down
}

// Перпендикуляр к направлению
vec2 perp_dir(vec2 d) {
    return vec2(-d.y, d.x);
}

// Скалярный прогресс вдоль направления (0..1, где 1 — прозрачная сторона)
float gradient_progress(vec2 uv) {
    if (fade_direction == 0) return uv.x;
    if (fade_direction == 1) return 1.0 - uv.x;
    if (fade_direction == 2) return 1.0 - uv.y;
    return uv.y;
}

// Альфа по градиенту — ровная граница
float gradient_alpha(float p) {
    float pc = pow(p, fade_curve);
    if (pc <= fade_start) return 1.0;
    if (pc >= fade_end)   return 0.0;
    float t = (pc - fade_start) / max(0.0001, (fade_end - fade_start));
    return 1.0 - smoothstep(0.0, 1.0, t);
}


// =========================
// Частица (спавн на fade_start, пучок по полосе)
// =========================
float particle_mask(vec2 uv, float id, float time) {
    if (!enable_particles) return 0.0;

    float life = mod(time + id * 0.13, particle_lifetime) / particle_lifetime; // 0..1
    if (life <= 0.0 || life >= 1.0) return 0.0;

    vec2 dir  = gradient_dir();
    vec2 perp = normalize(perp_dir(dir));

    // Полоса спавна вдоль перпендикуляра: центр + ширина
    float u = rand(vec2(id, 0.73)); // базовый случайный 0..1
    float half_w = particle_band_width * 0.5;
    float ort = particle_band_center + (u - 0.5) * particle_band_width;
    ort = clamp(ort, 0.0, 1.0);

    // Сужение плотности к краям полосы
    float edge_norm = clamp(abs(ort - particle_band_center) / max(half_w, 1e-4), 0.0, 1.0);
    float band_gain = 1.0 - smoothstep(0.0, particle_band_taper, edge_norm);

    // Прогресс вдоль направления: старт на fade_start, полёт к fade_end (+ небольшой зазор)
    float p_start = fade_start;
    float p_end   = clamp(fade_end + 0.02, 0.0, 1.0);
    float p = mix(p_start, p_end, life);

    // Позиция частицы в UV
    vec2 pos;
    if (fade_direction == 0) {
        pos = vec2(p, ort);
    } else if (fade_direction == 1) {
        pos = vec2(1.0 - p, ort);
    } else if (fade_direction == 2) {
        pos = vec2(ort, 1.0 - p);
    } else {
        pos = vec2(ort, p);
    }

    // Поперечный разброс
    float spread = (rand(vec2(id, 1.234)) * 2.0 - 1.0) * particle_spread;
    pos += perp * spread;

    // Форма и альфа
    float r = particle_size * (1.0 - life * 0.4);
    float d = length(uv - pos);
    float core = smoothstep(r + particle_softness, r, d);

    // Затухание по жизни + сужение по полосе
    float alpha = core * (1.0 - life) * band_gain;

    return alpha;
}


// =========================
// Основной фрагмент
// =========================
void fragment() {
    vec2 uv = UV;

    // Базовая текстура
    vec4 img = texture(TEXTURE, uv);

    // Ровная альфа по фейду
    float p = gradient_progress(uv);
    float a_grad = gradient_alpha(p);
    float a_combined = img.a * a_grad;

    // Цвет изображения
    vec4 color = vec4(img.rgb, a_combined);

    // Частицы (только пучок, glow отключён)
    float particles_accum = 0.0;
    if (enable_particles) {
        for (int i = 0; i < particle_count; i++) {
            particles_accum += particle_mask(uv, float(i), TIME);
        }
        particles_accum = clamp(particles_accum, 0.0, 1.0);
    }

    // Аддитивное добавление частиц
    vec4 add_particles = vec4(particle_color.rgb * particles_accum, particles_accum);
    color.rgb += add_particles.rgb;
    color.a = max(color.a, add_particles.a);

    // Подложка, если нужна
    color = mix(vec4(0.0), base_color, base_color.a) * (1.0 - color.a) + color;

    COLOR = color;
}
