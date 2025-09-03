shader_type canvas_item;
uniform float shake_strength = 0.01;
uniform vec4 base_color : source_color = vec4(0.75, 0.75, 0.75, 1.0);

void fragment() {
    vec2 uv = UV;
    uv += vec2(
        sin(TIME * 60.0) * shake_strength,
        cos(TIME * 55.0) * shake_strength
    );
    COLOR = texture(TEXTURE, uv) * base_color;
}