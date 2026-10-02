class_name PerformanceABTestController
extends Node

## One-switch A/B harness for the HD 620 performance epic (#172).
##
## Keep this node disabled in normal play. For a benchmark, enable it in the
## Key West scene, turn on exactly one test boolean, run the same location, and
## copy [PerfMeta], [PerfTest] and [PerfJSON] lines from the console.
##
## Baseline = enabled=true with every test boolean false.

const SNOW_SHELL_SCRIPT: GDScript = preload("res://scripts/systems/world/snow/snow_shell.gd")
const SNOWFALL_SCRIPT: GDScript = preload("res://scripts/systems/world/weather/snowfall_vfx.gd")
const INTERACT_SCRIPT: GDScript = preload("res://scripts/actors/player/henry/components/interact_component.gd")

const PERF_SCHEMA: String = "hoarbound_perf_ab_v1"
const MAP_GROUP: StringName = &"dev_diorama_map"
const SHAPE_NAMES: Array[StringName] = [&"SnowShape0", &"SnowShape1", &"SnowShape2"]

@export_group("Run")
## Master switch. False keeps the harness inert in normal gameplay.
@export var enabled: bool = false
## Optional note printed with every test event, e.g. "Fort Street / heavy snow".
@export var run_label: String = ""
## StatsDisplay is switched to PerfJSON console output before its UI is built.
@export var auto_enable_perf_json: bool = true
## Default protocol from #172: settle streaming/shaders before collecting data.
@export_range(0.0, 120.0, 1.0) var warmup_seconds: float = 15.0
## Measurement window. PerfJSON continues every second while this runs.
@export_range(5.0, 180.0, 1.0) var sample_seconds: float = 30.0
## Off by default so an accidental second checkbox cannot invalidate an A/B run.
@export var allow_combined_tests: bool = false

@export_group("A/B Tests — enable ONE")
## TEST 1 — presentation cadence only.
@export var test_01_vsync_off: bool = false
## TEST 2 — stops the hidden debug-map World3D render target.
@export var test_02_dev_map_viewport_off: bool = false
## TEST 3 — disables the complete local deformable SnowShell path.
@export var test_03_full_snow_shell_off: bool = false
## TEST 4 — keeps SnowShell alive but suppresses its three shaping viewports.
@export var test_04_snow_shaping_off: bool = false
## TEST 5 — disables Forward+ volumetric fog only.
@export var test_05_volumetric_fog_off: bool = false
## TEST 6 — disables the main DirectionalLight3D shadows only.
@export var test_06_directional_shadows_off: bool = false
## TEST 7 — replaces the dynamic Freeman sky render with a flat background.
@export var test_07_dynamic_sky_off: bool = false
## TEST 8 — disables snowfall particle emitters and the local height-field collider.
@export var test_08_snowfall_vfx_off: bool = false
## TEST 9 — disables InteractComponent physics-tick target detection/approach work.
@export var test_09_interaction_physics_off: bool = false
## TEST 10 — leaves the camera solver running but gives its collision probe a zero mask.
@export var test_10_camera_collision_probes_off: bool = false

var _context: WorldContext
var _active_tests: Array[String] = []
var _mutations: Array[String] = []
var _warnings: Array[String] = []
var _shape_viewports: Array[SubViewport] = []
var _snowfall: Node
var _flat_sky_environment: Environment
var _elapsed: float = 0.0
var _last_wall_usec: int = 0
var _sample_started: bool = false
var _sample_finished: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	## SnowShell is a dynamically appended system at default priority 0. Run
	## after it so shape UPDATE_ONCE requests can be cancelled before rendering.
	process_priority = 10000
	set_process(false)


func on_world_ready(context: WorldContext) -> void:
	_context = context
	if not enabled or context == null or context.world == null:
		return

	_active_tests = _collect_active_tests()
	if _active_tests.size() > 1 and not allow_combined_tests:
		_warnings.append(
			"Multiple A/B switches are enabled. No mutation was applied; enable allow_combined_tests only for an intentional combined run."
		)
		_print_event("rejected", {
			"active_tests": _active_tests,
			"warnings": _warnings,
		})
		push_error("PerformanceABTestController: multiple tests enabled; run rejected")
		return

	## World builds StatsDisplay after authored children are notified, so setting
	## this here guarantees PerfMeta/PerfJSON are enabled for the same run.
	if auto_enable_perf_json:
		context.world.set("print_runtime_debug_stats", true)

	## DevDioramaMap is UI and does not exist until World._build_ui(), which runs
	## after this callback. Deferred application sees the complete runtime tree.
	call_deferred("_apply_tests_deferred")


func _apply_tests_deferred() -> void:
	if not enabled or _context == null:
		return

	if test_01_vsync_off:
		_apply_vsync_off()
	if test_02_dev_map_viewport_off:
		_apply_dev_map_off()
	if test_03_full_snow_shell_off:
		_apply_full_snow_shell_off()
	if test_04_snow_shaping_off:
		_apply_snow_shaping_off()
	if test_05_volumetric_fog_off:
		_apply_volumetric_fog_off()
	if test_06_directional_shadows_off:
		_apply_directional_shadows_off()
	if test_07_dynamic_sky_off:
		_apply_dynamic_sky_off()
	if test_08_snowfall_vfx_off:
		_apply_snowfall_vfx_off()
	if test_09_interaction_physics_off:
		_apply_interaction_off()
	if test_10_camera_collision_probes_off:
		_apply_camera_probes_off()

	_print_event("configured", {
		"active_tests": _active_tests if not _active_tests.is_empty() else ["baseline"],
		"mutations": _mutations,
		"warnings": _warnings,
		"state": _state_snapshot(),
		"warmup_s": warmup_seconds,
		"sample_s": sample_seconds,
	})
	_begin_timing()


func _begin_timing() -> void:
	_elapsed = 0.0
	_last_wall_usec = Time.get_ticks_usec()
	_sample_started = warmup_seconds <= 0.0
	_sample_finished = false
	if _sample_started:
		_print_event("sample_begin", {"copy_perfjson_from_here": true})
	else:
		_print_event("warmup_begin", {"duration_s": warmup_seconds})
	set_process(true)


func _process(_delta: float) -> void:
	var now_usec: int = Time.get_ticks_usec()
	var wall_delta_s: float = maxf(float(now_usec - _last_wall_usec) / 1000000.0, 0.0)
	_last_wall_usec = now_usec

	## SnowShell asks its shape viewports for UPDATE_ONCE every frame. This
	## controller runs later in process priority and cancels those requests.
	if test_04_snow_shaping_off:
		_force_shape_viewports_off()

	## DayNightManager rewrites ambient-light source as the clock advances. Keep
	## the flat-sky test stable for the full sample instead of letting it drift.
	if test_07_dynamic_sky_off:
		_force_dynamic_sky_off()

	## Weather signals may change particle emission independently of _process,
	## so keep TEST 8 hard-disabled until the run ends.
	if test_08_snowfall_vfx_off:
		_force_snowfall_vfx_off()

	_elapsed += wall_delta_s
	if not _sample_started and _elapsed >= warmup_seconds:
		_sample_started = true
		_print_event("sample_begin", {"copy_perfjson_from_here": true})

	if _sample_started and not _sample_finished and _elapsed >= warmup_seconds + sample_seconds:
		_sample_finished = true
		_print_event("sample_complete", {
			"copy_perfjson_until_here": true,
			"state": _state_snapshot(),
		})
		## Keep processing only when a test needs frame-by-frame enforcement.
		if (
			not test_04_snow_shaping_off
			and not test_07_dynamic_sky_off
			and not test_08_snowfall_vfx_off
		):
			set_process(false)


func _collect_active_tests() -> Array[String]:
	var out: Array[String] = []
	if test_01_vsync_off:
		out.append("TEST 1 — VSync OFF")
	if test_02_dev_map_viewport_off:
		out.append("TEST 2 — Dev Map SubViewport OFF")
	if test_03_full_snow_shell_off:
		out.append("TEST 3 — Full SnowShell OFF")
	if test_04_snow_shaping_off:
		out.append("TEST 4 — Snow shaping OFF")
	if test_05_volumetric_fog_off:
		out.append("TEST 5 — Volumetric fog OFF")
	if test_06_directional_shadows_off:
		out.append("TEST 6 — Directional shadows OFF")
	if test_07_dynamic_sky_off:
		out.append("TEST 7 — Dynamic sky OFF")
	if test_08_snowfall_vfx_off:
		out.append("TEST 8 — Snowfall VFX OFF")
	if test_09_interaction_physics_off:
		out.append("TEST 9 — Interaction physics OFF")
	if test_10_camera_collision_probes_off:
		out.append("TEST 10 — Camera collision probes OFF")
	return out


func _apply_vsync_off() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_mutations.append("DisplayServer VSync -> DISABLED")


func _apply_dev_map_off() -> void:
	var maps: Array[Node] = get_tree().get_nodes_in_group(MAP_GROUP)
	if maps.is_empty():
		_warn("DevDioramaMap group was not found")
		return
	var changed: int = 0
	for map_node: Node in maps:
		var viewport := map_node.find_child("MapViewport", true, false) as SubViewport
		if viewport == null:
			continue
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		changed += 1
	if changed == 0:
		_warn("DevDioramaMap exists but MapViewport was not found")
	else:
		_mutations.append("Dev map SubViewport(s) UPDATE_DISABLED: %d" % changed)


func _apply_full_snow_shell_off() -> void:
	var shell: Node = _context.get_system(SNOW_SHELL_SCRIPT)
	if shell == null:
		_warn("SnowShell system was not found")
		return
	shell.set_process(false)
	shell.set_physics_process(false)
	_disable_render_work_recursive(shell)
	var mover: Node = _context.player.get_node_or_null(^"MovementController") if _context.player != null else null
	if mover != null:
		if &"snow_speed_multiplier" in mover:
			mover.set(&"snow_speed_multiplier", 1.0)
		if &"snow_accel_multiplier" in mover:
			mover.set(&"snow_accel_multiplier", 1.0)
	RenderingServer.global_shader_parameter_set(&"snow_window", Vector4.ZERO)
	_mutations.append("SnowShell process + physics + local viewports/visuals -> OFF")


func _apply_snow_shaping_off() -> void:
	var shell: Node = _context.get_system(SNOW_SHELL_SCRIPT)
	if shell == null:
		_warn("SnowShell system was not found")
		return
	_shape_viewports.clear()
	for shape_name: StringName in SHAPE_NAMES:
		var viewport := shell.find_child(String(shape_name), true, false) as SubViewport
		if viewport != null:
			viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
			_shape_viewports.append(viewport)
	if _shape_viewports.size() != SHAPE_NAMES.size():
		_warn("Expected 3 SnowShape viewports, found %d" % _shape_viewports.size())
	_mutations.append("SnowShape UPDATE_ONCE requests suppressed: %d viewports" % _shape_viewports.size())


func _force_shape_viewports_off() -> void:
	for viewport: SubViewport in _shape_viewports:
		if is_instance_valid(viewport):
			viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED


func _apply_volumetric_fog_off() -> void:
	var world_environment := _find_world_environment()
	if world_environment == null or world_environment.environment == null:
		_warn("WorldEnvironment/Environment was not found")
		return
	world_environment.environment.volumetric_fog_enabled = false
	_mutations.append("Environment volumetric_fog_enabled -> false")


func _apply_directional_shadows_off() -> void:
	var sun := _find_sun()
	if sun == null:
		_warn("SunLight DirectionalLight3D was not found")
		return
	sun.shadow_enabled = false
	_mutations.append("SunLight shadow_enabled -> false")


func _apply_dynamic_sky_off() -> void:
	var world_environment := _find_world_environment()
	if world_environment == null or world_environment.environment == null:
		_warn("WorldEnvironment/Environment was not found")
		return
	_flat_sky_environment = world_environment.environment
	_force_dynamic_sky_off()
	_mutations.append("Dynamic sky/radiance -> flat Environment background")


func _force_dynamic_sky_off() -> void:
	if _flat_sky_environment == null:
		return
	_flat_sky_environment.background_mode = Environment.BG_COLOR
	_flat_sky_environment.background_color = Color(0.18, 0.21, 0.25)
	_flat_sky_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_flat_sky_environment.ambient_light_color = Color(0.55, 0.58, 0.62)
	_flat_sky_environment.sky = null


func _apply_snowfall_vfx_off() -> void:
	_snowfall = _context.get_system(SNOWFALL_SCRIPT)
	if _snowfall == null:
		_warn("SnowfallVFX system was not found")
		return
	_snowfall.set_process(false)
	_force_snowfall_vfx_off()
	_mutations.append("Snowfall GPUParticles + local HeightFieldService -> OFF")


func _force_snowfall_vfx_off() -> void:
	if not is_instance_valid(_snowfall):
		return
	_disable_particles_recursive(_snowfall)
	var heightfield: Node = _snowfall.get("heightfield_service") as Node
	if heightfield != null and heightfield.has_method(&"set_active"):
		heightfield.call(&"set_active", false)
		heightfield.set_process(false)


func _apply_interaction_off() -> void:
	var interact: Node = _context.find_in_scene(INTERACT_SCRIPT)
	if interact == null:
		_warn("InteractComponent was not found")
		return
	interact.set_physics_process(false)
	if interact.has_method(&"_clear_current_target"):
		interact.call(&"_clear_current_target")
	_mutations.append("InteractComponent physics processing -> OFF")


func _apply_camera_probes_off() -> void:
	var camera: TpsCamera = _context.camera as TpsCamera
	if camera == null:
		_warn("TpsCamera was not found")
		return
	camera.collision_mask = 0
	if camera.has_method(&"_sync_helpers"):
		camera.call(&"_sync_helpers")
	_mutations.append("TpsCamera collision_mask -> 0; transform solver remains active")


func _disable_render_work_recursive(node: Node) -> void:
	if node is SubViewport:
		(node as SubViewport).render_target_update_mode = SubViewport.UPDATE_DISABLED
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).visible = false
	if node is GPUParticles3D:
		var particles := node as GPUParticles3D
		particles.emitting = false
		particles.amount_ratio = 0.0
		particles.visible = false
	for child: Node in node.get_children():
		_disable_render_work_recursive(child)


func _disable_particles_recursive(node: Node) -> void:
	if node is GPUParticles3D:
		var particles := node as GPUParticles3D
		particles.emitting = false
		particles.amount_ratio = 0.0
		particles.visible = false
	for child: Node in node.get_children():
		_disable_particles_recursive(child)


func _find_world_environment() -> WorldEnvironment:
	if _context == null or _context.world == null:
		return null
	return _context.world.find_child("WorldEnvironment", true, false) as WorldEnvironment


func _find_sun() -> DirectionalLight3D:
	if _context == null or _context.world == null:
		return null
	return _context.world.find_child("SunLight", true, false) as DirectionalLight3D


func _state_snapshot() -> Dictionary:
	var state := {
		"vsync_mode": int(DisplayServer.window_get_vsync_mode()),
	}
	var map_update_mode: Variant = null
	for map_node: Node in get_tree().get_nodes_in_group(MAP_GROUP):
		var map_viewport := map_node.find_child("MapViewport", true, false) as SubViewport
		if map_viewport != null:
			map_update_mode = int(map_viewport.render_target_update_mode)
			break
	state["dev_map_update_mode"] = map_update_mode

	var shell: Node = _context.get_system(SNOW_SHELL_SCRIPT) if _context != null else null
	state["snow_shell_process"] = shell.is_processing() if shell != null else null
	state["snow_shell_physics"] = shell.is_physics_processing() if shell != null else null
	state["snow_shape_viewports"] = _shape_viewports.size() if test_04_snow_shaping_off else null

	var world_environment := _find_world_environment()
	var environment: Environment = world_environment.environment if world_environment != null else null
	state["volumetric_fog"] = environment.volumetric_fog_enabled if environment != null else null
	state["sky_present"] = environment.sky != null if environment != null else null

	var sun := _find_sun()
	state["directional_shadows"] = sun.shadow_enabled if sun != null else null

	state["snowfall_process"] = _snowfall.is_processing() if is_instance_valid(_snowfall) else null

	var interact: Node = _context.find_in_scene(INTERACT_SCRIPT) if _context != null else null
	state["interaction_physics"] = interact.is_physics_processing() if interact != null else null

	var camera: TpsCamera = _context.camera as TpsCamera if _context != null else null
	state["camera_collision_mask"] = camera.collision_mask if camera != null else null
	return state


func _warn(message: String) -> void:
	_warnings.append(message)
	push_warning("PerformanceABTestController: %s" % message)


func _print_event(event: String, extra: Dictionary = {}) -> void:
	var payload := {
		"schema": PERF_SCHEMA,
		"event": event,
		"ticks_msec": Time.get_ticks_msec(),
		"run_label": run_label,
		"active_tests": _active_tests if not _active_tests.is_empty() else ["baseline"],
	}
	for key: Variant in extra:
		payload[key] = extra[key]
	print("[PerfTest] %s" % JSON.stringify(payload))
