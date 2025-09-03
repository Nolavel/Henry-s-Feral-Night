shader_type canvas_item;

// Thirst - Water Drop Theme
uniform float progress : hint_range(0.0, 1.0) = 1.0;

// Water colors - from crystal blue to muddy brown when thirsty
uniform vec4 full_color : source_color = vec4(0.2, 0.6, 1.0, 0.9);  // Crystal blue
uniform vec4 mid_color : source_color = vec4(0.3, 0.8, 0.9, 0.8);   // Light cyan
uniform vec4 low_color : source_color = vec4(0.6, 0.5, 0.3, 0.7);   // Muddy
uniform vec4 empty_color : source_color = vec4(0.5, 0.4, 0.3, 0.4); // Dry brown

// Water drop parameters
uniform float drop_size : hint_range(0.3, 0.7) = 0.5;
uniform float drop_roundness : hint_range(0.5, 1.0) = 0.8;

// Water effects
uniform float wave_amplitude : hint_range(0.0, 0.1) = 0.03;
uniform float wave_frequency : hint_range(1.0, 15.0) = 6.0;
uniform float wave_speed : hint_range(0.5, 4.0) = 2.0;
uniform float ripple_intensity : hint_range(0.0, 2.0) = 1.0;

uniform bool enable_waves = true;
uniform bool enable_bubbles = true;
uniform bool enable_reflection = true;

// Bubble parameters
uniform float bubble_count : hint_range(2.0, 12.0) = 8.0;
uniform float bubble_speed : hint_range(0.1, 1.0) = 0.4;

float rand(vec2 co) {
    return fract(sin(dot(co.xy, vec2(12.9898, 78.233))) * 43758.5453);
}

// Water drop shape
float water_drop(vec2 uv) {
    // Main drop body (teardrop shape)
    vec2 drop_uv = uv;
    drop_uv.y += 0.1; // Shift up slightly

    // Bottom rounded part
    float bottom_circle = length(drop_uv) - drop_size;

    // Top pointed part
    vec2 top_uv = drop_uv - vec2(0.0, -drop_size * 0.7);
    float top_angle = atan(top_uv.x, -top_uv.y);
    float top_dist = length(top_uv);
    float top_shape = top_dist - drop_size * 0.3 * (1.0 - abs(top_angle) / 3.14159);

    return min(bottom_circle, top_shape);
}

// Water level inside drop based on progress
float water_level(vec2 uv, float level) {
    // Create water surface with waves
    float base_water_y = mix(0.6, -0.6, level); // Water level from bottom to top

    float waves = 0.0;
    if (enable_waves && level > 0.1) {
        waves = wave_amplitude * sin(uv.x * wave_frequency + TIME * wave_speed);
        waves += wave_amplitude * 0.5 * sin(uv.x * wave_frequency * 2.0 - TIME * wave_speed * 0.7);
    }

    float water_surface = base_water_y + waves;
    return step(water_surface, uv.y);
}

// Bubbles in water
float water_bubbles(vec2 uv, float time, float water_level_val) {
    if (!enable_bubbles || water_level_val < 0.2) return 0.0;

    float bubbles = 0.0;

    for (float i = 0.0; i < bubble_count; i++) {
        float bubble_life = mod(time * bubble_speed + i * 0.3, 3.0) / 3.0;

        vec2 bubble_start = vec2(
            (rand(vec2(i, 0.0)) - 0.5) * drop_size * 1.5,
            0.4
        );

        vec2 bubble_pos = bubble_start + vec2(0.0, -bubble_life * 1.2);
        float bubble_dist = length(uv - bubble_pos);

        float bubble_size = 0.02 + rand(vec2(i, 1.0)) * 0.015;
        bubble_size *= (1.0 - bubble_life * 0.3); // Shrink as they rise

        float bubble_alpha = (1.0 - bubble_life) * water_level_val;
        bubbles += smoothstep(bubble_size + 0.005, bubble_size, bubble_dist) * bubble_alpha;
    }

    return clamp(bubbles, 0.0, 1.0);
}

// Water reflection/shine
float water_reflection(vec2 uv, float water_level_val) {
    if (!enable_reflection || water_level_val < 0.1) return 0.0;

    // Curved reflection on water surface
    vec2 reflection_center = vec2(-0.15, 0.0);
    float reflection_dist = length(uv - reflection_center);

    float reflection = smoothstep(0.25, 0.1, reflection_dist);
    reflection *= sin(TIME * 3.0) * 0.3 + 0.7; // Animated reflection
    reflection *= water_level_val; // Only show in water areas

    return reflection;
}

void fragment() {
    vec2 uv = UV * 2.0 - 1.0; // -1 to 1 range

    // Get water drop outline
    float drop_dist = water_drop(uv);
    float drop_outline = 1.0 - smoothstep(-0.02, 0.0, drop_dist);
    float drop_mask = 1.0 - smoothstep(-0.02, 0.02, drop_dist);

    // Water level inside drop
    float water_mask = water_level(uv, progress) * drop_mask;

    // Air/empty space mask
    float air_mask = drop_mask - water_mask;

    // Progress-based water color
    vec4 water_color;
    if (progress > 0.66) {
        water_color = mix(mid_color, full_color, (progress - 0.66) / 0.34);
    } else if (progress > 0.33) {
        water_color = mix(low_color, mid_color, (progress - 0.33) / 0.33);
    } else {
        water_color = mix(empty_color, low_color, progress / 0.33);
    }

    // Bubbles in water
    float bubbles = water_bubbles(uv, TIME, progress);

    // Water reflection
    float reflection = water_reflection(uv, progress);

    // Ripple effects for thirst level
    float ripples = 0.0;
    if (progress < 0.5) {
        float thirst_intensity = (0.5 - progress) / 0.5;
        ripples = sin(length(uv) * 10.0 - TIME * 4.0) * 0.1 * thirst_intensity;
        ripples *= drop_mask;
    }

    // Final composition
    vec4 final_color = vec4(0.0);

    // Water area
    final_color = mix(final_color, water_color, water_mask);

    // Air/empty area (lighter, more transparent)
    vec4 air_color = water_color;
    air_color.a *= 0.3;
    air_color.rgb = mix(air_color.rgb, vec3(0.9), 0.4);
    final_color = mix(final_color, air_color, air_mask);

    // Drop outline
    vec4 outline_color = vec4(0.4, 0.6, 0.8, 0.8);
    final_color = mix(final_color, outline_color, drop_outline - drop_mask);

    // Add bubbles
    vec4 bubble_color = vec4(0.8, 0.9, 1.0, 0.6);
    final_color = mix(final_color, bubble_color, bubbles);

    // Add reflection
    vec4 reflection_color = vec4(1.0, 1.0, 1.0, 0.4);
    final_color = mix(final_color, reflection_color, reflection * water_mask);

    // Add ripple distortion for low thirst
    final_color.rgb += vec3(ripples * 0.1);

    COLOR = final_color;
}