shader_type canvas_item;

uniform float arrow_direction = 1.0; // Направление стрелок (1.0 - вверх, -1.0 - вниз)
uniform float time_speed = 2.0; // Скорость мерцания
uniform vec4 arrow_color = vec4(1.0, 1.0, 1.0, 1.0); // Цвет стрелок
uniform float glow_intensity = 1.0; // Интенсивность мерцания

void fragment() {
    vec2 uv = UV;

    // Центрируем UV относительно кнопки
    uv = uv * 2.0 - vec2(1.0); // Преобразуем UV в диапазон [-1, 1] для центрирования

    // Смещение треугольников по вертикали
    float y_offset = 0.4; // Контролирует расстояние между треугольниками

    // Создаем три треугольника, расположенные по вертикали и центрированные по кнопке
    float triangle1 = step(uv.y * arrow_direction, 0.0) * step(abs(uv.x), uv.y * arrow_direction + 0.3); // Верхний треугольник
    float triangle2 = step((uv.y - y_offset * arrow_direction) * arrow_direction, 0.0) * step(abs(uv.x), (uv.y - y_offset * arrow_direction) * arrow_direction + 0.3); // Средний треугольник
    float triangle3 = step((uv.y - 2.0 * y_offset * arrow_direction) * arrow_direction, 0.0) * step(abs(uv.x), (uv.y - 2.0 * y_offset * arrow_direction) * arrow_direction + 0.3); // Нижний треугольник

    // Мерцание для каждой стрелки
    float flicker1 = sin(TIME * time_speed) * 0.5 + 0.5;
    float flicker2 = sin(TIME * time_speed + 1.0) * 0.5 + 0.5;
    float flicker3 = sin(TIME * time_speed + 2.0) * 0.5 + 0.5;

    // Применяем мерцание для треугольников
    triangle1 *= mix(1.0, flicker1, glow_intensity);
    triangle2 *= mix(1.0, flicker2, glow_intensity);
    triangle3 *= mix(1.0, flicker3, glow_intensity);

    // Применяем цвет к каждому треугольнику
    vec4 final_color = vec4(0.0);
    final_color += arrow_color * triangle1;
    final_color += arrow_color * triangle2;
    final_color += arrow_color * triangle3;

    COLOR = final_color;
}
