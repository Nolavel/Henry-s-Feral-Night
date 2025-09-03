shader_type canvas_item;

uniform float time; // Управляет временем
uniform vec4 glitch_color = vec4(1.0, 0.0, 0.0, 1.0); // Цвет глитча
uniform float glitch_intensity = 0.1; // Интенсивность глитча
uniform float glitch_speed = 10.0; // Скорость эффекта глитча

void fragment() {
    vec2 uv = UV;
    vec4 base_color = texture(TEXTURE, uv); // Получаем цвет логотипа

    // Эффект глитча с шумом
    float noise = fract(sin(dot(uv.xy * time * glitch_speed, vec2(12.9898, 78.233))) * 43758.5453);
    noise = smoothstep(0.5 - glitch_intensity, 0.5 + glitch_intensity, noise);

    // Применяем эффект глитча к основному цвету
    vec4 glitch_effect = glitch_color * noise * base_color.a; // Цвет глитча зависит от шума
    base_color = mix(base_color, glitch_effect, glitch_intensity); // Смешиваем основной цвет с глитч-эффектом

    COLOR = base_color;
}
