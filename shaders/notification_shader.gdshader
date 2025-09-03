shader_type canvas_item;

uniform sampler2D panel_texture; // Текстура панели
uniform vec4 edge_color = vec4(1.0, 0.5, 0.0, 1.0); // Цвет ржавчины по краям
uniform float time_factor = 1.0; // Скорость анимации
uniform float noise_strength = 0.1; // Сила шума
uniform float flicker_intensity = 0.05; // Интенсивность мерцания

void fragment() {
    // Получаем основной цвет из текстуры панели
    vec4 base_color = texture(panel_texture, UV);

    // Координаты фрагмента
    vec2 uv = FRAGCOORD.xy / SCREEN_PIXEL_SIZE;

    // Добавляем эффект ржавчины по краям панели
    float edge_dist = min(uv.x, uv.y);
    edge_dist = min(edge_dist, 1.0 - uv.x);
    edge_dist = min(edge_dist, 1.0 - uv.y);

    // Ржавчина по краям
    if (edge_dist < 0.1) {
        base_color = mix(base_color, edge_color, 1.0 - edge_dist / 0.1);
    }

    // Генерация шума
    float noise = fract(sin(dot(UV, vec2(12.9898, 78.233))) * 43758.5453);
    base_color.rgb += noise * noise_strength;

    // Эффект мерцания
    float flicker = sin(TIME * time_factor * 5.0) * flicker_intensity;
    base_color.rgb += flicker;

    // Выводим окончательный цвет
    COLOR = base_color;
}