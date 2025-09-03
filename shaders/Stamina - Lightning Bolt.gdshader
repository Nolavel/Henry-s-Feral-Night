shader_type canvas_item;

// Stamina - Dynamic Lightning Theme
uniform float progress : hint_range(0.0, 1.0) = 1.0;

// Lightning colors - more dramatic range
uniform vec4 full_color : source_color = vec4(0.2, 0.7, 1.0, 1.0);  // Bright electric blue
uniform vec4 mid_color : source_color = vec4(0.8, 0.9, 1.0, 1.0);   // White-blue
uniform vec4 low_color : source_color = vec4(1.0, 0.8, 0.2, 1.0);   // Orange warning
uniform vec4 critical_color : source_color = vec4(1.0, 0.3, 0.3, 1.0); // Red danger
uniform vec4 empty_color : source_color = vec4(0.4, 0.4, 0.4, 0.2);  // Dark gray

// Dynamic lightning parameters
uniform float bolt_base_thickness : hint_range(0.015, 0.1) = 0.045;
uniform float bolt_flicker_intensity : hint_range(0.0, 3.0) = 2.5;
uniform float energy_pulse_normal : hint_range(1.0, 8.0) = 3.0;
uniform float energy_pulse_panic : hint_range(5.0, 25.0) = 15.0;

// Advanced lightning shape
uniform float jagged_intensity : hint_range(0.05, 0.4) = 0.2;
uniform float segment_count : hint_range(4.0, 16.0) = 10.0;
uniform float branch_probability : hint_range(0.0, 0.8) = 0.4;

// Visual effects
uniform bool enable_sparks = true;
uniform bool enable_electric_field = true;
uniform bool enable_panic_flicker = true;
uniform float glow_intensity : hint_range(0.0, 4.0) = 2.2;

float rand(vec2 co) {
    return fract(sin(dot(co.xy, vec2(12.9898, 78.233))) * 43758.5453);
}

// Advanced lightning bolt with branching
float lightning_bolt(vec2 uv, float time, float energy_level) {
    float x_progress = (uv.x + 1.0) * 0.5; // Convert to 0-1

    // Main bolt zigzag pattern
    float segment_pos = x_progress * segment_count;
    float segment_floor = floor(segment_pos);
    float segment_fract = fract(segment_pos);

    // More chaotic pattern when energy is low
    float chaos_factor = (1.0 - energy_level) * 2.0;

    // Alternating pattern with time-based variation
    float zigzag_sign = (mod(segment_floor, 2.0) == 0.0) ? 1.0 : -1.0;
    float time_wobble = sin(time * 8.0 + segment_floor * 2.0) * 0.3 * chaos_factor;
    float random_offset = (rand(vec2(segment_floor, floor(time * 4.0))) - 0.5) * 0.4 * chaos_factor;

    float target_y = zigzag_sign * jagged_intensity + random_offset + time_wobble;
    float prev_y = -zigzag_sign * jagged_intensity + rand(vec2(segment_floor - 1.0, floor(time * 3.0))) * 0.3 * chaos_factor;

    float bolt_y = mix(prev_y, target_y, smoothstep(0.0, 1.0, segment_fract));

    // Distance from main bolt path
    float dist_to_bolt = abs(uv.y - bolt_y);

    // Dynamic thickness based on energy and flickering
    float flicker = sin(time * 12.0 + x_progress * 20.0) * 0.3 + 0.7;
    if (energy_level < 0.3) {
        flicker *= (sin(time * 30.0) * 0.5 + 0.5); // Rapid flicker when critical
    }

    float dynamic_thickness = bolt_base_thickness * (0.5 + 0.5 * energy_level) * flicker;

    float main_bolt = 1.0 - smoothstep(dynamic_thickness * 0.4, dynamic_thickness, dist_to_bolt);

    // Add secondary branches
    float branches = 0.0;
    if (rand(vec2(segment_floor, 1.0)) < branch_probability && energy_level > 0.2) {
        for (float j = 0.0; j < 2.0; j++) {
            float branch_x = segment_floor / segment_count * 2.0 - 1.0 + (j - 0.5) * 0.1;
            float branch_y_start = bolt_y;
            float branch_direction = (j == 0.0) ? 1.0 : -1.0;
            float branch_length = 0.15 + rand(vec2(segment_floor, j)) * 0.1;

            vec2 branch_end = vec2(branch_x + 0.08, branch_y_start + branch_direction * branch_length);

            // Simple branch line
            vec2 to_branch = uv - vec2(branch_x, branch_y_start);
            vec2 branch_dir = normalize(branch_end - vec2(branch_x, branch_y_start));
            float branch_proj = dot(to_branch, branch_dir);

            if (branch_proj > 0.0 && branch_proj < length(branch_end - vec2(branch_x, branch_y_start))) {
                vec2 closest_point = vec2(branch_x, branch_y_start) + branch_dir * branch_proj;
                float branch_dist = length(uv - closest_point);
                branches += (1.0 - smoothstep(0.01, 0.025, branch_dist)) * 0.6 * energy_level;
            }
        }
    }

    return clamp(main_bolt + branches, 0.0, 1.0);
}

// Enhanced electric sparks with panic mode
float generate_sparks(vec2 uv, float time, float energy_level) {
    if (!enable_sparks) return 0.0;

    float sparks = 0.0;
    float spark_count = 6.0 + (1.0 - energy_level) * 8.0; // More sparks when low energy

    // Spark frequency increases dramatically when energy is low
    float spark_freq = mix(8.0, 25.0, 1.0 - energy_level);

    for (float i = 0.0; i < spark_count; i++) {
        float spark_x = (rand(vec2(i, 0.0)) * 2.0 - 1.0) * 0.9;
        float spark_time_offset = rand(vec2(i, 1.0)) * 3.0;
        float spark_life = mod(time * spark_freq + spark_time_offset, 1.0);

        // Sparks last longer when energy is low (more desperate)
        float spark_duration = 0.3 + (1.0 - energy_level) * 0.4;
        if (spark_life > spark_duration) continue;

        vec2 spark_pos = vec2(
            spark_x,
            sin(spark_x * 4.0 + time * 6.0 + i) * jagged_intensity * (1.5 - energy_level)
        );
        float spark_dist = length(uv - spark_pos);

        // Bigger, brighter sparks when desperate
        float spark_size = (0.015 + (1.0 - energy_level) * 0.025) * (1.0 - spark_life / spark_duration);
        float spark_intensity = (1.0 - spark_life / spark_duration) * (1.5 - energy_level);

        sparks += smoothstep(spark_size + 0.008, spark_size, spark_dist) * spark_intensity;
    }

    return clamp(sparks, 0.0, 1.0);
}

// Electric field distortion around lightning
float electric_field(vec2 uv, float time, float energy_level) {
    if (!enable_electric_field || energy_level > 0.8) return 0.0;

    float field_intensity = (0.8 - energy_level) / 0.8;

    // Electric field lines
    float field = 0.0;
    float field_frequency = 15.0 + field_intensity * 20.0;

    // Horizontal field lines
    for (float i = -0.6; i <= 0.6; i += 0.15) {
        float line_y = i + sin(uv.x * 8.0 + time * 4.0 + i * 10.0) * 0.05 * field_intensity;
        float line_dist = abs(uv.y - line_y);
        field += (1.0 - smoothstep(0.002, 0.008, line_dist)) * 0.2 * field_intensity;
    }

    // Crackling noise
    float noise = sin(uv.x * field_frequency + time * 10.0) * sin(uv.y * field_frequency * 1.3 + time * 8.0);
    field += clamp(noise * 0.15 * field_intensity, 0.0, 0.3);

    return field;
}

void fragment() {
    vec2 uv = UV * 2.0 - 1.0; // -1 to 1 range

    // HEARTBEAT PULSE SYSTEM - realistic cardiac rhythm
    float heartbeat_pulse = 0.0;

    // Different heart rates based on stamina level
    float bpm_relaxed = 60.0;   // Resting heart rate
    float bpm_active = 90.0;    // Active heart rate
    float bpm_intense = 130.0;  // Intense exercise
    float bpm_panic = 180.0;    // Maximum panic/exhaustion

    float current_bpm;
    if (progress > 0.7) {
        current_bpm = mix(bpm_active, bpm_relaxed, (progress - 0.7) / 0.3);
    } else if (progress > 0.4) {
        current_bpm = mix(bpm_intense, bpm_active, (progress - 0.4) / 0.3);
    } else {
        current_bpm = mix(bpm_panic, bpm_intense, progress / 0.4);
    }

    // Convert BPM to heartbeat cycle
    float heart_cycle_speed = current_bpm / 60.0; // Beats per second
    float heart_time = TIME * heart_cycle_speed;
    float beat_phase = fract(heart_time);

    // Realistic heartbeat waveform (lub-dub pattern)
    if (beat_phase < 0.15) {
        // First beat (lub) - stronger
        float lub_phase = beat_phase / 0.15;
        heartbeat_pulse = sin(lub_phase * 3.14159) * 0.8;
    } else if (beat_phase > 0.25 && beat_phase < 0.35) {
        // Second beat (dub) - weaker
        float dub_phase = (beat_phase - 0.25) / 0.1;
        heartbeat_pulse = sin(dub_phase * 3.14159) * 0.4;
    } else {
        // Rest phase between beats
        heartbeat_pulse = 0.0;
    }

    // Add slight baseline pulse for realism
    float baseline_pulse = sin(heart_time * 2.0 * 3.14159) * 0.1 + 0.9;

    // Combine heartbeat with baseline
    float combined_pulse = baseline_pulse + heartbeat_pulse * (1.5 - progress); // Stronger heartbeat when tired

    // Additional panic irregularity for very low stamina
    float panic_irregularity = 1.0;
    if (enable_panic_flicker && progress < 0.2) {
        float panic_intensity = (0.2 - progress) / 0.2;
        // Irregular heartbeat - arrhythmia when critically low
        float irregular_beat = sin(TIME * 17.3) * sin(TIME * 23.7) * 0.3 * panic_intensity;
        panic_irregularity = 1.0 + irregular_beat;

        // Occasional heart palpitations
        float palpitation_time = mod(TIME * 0.3, 1.0);
        if (palpitation_time < 0.1) {
            panic_irregularity *= (1.0 + sin(TIME * 50.0) * 0.4 * panic_intensity);
        }
    }

    combined_pulse *= panic_irregularity;

    // Get lightning bolt shape
    float bolt = lightning_bolt(uv, TIME, progress);

    // Progress mask - only show bolt up to progress level
    float x_progress = (uv.x + 1.0) * 0.5;
    float progress_mask = step(x_progress, progress);

    // Dynamic color based on energy level
    vec4 current_color;
    if (progress > 0.75) {
        current_color = mix(mid_color, full_color, (progress - 0.75) / 0.25);
    } else if (progress > 0.4) {
        current_color = mix(low_color, mid_color, (progress - 0.4) / 0.35);
    } else if (progress > 0.15) {
        current_color = mix(critical_color, low_color, (progress - 0.15) / 0.25);
    } else {
        current_color = mix(empty_color, critical_color, progress / 0.15);
    }

    // Apply pulsing to color
    current_color.rgb *= combined_pulse;
    current_color.a *= (0.7 + 0.3 * combined_pulse);

    // Electric sparks
    float sparks = generate_sparks(uv, TIME, progress);

    // Electric field effect
    float field = electric_field(uv, TIME, progress);

    // Combine bolt with progress
    float final_bolt = bolt * progress_mask;

    // Enhanced glow effect - stronger when energy is low
    float glow = 0.0;
    float glow_radius = 0.15 + (1.0 - progress) * 0.25; // Bigger glow when desperate
    float glow_strength = glow_intensity * (0.8 + 0.4 * (1.0 - progress));

    // Distance-based glow
    float x_progress_uv = (uv.x + 1.0) * 0.5;
    if (x_progress_uv <= progress) {
        // Find distance to nearest lightning
        float min_dist_to_lightning = 1.0;
        for (float test_x = -1.0; test_x <= 1.0; test_x += 0.05) {
            if ((test_x + 1.0) * 0.5 > progress) break;
            float test_bolt = lightning_bolt(vec2(test_x, uv.y), TIME, progress);
            if (test_bolt > 0.1) {
                min_dist_to_lightning = min(min_dist_to_lightning, abs(test_x - uv.x));
            }
        }
        glow = (1.0 - smoothstep(0.0, glow_radius, min_dist_to_lightning)) * glow_strength * combined_pulse;
    }

    // Final composition
    vec4 final_color = vec4(0.0);

    // Main lightning bolt
    final_color = mix(final_color, current_color, final_bolt);

    // Add sparks (enhanced brightness)
    vec4 spark_color = mix(critical_color, full_color, progress);
    spark_color.rgb *= 1.8; // Very bright sparks
    final_color = mix(final_color, spark_color, sparks * progress_mask);

    // Add electric field
    vec4 field_color = mix(critical_color, low_color, 0.5);
    field_color.a *= 0.4;
    final_color = mix(final_color, field_color, field * progress_mask);

    // Add glow
    vec4 glow_color = current_color;
    glow_color.a *= glow * 0.6;
    final_color = final_color + glow_color;

    COLOR = final_color;
}