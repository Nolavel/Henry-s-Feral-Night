shader_type canvas_item;

uniform float time; // Время, управляющее появлением и вращением квадратов
uniform float square_size : hint_range(0.0, 1.0) = 0.05; // Размер каждого квадрата
uniform int num_squares = 10; // Общее количество квадратов
uniform float spacing : hint_range(0.0, 1.0) = 0.1; // Расстояние между квадратами
uniform vec2 viewport_size; // Размеры вьюпорта или области отображения

void fragment() {
    // Нормализуем координаты в диапазон от -1 до 1
    vec2 uv = (FRAGCOORD.xy / viewport_size) * 2.0 - vec2(1.0);
    vec2 center = vec2(0.0); // Центр экрана в нормализованных координатах

    float square_half_size = square_size * 0.5;
    float animation_delay = 5.0; // Задержка появления следующего квадрата
    float total_time = float(num_squares) * animation_delay; // Общее время появления всех квадратов
    float rotation_speed = 1.0; // Скорость вращения квадратов

    vec2 square_pos;
    bool in_square = false;

    // Появление квадратов
    for (int i = 0; i < num_squares; i++) {
        float appear_time = float(i) * animation_delay;
        float alpha = smoothstep(appear_time, appear_time + 1.0, time);

        if (time >= appear_time) {
            square_pos = center + vec2(float(i) * (square_size + spacing) - (float(num_squares) / 2.0) * (square_size + spacing), 0.0);

            // Анимация вращения после полного появления всех квадратов
            if (time > total_time) {
                float angle = rotation_speed * (time - total_time) + float(i) * 0.5; // Вращение по времени и сдвигу
                square_pos = vec2(
                    cos(angle) * (square_pos.x - center.x) - sin(angle) * (square_pos.y - center.y) + center.x,
                    sin(angle) * (square_pos.x - center.x) + cos(angle) * (square_pos.y - center.y) + center.y
                );
            }

            // Проверка, находится ли текущая точка в квадрате
            if (abs(uv.x - square_pos.x) < square_half_size * alpha && abs(uv.y - square_pos.y) < square_half_size * alpha) {
                in_square = true;
            }
        }
    }

    // Устанавливаем цвет квадрата
    if (in_square) {
        COLOR = vec4(1.0, 1.0, 1.0, 1.0); // Белый квадрат
    } else {
        COLOR = vec4(0.0, 0.0, 0.0, 0.0); // Прозрачный фон
    }
}
