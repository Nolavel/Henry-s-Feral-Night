shader_type spatial;
render_mode cull_front, unshaded;

uniform vec4 outline_color : source_color = vec4(1.0, 1.0, 0.0, 1.0); // цвет обводки
uniform float outline_size = 0.05;

void vertex() {
    VERTEX += NORMAL * outline_size;
}

void fragment() {
    ALBEDO = outline_color.rgb;
    ALPHA = outline_color.a;
}
