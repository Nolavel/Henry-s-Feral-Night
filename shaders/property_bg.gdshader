shader_type canvas_item;

uniform vec4 background_color : source_color = vec4(0.02, 0.02, 0.05, 1.0);
uniform float time_scale : hint_range(0.1, 2.0) = 0.1;

// Звезды
const int NUM_STARS = 200; // Увеличено количество звезд
uniform vec2 star_positions[NUM_STARS];
uniform float star_sizes[NUM_STARS]; // Размеры будут управляться извне
uniform vec3 star_colors[NUM_STARS];

float rand(vec2 co) {
    return fract(sin(dot(co.xy, vec2(12.9898, 78.233))) * 43758.5453);
}

float star_flicker(vec2 uv, vec2 pos, float size, float time) {
    float dist = length(uv - pos);
    float brightness = smoothstep(size * 1.5, 0.0, dist); // Увеличенный размер звезд
    brightness *= 0.5 + 0.5 * sin(time * 3.0 + rand(pos) * 10.0); // Мерцание
    return brightness * brightness; // Squared for more realistic falloff
}

void fragment() {
    vec2 uv = UV;
    vec3 color = background_color.rgb;
    float time = TIME * time_scale;

    // Рисуем звезды
    for (int i = 0; i < NUM_STARS; i++) {
        color += star_colors[i] * star_flicker(uv, star_positions[i], star_sizes[i], time);
    }

    COLOR = vec4(color, 1.0);
}
