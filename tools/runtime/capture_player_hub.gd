extends SceneTree

## Issue #68 frames in the main scene: Henry's pack closed, top-only, a tap-F
## stow flying into the top flap, and fully open in the Hub. Frames go to user://shots/hub/, through a capture SubViewport.
## Run: xvfb-run godot --path . --rendering-driver vulkan --script res://tools/runtime/capture_player_hub.gd

const SCENE: String = "res://experimental_location/scenes/Graciosa_Island_Terrain.tscn"
const OUT_DIR: String = "user://shots/hub"
const WARMUP: float = 3.0
## [seconds after warmup, what to do, frame name]
const STEPS: Array = [
	[0.0, "closed", ""], [0.6, "", "01_pack_closed"],
	[0.7, "top", ""], [1.6, "", "02_pack_top_only"],
	[1.7, "stow", ""], [1.9, "", "04_stow_lift"], [2.2, "", "05_stow_drop"], [3.2, "", "06_stow_closed"],
	[3.3, "hub", ""], [4.6, "", "03_hub_full"],
	[4.7, "place", ""], [6.0, "", "07_hold_placement"],
]

var _player: Player
var _hub: PlayerHubComponent
var _view: SubViewport
var _camera: Camera3D
var _time: float = 0.0
var _step: int = 0


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var scene: Node = (load(SCENE) as PackedScene).instantiate()
	root.add_child(scene)
	_player = scene.find_child("Player", true, false) as Player
	_hub = _player.get_node(^"PlayerHubComponent") as PlayerHubComponent
	_view = SubViewport.new()
	_view.size = Vector2i(1280, 720)
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_view)
	_camera = Camera3D.new()
	_camera.fov = 50.0
	_view.add_child(_camera)


func _process(delta: float) -> bool:
	_time += delta
	if _time < WARMUP:
		return false
	_camera.global_transform = _hub.get_camera_target()
	while _step < STEPS.size() and _time - WARMUP >= float(STEPS[_step][0]):
		var step: Array = STEPS[_step]
		_step += 1
		match step[1]:
			"top":
				_player.animation_component.get_pack_rig().set_openness(PackRig.Openness.TOP_ONLY)
			"stow":
				_spawn_and_pick()
			"place":
				_hub.close()
				print("[hub] placement=", _hub.open_placement(&"road_flare"))
			"hub":
				_player.animation_component.get_pack_rig().set_openness(PackRig.Openness.CLOSED, true)
				print("[hub] open=", _hub.open())
		if step[2] == "07_hold_placement":
			## The placement UI lives on the root viewport, so this frame is the game view.
			root.get_texture().get_image().save_png("%s/%s.png" % [OUT_DIR, step[2]])
		elif step[2] != "":
			_view.get_texture().get_image().save_png("%s/%s.png" % [OUT_DIR, step[2]])
			print("[hub] shot ", step[2])
	if _step >= STEPS.size():
		quit()
	return false


## A flare lying beside Henry, picked up with a tap of F.
func _spawn_and_pick() -> void:
	var area: Node = (load("res://scenes/environment/interactive/InteractiveArea.tscn") as PackedScene).instantiate()
	area.set_script(load("res://scripts/environment/interactive/item_pickup.gd"))
	area.set(&"interactable_scene", null)
	var pickup := area as ItemPickup
	pickup.item_id = &"road_flare"
	_player.get_parent().add_child(pickup)
	var basis: Basis = _player.global_transform.basis.orthonormalized()
	pickup.global_position = _player.global_position - basis.z * 0.8 + basis.x * 0.7
	print("[hub] picked=", pickup.pick_up())
