class_name DryingSteamComponent
extends Node3D

## Steam rising off Henry's wet clothes while a burning stove dries them. It thins
## with wetness and stops when he is dry or out of the heat: the drying readout.

## Wetness below this shows no steam.
const MIN_WETNESS: float = 0.04

var _thermal: ThermalManager
var _steam: GPUParticles3D


func _ready() -> void:
	_steam = GPUParticles3D.new()
	_steam.name = "Steam"
	_steam.amount = 40
	_steam.lifetime = 1.8
	_steam.emitting = false
	_steam.visibility_aabb = AABB(Vector3(-2.0, -1.0, -2.0), Vector3(4.0, 4.0, 4.0))
	_steam.position = Vector3(0.0, -0.05, 0.0)  # the body origin is the capsule centre
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(0.22, 0.3, 0.16)
	process.direction = Vector3.UP
	process.spread = 12.0
	process.initial_velocity_min = 0.06
	process.initial_velocity_max = 0.18
	process.gravity = Vector3(0.0, 0.05, 0.0)
	process.scale_min = 0.6
	process.scale_max = 1.4
	var fade := Gradient.new()
	fade.set_color(0, Color(1.0, 1.0, 1.0, 0.0))
	fade.add_point(0.25, Color(1.0, 1.0, 1.0, 0.28))
	fade.set_color(fade.get_point_count() - 1, Color(1.0, 1.0, 1.0, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	process.color_ramp = ramp
	_steam.process_material = process
	var puff := QuadMesh.new()
	puff.size = Vector2(0.24, 0.24)
	var look := StandardMaterial3D.new()
	look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	look.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	look.vertex_color_use_as_albedo = true
	var soft := GradientTexture2D.new()
	soft.fill = GradientTexture2D.FILL_RADIAL
	soft.fill_from = Vector2(0.5, 0.5)
	soft.fill_to = Vector2(1.0, 0.5)
	var falloff := Gradient.new()
	falloff.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	falloff.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	soft.gradient = falloff
	look.albedo_texture = soft
	look.disable_fog = true  # the shelter's haze would swallow thin steam
	look.albedo_color = Color(0.92, 0.92, 0.9)
	puff.material = look
	_steam.draw_pass_1 = puff
	add_child(_steam)


## Given by Player once the world's thermal model exists.
func set_thermal(thermal: ThermalManager) -> void:
	_thermal = thermal


func is_steaming() -> bool:
	return _steam != null and _steam.emitting


func _process(_delta: float) -> void:
	var wetness: float = _thermal.get_wetness() if _thermal != null else 0.0
	var steaming: bool = wetness > MIN_WETNESS and _near_fire()
	if _steam.emitting != steaming:
		_steam.emitting = steaming
	var ratio: float = snappedf(clampf(wetness * 1.5, 0.15, 1.0), 0.05)
	if not is_equal_approx(_steam.amount_ratio, ratio):
		_steam.amount_ratio = ratio


func _near_fire() -> bool:
	for source: HeatSource in HeatSource.get_all():
		if source.get_offset_at(global_position) > 0.0:
			return true
	return false
