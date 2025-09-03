shader_type canvas_item;

uniform float progress : hint_range(0, 1);
uniform vec4 bg_color : source_color = vec4(0.1, 0.1, 0.1, 1.0);
uniform vec4 fill_color : source_color = vec4(0.0, 0.7, 1.0, 1.0);

void fragment() {
    vec2 uv = UV;

    // Создаем эффект волны
    float wave = sin(uv.x * 10.0 + TIME * 2.0) * 0.05;
    uv.y += wave;

    // Основная форма прогресс-бара
    float bar = step(uv.x, progress);

    // Добавляем свечение на краю заполнения
    float glow = smoothstep(progress - 0.05, progress, uv.x) * smoothstep(progress + 0.05, progress, uv.x);
    vec4 glow_color = vec4(1.0, 1.0, 1.0, glow * 0.5);

    // Смешиваем цвета
    vec4 final_color = mix(bg_color, fill_color, bar);
    final_color += glow_color;

    // Добавляем эффект частиц
    if (bar > 0.5 && fract(uv.y * 10.0 + TIME) < 0.1) {
        final_color += vec4(1.0, 1.0, 1.0, 0.2);
    }

    COLOR = final_color;
}