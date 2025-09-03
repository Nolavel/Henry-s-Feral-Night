shader_type canvas_item;

uniform float intensity = 0.0; // Интенсивность звука (передаётся в зависимости от уровня музыки)
uniform float line_thickness = 0.02; // Толщина линии
uniform vec3 line_color = vec3(0.8, 0.2, 0.6); // Цвет линии
uniform vec3 background_color = vec3(0.0, 0.0, 0.0); // Фоновый цвет (игнорируется при прозрачности)
uniform float sensitivity = 10.0; // Чувствительность реакции линии на звук
uniform float background_alpha = 0.0; // Прозрачность фона (0.0 - полностью прозрачно)

void fragment() {
    vec2 uv = UV;

    // Определяем, как сильно линия будет искривляться в зависимости от интенсивности звука
    float time_factor = TIME * 10.0;
    float wave = sin(uv.x * 20.0 + time_factor) * intensity * sensitivity * 0.2; // Искривление зависит от интенсивности

    // Если интенсивность низкая (звук слабый), линия остаётся ровной
    wave *= step(0.01, intensity); // Искривление применяется только при ненулевой интенсивности

    // Рассчитываем расстояние до линии
    float dist_to_line = abs(uv.y - (0.5 + wave));

    // Цвет линии и фона
    vec3 color = mix(line_color, background_color, smoothstep(0.0, line_thickness, dist_to_line));

    // Выводим цвет с прозрачным фоном
    COLOR = vec4(color, (1.0 - smoothstep(0.0, line_thickness, dist_to_line)) * (1.0 - background_alpha));
}
