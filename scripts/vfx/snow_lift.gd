class_name SnowLift
extends GPUParticles3D

## A gust lifting loose snow off the surface: grains leave almost flat along
## local +X, curve ever steeper upwards and fade. One-shot; call lift().

## Patch of snow the grains leave from, metres (X along the wind, Z across).
@export var patch: Vector2 = Vector2(1.6, 1.2)
## Upward pull that bends the flat start into a climb, m/s².
@export var climb: float = 3.2


func _init() -> void:
	one_shot = true
	emitting = false
	amount = 160
	lifetime = 1.3
	explosiveness = 0.55
	randomness = 0.3
	local_coords = false
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _ready() -> void:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(patch.x * 0.5, 0.02, patch.y * 0.5)
	process.direction = Vector3(1.0, 0.18, 0.0)  # ~10 degrees above the surface
	process.spread = 8.0
	process.initial_velocity_min = 1.6
	process.initial_velocity_max = 3.0
	process.gravity = Vector3(0.0, climb, 0.0)
	process.damping_min = 0.3
	process.damping_max = 0.8
	process.scale_min = 0.5
	process.scale_max = 1.0
	var fade := Gradient.new()
	fade.set_color(0, Color(1.0, 1.0, 1.0, 0.0))
	fade.add_point(0.12, Color(1.0, 1.0, 1.0, 0.9))
	fade.add_point(0.55, Color(1.0, 1.0, 1.0, 0.6))
	fade.set_color(fade.get_point_count() - 1, Color(1.0, 1.0, 1.0, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	process.color_ramp = ramp
	process_material = process
	var grain := QuadMesh.new()
	grain.size = Vector2(0.06, 0.06)
	var look := StandardMaterial3D.new()
	look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	look.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	look.vertex_color_use_as_albedo = true
	look.albedo_color = Color(0.7, 0.77, 0.87)  # a shade off the snow so grains read against it
	look.disable_fog = true
	var soft := GradientTexture2D.new()
	soft.fill = GradientTexture2D.FILL_RADIAL
	soft.fill_from = Vector2(0.5, 0.5)
	soft.fill_to = Vector2(1.0, 0.5)
	var falloff := Gradient.new()
	falloff.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	soft.gradient = falloff
	look.albedo_texture = soft
	grain.material = look
	draw_pass_1 = grain


## Plays one lift at the current transform.
func lift() -> void:
	restart()
