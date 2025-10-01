shader_type canvas_item;

uniform float diamond_softness : hint_range(0.0, 0.2) = 0.02; // мягкость внешней границы ромба
uniform float aspect : hint_range(0.1, 5.0) = 1.0;
uniform vec4 modulate_color : source_color = vec4(1.0);

uniform float border_thickness : hint_range(0.0, 0.2) = 0.05;
uniform float border_softness : hint_range(0.0, 0.2) = 0.02;
uniform vec4 border_color : source_color = vec4(1.0, 0.8, 0.2, 1.0);

uniform float fade_amount : hint_range(0.0, 1.0) = 0.0; // 0=ничего, 1=всё
uniform float fade_softness : hint_range(0.0, 0.2) = 0.05;

void fragment() {
    vec2 uv = UV * 2.0 - 1.0;
    uv.x *= aspect;

    float diamond = abs(uv.x) + abs(uv.y);

    // внешняя маска ромба
    float outer = smoothstep(1.0, 1.0 - diamond_softness, diamond);

    // внутренняя маска ромба
    float inner = smoothstep(1.0 - border_thickness, 1.0 - border_thickness - border_softness, diamond);

    // рамка = разница
    float border_mask = outer - inner;

    // fade: от нижнего угла (y=-1) к верхнему (y=+1)
    float y_threshold = -1.0 + 2.0 * fade_amount;
    float reveal = 1.0 - smoothstep(y_threshold - fade_softness, y_threshold + fade_softness, uv.y);
    border_mask *= reveal;

    vec4 tex = texture(TEXTURE, UV) * modulate_color;
    vec4 border = border_color * border_mask;

    COLOR = vec4(tex.rgb, tex.a * outer) + border;
}
