shader_type canvas_item;

// =========================
// Базовое изображение
// =========================
uniform float image_alpha : hint_range(0.05,0.55) = 0.55;

// =========================
// Звёзды
// =========================
uniform bool enable_stars = true;
uniform int star_count : hint_range(1, 30) = 10;
uniform float star_twinkle_speed : hint_range(0.5, 3.0) = 1.5;

// =========================
// "ZZZ" частицы
// =========================
uniform bool enable_zzz_particles = true;
uniform float zzz_speed : hint_range(0.2, 2.0) = 1.0;

// =========================
// Wisps
// =========================
uniform bool enable_dream_wisps = true;
uniform float dream_intensity : hint_range(0.0, 2.0) = 1.0;

// -------------------------
// Вспомогательные
// -------------------------
float rand(vec2 co) {
    return fract(sin(dot(co, vec2(12.9898,78.233))) * 43758.5453);
}

// -------------------------
// Звёзды
// -------------------------
float generate_stars(vec2 uv, float time) {
    if (!enable_stars) return 0.0;
    float stars = 0.0;
    for (int i=0; i<star_count; i++) {
        float fi = float(i);
        vec2 star_pos = vec2(
            rand(vec2(fi, 0.1)) * 2.0 - 1.0,
            rand(vec2(fi, 0.2)) * 2.0 - 1.0
        );
        float star_dist = length(uv - star_pos);
        float star_size = 0.01 + rand(vec2(fi,0.3))*0.01;
        float twinkle = sin(time*star_twinkle_speed + fi) * 0.3 + 0.7;
        stars += smoothstep(star_size+0.005, star_size, star_dist) * twinkle;
    }
    return clamp(stars,0.0,1.0);
}

// -------------------------
// ZZZ частицы
// -------------------------
float zzz_particles(vec2 uv, float time) {
    if (!enable_zzz_particles) return 0.0;
    float zzz = 0.0;
    for (int i=0; i<3; i++) {
        float fi = float(i);
        float t = mod(time*zzz_speed + fi*0.7, 2.0)/2.0;
        if (t>0.8) continue;
        vec2 pos = vec2(0.6 + fi*0.15 - t*0.1, -0.3 + t*0.8);
        float d = length(uv - pos);
        float size = 0.05 + fi*0.01;
        float a = smoothstep(size+0.01, size*0.7, d);
        a *= (1.0 - t);
        zzz += a;
    }
    return clamp(zzz,0.0,1.0);
}

// -------------------------
// Wisps
// -------------------------
float dream_wisps(vec2 uv, float time) {
    if (!enable_dream_wisps) return 0.0;
    float wisps = 0.0;
    for (int i=0; i<5; i++) {
        float fi = float(i);
        float wt = time*0.5 + fi*1.2;
        vec2 center = vec2(sin(wt*0.8+fi)*0.6, cos(wt*0.6+fi*0.7)*0.4);
        float d = length(uv - center);
        float size = 0.08 + sin(wt+fi)*0.02;
        float a = smoothstep(size+0.02, size*0.5, d);
        a *= (sin(wt*2.0+fi)*0.3+0.7);
        a *= dream_intensity;
        wisps += a;
    }
    return clamp(wisps,0.0,1.0);
}

// -------------------------
// Основной фрагмент
// -------------------------
void fragment() {
    vec2 uv = UV;
    vec4 img = texture(TEXTURE, uv);
    img.a *= image_alpha;

    vec2 uv_particles = uv*2.0 - 1.0; // -1..1 для частиц
    float stars = generate_stars(uv_particles, TIME);
    float zzz   = zzz_particles(uv_particles, TIME);
    float wisps = dream_wisps(uv_particles, TIME);

    vec4 color = img;
    color.rgb += vec3(1.0,1.0,0.9)*stars;
    color.rgb += vec3(0.9,0.9,0.7)*zzz;
    color.rgb += vec3(0.7,0.8,1.0)*wisps;

    COLOR = color;
}
