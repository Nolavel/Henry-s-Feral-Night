extends SceneTree

var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for path: String in [
		"res://shaders/environment/terrain/island_terrain.gdshader",
		"res://shaders/environment/snow/snow_chunk_cover.gdshader",
		"res://shaders/environment/snow/snow_ground.gdshader",
		"res://shaders/environment/materials/stylized_environment.gdshader",
		"res://shaders/environment/materials/stylized_environment_double_sided.gdshader",
		"res://shaders/environment/ice/frozen_sea.gdshader",
		"res://shaders/environment/stylized_shadows.gdshader",
	]:
		_check(load(path) is Shader, "shader failed to load: %s" % path)

	var material := StylizedEnvironmentMaterial.make(Color.WHITE, 0.8)
	_check(material is ShaderMaterial, "opaque environment factory did not return ShaderMaterial")
	_check(material.shader != null, "environment ShaderMaterial has no shader")

	var double_sided := StylizedEnvironmentMaterial.make(Color.WHITE, 0.8, false, true)
	_check(double_sided is ShaderMaterial, "double-sided environment factory failed")
	_check(double_sided.shader != material.shader, "double-sided material did not select its cull-disabled shader")

	var shelter_source := StandardMaterial3D.new()
	var shelter_material := StylizedEnvironmentMaterial.from_standard(shelter_source, false) as ShaderMaterial
	_check(shelter_material != null, "shelter material conversion failed")
	if shelter_material != null:
		_check(
			shelter_material.get_shader_parameter("stylized_shadow_warp_enabled") == false,
			"shelter receiver still warps local-light shadow lookup"
		)

	var source := StandardMaterial3D.new()
	source.albedo_color = Color(0.3, 0.4, 0.5)
	source.roughness = 0.77
	source.metallic = 0.2
	_check(
		StylizedEnvironmentMaterial.from_standard(source) is ShaderMaterial,
		"opaque StandardMaterial3D was not adapted"
	)

	var transparent := StandardMaterial3D.new()
	transparent.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_check(
		StylizedEnvironmentMaterial.from_standard(transparent) == transparent,
		"transparent material should stay on its original path"
	)

	var city := KeyWestCityVisuals.make_materials()
	_check(city.get("building") is ShaderMaterial, "city building material bypasses stylized lighting")
	_check(city.get("asphalt") is ShaderMaterial, "city road material bypasses stylized lighting")
	var line := city.get("white_line") as StandardMaterial3D
	_check(
		line != null and line.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED,
		"road marking should remain deliberately unshaded"
	)

	var contract_source := FileAccess.get_file_as_string(
		"res://shaders/environment/stylized_shadow.gdshaderinc"
	)
	_check(contract_source.contains("hfn_shadow_value_noise"), "shared contract lost procedural breakup noise")
	_check(contract_source.contains("sample_directional_shadow"), "shared contract is not using the custom engine sampler")
	_check(contract_source.contains("LIGHT_INDEX"), "shared contract is not addressing the current directional light")
	_check(contract_source.contains("if (!directional)"), "local-light physical attenuation guard is missing")
	_check(contract_source.contains("return base;"), "local lights are still being ink-darkened")

	for key: String in [
		"stylized_shadow_strength",
		"stylized_shadow_local_strength",
		"stylized_shadow_floor",
		"stylized_shadow_edge_light",
		"stylized_shadow_threshold",
		"stylized_shadow_break_softness",
		"stylized_shadow_macro_scale",
		"stylized_shadow_detail_scale",
		"stylized_shadow_detail_amount",
	]:
		_check(
			ProjectSettings.has_setting("shader_globals/%s" % key),
			"missing global shader parameter: %s" % key
		)

	_check(contract_source.contains("HFN_SHADOW_OFFSET_1_M"), "primary shadow sample offset is missing")
	_check(contract_source.contains("HFN_SHADOW_OFFSET_2_M"), "secondary shadow sample offset is missing")
	var body_source := FileAccess.get_file_as_string(
		"res://shaders/environment/materials/stylized_environment_body.gdshaderinc"
	)
	_check(body_source.contains("HFN_STYLIZED_SHADOW_WARP"), "generic environment lost the stock shadow-lookup warp")
	## Stock Godot is the baseline: the patched sampler must stay behind its define.
	_check(contract_source.contains("// #define HFN_PATCHED_SHADOW_SAMPLER"), "the patched shadow sampler is switched on by default")
	_check(contract_source.contains("coarse_islands"), "stock contract lost hard noise islands")

	if _failures > 0:
		push_error("stylized shadows: %d check(s) failed" % _failures)
		quit(1)
		return
	print("stylized shadows: shared production contract passed")
	quit(0)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("stylized shadows: %s" % message)
