class_name LighterStrikeVFX
extends Node3D

## Tiny self-contained lighter feedback. Built from primitive meshes so the
## gameplay does not depend on a texture, imported particle asset or post effect.

var success: bool = false


static func spawn(parent: Node3D, did_ignite: bool) -> LighterStrikeVFX:
	if parent == null:
		return null
	var vfx := LighterStrikeVFX.new()
	vfx.success = did_ignite
	parent.add_child(vfx)
	return vfx


func _ready() -> void:
	position = Vector3(0.0, 0.07, 0.045)
	_build_light()
	_build_sparks()
	if success:
		_build_flame()
	get_tree().create_timer(0.45).timeout.connect(queue_free)


func _build_light() -> void:
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.58, 0.22)
	light.light_energy = 2.8 if success else 1.35
	light.omni_range = 0.7 if success else 0.42
	light.shadow_enabled = false
	add_child(light)
	create_tween().tween_property(
		light,
		^"light_energy",
		0.0,
		0.30 if success else 0.10
	)


func _build_sparks() -> void:
	var spark_mesh := SphereMesh.new()
	spark_mesh.radius = 0.005
	spark_mesh.height = 0.01
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.emission_enabled = true
	material.emission = Color(1.0, 0.42, 0.08)
	material.albedo_color = Color(1.0, 0.55, 0.16)
	spark_mesh.material = material

	for index: int in range(7):
		var spark := MeshInstance3D.new()
		spark.mesh = spark_mesh
		add_child(spark)
		var angle: float = TAU * float(index) / 7.0 + 0.31
		var lift: float = 0.025 + 0.008 * float(index % 3)
		var target := Vector3(cos(angle) * 0.055, lift, sin(angle) * 0.055)
		var tween := create_tween().set_parallel(true)
		tween.tween_property(spark, ^"position", target, 0.12)
		tween.tween_property(spark, ^"scale", Vector3.ZERO, 0.12)


func _build_flame() -> void:
	var flame := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.012
	mesh.height = 0.038
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.emission_enabled = true
	material.emission = Color(1.0, 0.3, 0.05)
	material.albedo_color = Color(1.0, 0.48, 0.10)
	mesh.material = material
	flame.mesh = mesh
	flame.position = Vector3(0.0, 0.025, 0.0)
	flame.scale = Vector3(0.75, 1.35, 0.75)
	add_child(flame)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(flame, ^"position:y", 0.045, 0.28)
	tween.tween_property(flame, ^"scale", Vector3(0.2, 0.35, 0.2), 0.28)
