shader_type canvas_item;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float vignette_size : hint_range(0.3, 2.0) = 1.2;
uniform vec4 fade_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float edge_softness : hint_range(0.01, 0.5) = 0.2;

void fragment() {
    vec2 uv = UV;
    vec2 center = vec2(0.5, 0.5);

    float dist = distance(uv, center);
    float vignette = smoothstep(vignette_size - edge_softness - progress, vignette_size - progress, dist);

    COLOR = mix(vec4(0.0), fade_color, vignette * progress);
}