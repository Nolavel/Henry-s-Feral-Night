extends SceneTree

const ISLAND_SCENE := "res://experimental_location/scenes/Graciosa_Island_Terrain.tscn"
const FADE_VOLUME_SCENE := "res://scenes/environment/visual_fx/FadeVolume.tscn"
const SHADOW_MATERIAL := "res://scenes/environment/visual_fx/StylizedShadowMaterial.tres"
const OUTPUT_DIR := "res://artifacts/island_visual_fx"
const INITIAL_WARMUP_FRAMES := 72
const SHOT_SETTLE_FRAMES := 18

const SHOTS := [
	{
		"name": "01_spawn_wide",
		"camera_offset": Vector3(165.0, 92.0, 185.0),
		"target_offset": Vector3(-35.0, 5.0, -55.0),
		"fov": 60.0,
		"volume_t": 0.58,
		"volume_scale": Vector3(28.0, 18.0, 24.0),
	},
	{
		"name": "02_ground_tps",
		"camera_offset": Vector3(42.0, 12.0, 52.0),
		"target_offset": Vector3(-22.0, 3.0, -34.0),
		"fov": 64.0,
		"volume_t": 0.66,
		"volume_scale": Vector3(13.0, 7.0, 10.0),
	},
	{
		"name": "03_cross_slope",
		"camera_offset": Vector3(-175.0, 58.0, 48.0),
		"target_offset": Vector3(78.0, 7.0, -88.0),
		"fov": 58.0,
		"volume_t": 0.63,
		"volume_scale": Vector3(30.0, 17.0, 22.0),
	},
	{
		"name": "04_overlook",
		"camera_offset": Vector3(30.0, 175.0, 250.0),
		"target_offset": Vector3(-45.0, 4.0, -75.0),
		"fov": 55.0,
		"volume_t": 0.62,
		"volume_scale": Vector3(44.0, 25.0, 34.0),
	},
]

var _scene_root: Node3D
var _terrain: Terrain3D
var _camera: Camera3D
var _sun: DirectionalLight3D
var _volume: Node3D
var _anchor: Vector3
var _frame := 0
var _configured := false
var _shot_index := -1
var _settle := 0


func _initialize() -> void:
	var packed := load(ISLAND_SCENE) as PackedScene
	if packed == null:
		push_error("Island VFX capture: Graciosa scene failed to load.")
		quit(1)
		return

	_scene_root = packed.instantiate() as Node3D
	if _scene_root == null:
		push_error("Island VFX capture: Graciosa root is not Node3D.")
		quit(1)
		return

	root.add_child(_scene_root)


func _process(_delta: float) -> bool:
	_frame += 1

	if not _configured:
		if _frame < 4:
			return false
		_configure_scene()
		return false

	if _frame < INITIAL_WARMUP_FRAMES:
		return false

	if _settle > 0:
		_settle -= 1
		if _settle == 0:
			_capture_current_shot()
		return false

	_shot_index += 1
	if _shot_index >= SHOTS.size():
		quit()
		return true

	_apply_shot(SHOTS[_shot_index])
	_settle = SHOT_SETTLE_FRAMES
	return false


func _configure_scene() -> void:
	_camera = _scene_root.get_node_or_null("PlayerCamera") as Camera3D
	_terrain = _scene_root.get_node_or_null("NavigationRegion3D/Terrain3D") as Terrain3D
	_sun = _scene_root.get_node_or_null("WorldEnvironmentSystem/Lighting/SunLight") as DirectionalLight3D
	var spawner := _scene_root.get_node_or_null("FirstSpawner") as Marker3D

	if _camera == null or _terrain == null or spawner == null:
		push_error("Island VFX capture: required Graciosa nodes are missing.")
		quit(1)
		return

	_anchor = spawner.global_position

	_camera.process_mode = Node.PROCESS_MODE_DISABLED
	_camera.current = true

	var player := _scene_root.get_node_or_null("Player")
	if player != null:
		player.process_mode = Node.PROCESS_MODE_DISABLED

	var world_environment_system := _scene_root.get_node_or_null("WorldEnvironmentSystem")
	if world_environment_system != null:
		world_environment_system.process_mode = Node.PROCESS_MODE_DISABLED

	if _sun != null:
		_sun.visible = true
		_sun.rotation_degrees = Vector3(-28.0, -55.0, 0.0)
		_sun.light_energy = 3.25
		_sun.light_angular_distance = 1.2
		_sun.shadow_enabled = true
		_sun.shadow_bias = 0.085
		_sun.shadow_normal_bias = 1.25
		_sun.directional_shadow_max_distance = 1800.0

	_terrain.show_grid = false
	_terrain.show_region_grid = false
	_install_terrain_stylized_shadows()

	var fade_packed := load(FADE_VOLUME_SCENE) as PackedScene
	if fade_packed == null:
		push_error("Island VFX capture: FadeVolume scene failed to load.")
		quit(1)
		return

	_volume = fade_packed.instantiate() as Node3D
	if _volume == null:
		push_error("Island VFX capture: FadeVolume root is not Node3D.")
		quit(1)
		return
	_scene_root.add_child(_volume)

	_hide_capture_ui(_scene_root)
	_configured = true


func _install_terrain_stylized_shadows() -> void:
	var terrain_material: Terrain3DMaterial = _terrain.material
	if terrain_material == null:
		push_error("Island VFX capture: Terrain3D material missing.")
		quit(1)
		return

	# Ask Terrain3D for the exact shader generated from the island's own current
	# material settings, then add only a custom light() function.
	terrain_material.shader_override_enabled = true
	var generated: Shader = terrain_material.shader_override
	if generated == null:
		push_error("Island VFX capture: Terrain3D did not generate shader override.")
		quit(1)
		return

	var code := generated.code
	if code.contains("void light()"):
		push_error("Island VFX capture: generated Terrain3D shader already owns light().")
		quit(1)
		return
	if not code.contains("varying vec3 v_vertex"):
		push_error("Island VFX capture: generated Terrain3D shader has no v_vertex varying.")
		quit(1)
		return

	code += """

// HFN island preview: the same solid-core / torn-perimeter shadow treatment
// used by StylizedShadowMaterial, applied to Terrain3D's real generated shader.
uniform sampler2D hfn_shadow_noise : source_color, filter_linear_mipmap, repeat_enable;
uniform float hfn_scale_macro = 0.09;
uniform float hfn_scale_detail = 0.44;
uniform float hfn_shadow_floor = 0.005;
uniform float hfn_shadow_edge_light = 0.06;
uniform float hfn_shadow_threshold = 0.46;
uniform float hfn_break_softness = 0.045;
uniform float hfn_detail_amount = 0.12;

void light() {
	float ndotl = max(dot(NORMAL, LIGHT), 0.0);

	if (LIGHT_IS_DIRECTIONAL) {
		float physical_shadow = clamp(1.0 - ATTENUATION, 0.0, 1.0);
		float solid_core = smoothstep(0.48, 0.68, physical_shadow);
		float perimeter_gate =
			smoothstep(0.10, 0.22, physical_shadow)
			* (1.0 - smoothstep(0.50, 0.72, physical_shadow));

		float macro_noise = texture(hfn_shadow_noise, v_vertex.xz * hfn_scale_macro).r;
		float detail_noise = texture(
			hfn_shadow_noise,
			v_vertex.xz * hfn_scale_detail + vec2(11.7, -4.3)
		).r;

		float edge_field =
			physical_shadow * 0.56
			+ macro_noise * 0.78
			+ (detail_noise - 0.5) * 0.10 * hfn_detail_amount;

		float ragged_edge = smoothstep(
			hfn_shadow_threshold - hfn_break_softness,
			hfn_shadow_threshold + hfn_break_softness,
			edge_field
		);

		float perimeter_ink = ragged_edge * perimeter_gate;
		float ink_mask = clamp(max(solid_core, perimeter_ink), 0.0, 1.0);
		float edge_darkness = mix(
			hfn_shadow_edge_light,
			hfn_shadow_floor,
			smoothstep(0.42, 0.72, macro_noise)
		);
		float ink_darkness = mix(edge_darkness, hfn_shadow_floor, solid_core);
		float stylized_shadow = mix(1.0, ink_darkness, ink_mask);

		DIFFUSE_LIGHT += ndotl * stylized_shadow * LIGHT_COLOR / PI;
	} else {
		DIFFUSE_LIGHT += ndotl * ATTENUATION * LIGHT_COLOR / PI;
	}
}
"""

	var custom := Shader.new()
	custom.code = code
	terrain_material.shader_override = custom
	terrain_material.shader_override_enabled = true

	var source_material := load(SHADOW_MATERIAL) as ShaderMaterial
	if source_material == null:
		push_error("Island VFX capture: StylizedShadowMaterial failed to load.")
		quit(1)
		return

	var noise_texture = source_material.get_shader_parameter("noise_texture")
	terrain_material.set_shader_param("hfn_shadow_noise", noise_texture)
	terrain_material.set_shader_param("hfn_scale_macro", 0.09)
	terrain_material.set_shader_param("hfn_scale_detail", 0.44)
	terrain_material.set_shader_param("hfn_shadow_floor", 0.005)
	terrain_material.set_shader_param("hfn_shadow_edge_light", 0.06)
	terrain_material.set_shader_param("hfn_shadow_threshold", 0.46)
	terrain_material.set_shader_param("hfn_break_softness", 0.045)
	terrain_material.set_shader_param("hfn_detail_amount", 0.12)


func _apply_shot(shot: Dictionary) -> void:
	var camera_xz := Vector2(
		_anchor.x + float((shot["camera_offset"] as Vector3).x),
		_anchor.z + float((shot["camera_offset"] as Vector3).z)
	)
	var target_xz := Vector2(
		_anchor.x + float((shot["target_offset"] as Vector3).x),
		_anchor.z + float((shot["target_offset"] as Vector3).z)
	)

	var camera_height := float((shot["camera_offset"] as Vector3).y)
	var target_height := float((shot["target_offset"] as Vector3).y)
	var camera_pos := _position_above_terrain(camera_xz, camera_height)
	var target_pos := _position_above_terrain(target_xz, target_height)

	_camera.global_position = camera_pos
	_camera.fov = float(shot["fov"])
	_camera.look_at(target_pos, Vector3.UP)

	_place_fade_volume(
		camera_pos,
		target_pos,
		float(shot["volume_t"]),
		shot["volume_scale"] as Vector3
	)

	print(
		"Island VFX shot %s camera=%s target=%s"
		% [String(shot["name"]), camera_pos, target_pos]
	)


func _position_above_terrain(xz: Vector2, above: float) -> Vector3:
	var probe := Vector3(xz.x, 0.0, xz.y)
	var ground := _terrain.data.get_height(probe)
	if is_nan(ground):
		ground = _anchor.y
	return Vector3(xz.x, ground + above, xz.y)


func _place_fade_volume(
	camera_pos: Vector3,
	target_pos: Vector3,
	t: float,
	volume_scale: Vector3
) -> void:
	var center := camera_pos.lerp(target_pos, t)
	var direction := target_pos - camera_pos
	direction.y = 0.0
	if direction.length_squared() < 0.001:
		direction = Vector3.RIGHT
	direction = direction.normalized()

	var x_axis := direction
	var y_axis := Vector3.UP
	var z_axis := x_axis.cross(y_axis).normalized()
	_volume.global_transform = Transform3D(Basis(x_axis, y_axis, z_axis), center)
	_volume.scale = volume_scale


func _capture_current_shot() -> void:
	var shot: Dictionary = SHOTS[_shot_index]
	var image := root.get_texture().get_image()
	if image == null:
		push_error("Island VFX capture: viewport image is null.")
		quit(1)
		return

	var path := "%s/island_fx_%s.png" % [OUTPUT_DIR, String(shot["name"])]
	var absolute := ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var error := image.save_png(absolute)
	if error != OK:
		push_error("Island VFX capture: save_png failed: %s" % error)
		quit(1)
		return
	print("Island VFX capture saved: %s" % absolute)


func _hide_capture_ui(node: Node) -> void:
	if node is CanvasItem:
		(node as CanvasItem).visible = false
	if node is CanvasLayer:
		(node as CanvasLayer).visible = false
	if node is Label3D:
		(node as Label3D).visible = false

	if node.name == "Perfomance&Debugging" or node.name == "StatsDisplay":
		if node is Node3D:
			(node as Node3D).visible = false

	for child in node.get_children():
		_hide_capture_ui(child)
