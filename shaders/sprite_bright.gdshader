shader_type canvas_item;

uniform vec4 hologram_color : source_color = vec4(0.0, 1.0, 0.8, 1.0);
uniform float hologram_intensity : hint_range(0.0, 1.0) = 0.5;
uniform float scan_line_speed : hint_range(0.1, 5.0) = 1.0;
uniform float scan_line_width : hint_range(0.0, 0.1) = 0.05;
uniform float distortion_speed : hint_range(0.1, 5.0) = 0.5;
uniform float distortion_intensity : hint_range(0.0, 0.1) = 0.01;

void fragment() {
    vec2 uv = UV;
    
    // Искажение
    float distortion = sin(uv.y * 10.0 + TIME * distortion_speed) * distortion_intensity;
    uv.x += distortion;
    
    // Основной цвет логотипа
    vec4 color = texture(TEXTURE, uv);
    
    // Сканирующие линии
    float scan_line = step(1.0 - scan_line_width, fract(uv.y - TIME * scan_line_speed));
    
    // Применяем голографический эффект
    vec4 hologram = hologram_color * scan_line * hologram_intensity;
    
    // Смешиваем оригинальный цвет и голографический эффект
    COLOR = mix(color, hologram, hologram.a * (1.0 - color.a));
    COLOR.a = color.a;
    
    // Добавляем свечение по краям
    float edge = 1.0 - texture(TEXTURE, uv).a;
    COLOR += hologram_color * edge * hologram_intensity;
}