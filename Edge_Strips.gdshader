shader_type canvas_item;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float strip_width : hint_range(0.1, 0.5) = 0.25;
uniform vec4 fade_color : source_color = vec4(0.0, 0.0, 0.0, 0.8);
uniform float edge_softness : hint_range(0.01, 0.1) = 0.05;

void fragment() {
    vec2 uv = UV;
    float alpha = 0.0;

    // Верх и низ
    float top = smoothstep(strip_width * progress - edge_softness, strip_width * progress, uv.y);
    float bottom = smoothstep(strip_width * progress - edge_softness, strip_width * progress, 1.0 - uv.y);

    // Лево и право
    float left = smoothstep(strip_width * progress - edge_softness, strip_width * progress, uv.x);
    float right = smoothstep(strip_width * progress - edge_softness, strip_width * progress, 1.0 - uv.x);

    alpha = max(max(1.0 - top, 1.0 - bottom), max(1.0 - left, 1.0 - right));

    COLOR = mix(vec4(0.0), fade_color, alpha * progress);
}