extends SceneTree

## Checks the HUD thermometer actually follows the thermal model: icon opacity,
## the freezing warning sign, and the red critical indicator.
## Run: godot --headless --script tests/systems/test_vital_signs_binding.gd

const HUD_SCRIPT: String = "res://scripts/ui/hud/indicators/vital_signs.gd"
const STEP_MINUTES: float = 10.0

var _failures: int = 0


## Nodes added to root during _initialize() are not in the tree, so transforms
## and _ready() are both unavailable there. Running from the first frame puts
## the suite in the same conditions as the running game.
func _process(_delta: float) -> bool:
	_run()
	return true


func _run() -> void:
	_test_icon_darkens_as_the_body_cools()
	_test_warning_sign_follows_the_stage()
	_test_missing_manager_is_survivable()
	if _failures > 0:
		push_error("vitals: %d check(s) failed" % _failures)
		quit(1)
		return
	print("vitals: all checks passed")
	quit(0)


## Builds a HUD with stub TextureRects and a manager at a fixed ambient.
func _make_rig(ambient_c: float) -> Dictionary:
	var manager := ThermalManager.new()
	manager.ambient_min_c = ambient_c
	manager.ambient_max_c = ambient_c
	root.add_child(manager)
	manager.initialize()

	var hud: Control = load(HUD_SCRIPT).new()
	var icon := TextureRect.new()
	var warning := TextureRect.new()
	var upper := TextureRect.new()
	var lower := TextureRect.new()
	hud.add_child(icon)
	hud.add_child(warning)
	hud.add_child(upper)
	hud.add_child(lower)
	hud.temperature_icon = icon
	hud.temperature_warning_sign = warning
	hud.temperature_upper = upper
	hud.temperature_lower = lower
	hud.thermal_manager = manager
	root.add_child(hud)
	hud.setup_thermal_connections()

	return {"manager": manager, "hud": hud, "icon": icon, "warning": warning, "lower": lower}


func _simulate(manager: ThermalManager, hours: float) -> void:
	var step: float = STEP_MINUTES / 60.0
	var elapsed: float = 0.0
	var clock: float = 0.0
	manager.reset_clock()
	manager._on_time_update(clock)
	while elapsed < hours:
		clock = fmod(clock + step, 24.0)
		manager._on_time_update(clock)
		elapsed += step


func _dispose_rig(rig: Dictionary) -> void:
	for key: String in ["hud", "manager"]:
		var node: Node = rig[key]
		if node.get_parent() != null:
			node.get_parent().remove_child(node)
		node.free()


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("vitals: %s" % message)


func _test_icon_darkens_as_the_body_cools() -> void:
	var rig: Dictionary = _make_rig(-25.0)
	var icon: TextureRect = rig["icon"]
	var before: float = icon.modulate.a
	_simulate(rig["manager"], 3.0)
	var after: float = icon.modulate.a

	_check(after > before, "thermometer icon did not grow more opaque as the body cooled")
	_check(after <= 0.9 + 0.001, "thermometer icon exceeded ICON_MAX_ALPHA")
	_dispose_rig(rig)


func _test_warning_sign_follows_the_stage() -> void:
	var rig: Dictionary = _make_rig(-25.0)
	var hud: Control = rig["hud"]
	var warning: TextureRect = rig["warning"]
	var lower: TextureRect = rig["lower"]

	_check(is_zero_approx(warning.modulate.a), "freezing warning was visible while still warm")

	_simulate(rig["manager"], 4.0)
	_check(
		rig["manager"].get_stage() >= ThermalManager.Stage.HYPOTHERMIC,
		"four hours at -25C did not reach hypothermia; the rig cannot test the warning"
	)
	_check(hud.is_freezing_in_hud, "HUD did not register the hypothermia stage")
	_check(warning.modulate.a > 0.9, "freezing warning sign stayed hidden during hypothermia")
	_check(lower.modulate.r > 0.9 and lower.modulate.g < 0.1, "critical indicator did not turn red")

	rig["manager"].restore_body_temperature()
	_check(not hud.is_freezing_in_hud, "HUD stayed frozen after the body was restored")
	_check(is_zero_approx(warning.modulate.a), "freezing warning sign stayed up after recovery")
	_dispose_rig(rig)


## A HUD without a manager must warn and keep working, never crash.
func _test_missing_manager_is_survivable() -> void:
	var hud: Control = load(HUD_SCRIPT).new()
	root.add_child(hud)
	hud.setup_thermal_connections()
	hud.update_warning_signs()
	_check(not hud.is_freezing_in_hud, "HUD without a manager reported freezing")
	if hud.get_parent() != null:
		hud.get_parent().remove_child(hud)
	hud.free()
