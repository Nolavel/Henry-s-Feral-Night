shader_type canvas_item;

// Hunger - Effects for existing image
uniform float progress : hint_range(0.0, 1.0) = 1.0;

// Color modifications based on hunger
uniform vec4 full_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);    // Normal silver
uniform vec4 mid_tint : source_color = vec4(0.9, 0.9, 0.8, 1.0);     // Slightly dull
uniform vec4 low_tint : source_color = vec4(0.8, 0.6, 0.4, 1.0);     // Rusty brown
uniform vec4 empty_tint : source_color = vec4(0.5, 0.5, 0.5, 0.8);   // Dark gray

// Visual effects
uniform bool enable_shine = true;
uniform float shine_intensity : hint_range(0.0, 3.0) = 1.8;
uniform bool enable_food_particles = true;
uniform float particle_intensity : hint_range(0.0, 2.5) = 1.5;
uniform bool enable_rust_spots = true;
uniform float rust_intensity : hint_range(0.0, 2.0) = 1.2;

// Hunger effects
uniform bool enable_crumbs = true;
uniform float crumb_intensity : hint_range(0.0, 2.0) = 1.3;
uniform bool enable_grease_shine = true;
uniform float grease_amount : hint_range(0.0, 2.0) = 1.0;

float rand(vec2 co) {
    return fract(sin(dot(co.xy, vec2(12.9898, 78.233))) * 43758.5453);
}

// Metallic shine effect moving across cutlery
float metallic_shine(vec2 uv, float time, float hunger_level) {
    if (!enable_shine || hunger_level < 0.2) return 0.0;

    float shine = 0.0;

    // Moving shine wave across the image
    float wave1 = sin((uv.x + uv.y) * 8.0 + time * 3.0) * 0.5 + 0.5;
    float wave2 = sin((uv.x - uv.y) * 6.0 + time * 2.0) * 0.5 + 0.5;
    shine = (wave1 + wave2) * 0.2;

    // Bright reflection spots
    vec2 spot1 = vec2(0.3 + sin(time * 1.5) * 0.2, 0.4 + cos(time * 1.8) * 0.2);
    float spot1_dist = length(uv - spot1);
    shine += (1.0 - smoothstep(0.05, 0.15, spot1_dist)) * 0.6;

    vec2 spot2 = vec2(-0.3 + cos(time * 1.2) * 0.15, -0.2 + sin(time * 2.1) * 0.15);
    float spot2_dist = length(uv - spot2);
    shine += (1.0 - smoothstep(0.04, 0.12, spot2_dist)) * 0.4;

    return clamp(shine * hunger_level * shine_intensity, 0.0, 1.0);
}

// Food particles around cutlery when well-fed
float food_particles(vec2 uv, float time, float hunger_level) {
    if (!enable_food_particles || hunger_level < 0.4) return 0.0;

    float particles = 0.0;

    // Floating food particles/crumbs
    for (float i = 0.0; i < 10.0; i++) {
        float particle_time = time * 0.6 + i * 0.3;
        float life_cycle = mod(particle_time, 4.0) / 4.0;

        if (life_cycle > 0.7) continue; // Particle appears and disappears

        vec2 particle_pos = vec2(
            (rand(vec2(i, 0.0)) - 0.5) * 1.4,
            (rand(vec2(i, 1.0)) - 0.5) * 1.2
        );

        // Gentle floating motion
        particle_pos += vec2(
            sin(particle_time + i) * 0.08,
            cos(particle_time * 0.8 + i * 1.3) * 0.06
        );

        float particle_dist = length(uv - particle_pos);
        float particle_size = 0.012 + rand(vec2(i, 2.0)) * 0.008;

        float particle_alpha = (1.0 - smoothstep(particle_size, particle_size + 0.008, particle_dist));
        particle_alpha *= (1.0 - life_cycle) * hunger_level; // Fade over time

        particles += particle_alpha;
    }

    return clamp(particles * particle_intensity, 0.0, 1.0);
}

// Rust spots when very hungry
float rust_spots(vec2 uv, float hunger_level) {
    if (!enable_rust_spots || hunger_level > 0.4) return 0.0;

    float rust_amount = (0.4 - hunger_level) / 0.4;
    float rust = 0.0;

    // Multiple rust spots with different sizes
    for (float i = 0.0; i < 8.0; i++) {
        vec2 rust_pos = vec2(
            (rand(vec2(i, 3.0)) - 0.5) * 1.6,
            (rand(vec2(i, 4.0)) - 0.5) * 1.4
        );

        float rust_size = 0.02 + rand(vec2(i, 5.0)) * 0.04;
        float rust_dist = length(uv - rust_pos);

        float rust_spot = 1.0 - smoothstep(rust_size * 0.7, rust_size, rust_dist);
        rust += rust_spot * rand(vec2(i, 6.0)) * 0.3; // Varying intensity
    }

    // Add noise pattern for realistic rust texture
    float rust_noise = sin(uv.x * 40.0) * sin(uv.y * 35.0) * 0.1;
    rust_noise += sin(uv.x * 60.0 + uv.y * 45.0) * 0.05;
    rust += clamp(rust_noise, 0.0, 0.2);

    return clamp(rust * rust_amount * rust_intensity, 0.0, 1.0);
}

// Falling crumbs when hungry
float falling_crumbs(vec2 uv, float time, float hunger_level) {
    if (!enable_crumbs || hunger_level > 0.5) return 0.0;

    float hunger_amount = (0.5 - hunger_level) / 0.5;
    float crumbs = 0.0;

    for (float i = 0.0; i < 8.0; i++) {
        float crumb_time = mod(time * 1.0 + i * 0.4, 3.0) / 3.0;

        vec2 crumb_start = vec2(
            (rand(vec2(i, 7.0)) - 0.5) * 1.2,
            -0.9
        );

        vec2 crumb_pos = crumb_start + vec2(
            sin(crumb_time * 6.28 + i) * 0.1, // Slight sway
            crumb_time * 1.8
        );

        float crumb_dist = length(uv - crumb_pos);
        float crumb_size = 0.006 + rand(vec2(i, 8.0)) * 0.008;

        float crumb_alpha = 1.0 - smoothstep(crumb_size, crumb_size + 0.005, crumb_dist);
        crumb_alpha *= (1.0 - crumb_time) * hunger_amount; // Fade as they fall

        crumbs += crumb_alpha;
    }

    return clamp(crumbs * crumb_intensity, 0.0, 1.0);
}

// Grease shine effect when well-fed
float grease_shine(vec2 uv, float time, float hunger_level) {
    if (!enable_grease_shine || hunger_level < 0.6) return 0.0;

    float grease = 0.0;

    // Grease spots that make cutlery look well-used and fresh
    vec2 grease_center1 = vec2(0.2, -0.1);
    float grease_dist1 = length(uv - grease_center1);
    grease += (1.0 - smoothstep(0.08, 0.15, grease_dist1)) * (sin(time * 2.5) * 0.2 + 0.8);

    vec2 grease_center2 = vec2(-0.25, 0.15);
    float grease_dist2 = length(uv - grease_center2);
    grease += (1.0 - smoothstep(0.06, 0.12, grease_dist2)) * (sin(time * 1.8 + 1.0) * 0.3 + 0.7) * 0.8;

    return clamp(grease * hunger_level * grease_amount, 0.0, 1.0);
}

void fragment() {
    vec2 uv = UV * 2.0 - 1.0; // Convert to -1 to 1 range

    // Sample the original image
    vec4 original_color = texture(TEXTURE, UV);

    // Only apply effects where there's actual image content (not transparent)
    float image_mask = original_color.a;
    if (image_mask < 0.1) {
        COLOR = original_color; // Keep transparent areas transparent
    }

    // Progress-based tinting
    vec4 current_tint;
    if (progress > 0.66) {
        current_tint = mix(mid_tint, full_tint, (progress - 0.66) / 0.34);
    } else if (progress > 0.33) {
        current_tint = mix(low_tint, mid_tint, (progress - 0.33) / 0.33);
    } else {
        current_tint = mix(empty_tint, low_tint, progress / 0.33);
    }

    // Apply base tinting
    vec4 tinted_color = original_color * current_tint;

    // Calculate effects
    float shine = metallic_shine(uv, TIME, progress);
    float particles = food_particles(uv, TIME, progress);
    float rust = rust_spots(uv, progress);
    float crumbs = falling_crumbs(uv, TIME, progress);
    float grease = grease_shine(uv, TIME, progress);

    // Start with tinted base
    vec4 final_color = tinted_color;

    // Add metallic shine (brighten)
    vec4 shine_color = vec4(1.2, 1.2, 1.0, 1.0);
    final_color = mix(final_color, final_color * shine_color, shine);

    // Add grease shine (subtle golden tint)
    vec4 grease_color = vec4(1.1, 1.05, 0.9, 1.0);
    final_color = mix(final_color, final_color * grease_color, grease);

    // Add rust (darken with brown tint) - only on existing image
    vec4 rust_color = vec4(0.6, 0.3, 0.2, 1.0);
    final_color = mix(final_color, rust_color, rust * image_mask);

    // Add food particles (golden breadcrumbs)
    vec4 particle_color = vec4(0.9, 0.7, 0.4, 1.0);
    final_color = mix(final_color, particle_color, particles);

    // Add falling crumbs
    vec4 crumb_color = vec4(0.8, 0.6, 0.4, 0.9);
    final_color = mix(final_color, crumb_color, crumbs);

    COLOR = final_color;
}