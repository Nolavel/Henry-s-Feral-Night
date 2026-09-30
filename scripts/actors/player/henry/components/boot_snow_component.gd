class_name BootSnowComponent
extends Node

## Snow that sticks to Henry's boots. A boot pulled out of a deep print carries a
## clod on its toe cap, most in wet snow near melting; a brisk step shakes some
## off, and it melts away in warmth or slowly sublimates in the cold.

## Bones per foot on the UAL rig: ankle, ball of the foot and toe tip.
const FEET: Array[Dictionary] = [
	{"heel": &"foot_l", "ball": &"ball_l", "toe": &"ball_leaf_l"},
	{"heel": &"foot_r", "ball": &"ball_r", "toe": &"ball_leaf_r"},
]

@export_group("Wiring")
@export var visual: HenryUALAnimation

@export_group("Sticking")
## A boot must have sunk this deep to come out carrying snow, metres.
@export var stick_sink_m: float = 0.08
## Clod gained by one step out of the deepest snow, as a share of a full clod.
@export_range(0.0, 1.0) var pickup_per_step: float = 0.35
## Air temperature where snow barely sticks and where it sticks fully, °C:
## dry cold grains roll off, wet snow near 0 °C packs on like a snowball.
@export var stick_air_c: Vector2 = Vector2(-15.0, -1.0)
## Stickiness left in the driest, coldest snow.
@export_range(0.0, 1.0) var dry_stick: float = 0.2

@export_group("Shedding")
## Chance a lift-off shakes part of the clod loose at a brisk pace.
@export_range(0.0, 1.0) var shed_chance: float = 0.35
## Pace at which that chance is full, m/s; a slow step rarely sheds.
@export var shed_speed_mps: float = 2.5
## Seconds a full clod takes to melt in warmth (above 0 °C or a heated room),
## and to sublimate away at -20 °C.
@export var melt_warm_s: float = 45.0
@export var melt_cold_s: float = 900.0

@export_group("Look")
## Clod centre from the ball of the foot in the foot's frame: x out to the side,
## y up, z towards the toe, metres. Sits on the toe cap.
@export var cap_offset: Vector3 = Vector3(0.0, 0.06, 0.035)
## Size of a full clod: width, height, length, metres.
@export var full_size: Vector3 = Vector3(0.1, 0.045, 0.09)
@export var snow_color: Color = Color(0.88, 0.9, 0.95)
## Snow going to slush as it melts.
@export var slush_color: Color = Color(0.62, 0.66, 0.72)

var _amount: Array[float] = [0.0, 0.0]
var _wet: Array[float] = [0.0, 0.0]
var _clods: Array[MeshInstance3D] = []
var _materials: Array[StandardMaterial3D] = []
var _bursts: Array[GPUParticles3D] = []
var _thermal: ThermalManager
var _shell: SnowShell
var _skeleton: Skeleton3D
var _index: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	var lump: Mesh = _lumpy_mesh()
	for side: int in range(2):
		var material := StandardMaterial3D.new()
		material.albedo_color = snow_color
		material.roughness = 0.9
		var clod := MeshInstance3D.new()
		clod.name = "BootSnow%d" % side
		clod.mesh = lump
		clod.material_override = material
		clod.visible = false
		clod.top_level = true
		clod.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(clod)
		_clods.append(clod)
		_materials.append(material)
		_bursts.append(_shed_burst("BootShed%d" % side))


func _exit_tree() -> void:
	if is_instance_valid(_skeleton) and _skeleton.skeleton_updated.is_connected(_on_skeleton_updated):
		_skeleton.skeleton_updated.disconnect(_on_skeleton_updated)
	_skeleton = null
	if is_instance_valid(_shell) and _shell.foot_lifted.is_connected(_on_foot_lifted):
		_shell.foot_lifted.disconnect(_on_foot_lifted)
	_shell = null


func set_thermal(thermal: ThermalManager) -> void:
	_thermal = thermal


func _process(delta: float) -> void:
	_bind()
	var air: float = _air_c()
	var warm: bool = air > 0.0 or (is_instance_valid(_thermal) and _thermal.is_sheltered() and _thermal.get_room_temperature_c() > 2.0)
	var melt_s: float = melt_warm_s if warm else lerpf(melt_cold_s, melt_warm_s * 3.0, clampf(inverse_lerp(-20.0, 0.0, air), 0.0, 1.0))
	for side: int in range(2):
		if _amount[side] <= 0.0:
			continue
		_amount[side] = maxf(_amount[side] - delta / maxf(melt_s, 1.0), 0.0)
		_wet[side] = move_toward(_wet[side], 1.0 if warm else 0.0, delta / 20.0)
		_materials[side].albedo_color = snow_color.lerp(slush_color, _wet[side])
		_materials[side].roughness = lerpf(0.9, 0.35, _wet[side])


## How well snow sticks at `air_c`, 0..1.
func stickiness(air_c: float) -> float:
	return lerpf(dry_stick, 1.0, smoothstep(stick_air_c.x, stick_air_c.y, air_c))


## Clod share on the `side` boot, 0..1.
func get_amount(side: int) -> float:
	return _amount[side]


func _on_foot_lifted(side: int, position: Vector3, sink_m: float, softness: float) -> void:
	var body := get_parent() as CharacterBody3D
	var speed: float = Vector2(body.velocity.x, body.velocity.z).length() if body != null else 0.0
	## A brisk step shakes loose part of what the boot already carries.
	if _amount[side] > 0.05 and _rng.randf() < shed_chance * clampf(speed / maxf(shed_speed_mps, 0.1), 0.0, 1.0):
		var lost: float = _amount[side] * _rng.randf_range(0.3, 0.8)
		_amount[side] -= lost
		_shed(side, lost)
	if sink_m < stick_sink_m:
		return
	var deep: float = clampf(sink_m / 0.3, 0.0, 1.0)
	var gain: float = pickup_per_step * deep * stickiness(_air_c()) * lerpf(0.6, 1.0, softness)
	_amount[side] = minf(_amount[side] + gain * _rng.randf_range(0.6, 1.2), 1.0)
	if _amount[side] > 0.0:
		_wet[side] = minf(_wet[side], 0.2)


## Places the clods on the boots after the skeleton's modifiers have run.
func _on_skeleton_updated() -> void:
	## The skeleton can still emit while it or Henry leaves the tree (a scene
	## swap); world transforms do not exist there.
	if not is_inside_tree() or not is_instance_valid(_skeleton) or not _skeleton.is_inside_tree():
		return
	for side: int in range(2):
		var clod: MeshInstance3D = _clods[side]
		clod.visible = _amount[side] > 0.03
		if not clod.visible:
			continue
		var bones: Dictionary = FEET[side]
		var heel: Vector3 = _bone_world(bones["heel"])
		var ball: Vector3 = _bone_world(bones["ball"])
		var toe: Vector3 = _bone_world(bones["toe"])
		var forward := Vector3(toe.x - heel.x, 0.0, toe.z - heel.z)
		if forward.length_squared() < 1e-6:
			continue
		var basis := Basis.looking_at(forward.normalized(), Vector3.UP)
		var offset: Vector3 = basis * Vector3(cap_offset.x, cap_offset.y, -cap_offset.z)
		## A clod grows in volume: its size goes with the cube root of the share.
		var size: Vector3 = full_size * pow(_amount[side], 1.0 / 3.0)
		clod.global_transform = Transform3D(basis.scaled_local(size), ball + offset)


func _shed(side: int, lost: float) -> void:
	if not is_inside_tree():
		return
	var burst: GPUParticles3D = _bursts[side]
	burst.global_position = _clods[side].global_position
	burst.amount_ratio = clampf(lost * 1.5, 0.2, 1.0)
	burst.restart()


func _bind() -> void:
	if not is_instance_valid(_skeleton) and visual != null and is_instance_valid(visual.skeleton):
		_skeleton = visual.skeleton
		if not _skeleton.skeleton_updated.is_connected(_on_skeleton_updated):
			_skeleton.skeleton_updated.connect(_on_skeleton_updated)
	if not is_instance_valid(_shell) and is_instance_valid(SnowShell.active):
		_shell = SnowShell.active
		if not _shell.foot_lifted.is_connected(_on_foot_lifted):
			_shell.foot_lifted.connect(_on_foot_lifted)


func _bone_world(bone: StringName) -> Vector3:
	if not _index.has(bone):
		_index[bone] = _skeleton.find_bone(bone)
	var i: int = _index[bone]
	return _skeleton.global_transform * _skeleton.get_bone_global_pose(i).origin if i >= 0 else Vector3.ZERO


func _air_c() -> float:
	return _thermal.get_outdoor_air_c() if is_instance_valid(_thermal) else -10.0


## A unit sphere pushed about by noise, so a clod reads as packed snow.
func _lumpy_mesh() -> ArrayMesh:
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 12
	sphere.rings = 6
	var arrays: Array = sphere.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var noise := FastNoiseLite.new()
	noise.seed = 311
	noise.frequency = 2.2
	for i: int in range(verts.size()):
		var v: Vector3 = verts[i]
		verts[i] = v * (1.0 + 0.28 * noise.get_noise_3dv(v * 4.0))
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = null
	arrays[Mesh.ARRAY_TANGENT] = null
	var st := SurfaceTool.new()
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	st.create_from(mesh, 0)
	st.generate_normals()
	return st.commit()


## A few clods that drop off a boot and bounce once on the snow.
func _shed_burst(node_name: String) -> GPUParticles3D:
	var lump := SphereMesh.new()
	lump.radius = 0.02
	lump.height = 0.03
	lump.radial_segments = 6
	lump.rings = 3
	var material := StandardMaterial3D.new()
	material.albedo_color = snow_color
	material.roughness = 0.9
	lump.material = material
	var motion := ParticleProcessMaterial.new()
	motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	motion.emission_sphere_radius = 0.03
	motion.direction = Vector3(0.0, 0.3, 0.0)
	motion.spread = 70.0
	motion.initial_velocity_min = 0.2
	motion.initial_velocity_max = 0.7
	motion.gravity = Vector3(0.0, -9.8, 0.0)
	motion.scale_min = 0.6
	motion.scale_max = 1.6
	var burst := GPUParticles3D.new()
	burst.name = node_name
	burst.draw_pass_1 = lump
	burst.process_material = motion
	burst.amount = 8
	burst.lifetime = 0.8
	burst.one_shot = true
	burst.explosiveness = 0.9
	burst.emitting = false
	burst.local_coords = false
	burst.top_level = true
	burst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	burst.visibility_aabb = AABB(Vector3(-1, -1.5, -1), Vector3(2, 2, 2))
	add_child(burst)
	return burst
