shader_type canvas_item;

uniform float time; // Управляет движением волны подсветки
uniform float wave_speed = 1.0; // Скорость движения волны
uniform float wave_width = 0.2; // Ширина волны
uniform vec4 highlight_color = vec4(1.0, 1.0, 1.0, 0.5); // Цвет подсветки
uniform float intensity = 1.0; // Интенсивность подсветки

void fragment() {
    vec2 uv = UV;  // Координаты текстуры от 0 до 1
    
    // Вычисляем положение волны по X-координате
    float wave_position = sin(uv.x * 10.0 + time * wave_speed) * wave_width;
    
    // Вычисляем яркость подсветки в зависимости от положения волны
    float highlight = smoothstep(0.0, 1.0, wave_position + 0.5);
    
    // Получаем цвет пикселя и применяем подсветку
    vec4 base_color = vec4(0.0);  // Начальный цвет
    base_color.rgb += highlight_color.rgb * highlight * intensity; // Применяем подсветку
    
    COLOR = base_color;
}
