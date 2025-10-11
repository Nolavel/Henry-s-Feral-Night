shader_type spatial;

varying vec3 world_vertex;

void vertex() {
    world_vertex = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    float h = world_vertex.y;
    
    vec3 deep_water = vec3(0.0, 0.2, 0.5);
    vec3 shallow_water = vec3(0.2, 0.4, 0.6);
    vec3 sand = vec3(0.8, 0.7, 0.5);
    vec3 grass = vec3(0.3, 0.5, 0.2);
    vec3 rock = vec3(0.4, 0.35, 0.3);
    
    vec3 color;
    
    if (h < -2.0) {
        color = deep_water;
    } else if (h < 0.0) {
        color = mix(deep_water, shallow_water, (h + 2.0) / 2.0);
    } else if (h < 2.0) {
        color = mix(shallow_water, sand, h / 2.0);
    } else if (h < 20.0) {
        color = mix(sand, grass, (h - 2.0) / 18.0);
    } else {
        color = mix(grass, rock, clamp((h - 20.0) / 80.0, 0.0, 1.0));
    }
    
    ALBEDO = color;
}