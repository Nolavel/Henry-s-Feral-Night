shader_type canvas_item;

// Sleep - Moon and Stars Theme
uniform float progress : hint_range(0.0, 1.0) = 1.0;

// Sleep colors - from bright moon to dark exhaustion
uniform vec4 full_color : source_color = vec4(0.9, 0.9, 0.7, 1.0);  // Bright moon
uniform vec4 mid_color : source_color = vec4(0.7, 0.7, 0.9, 0.9);   // Twilight
uniform vec4 low_color : source_color = vec4(0.4, 0.3, 0.5, 0.8);   // Dark purple
uniform vec4 empty_color : source_color = vec4(0.2, 0.2, 0.2, 0.6); // Almost black

// Moon parameters
uniform float moon_size : hint_range(0.25, 0.6) = 0.4;
uniform float crescent_depth : hint_range(0.0, 0.8) = 0.3;

// Star parameters
uniform bool enable_stars = true;
uniform float star_count : hint_range(3.0, 15.0) = 10.0;
uniform float star_twinkle_speed : hint_range(0.5, 3.0) = 1.8;
uniform float shooting_star_chance : hint_range(0.0, 1.0) = 0.3;

// Sleep effects
uniform bool enable_zzz_particles = true;
uniform float zzz_speed : hint_range(0.2, 2.0) = 1.0;
uniform bool enable_dream_wisps = true;
uniform float dream_intensity : hint_range(0.0, 2.0) = 1.2;

// Fatigue effects
uniform bool enable_tiredness_shadow = true;
uniform float shadow_intensity : hint_range(0.0, 1.0) = 0.8;

float rand(vec2 co) {
    return fract(sin(dot(co.xy, vec2(12.9898, 78.233))) * 43758.5453);
}

// Moon shape with crescent based on progress
float moon_shape(vec2 uv, float sleep_level) {
    // Main moon circle
    float moon_dist = length(uv) - moon_size;

    // Crescent effect - more crescent when tired
    float crescent_amount = (1.0 - sleep_level) * crescent_depth;
    vec2 crescent_center = vec2(moon_size * crescent_amount, 0.0);
    float crescent_dist = length(uv - crescent_center) - moon_size * (0.8 + crescent_amount);

    // Combine moon and crescent
    float final_moon = max(moon_dist, -crescent_dist);

    return final_moon;
}

// Twinkling stars
float generate_stars(vec2 uv, float time, float sleep_level) {
    if (!enable_stars) return 0.0;

    float stars = 0.0;
    float star_visibility = sleep_level * 0.8 + 0.2; // More stars when well-rested

    for (float i = 0.0; i < star_count; i++) {
        vec2 star_pos = vec2(
            (rand(vec2(i, 0.0)) - 0.5) * 3.0,
            (rand(vec2(i, 1.0)) - 0.5) * 3.0
        );

        // Avoid stars too close to moon
        if (length(star_pos) < moon_size + 0.2) continue;

        float star_dist = length(uv - star_pos);
        float star_size = 0.015 + rand(vec2(i, 2.0)) * 0.01;

        // Twinkling effect
        float twinkle = sin(time * star_twinkle_speed + i * 2.0) * 0.3 + 0.7;
        float star_alpha = smoothstep(star_size + 0.005, star_size, star_dist) * twinkle;

        stars += star_alpha * star_visibility;
    }

    return clamp(stars, 0.0, 1.0);
}

// Shooting star effect
float shooting_star(vec2 uv, float time) {
    if (rand(vec2(floor(time * 0.3), 0.0)) > shooting_star_chance) return 0.0;

    float shoot_time = mod(time * 2.0, 3.0);
    if (shoot_time > 1.0) return 0.0; // Shooting star lasts 0.5 seconds

    vec2 start_pos = vec2(-1.5, 0.8);
    vec2 end_pos = vec2(1.5, -0.8);
    vec2 star_pos = mix(start_pos, end_pos, shoot_time);

    // Trail effect
    vec2 to_star = uv - star_pos;
    vec2 trail_dir = normalize(end_pos - start_pos);
    float trail_dist = abs(dot(to_star, vec2(-trail_dir.y, trail_dir.x)));
    float along_trail = dot(to_star, trail_dir);

    float trail = smoothstep(0.02, 0.0, trail_dist) * smoothstep(-0.3, 0.0, along_trail);
    trail *= (1.0 - shoot_time); // Fade out

    return trail;
}

// "ZZZ" sleep particles
float zzz_particles(vec2 uv, float time, float sleep_level) {
    if (!enable_zzz_particles || sleep_level < 0.3) return 0.0;

    float zzz = 0.0;

    // Multiple Z letters floating up
    for (float i = 0.0; i < 3.0; i++) {
        float particle_time = mod(time * zzz_speed + i * 0.7, 2.0) / 2.0;

        if (particle_time > 0.8) continue; // Z appears briefly

        vec2 z_pos = vec2(
            0.6 + i * 0.15 - particle_time * 0.1,
            -0.3 + particle_time * 0.8
        );

        // Simple Z shape approximation
        float z_dist = length(uv - z_pos);
        float z_size = 0.05 + i * 0.01;

        float z_alpha = smoothstep(z_size + 0.01, z_size * 0.7, z_dist);
        z_alpha *= (1.0 - particle_time) * sleep_level; // Fade out as it rises

        zzz += z_alpha;
    }

    return clamp(zzz, 0.0, 1.0);
}

// Dream wisps for good sleep
float dream_wisps(vec2 uv, float time, float sleep_level) {
    if (!enable_dream_wisps || sleep_level < 0.5) return 0.0;

    float wisps = 0.0;

    for (float i = 0.0; i < 5.0; i++) {
        float wisp_time = time * 0.5 + i * 1.2;

        vec2 wisp_center = vec2(
            sin(wisp_time * 0.8 + i) * 0.6,
            cos(wisp_time * 0.6 + i * 0.7) * 0.4
        );

        float wisp_dist = length(uv - wisp_center);
        float wisp_size = 0.08 + sin(wisp_time + i) * 0.02;

        float wisp_alpha = smoothstep(wisp_size + 0.02, wisp_size * 0.5, wisp_dist);
        wisp_alpha *= (sin(wisp_time * 2.0 + i) * 0.3 + 0.7); // Gentle pulsing
        wisp_alpha *= sleep_level * dream_intensity;

        wisps += wisp_alpha;
    }

    return clamp(wisps, 0.0, 1.0);
}

// Tiredness shadow effect
float tiredness_shadow(vec2 uv, float sleep_level) {
    if (!enable_tiredness_shadow || sleep_level > 0.5) return 0.0;

    float tiredness = (0.5 - sleep_level) / 0.5;

    // Dark circles/shadows around the moon
    float shadow_dist = length(uv) - (moon_size + 0.1);
    float shadow = smoothstep(0.15, 0.05, shadow_dist) * tiredness * shadow_intensity;

    // Additional fatigue particles
    float fatigue_noise = sin(uv.x * 20.0) * sin(uv.y * 15.0) * 0.1;
    shadow += fatigue_noise * tiredness * 0.3;

    return clamp(shadow, 0.0, 1.0);
}

void fragment() {
    vec2 uv = UV * 2.0 - 1.0; // -1 to 1 range

    // Get moon shape
    float moon_dist = moon_shape(uv, progress);
    float moon_mask = 1.0 - smoothstep(-0.02, 0.02, moon_dist);

    // Progress-based color
    vec4 current_color;
    if (progress > 0.66) {
        current_color = mix(mid_color, full_color, (progress - 0.66) / 0.34);
    } else if (progress > 0.33) {
        current_color = mix(low_color, mid_color, (progress - 0.33) / 0.33);
    } else {
        current_color = mix(empty_color, low_color, progress / 0.33);
    }

    // Moon glow effect
    float moon_glow = 0.0;
    if (progress > 0.2) {
        float glow_dist = length(uv) - (moon_size + 0.1);
        moon_glow = (1.0 - smoothstep(0.0, 0.3, glow_dist)) * progress * 0.4;
    }

    // Generate stars
    float stars = generate_stars(uv, TIME, progress);

    // Shooting star
    float shooting = shooting_star(uv, TIME);

    // Sleep effects
    float zzz = zzz_particles(uv, TIME, progress);
    float wisps = dream_wisps(uv, TIME, progress);

    // Tiredness effects
    float shadow = tiredness_shadow(uv, progress);

    // Final composition
    vec4 final_color = vec4(0.0);

    // Moon
    final_color = mix(final_color, current_color, moon_mask);

    // Moon glow
    vec4 glow_color = current_color;
    glow_color.a *= 0.3;
    final_color = mix(final_color, glow_color, moon_glow);

    // Stars
    vec4 star_color = vec4(1.0, 1.0, 0.9, 1.0);
    final_color = mix(final_color, star_color, stars);

    // Shooting star
    vec4 shoot_color = vec4(1.0, 1.0, 0.8, 0.8);
    final_color = mix(final_color, shoot_color, shooting);

    // ZZZ particles
    vec4 zzz_color = vec4(0.9, 0.9, 0.7, 0.8);
    final_color = mix(final_color, zzz_color, zzz);

    // Dream wisps
    vec4 wisp_color = vec4(0.7, 0.8, 1.0, 0.6);
    final_color = mix(final_color, wisp_color, wisps);

    // Tiredness shadow
    vec4 shadow_color = vec4(0.1, 0.1, 0.15, 0.7);
    final_color = mix(final_color, shadow_color, shadow);

    COLOR = final_color;
}