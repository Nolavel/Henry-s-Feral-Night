extends SceneTree

## Captures the First Exit greybox on the Graciosa terrain: the view from the
## bunker door toward the landmark, an oblique aerial, the shelter and the fort.
## Builds a light stage (terrain, blockout, sun, sky) because the full Graciosa
## scene crashes under lavapipe; HFN_FULL_SCENE=1 uses the real scene instead.
## Run: xvfb-run godot --path . --rendering-driver vulkan --script res://tools/runtime/capture_first_exit.gd

const SCENE: String = "res://experimental_location/scenes/Graciosa_Island_Terrain.tscn"
const BLOCKOUT: String = "res://scenes/world/first_exit/first_exit_blockout.tscn"
const TERRAIN_DIR: String = "res://experimental_location/Graciosa/terrain_graciosa"
const OUT_DIR: String = "user://shots/first_exit"
const WARMUP_FRAMES: int = 60
## [name, camera position, look-at target]
const SHOTS: Array = [
	["from_bunker", Vector3(1421.0, 5.0, -945.0), Vector3(1119.0, 12.0, -668.0)],
	["aerial_sector", Vector3(1520.0, 170.0, -1060.0), Vector3(1230.0, 0.0, -790.0)],
	["shelter_close", Vector3(1135.0, 9.0, -612.0), Vector3(1101.0, 3.0, -650.0)],
	["fort_ruins", Vector3(1372.0, 14.0, -700.0), Vector3(1335.0, 3.0, -760.0)],
	["bunker_door", Vector3(1412.0, 4.0, -935.0), Vector3(1427.0, 2.5, -952.0)],
]

var _frame: int = 0
var _shot: int = -1
var _camera: Camera3D


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	if OS.get_environment("HFN_FULL_SCENE") == "1":
		root.add_child((load(SCENE) as PackedScene).instantiate())
	else:
		_build_stage()


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < WARMUP_FRAMES:
		return false
	if _camera == null:
		_camera = Camera3D.new()
		_camera.far = 3000.0
		_camera.fov = 60.0
		root.add_child(_camera)
	_camera.make_current()
	if (_frame - WARMUP_FRAMES) % 20 == 0:
		if _shot >= 0:
			var shot_name: String = SHOTS[_shot][0]
			root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [OUT_DIR, shot_name])
			print("first exit capture: ", shot_name)
		_shot += 1
		if _shot >= SHOTS.size():
			quit()
			return true
		_camera.look_at_from_position(SHOTS[_shot][1], SHOTS[_shot][2])
	return false


func _build_stage() -> void:
	var terrain := Terrain3D.new()
	terrain.data_directory = TERRAIN_DIR
	root.add_child(terrain)
	var sea := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(6000.0, 6000.0)
	var water := StandardMaterial3D.new()
	water.albedo_color = Color(0.55, 0.62, 0.68)
	water.roughness = 0.3
	plane.material = water
	sea.mesh = plane
	sea.position = Vector3(0.0, 0.04, 0.0)
	root.add_child(sea)
	root.add_child((load(BLOCKOUT) as PackedScene).instantiate())
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35.0, -40.0, 0.0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 400.0
	root.add_child(sun)
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.55, 0.6, 0.66)
	sky_mat.sky_horizon_color = Color(0.78, 0.8, 0.82)
	sky_mat.ground_horizon_color = Color(0.78, 0.8, 0.82)
	env.sky.sky_material = sky_mat
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.fog_enabled = true
	env.fog_light_color = Color(0.8, 0.82, 0.85)
	env.fog_density = 0.0012
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	root.add_child(world_env)
