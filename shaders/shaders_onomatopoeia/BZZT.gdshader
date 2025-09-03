shader_type canvas_item;
uniform float crack_scale = 20.0;
uniform float echo_shift = 0.015;
uniform vec4 base_color : source_color = vec4(1.0, 0.0, 0.0, 1.0);

float noise(vec2 uv) {
    return fract(sin(dot(uv.xy, vec2(12.9898,78.233))) * 43758.5453);
}

void fragment() {
    vec2 uv = UV;
    vec4 base = texture(TEXTURE, uv);
    
    // Эхо
    vec4 echo = texture(TEXTURE, uv - vec2(echo_shift*sin(TIME), echo_shift*cos(TIME)));
    
    // Трещины
    float cracks = step(0.95, noise(uv * crack_scale + TIME));
    
    COLOR = mix(base, echo, 0.5) * base_color;
    COLOR.rgb *= (1.0 - cracks * 0.5);
}