extends SceneTree

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var fade_scene := load("res://scenes/environment/visual_fx/FadeVolume.tscn") as PackedScene
	if fade_scene == null:
		push_error("VisualFXValidation: FadeVolume.tscn failed to load.")
		quit(2)
		return

	var fade_instance := fade_scene.instantiate() as Node3D
	if fade_instance == null:
		push_error("VisualFXValidation: FadeVolume failed to instantiate.")
		quit(3)
		return

	var stylized_material := load(
		"res://scenes/environment/visual_fx/StylizedShadowMaterial.tres"
	) as ShaderMaterial
	if stylized_material == null or stylized_material.shader == null:
		push_error("VisualFXValidation: StylizedShadowMaterial failed to load.")
		quit(4)
		return

	var root_3d := Node3D.new()
	root.add_child(root_3d)
	root_3d.add_child(fade_instance)

	var test_mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(2.0, 2.0, 2.0)
	test_mesh.mesh = box
	test_mesh.material_override = stylized_material
	test_mesh.position = Vector3(0.0, 0.0, -4.0)
	root_3d.add_child(test_mesh)

	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 1.5, 5.5)
	camera.look_at(Vector3(0.0, 0.0, -1.0), Vector3.UP)
	camera.current = true
	root_3d.add_child(camera)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45.0, -30.0, 0.0)
	sun.shadow_enabled = true
	root_3d.add_child(sun)

	for _i in range(8):
		await process_frame
	await RenderingServer.frame_post_draw

	print("[HFN_VISUAL_FX] FadeVolume loaded")
	print("[HFN_VISUAL_FX] StylizedShadows loaded")
	quit(0)
