shader_type canvas_item;
uniform vec2 offset = vec2(0.02, 0.02);
uniform vec4 echo_color = vec4(1.0, 1.0, 0.0, 0.5);
uniform vec4 base_color : source_color = vec4(1.0, 1.0, 0.0, 1.0);

void fragment() {
    vec4 main_tex = texture(TEXTURE, UV);
    vec4 echo_tex = texture(TEXTURE, UV - offset);
    COLOR = (main_tex + echo_tex * echo_color.a) * base_color;
}