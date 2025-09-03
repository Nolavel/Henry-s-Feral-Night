shader_type canvas_item;

uniform float darkness : hint_range(0.0, 1.0) = 0.5;  // Интенсивность затемнения по границам
uniform float edge_width : hint_range(0.0, 0.5) = 0.1;  // Ширина затемненных границ
uniform sampler2D texture;  // Спрайт, который будет затемняться по границам

void fragment() {
    vec4 sprite_color = texture(texture, UV);  // Получаем цвет пикселя из текстуры
    
    // Вычисляем расстояние от центра до границы
    vec2 center = vec2(0.5, 0.5);  // Центр экрана
    float dist = distance(UV, center);

    // Определяем интенсивность затемнения, применяя его ближе к краям
    float edge_factor = smoothstep(0.5, 0.5 - edge_width, dist);
    float darkness_factor = darkness * edge_factor;

    // Применяем затемнение к альфа-каналу
    sprite_color.a *= (1.0 - darkness_factor);
    COLOR = sprite_color;
}
