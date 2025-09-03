shader_type spatial;

uniform sampler2D stars_texture; // Текстура звездного неба
uniform float time_factor : hint_range(0.1, 10.0) = 1.0; // Фактор времени для мерцания звезд
uniform float flicker_intensity : hint_range(0.0, 1.0) = 0.3; // Интенсивность мерцания
uniform float flicker_speed : hint_range(0.1, 5.0) = 1.0; // Скорость мерцания

// Параметры для линии
uniform vec4 line_color = vec4(1.0, 0.0, 0.0, 1.0); // Цвет линии
uniform float line_width : hint_range(10.0, 100.0) = 50.0; // Ширина линии
uniform float border_offset : hint_range(1000.0, 10000.0) = 5000.0; // Отступ от границ

void fragment() {
    vec2 uv = UV;

    // Семплирование звездного неба
    vec4 stars = texture(stars_texture, uv);

    // Генерация мерцания с использованием шума и времени
    float flicker = sin(TIME * flicker_speed + uv.x * 100.0 + uv.y * 100.0) * 0.5 + 0.5;
    flicker = mix(1.0 - flicker_intensity, 1.0, flicker);

    // Применение мерцания к звездам
    stars.rgb *= flicker;

    // Логика для рисования линии по краям плоскости
    vec2 scaled_uv = uv * 100000.0; // Масштабируем UV до размеров плоскости (100 тыс. на 100 тыс.)

    // Определяем границы плоскости с учетом отступа
    float left = border_offset;
    float right = 100000.0 - border_offset;
    float top = border_offset;
    float bottom = 100000.0 - border_offset;

    // Определяем, находимся ли мы в области линии по горизонтали или вертикали
    bool on_left_or_right = (abs(scaled_uv.x - left) < line_width || abs(scaled_uv.x - right) < line_width) && (scaled_uv.y > top && scaled_uv.y < bottom);
    bool on_top_or_bottom = (abs(scaled_uv.y - top) < line_width || abs(scaled_uv.y - bottom) < line_width) && (scaled_uv.x > left && scaled_uv.x < right);

    // Прерывание линии каждые 5000 метров на 500 метров
    bool pattern = mod(scaled_uv.x, 5000.0) < 500.0 || mod(scaled_uv.y, 5000.0) < 500.0;

    // Если пиксель попадает в зону линии и не находится в зоне прерывания, рисуем линию
    if ((on_left_or_right || on_top_or_bottom) && !pattern) {
        ALBEDO = line_color.rgb;
        ALPHA = line_color.a;
    } else {
        // Применяем результат мерцания звездного неба
        ALBEDO = stars.rgb;
        ALPHA = stars.a;
    }
}
