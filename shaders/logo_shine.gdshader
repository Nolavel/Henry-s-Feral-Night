shader_type canvas_item;

uniform vec4 shine_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float shine_speed : hint_range(0.0, 10.0) = 1.0;
uniform float shine_width : hint_range(0.01, 1.0) = 0.1;
uniform float shine_softness : hint_range(0.01, 1.0) = 0.1;
uniform float shine_angle : hint_range(-1.57, 1.57) = 0.0;
uniform vec2 shine_scale = vec2(1.0, 1.0);

void fragment() {
    vec4 texture_color = texture(TEXTURE, UV);
    
    // Масштабирование и поворот UV координат
    vec2 scaled_uv = (UV - 0.5) * shine_scale + 0.5;
    float angle_cos = cos(shine_angle);
    float angle_sin = sin(shine_angle);
    float rotated_u = scaled_uv.x * angle_cos - scaled_uv.y * angle_sin;
    
    // Вычисление позиции блика
    float time = TIME * shine_speed;
    float shine_pos = fract(rotated_u + time);
    
    // Создание мягкого перехода для блика
    float shine_value = smoothstep(0.0, shine_softness, shine_pos) * 
                        smoothstep(shine_width + shine_softness, shine_width, shine_pos);
    
    // Применение блика только к непрозрачным частям
    vec4 shine_overlay = shine_value * shine_color * texture_color.a;
    
    // Смешивание с исходным цветом
    COLOR = texture_color + shine_overlay - (texture_color * shine_overlay);
}