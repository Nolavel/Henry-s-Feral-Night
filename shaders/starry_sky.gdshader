shader_type canvas_item;

uniform vec4 background_color : source_color = vec4(0.0, 0.0, 0.1, 1.0);
uniform int star_count : hint_range(0, 1000) = 600;

float random(vec2 uv) {
    return fract(sin(dot(uv, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
    vec2 uv = FRAGCOORD.xy / (1.0 / SCREEN_PIXEL_SIZE);
    vec3 color = background_color.rgb;

    for (int i = 0; i < star_count; i++) {
        vec2 star_pos = vec2(random(vec2(float(i), 0.0)), random(vec2(0.0, float(i))));
        float distance = length(uv * SCREEN_PIXEL_SIZE - star_pos);

        if (distance < 0.005) {
            color = vec3(1.0); // Белая звезда
        }
    }

    COLOR = vec4(color, 1.0);
}