extends SceneTree

## Lightweight local preview for HeldFlare. Not wired to CI.
## Run:
## godot --path . --script res://tools/runtime/capture_held_flare.gd
##
## Outputs three PNGs into artifacts/ so the irregular burn can be judged
## without touching the production island or consuming render Actions.

const FLARE_SCENE := preload("res://scenes/actors/player/held/HeldFlare.tscn")
const OUTPUTS := [
	"res://artifacts/held_flare_early.png",
	"res://artifacts/held_flare_mid.png",
	"res://artifacts/held_flare_late.png",
]
const CAPTURE_FRAMES := [36, 104, 178]

var _frame: int = 0
var _capture_index: int = 0
var _flare: HeldFlare


func _initialize() -> void:
	var stage := Node3D.new()
	stage.name = "HeldFlarePreview"
	root.add_child(stage)

	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.008, 0.012, 0.018, 1.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.06, 0.075, 0.10, 1.0)
	env.ambient_light_energy = 0.11
	environment.environment = env
	stage.add_child(environment)

	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(6.0, 6.0)
	floor.mesh = plane
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.62, 0.67, 0.72, 1.0)
	floor_material.roughness = 0.92
	floor.material_override = floor_material
	stage.add_child(floor)

	var wall := MeshInstance3D.new()
	var wall_mesh := BoxMesh.new()
	wall_mesh.size = Vector3(4.2, 2.8, 0.16)
	wall.mesh = wall_mesh
	wall.position = Vector3(0.0, 1.4, -1.15)
	var wall_material := StandardMaterial3D.new()
	wall_material.albedo_color = Color(0.23, 0.26, 0.29, 1.0)
	wall_material.roughness = 0.85
	wall.material_override = wall_material
	stage.add_child(wall)

	_flare = FLARE_SCENE.instantiate() as HeldFlare
	_flare.position = Vector3(0.0, 1.18, -0.36)
	_flare.rotation_degrees = Vector3(0.0, 0.0, -13.0)
	stage.add_child(_flare)

	var camera := Camera3D.new()
	camera.position = Vector3(1.55, 1.42, 2.55)
	camera.look_at(Vector3(0.0, 1.12, -0.35), Vector3.UP)
	camera.fov = 48.0
	camera.current = true
	stage.add_child(camera)


func _process(_delta: float) -> bool:
	_frame += 1
	if _capture_index >= CAPTURE_FRAMES.size():
		quit(0)
		return true
	if _frame < CAPTURE_FRAMES[_capture_index]:
		return false
	_capture(OUTPUTS[_capture_index])
	_capture_index += 1
	return false


func _capture(path: String) -> void:
	var image := root.get_texture().get_image()
	if image == null:
		push_error("HeldFlare capture: viewport image is null.")
		quit(1)
		return
	var absolute := ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var error := image.save_png(absolute)
	if error != OK:
		push_error("HeldFlare capture failed: %s" % error)
		quit(1)
		return
	print(
		"HeldFlare capture: %s energy=%.3f"
		% [absolute, _flare.get_current_energy()]
	)
