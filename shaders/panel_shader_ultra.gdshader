shader_type canvas_item;

uniform vec4 base_color = vec4(0.1, 0.3, 0.6, 0.9); // Цвет панели
uniform vec4 glow_color = vec4(0.7, 0.8, 1.0, 1.0); // Цвет свечения
uniform float glow_strength = 0.6; // Сила свечения
uniform float line_thickness = 0.003; // Толщина линий
uniform float line_frequency = 15.0; // Частота линий
uniform float pulse_speed = 1.5; // Скорость пульсации

// Добавляем параметры для подсветки границ
uniform vec4 border_color = vec4(1.0, 1.0, 1.0, 1.0); // Цвет границ
uniform float border_thickness = 0.02; // Толщина границ
uniform float border_glow_intensity = 0.0; // Интенсивность свечения границ (меняется в GDScript)

void fragment() {
    // База панели
    vec4 color = base_color;

    // Вычисляем расстояние от краёв
    vec2 dist_from_center = abs(UV - vec2(0.5));
    float edge_glow = 1.0 - max(dist_from_center.x, dist_from_center.y) * 2.0;

    // Пульсирующие линии
    float time = TIME * pulse_speed;
    float line_val = sin(UV.y * line_frequency + time) * 0.5 + 0.5;
    line_val = smoothstep(1.0 - line_thickness, 1.0, line_val);

    // Вертикальные линии
    float v_line_val = sin(UV.x * line_frequency * 0.7 + time) * 0.5 + 0.5;
    v_line_val = smoothstep(1.0 - line_thickness, 1.0, v_line_val);

    // Комбинируем эффекты
    float glow = max(line_val, v_line_val) * edge_glow * glow_strength;
    color = mix(color, glow_color, glow);

    // Добавляем мерцающее свечение
    color.rgb += glow_color.rgb * edge_glow * glow_strength * (sin(time * 0.5) * 0.5 + 0.5);

    // Подсвечивание границ
    vec2 dist_from_edge = min(UV, 1.0 - UV);
    float border = smoothstep(0.0, border_thickness, min(dist_from_edge.x, dist_from_edge.y));
    color = mix(color, border_color, border * border_glow_intensity);

    // Итоговый цвет
    COLOR = color;
}
