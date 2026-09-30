class_name StylizedEnvironmentMaterial
extends RefCounted

## Central material adapter for opaque environment meshes.
## Custom shader families should include stylized_shadow.gdshaderinc directly.
## Transparent/unshaded StandardMaterial3D resources are intentionally left alone.

const OPAQUE_SHADER: Shader = preload(
	"res://shaders/environment/materials/stylized_environment.gdshader"
)
const DOUBLE_SIDED_SHADER: Shader = preload(
	"res://shaders/environment/materials/stylized_environment_double_sided.gdshader"
)


static func make(
	color: Color,
	roughness: float,
	vertex_color: bool = false,
	double_sided: bool = false,
	metallic: float = 0.0
) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = DOUBLE_SIDED_SHADER if double_sided else OPAQUE_SHADER
	material.set_shader_parameter("albedo_color", color)
	material.set_shader_parameter("roughness", roughness)
	material.set_shader_parameter("metallic", metallic)
	material.set_shader_parameter("use_vertex_color", vertex_color)
	return material


static func make_unshaded(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material


static func from_standard(source: StandardMaterial3D) -> Material:
	if source == null:
		return null
	if source.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
		return source
	if source.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		return source

	var material := make(
		source.albedo_color,
		source.roughness,
		source.vertex_color_use_as_albedo,
		source.cull_mode == BaseMaterial3D.CULL_DISABLED,
		source.metallic
	)
	if source.albedo_texture != null:
		material.set_shader_parameter("use_albedo_texture", true)
		material.set_shader_parameter("albedo_texture", source.albedo_texture)
	if source.normal_enabled and source.normal_texture != null:
		material.set_shader_parameter("use_normal_texture", true)
		material.set_shader_parameter("normal_texture", source.normal_texture)
		material.set_shader_parameter("normal_scale", source.normal_scale)
	material.set_shader_parameter(
		"uv_scale",
		Vector2(source.uv1_scale.x, source.uv1_scale.y)
	)
	material.set_shader_parameter(
		"uv_offset",
		Vector2(source.uv1_offset.x, source.uv1_offset.y)
	)
	if source.emission_enabled:
		material.set_shader_parameter(
			"emission_color",
			Vector3(source.emission.r, source.emission.g, source.emission.b)
		)
		material.set_shader_parameter(
			"emission_energy",
			source.emission_energy_multiplier
		)
	return material


static func apply_to_tree(root: Node) -> int:
	if root == null:
		return 0
	return _apply_subtree(root, true)


static func _apply_subtree(node: Node, is_root: bool) -> int:
	## Script-owned visual subtrees often mutate their material objects at runtime
	## (stove embers, particles, interaction previews). Do not sever those links.
	if not is_root and node.get_script() != null and not node is MeshInstance3D:
		return 0
	var converted := 0
	if node is MeshInstance3D:
		converted += _apply_to_mesh(node as MeshInstance3D)
	for child: Node in node.get_children():
		converted += _apply_subtree(child, false)
	return converted


static func _apply_to_mesh(instance: MeshInstance3D) -> int:
	var converted := 0
	if instance.material_override is StandardMaterial3D:
		var source_override := instance.material_override as StandardMaterial3D
		var replacement := from_standard(source_override)
		if replacement != source_override:
			instance.material_override = replacement
			converted += 1
			return converted

	if instance.mesh == null:
		return converted
	for surface: int in range(instance.mesh.get_surface_count()):
		var source: Material = instance.get_surface_override_material(surface)
		if source == null:
			source = instance.mesh.surface_get_material(surface)
		if not source is StandardMaterial3D:
			continue
		var standard := source as StandardMaterial3D
		var replacement := from_standard(standard)
		if replacement == standard:
			continue
		instance.set_surface_override_material(surface, replacement)
		converted += 1
	return converted
