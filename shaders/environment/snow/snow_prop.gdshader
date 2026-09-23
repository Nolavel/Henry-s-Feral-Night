// Prop and environment material with settled snow and rime on top of a plain
// base. For placeholder geometry now; real assets include the .gdshaderinc.
shader_type spatial;

#include "res://shaders/environment/snow/snow_surface.gdshaderinc"

uniform vec4 base_color : source_color = vec4(0.32, 0.3, 0.28, 1.0);
uniform sampler2D base_texture : source_color, hint_default_white, filter_linear_mipmap;
uniform float base_roughness : hint_range(0.0, 1.0) = 0.9;
uniform float base_metallic : hint_range(0.0, 1.0) = 0.0;

group_uniforms snow;
uniform vec4 snow_color : source_color = vec4(0.92, 0.94, 0.97, 1.0);
uniform float snow_roughness : hint_range(0.0, 1.0) = 0.82;
// Width of the snow edge; wider reads softer, narrower reads icier.
uniform float snow_softness : hint_range(0.01, 0.5) = 0.12;

group_uniforms frost;
uniform vec4 frost_color : source_color = vec4(0.82, 0.88, 0.95, 1.0);
uniform float frost_strength : hint_range(0.0, 1.0) = 0.85;
// Baked edge/cavity mask for real assets, white where rime gathers.
uniform sampler2D edge_mask : hint_default_black, filter_linear_mipmap;
// How far in from an edge rime reaches at full cold, in metres.
uniform float rime_edge_width : hint_range(0.02, 2.0) = 0.45;
// Height of the cold band along the base of an object, in metres.
uniform float rime_base_height : hint_range(0.0, 2.0) = 0.5;

// Placeholder boxes describe the whole surface they belong to, so seams between
// pieces of one wall do not read as edges. Zero extents means use edge_mask.
instance uniform vec3 box_half_extents = vec3(0.0);
instance uniform vec3 box_center_offset = vec3(0.0);

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	vec3 world_normal = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;

	vec3 albedo = base_color.rgb * texture(base_texture, UV).rgb;
	float roughness = base_roughness;
	float metallic = base_metallic;

	float edge = texture(edge_mask, UV).r;
	if (box_half_extents.x > 0.0) {
		edge = max(edge, box_edge_factor(local_pos + box_center_offset, box_half_extents, rime_edge_width, rime_base_height));
	}
	float frost = frost_weight(world_normal, world_pos, edge) * frost_strength;
	albedo = mix(albedo, frost_color.rgb, frost);
	metallic = mix(metallic, 0.0, frost);

	float snow = snow_weight(world_normal, world_pos, snow_softness);
	albedo = mix(albedo, snow_color.rgb, snow);
	roughness = mix(roughness, snow_roughness, snow);
	metallic = mix(metallic, 0.0, snow);

	ALBEDO = albedo;
	ROUGHNESS = roughness;
	METALLIC = metallic;
}
