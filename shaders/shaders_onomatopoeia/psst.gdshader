shader_type canvas_item;
uniform float glitch_strength = 0.02;
uniform vec4 base_color : source_color = vec4(1.0, 0.65, 0.0, 1.0);

void fragment() {
    vec2 uv = UV;
    float glitch = (fract(sin(dot(uv.xy + TIME, vec2(12.9898,78.233))) * 43758.5453));
    uv.x += glitch_strength * (glitch - 0.5);
    vec4 col = texture(TEXTURE, uv);
    col.r = texture(TEXTURE, uv + vec2(glitch_strength, 0.0)).r;
    col.b = texture(TEXTURE, uv - vec2(glitch_strength, 0.0)).b;
    COLOR = col * base_color;
}