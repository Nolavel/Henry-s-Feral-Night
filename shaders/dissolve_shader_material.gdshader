shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform sampler2D albedo_texture : source_color;
uniform vec4 albedo_color : source_color;
uniform float dissolve_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 dissolve_color : source_color = vec4(1.0, 0.5, 0.0, 1.0); // Оранжевое свечение
uniform float dissolve_width : hint_range(0.01, 0.5) = 0.1;

// НОВЫЕ ПАРАМЕТРЫ для улучшенного эффекта
uniform int dissolve_type : hint_range(0, 3) = 1; // 0=слева направо, 1=снизу вверх, 2=от центра, 3=шум
uniform float noise_scale : hint_range(0.1, 10.0) = 3.0; // Масштаб шума для рандомного растворения
uniform float glow_intensity : hint_range(0.0, 3.0) = 2.0; // Интенсивность свечения

// Простая функция шума
float random(vec2 st) {
    return fract(sin(dot(st.xy, vec2(12.9898,78.233))) * 43758.5453123);
}

// Более сложный шум
float noise(vec2 st) {
    vec2 i = floor(st);
    vec2 f = fract(st);
    
    float a = random(i);
    float b = random(i + vec2(1.0, 0.0));
    float c = random(i + vec2(0.0, 1.0));
    float d = random(i + vec2(1.0, 1.0));
    
    vec2 u = f * f * (3.0 - 2.0 * f);
    
    return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

void fragment() {
    vec4 base_color;
    if (texture(albedo_texture, UV).a < 0.1) {
        base_color = albedo_color;
    } else {
        base_color = texture(albedo_texture, UV) * albedo_color;
    }
    
    float dissolve_mask = 0.0;
    
    // Выбираем тип растворения
    if (dissolve_type == 0) {
        // Слева направо
        dissolve_mask = UV.x;
    } else if (dissolve_type == 1) {
        // Снизу вверх
        dissolve_mask = UV.y;
    } else if (dissolve_type == 2) {
        // От центра к краям
        vec2 center = vec2(0.5, 0.5);
        dissolve_mask = distance(UV, center) * 1.414; // 1.414 для нормализации диагонали
    } else if (dissolve_type == 3) {
        // Шумовое растворение (самый эффектный!)
        dissolve_mask = noise(UV * noise_scale);
    }
    
    // Вычисляем финальную прозрачность
    float final_alpha;
    vec3 final_color = base_color.rgb;
    
    if (dissolve_mask < dissolve_amount - dissolve_width) {
        // Полностью растворенная область
        final_alpha = 0.0;
    } else if (dissolve_mask < dissolve_amount) {
        // Зона свечения на границе растворения
        float glow_factor = 1.0 - (dissolve_amount - dissolve_mask) / dissolve_width;
        final_color = mix(base_color.rgb, dissolve_color.rgb, glow_factor * glow_intensity);
        final_alpha = base_color.a * (1.0 - glow_factor * 0.3); // Слегка делаем прозрачнее
    } else {
        // Обычная область
        final_alpha = base_color.a;
    }
    
    ALBEDO = final_color;
    ALPHA = final_alpha;
    
    // Добавляем эмиссию для свечения
    if (dissolve_mask >= dissolve_amount - dissolve_width && dissolve_mask < dissolve_amount) {
        float glow_factor = 1.0 - (dissolve_amount - dissolve_mask) / dissolve_width;
        EMISSION = dissolve_color.rgb * glow_factor * glow_intensity;
    }
}