shader_type canvas_item;

uniform float fade_start : hint_range(0.0, 1.0) = 0.3;
uniform float fade_end   : hint_range(0.0, 1.0) = 0.8;
uniform float fade_curve : hint_range(0.1, 4.0) = 1.0;
uniform int   fade_direction : hint_range(0, 3) = 0;

uniform float circle_radius : hint_range(0.0, 1.0) = 0.5; // радиус круга (0.5 = половина стороны)
uniform float circle_softness : hint_range(0.0, 0.2) = 0.02; // мягкость края

void fragment() {
    vec2 uv = UV;

    // Берём цвет из текстуры
    vec4 tex_col = texture(TEXTURE, uv);

    // Градиентное исчезновение
    float fade_progress = 0.0;
    if (fade_direction == 0) fade_progress = uv.x;
    else if (fade_direction == 1) fade_progress = 1.0 - uv.x;
    else if (fade_direction == 2) fade_progress = 1.0 - uv.y;
    else fade_progress = uv.y;

    fade_progress = pow(fade_progress, fade_curve);

    float fade_alpha = 1.0;
    if (fade_progress > fade_start) {
        if (fade_progress < fade_end) {
            float fade_zone_progress = (fade_progress - fade_start) / (fade_end - fade_start);
            fade_alpha = 1.0 - smoothstep(0.0, 1.0, fade_zone_progress);
        } else {
            fade_alpha = 0.0;
        }
    }

    // Круглая маска
    vec2 centered = uv - 0.5; // центр в (0.5,0.5)
    float dist = length(centered);
    float circle_alpha = 1.0 - smoothstep(circle_radius - circle_softness,
                                          circle_radius + circle_softness,
                                          dist);

    // Итоговая альфа = текстура * фейд * круг
    float final_alpha = tex_col.a * fade_alpha * circle_alpha;

    COLOR = vec4(tex_col.rgb, final_alpha);
}
