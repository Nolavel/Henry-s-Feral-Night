shader_type canvas_item;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 fade_color : source_color = vec4(0.0, 0.0, 0.0, 0.9);
uniform float wipe_angle : hint_range(0.0, 360.0) = 45.0;
uniform float edge_softness : hint_range(0.01, 0.2) = 0.1;

void fragment() {
    vec2 uv = UV - vec2(0.5);
    
    float angle = radians(wipe_angle);
    vec2 direction = vec2(cos(angle), sin(angle));
    
    float dist = dot(uv, direction);
    float wipe_progress = progress * 2.0 - 1.0; // -1 to 1
    
    float alpha = smoothstep(wipe_progress - edge_softness, wipe_progress + edge_softness, dist);
    
    COLOR = mix(vec4(0.0), fade_color, alpha);
}