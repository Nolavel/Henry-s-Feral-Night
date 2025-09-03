// Letter Wave Text Shader for Godot 4.3
// Применяется к Label через CanvasItem материал
shader_type canvas_item;

// Основные параметры анимации
uniform float wave_speed : hint_range(0.5, 5.0) = 2.0;
uniform float wave_amplitude : hint_range(0.0, 2.0) = 0.3;
uniform float wave_frequency : hint_range(0.1, 3.0) = 1.0;
uniform float letter_spacing : hint_range(0.01, 0.1) = 0.05;

// Цветовые параметры
uniform vec4 base_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 wave_color : source_color = vec4(1.2, 1.2, 0.8, 1.0);
uniform float color_mix : hint_range(0.0, 1.0) = 0.5;

// Дополнительные эффекты
uniform bool enable_glow = false;
uniform vec4 glow_color : source_color = vec4(1.0, 0.5, 0.0, 1.0);
uniform float glow_intensity : hint_range(0.0, 3.0) = 1.5;

varying vec2 world_position;

void vertex() {
    world_position = VERTEX;
}

void fragment() {
    // Получаем исходный цвет и альфа-канал текста
    vec4 original_color = texture(TEXTURE, UV);

    // Если пиксель прозрачный (не текст), не применяем эффект
    if (original_color.a < 0.1) {
        COLOR = original_color;
    } else {

    // Рассчитываем позицию "буквы" на основе UV координат
    // UV.x идет от 0 до 1 по ширине текста
    float letter_position = UV.x / letter_spacing;

    // Создаем волну, которая двигается по буквам
    float time_offset = TIME * wave_speed;
    float wave_phase = letter_position * wave_frequency - time_offset;

    // Рассчитываем амплитуду волны (увеличение размера)
    float wave_value = sin(wave_phase) * 0.5 + 0.5; // Нормализуем к 0-1
    float scale_factor = 1.0 + wave_value * wave_amplitude;

    // Создаем эффект "увеличения" через смещение UV
    vec2 center = vec2(0.5, 0.5);
    vec2 scaled_uv = center + (UV - center) / scale_factor;

    // Получаем цвет с учетом масштабирования
    vec4 scaled_color = texture(TEXTURE, scaled_uv);

    // Если после масштабирования мы вышли за границы, используем исходный цвет
    if (scaled_uv.x < 0.0 || scaled_uv.x > 1.0 || scaled_uv.y < 0.0 || scaled_uv.y > 1.0) {
        scaled_color = original_color;
    }

    // Смешиваем базовый цвет с волновым цветом
    vec4 final_base_color = mix(base_color, wave_color, wave_value * color_mix);

    // Применяем цвет к тексту, сохраняя исходную альфу
    vec4 final_color = vec4(final_base_color.rgb * scaled_color.rgb, scaled_color.a);

    // Добавляем эффект свечения, если включен
    if (enable_glow && wave_value > 0.7) {
        float glow_factor = (wave_value - 0.7) / 0.3; // Свечение только на пиках волны
        vec3 glow_effect = glow_color.rgb * glow_intensity * glow_factor;
        final_color.rgb += glow_effect * scaled_color.a;
    }

    COLOR = final_color;
    }
}