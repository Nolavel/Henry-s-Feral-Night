extends SceneTree

## Issue #42 frames: Henry sits on the crate by the burning stove in wet clothes;
## steam rises and the HUD shows warmth rising and wetness falling.
## Run: xvfb-run godot --path . --rendering-driver vulkan --script res://tools/runtime/capture_shelter_recovery.gd

const SCENE: String = "res://experimental_location/scenes/Graciosa_Island_Terrain.tscn"
const OUT_DIR: String = "user://shots/recovery"
const WARMUP: float = 3.0

var _player: Player
var _thermal: ThermalManager
var _time: float = 0.0
var _step: int = 0
var _camera: Camera3D


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var scene: Node = (load(SCENE) as PackedScene).instantiate()
	root.add_child(scene)
	_player = scene.find_child("Player", true, false) as Player


func _process(delta: float) -> bool:
	_time += delta
	if _time < WARMUP:
		return false
	if _step == 0:
		_step = 1
		for node: Node in root.find_children("*", "", true, false):
			if node is ThermalManager:
				_thermal = node
			elif node is WeatherController:
				(node as WeatherController).set_weather(&"clear", true)
			elif node is Label3D:
				(node as Label3D).visible = false
		var zone: Node = root.find_child("ShelterZone", true, false)
		var crate := zone.find_child("RestCrate", true, false) as Node3D
		var stove := zone.find_child("Stove", true, false) as HeatSource
		stove.ignite()
		_player.global_position = crate.global_position + Vector3(0.0, 0.2, 0.0)
		_thermal.add_wetness(0.7)
		print("[recovery] sat=", (_player.get_node(^"RestComponent") as RestComponent).sit(crate.find_child("Rest") as Node3D))
		_camera = Camera3D.new()
		_camera.fov = 55.0
		scene_root().add_child(_camera)
		var basis: Basis = crate.global_transform.basis
		_camera.global_position = crate.global_position + basis.x * 2.0 - basis.z * 0.6 + Vector3(0.0, 1.5, 0.0)
		_camera.look_at(crate.global_position + Vector3(0.0, 0.7, 0.0) - basis.z * 0.5, Vector3.UP)
		_camera.make_current()
	elif _time > WARMUP + 5.0 and _step == 1:
		_step = 2
		root.get_texture().get_image().save_png("%s/01_sitting_by_stove.png" % OUT_DIR)
		print("[recovery] shot wetness=%.2f steaming=%s" % [_thermal.get_wetness(),
			(_player.get_node(^"DryingSteamComponent") as DryingSteamComponent).is_steaming()])
		quit()
	return false


func scene_root() -> Node:
	return root.get_child(root.get_child_count() - 1)
