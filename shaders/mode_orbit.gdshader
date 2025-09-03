shader_type canvas_item;

uniform vec4 base_color = vec4(0.1, 0.1, 0.1, 1.0);
uniform vec4 wave_color = vec4(0.0, 0.8, 1.0, 1.0);
uniform float time_factor = 2.0; // Скорость волн
uniform float wave_amplitude = 0.05; // Амплитуда волн
uniform bool mouse_over = false;

void fragment() {
    vec2 uv = FRAGCOORD.xy / SCREEN_PIXEL_SIZE.xy;

    // Базовый цвет панели
    COLOR = base_color;

    if (mouse_over) {
        // Добавляем динамический эффект волн
        float wave = sin(uv.x * 10.0 + TIME * time_factor) * wave_amplitude;
        wave += sin(uv.y * 15.0 + TIME * time_factor * 0.5) * wave_amplitude;

        // Применяем эффект на цвет
        COLOR.rgb += wave * wave_color.rgb;
    }
}
