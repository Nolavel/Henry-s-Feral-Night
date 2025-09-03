shader_type canvas_item;

// Main texture (your image)
uniform sampler2D main_texture : source_color;

// Particle settings
uniform bool enable_particles = true;
uniform int particle_count : hint_range(8, 40) = 20;
uniform float particle_speed : hint_range(0.05, 0.8) = 0.25;
uniform float particle_size : hint_range(0.005, 0.03) = 0.012;
uniform float particle_lifetime : hint_range(1.0, 6.0) = 3.5;

// Particle appearance
uniform vec4 particle_color : source_color = vec4(1.0, 0.4, 0.2, 0.9);
uniform float particle_brightness : hint_range(0.8, 4.0) = 2.0;
uniform bool use_image_color = true; // Use colors from the image edges

// Animation settings
uniform float animation_speed : hint_range(0.3, 3.0) = 1.2;
uniform float edge_detection_threshold : hint_range(0.1, 0.9) = 0.3;
uniform float spawn_distance_from_edge : hint_range(0.01, 0.1) = 0.03;

// NEW: Edge distortion settings
uniform bool enable_edge_distortion = true;
uniform float distortion_strength : hint_range(0.0, 0.15) = 0.08;
uniform float distortion_frequency : hint_range(1.0, 20.0) = 6.0;
uniform float distortion_speed : hint_range(0.5, 4.0) = 2.0;
uniform float edge_fade_width : hint_range(0.05, 0.3) = 0.15;
uniform float distortion_noise_scale : hint_range(0.5, 5.0) = 2.5;

// Pseudo-random function
float rand(vec2 co) {
    return fract(sin(dot(co.xy, vec2(12.9898, 78.233))) * 43758.5453);
}

float rand2(vec2 co, float seed) {
    return fract(sin(dot(co.xy + seed, vec2(12.9898, 78.233))) * 43758.5453);
}

// Noise function for edge distortion
float noise(vec2 uv) {
    vec2 i = floor(uv);
    vec2 f = fract(uv);
    f = f * f * (3.0 - 2.0 * f);

    float a = rand(i);
    float b = rand(i + vec2(1.0, 0.0));
    float c = rand(i + vec2(0.0, 1.0));
    float d = rand(i + vec2(1.0, 1.0));

    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Edge distortion function
vec2 apply_edge_distortion(vec2 uv, float time) {
    if (!enable_edge_distortion) return uv;

    vec2 distorted_uv = uv;

    // Left edge distortion (only affect X coordinate near left edge)
    float left_edge_factor = smoothstep(edge_fade_width, 0.0, uv.x);
    if (left_edge_factor > 0.0) {
        float noise_left = noise(vec2(uv.y * distortion_frequency, time * distortion_speed));
        float distortion_left = (noise_left - 0.5) * distortion_strength * left_edge_factor;
        distorted_uv.x += distortion_left;
    }

    // Right edge distortion (only affect X coordinate near right edge)
    float right_edge_factor = smoothstep(1.0 - edge_fade_width, 1.0, uv.x);
    if (right_edge_factor > 0.0) {
        float noise_right = noise(vec2(uv.y * distortion_frequency, time * distortion_speed + 100.0));
        float distortion_right = (noise_right - 0.5) * distortion_strength * right_edge_factor;
        distorted_uv.x += distortion_right;
    }

    return distorted_uv;
}

// Check if pixel is near the edge of the image
bool is_near_edge(vec2 uv, sampler2D tex) {
    vec4 center = texture(tex, uv);
    if (center.a < edge_detection_threshold) return false;

    float step_size = 0.01;
    vec4 left = texture(tex, uv + vec2(-step_size, 0.0));
    vec4 right = texture(tex, uv + vec2(step_size, 0.0));
    vec4 up = texture(tex, uv + vec2(0.0, -step_size));
    vec4 down = texture(tex, uv + vec2(0.0, step_size));

    // If any neighbor has low alpha, we're near an edge
    return (left.a < edge_detection_threshold ||
            right.a < edge_detection_threshold ||
            up.a < edge_detection_threshold ||
            down.a < edge_detection_threshold);
}

// Get edge color at specific position
vec4 get_edge_color(vec2 uv, sampler2D tex) {
    return texture(tex, uv);
}

// Generate particles from image edges
float generate_edge_particle(vec2 uv, float particle_id, float time, out vec4 particle_final_color) {
    if (!enable_particles) return 0.0;

    float spawn_offset = particle_id * 0.15;
    float life = mod(time * animation_speed + spawn_offset, particle_lifetime) / particle_lifetime;

    if (life <= 0.0 || life >= 1.0) return 0.0;

    // Find a spawn point on the edge
    float edge_y = rand2(vec2(particle_id, 1.0), 10.0); // Random Y position
    float side_choice = rand2(vec2(particle_id, 2.0), 20.0);

    vec2 spawn_uv;
    float direction;

    // Choose left or right edge
    if (side_choice > 0.5) {
        // Right edge
        spawn_uv = vec2(1.0 - spawn_distance_from_edge, edge_y);
        direction = 1.0; // Move right
    } else {
        // Left edge
        spawn_uv = vec2(spawn_distance_from_edge, edge_y);
        direction = -1.0; // Move left
    }

    // Apply distortion to spawn point to match distorted image
    spawn_uv = apply_edge_distortion(spawn_uv, time);

    // Check if spawn point is actually near an edge
    if (spawn_uv.x < 0.0 || spawn_uv.x > 1.0 || spawn_uv.y < 0.0 || spawn_uv.y > 1.0) {
        return 0.0;
    }

    if (!is_near_edge(spawn_uv, main_texture)) {
        return 0.0;
    }

    // Get color from the edge
    vec4 edge_color = get_edge_color(spawn_uv, main_texture);
    if (use_image_color) {
        particle_final_color = edge_color * particle_brightness;
    } else {
        particle_final_color = particle_color * particle_brightness;
    }

    // Calculate particle movement
    float x_movement = direction * life * particle_speed;
    float y_drift = (rand2(vec2(particle_id, 3.0), 30.0) - 0.5) * 0.2 * life;

    // Add some turbulence to particle movement
    float turbulence = noise(vec2(particle_id, time * 2.0)) * 0.1;

    // Convert spawn UV to screen space (-1 to 1)
    vec2 spawn_screen = spawn_uv * 2.0 - 1.0;
    vec2 particle_pos = spawn_screen + vec2(x_movement + turbulence, y_drift);

    // Distance from current UV to particle
    float dist = length(uv - particle_pos);

    // Particle size animation (grows then shrinks)
    float size_curve = sin(life * 3.14159) * 1.5;
    float size = particle_size * size_curve;

    // Alpha animation (fade in, stay bright, fade out)
    float alpha = 1.0;
    if (life < 0.15) {
        alpha = life / 0.15; // Quick fade in
    } else if (life > 0.75) {
        alpha = (1.0 - life) / 0.25; // Slow fade out
    }

    // Create particle with soft edges
    float particle = smoothstep(size + 0.008, size * 0.2, dist) * alpha;

    return particle;
}

void fragment() {
    vec2 uv = UV;
    vec2 screen_uv = UV * 2.0 - 1.0; // For particle positioning

    // Apply edge distortion to UV coordinates
    vec2 distorted_uv = apply_edge_distortion(uv, TIME);

    // Get the original image with distortion applied
    vec4 original_color = vec4(0.0);
    if (distorted_uv.x >= 0.0 && distorted_uv.x <= 1.0 &&
        distorted_uv.y >= 0.0 && distorted_uv.y <= 1.0) {
        original_color = texture(main_texture, distorted_uv);
    }

    // Apply edge fade to make distortion look more natural
    if (enable_edge_distortion) {
        float left_fade = smoothstep(0.0, edge_fade_width * 0.5, uv.x);
        float right_fade = smoothstep(1.0, 1.0 - edge_fade_width * 0.5, uv.x);
        float edge_alpha = left_fade * right_fade;
        original_color.a *= edge_alpha;
    }

    // Start with the distorted image
    vec4 final_color = original_color;

    // Generate particles from edges
    if (enable_particles) {
        float total_particles = 0.0;
        vec4 accumulated_particle_color = vec4(0.0);

        for (int i = 0; i < particle_count; i++) {
            vec4 particle_color_out;
            float particle = generate_edge_particle(screen_uv, float(i), TIME, particle_color_out);

            if (particle > 0.0) {
                total_particles += particle;
                accumulated_particle_color += particle_color_out * particle;
            }
        }

        // Blend particles with the original image
        if (total_particles > 0.0) {
            accumulated_particle_color /= total_particles;
            accumulated_particle_color.a *= clamp(total_particles, 0.0, 1.0);
            final_color = mix(final_color, accumulated_particle_color, accumulated_particle_color.a);
        }
    }

    COLOR = final_color;
}