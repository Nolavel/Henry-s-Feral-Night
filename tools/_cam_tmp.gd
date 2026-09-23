extends SceneTree
var f := 0
var scene: Node
var player: CharacterBody3D
var cam: TpsCamera
var mouse_deg := 0.0
func _initialize() -> void:
	mouse_deg = float(OS.get_cmdline_user_args()[0])
	scene = (load("res://tests/scenes/TestScene.tscn") as PackedScene).instantiate()
	root.add_child(scene)
func _process(_d: float) -> bool:
	f += 1
	if f == 15:
		player = scene.get_node("Player")
		cam = scene.get_node("PlayerCamera")
		## South wall outer face z=17.15; Henry's back against it, facing +Z.
		player.global_position = Vector3(0.5, 1, 17.6)
		player.rotation.y = PI
		cam.set_look(deg_to_rad(mouse_deg), -10.0)
	if f == 420:
		var eye := player.global_position + Vector3.UP * 0.69
		print("SHOT mouse=%d assist=%.0f dist=%.2f hidden=%s" % [mouse_deg, rad_to_deg(cam._assist_yaw), cam.global_position.distance_to(eye), cam.is_body_hidden()])
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("user://wall_%d.png" % int(mouse_deg)))
		quit()
	return false
