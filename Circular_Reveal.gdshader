shader_type canvas_item;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec2 iris_center = vec2(0.5, 0.5);
uniform float max_radius : hint_range(0.5, 2.0) = 1.0;
uniform vec4 fade_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float edge_blur : hint_range(0.01, 0.2) = 0.1;
uniform int segments : hint_range(6, 20) = 8;

void fragment() {
    vec2 uv = UV - iris_center;
    float angle = atan(uv.y, uv.x);
    float radius = length(uv);

    // Создаем многоугольную диафрагму
    float segment_angle = TAU / float(segments);
    float current_segment = floor(angle / segment_angle);
    float segment_progress = fract(angle / segment_angle);

    float iris_radius = progress * max_radius;
    float polygon_factor = cos(PI / float(segments)) / cos((segment_progress - 0.5) * segment_angle);
    float effective_radius = iris_radius * polygon_factor;

    float alpha = 1.0 - smoothstep(effective_radius - edge_blur, effective_radius + edge_blur, radius);

    COLOR = mix(vec4(0.0), fade_color, alpha);
}