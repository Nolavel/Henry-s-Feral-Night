// Island ground from the heightmap mesh: sand at the tide line, turf on the
// flats, rock on slopes, with the shared settled-snow response on top.
shader_type spatial;

#include "res://shaders/environment/snow/snow_surface.gdshaderinc"

uniform vec4 sand_color : source_color = vec4(0.62, 0.58, 0.49, 1.0);
uniform vec4 turf_color : source_color = vec4(0.38, 0.40, 0.33, 1.0);
uniform vec4 rock_color : source_color = vec4(0.36, 0.35, 0.34, 1.0);
uniform vec4 snow_color : source_color = vec4(0.8, 0.83, 0.88, 1.0);
// Sand up to this height above the sea, blending out over the next metre.
uniform float sand_height_m = 1.2;
uniform float snow_softness : hint_range(0.01, 0.5) = 0.15;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float up = clamp(world_normal.y, 0.0, 1.0);
	float grain = snow_breakup(world_pos, 0.35);
	vec3 ground = mix(turf_color.rgb, rock_color.rgb, smoothstep(0.93, 0.8, up + (grain - 0.5) * 0.08));
	float sand = 1.0 - smoothstep(sand_height_m, sand_height_m + 1.0, world_pos.y + (grain - 0.5) * 0.6);
	ground = mix(ground, sand_color.rgb, sand);
	ground *= 0.9 + grain * 0.2;
	float snow = snow_weight(world_normal, world_pos, snow_softness);
	ALBEDO = mix(ground, snow_color.rgb, snow);
	ROUGHNESS = mix(0.95, 0.85, snow);
}
