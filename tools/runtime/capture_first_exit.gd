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
## [name, camera position, look-at target]; both heights are above the ground.
## HFN_SHOT=<index> renders one shot per process: Terrain3D under lavapipe can
## crash on a camera jump, so tools loop over processes instead.
const SHOTS: Array = [
	["from_bunker", Vector3(1421.0, 1.7, -945.0), Vector3(1140.0, 6.0, -690.0)],
	["aerial_sector", Vector3(1470.0, 150.0, -990.0), Vector3(1170.0, 0.0, -690.0)],
	["shelter_lot", Vector3(1150.0, 1.7, -676.0), Vector3(1128.0, 1.5, -645.0)],
	["junction", Vector3(1075.0, 4.0, -648.0), Vector3(1116.0, 1.0, -690.0)],
	["suburb_aerial", Vector3(1215.0, 55.0, -590.0), Vector3(1100.0, 0.0, -662.0)],
	["road_bus", Vector3(1378.0, 2.2, -858.0), Vector3(1348.0, 1.0, -822.0)],
	["beach_wrecks", Vector3(1330.0, 3.0, -945.0), Vector3(1250.0, 0.5, -890.0)],
]

var _frame: int = 0
var _shot: int = -1
var _camera: Camera3D
var _terrain: Terrain3D
var _island: IslandTerrain
var _only: int = -1


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	if OS.get_environment("HFN_SHOT") != "":
		_only = int(OS.get_environment("HFN_SHOT"))
		_shot = _only - 1
	if OS.get_environment("HFN_FULL_SCENE") == "1":
		var scene: Node = (load(SCENE) as PackedScene).instantiate()
		if OS.get_environment("HFN_TERRAIN") == "mesh":
			scene.get_node(^"NavigationRegion3D/Terrain3D").free()
			_island = IslandTerrain.new()
			scene.add_child(_island)
		root.add_child(scene)
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
		if _shot >= 0 and (_only < 0 or _shot == _only):
			var shot_name: String = SHOTS[_shot][0]
			root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [OUT_DIR, shot_name])
			print("first exit capture: ", shot_name)
		_shot += 1
		if _shot >= SHOTS.size() or (_only >= 0 and _shot > _only):
			quit()
			return true
		_camera.look_at_from_position(_lift(SHOTS[_shot][1]), _lift(SHOTS[_shot][2]))
		if _island != null:
			_island.update_now()
	return false


## Raises a point by the ground under it; the sea counts as ground level 0.
func _lift(p: Vector3) -> Vector3:
	if _island != null:
		return Vector3(p.x, p.y + maxf(_island.get_height(p.x, p.z), 0.0), p.z)
	if _terrain == null:
		return p
	var h: float = _terrain.data.get_height(Vector3(p.x, 0.0, p.z))
	return Vector3(p.x, p.y + (0.0 if is_nan(h) else maxf(h, 0.0)), p.z)


## HFN_TERRAIN=mesh renders the heightmap IslandTerrain instead of Terrain3D.
func _build_stage() -> void:
	if OS.get_environment("HFN_TERRAIN") == "mesh":
		_island = IslandTerrain.new()
		_island.focus = null
		root.add_child(_island)
	else:
		var terrain := Terrain3D.new()
		terrain.data_directory = TERRAIN_DIR
		root.add_child(terrain)
		_terrain = terrain
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
