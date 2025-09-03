shader_type canvas_item;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float hex_scale : hint_range(5.0, 50.0) = 20.0;
uniform vec4 fade_color : source_color = vec4(0.0, 0.0, 0.0, 0.8);
uniform float spread : hint_range(0.1, 2.0) = 1.0;

vec2 hex_to_grid(vec2 hex) {
    float x = hex.x;
    float y = hex.y;
    
    float q = (sqrt(3.0) / 3.0 * x - 1.0 / 3.0 * y);
    float r = (2.0 / 3.0 * y);
    
    return vec2(q, r);
}

void fragment() {
    vec2 uv = UV * hex_scale;
    
    // Hex grid conversion
    vec2 grid = floor(hex_to_grid(uv));
    
    float dist_from_center = length(grid - hex_scale * 0.5);
    float reveal = smoothstep(progress * hex_scale * spread - 3.0, progress * hex_scale * spread, dist_from_center);
    
    COLOR = mix(vec4(0.0), fade_color, 1.0 - reveal);
}