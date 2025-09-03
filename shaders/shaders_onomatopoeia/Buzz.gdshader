shader_type canvas_item;
uniform float burn_speed = 0.5;
uniform vec4 base_color : source_color = vec4(0.0, 1.0, 0.0, 1.0);

float noise(vec2 p){
    return fract(sin(dot(p, vec2(12.9898,78.233))) * 43758.5453);
}

void fragment() {
    vec2 uv = UV;
    vec4 col = texture(TEXTURE, uv);

    float burn = noise(uv * 5.0 + TIME * burn_speed);

    if (burn > 0.8) {
        col.a *= (0.8 - burn) * 5.0;
        col.rgb = mix(col.rgb, vec3(0.1,0.1,0.1), 0.7);
    }

    COLOR = col * base_color;
}