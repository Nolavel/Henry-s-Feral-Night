shader_type canvas_item;

uniform float glow_intensity : hint_range(0.0, 5.0) = 2.0;
uniform vec4 glow_color : source_color = vec4(0.0, 1.0, 1.0, 1.0); // Голубой
uniform float pulse_speed : hint_range(0.1, 10.0) = 3.0;
uniform float pulse_strength : hint_range(0.0, 2.0) = 0.5;
uniform bool enable_pulse = true;

void fragment() {
    vec4 tex_color = texture(TEXTURE, UV);
    
    if (tex_color.a > 0.0) {
        // Пульсация интенсивности
        float pulse = 1.0;
        if (enable_pulse) {
            pulse = 1.0 + sin(TIME * pulse_speed) * pulse_strength;
        }
        
        // Применяем свечение к существующим пикселям
        vec3 final_color = tex_color.rgb + (glow_color.rgb * glow_intensity * pulse);
        COLOR = vec4(final_color, tex_color.a);
    } else {
        COLOR = tex_color;
    }
}