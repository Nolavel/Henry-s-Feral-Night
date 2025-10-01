shader_type canvas_item;

// Main progress value (0.0 to 1.0)
uniform float progress : hint_range(0.0, 1.0) = 1.0;

// Colors for different stamina levels
uniform vec4 full_stamina_color : source_color = vec4(0.8, 0.9, 0.3, 1.0); // Yellowish-green
uniform vec4 low_stamina_color : source_color = vec4(0.9, 0.2, 0.2, 1.0);  // Red

// Bar appearance
uniform float bar_height : hint_range(0.1, 1.0) = 0.8;
uniform float bar_roundness : hint_range(0.0, 0.5) = 0.1;
uniform float border_width : hint_range(0.0, 0.1) = 0.02;
uniform vec4 border_color : source_color = vec4(0.2, 0.2, 0.2, 0.8);

// Wave effect for the progress line
uniform float wave_amplitude : hint_range(0.0, 0.05) = 0.015;
uniform float wave_frequency : hint_range(0.0, 15.0) = 8.0;
uniform float wave_speed : hint_range(0.0, 3.0) = 2.0;

// Particle effects
uniform bool enable_particles = true;
uniform int particle_count : hint_range(0, 25) = 12;
uniform float particle_speed : hint_range(0.01, 0.3) = 0.08;
uniform float particle_size : hint_range(0.005, 0.05) = 0.015;
uniform float particle_lifetime : hint_range(1.0, 5.0) = 2.5;

// Glow effect
uniform bool enable_glow = true;
uniform float glow_intensity : hint_range(0.0, 2.0) = 0.6;
uniform float glow_size : hint_range(0.01, 0.2) = 0.08;

// Pseudo-random function
float rand(vec2 co) {
    return fract(sin(dot(co.xy, vec2(12.9898, 78.233))) * 43758.5453);
}

// Rounded rectangle function
float rounded_rect(vec2 uv, vec2 size, float radius) {
    vec2 d = abs(uv) - size + radius;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - radius;
}

// Particle function
float generate_particle(vec2 uv, float particle_id, float time) {
    if (!enable_particles) return 0.0;

    float spawn_offset = particle_id * 0.15;
    float life = mod(time + spawn_offset, particle_lifetime) / particle_lifetime;

    if (life <= 0.0 || life >= 1.0) return 0.0;

    // Particle position
    float y_pos = rand(vec2(particle_id, 1.0)) * 0.6 - 0.3; // Random Y within bar height
    float x_start = progress - 0.1; // Start near the progress edge
    float x_pos = x_start + life * particle_speed;

    // Don't show particles beyond progress
    if (x_pos > progress + 0.05) return 0.0;

    vec2 particle_pos = vec2(x_pos, y_pos);
    float dist = length(uv - particle_pos);

    // Particle size varies with life
    float size = particle_size * (1.0 - life * 0.5);
    float alpha = (1.0 - life) * (1.0 - life); // Fade out over time

    return smoothstep(size + 0.01, size, dist) * alpha;
}

void fragment() {
    vec2 uv = UV * 2.0 - 1.0; // Convert to -1 to 1 range

    // Calculate current stamina color based on progress
    vec4 stamina_color = mix(low_stamina_color, full_stamina_color, progress);

    // Create the main bar shape
    vec2 bar_size = vec2(0.9, bar_height * 0.5);
    float bar_dist = rounded_rect(uv, bar_size, bar_roundness);

    // Create border
    float border = smoothstep(0.0, 0.01, bar_dist);
    float inner_bar = smoothstep(0.0, 0.01, bar_dist + border_width);

    // Calculate wave effect
    float wave_offset = wave_amplitude * sin(wave_frequency * uv.y + TIME * wave_speed);
    float progress_with_wave = progress + wave_offset * 0.5;

    // Progress fill with wave
    float progress_x = (uv.x + 0.9) / 1.8; // Convert to 0-1 range for progress
    float fill = step(progress_x, progress_with_wave);

    // Only show fill within the bar
    fill *= (1.0 - inner_bar);

    // Generate particles
    float particles = 0.0;
    if (enable_particles && progress > 0.1) {
        for (int i = 0; i < particle_count; i++) {
            particles += generate_particle(uv, float(i), TIME);
        }
        particles = clamp(particles, 0.0, 1.0);
    }

    // Glow effect
    float glow = 0.0;
    if (enable_glow && progress > 0.0) {
        float glow_dist = bar_dist + glow_size;
        glow = (1.0 - smoothstep(0.0, glow_size, glow_dist)) * glow_intensity;
        glow *= progress; // Glow intensity based on stamina level
    }

    // Combine everything
    vec4 final_color = vec4(0.0); // Transparent background

    // Add border
    final_color = mix(final_color, border_color, (1.0 - border) * border_color.a);

    // Add main bar fill
    final_color = mix(final_color, stamina_color, fill);

    // Add particles
    final_color = mix(final_color, stamina_color, particles);

    // Add glow
    if (enable_glow) {
        vec4 glow_color = stamina_color;
        glow_color.a *= glow * 0.3;
        final_color = mix(final_color, glow_color, glow);
    }

    COLOR = final_color;
}