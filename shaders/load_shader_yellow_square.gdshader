shader_type canvas_item;

uniform float speed = 1.0; // Скорость пульсации
uniform float intensity = 1.0; // Интенсивность свечения
uniform float shadow_intensity = 0.5; // Интенсивность тени
uniform vec4 square_color = vec4(1.0, 1.0, 0.0, 1.0); // Цвет квадратов (желтый)

float rand(vec2 co) {
    return fract(sin(dot(co.xy ,vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
    // Определяем координаты для 4 квадратов, расположенных по горизонтали
    vec2 center1 = vec2(0.2, 0.5);  // Левый квадрат
    vec2 center2 = vec2(0.4, 0.5);  // Левее от центра
    vec2 center3 = vec2(0.6, 0.5);  // Правее от центра
    vec2 center4 = vec2(0.8, 0.5);  // Правый квадрат

    float size = 0.15; // Размер квадратов

    // Псевдослучайная яркость и скорость для каждого квадрата
    float pulse1 = sin(TIME * speed + rand(UV * 10.0)) * 0.5 + 0.5;
    float pulse2 = sin(TIME * (speed + 0.3) + rand(UV * 20.0)) * 0.5 + 0.5;
    float pulse3 = sin(TIME * (speed + 0.5) + rand(UV * 30.0)) * 0.5 + 0.5;
    float pulse4 = sin(TIME * (speed + 0.7) + rand(UV * 40.0)) * 0.5 + 0.5;

    // Рассчитываем расстояние от центра для каждого квадрата
    float square1 = smoothstep(size, 0.0, length(UV - center1));
    float square2 = smoothstep(size, 0.0, length(UV - center2));
    float square3 = smoothstep(size, 0.0, length(UV - center3));
    float square4 = smoothstep(size, 0.0, length(UV - center4));

    // Цвет квадратов с пульсацией и тенями
    vec4 final_color = vec4(0.0);

    final_color += square_color * vec4(pulse1 * intensity, pulse1 * intensity, pulse1 * intensity, 1.0) * square1;
    final_color += square_color * vec4(pulse2 * intensity, pulse2 * intensity, pulse2 * intensity, 1.0) * square2;
    final_color += square_color * vec4(pulse3 * intensity, pulse3 * intensity, pulse3 * intensity, 1.0) * square3;
    final_color += square_color * vec4(pulse4 * intensity, pulse4 * intensity, pulse4 * intensity, 1.0) * square4;

    // Тени
    final_color.rgb *= 1.0 - shadow_intensity * (1.0 - (square1 + square2 + square3 + square4));

    COLOR = final_color;
}
