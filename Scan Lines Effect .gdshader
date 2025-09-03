shader_type canvas_item;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float line_density : hint_range(50.0, 300.0) = 120.0;
uniform float line_width : hint_range(0.01, 0.3) = 0.08;
uniform vec4 fade_color : source_color = vec4(0.05, 0.15, 0.2, 0.8);
uniform float scan_speed : hint_range(0.1, 5.0) = 1.5;
uniform bool horizontal = true;
uniform float glow_strength : hint_range(0.0, 1.0) = 0.3;
uniform float flicker_strength : hint_range(0.0, 1.0) = 0.2;
uniform float noise_scale : hint_range(0.1, 10.0) = 2.0;

float rand(vec2 co){
    return fract(sin(dot(co.xy ,vec2(12.9898,78.233))) * 43758.5453);
}

void fragment() {
    vec2 uv = UV;
    float coord = horizontal ? uv.y : uv.x;

    // Неровные линии
    float noise = (rand(vec2(coord * noise_scale, TIME * 0.5)) - 0.5) * 0.02;
    coord += noise;

    float lines = sin(coord * line_density * PI) * 0.5 + 0.5;
    float line_mask = step(1.0 - line_width, lines);

    // Позиция сканирующей линии
    float scan_pos = fract(TIME * scan_speed + progress);
    float scan_influence = 1.0 - abs(coord - scan_pos) * 3.0;
    scan_influence = clamp(scan_influence, 0.0, 1.0);

    // Слабое мерцание линии
    float flicker = 0.8 + sin(TIME * 30.0) * flicker_strength;

    // Эффект свечения
    float glow = scan_influence * glow_strength;

    float alpha = (line_mask * flicker + glow) * progress;

    COLOR = mix(vec4(0.0), fade_color, alpha);
}
