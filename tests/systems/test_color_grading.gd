extends SceneTree

## Run: godot --headless --script tests/systems/test_color_grading.gd

const NIGHT_PATH: String = "res://resources/environment/color_grading/HFN_ColdAsh_Night.tres"
const SHELTER_PATH: String = "res://resources/environment/color_grading/HFN_ColdAsh_Shelter.tres"
const LUT_SIZE: int = 33

var _failures: int = 0


func _initialize() -> void:
	var night := load(NIGHT_PATH) as ColorGradeProfile
	var shelter := load(SHELTER_PATH) as ColorGradeProfile
	_check_profile(night, ColorGradeController.OUTDOOR_PROFILE_ID)
	_check_profile(shelter, ColorGradeController.SHELTER_PROFILE_ID)
	_check_switching(night, shelter)

	if _failures > 0:
		push_error("color grading: %d check(s) failed" % _failures)
		quit(1)
		return
	print("color grading: both 33^3 LUT profiles and switching passed")
	quit(0)


func _check_profile(profile: ColorGradeProfile, expected_id: StringName) -> void:
	_check(profile != null, "%s did not load" % expected_id)
	if profile == null:
		return
	_check(profile.profile_id == expected_id, "%s has the wrong profile id" % expected_id)
	_check(profile.lut != null, "%s has no Texture3D" % expected_id)
	if profile.lut == null:
		return
	_check(profile.lut.get_width() == LUT_SIZE, "%s width is not 33" % expected_id)
	_check(profile.lut.get_height() == LUT_SIZE, "%s height is not 33" % expected_id)
	_check(profile.lut.get_depth() == LUT_SIZE, "%s depth is not 33" % expected_id)


func _check_switching(night: ColorGradeProfile, shelter: ColorGradeProfile) -> void:
	if night == null or shelter == null or night.lut == null or shelter.lut == null:
		return
	var world_environment := WorldEnvironment.new()
	world_environment.environment = Environment.new()
	var controller := ColorGradeController.new()
	controller.world_environment = world_environment
	controller.outdoor_profile = night
	controller.shelter_profile = shelter
	root.add_child(world_environment)
	# SceneTree scripts run their assertions before a newly attached Node gets its
	# normal ready notification, so drive the same startup entry point directly.
	controller._ready()

	_check(
		controller.get_current_profile_id() == ColorGradeController.OUTDOOR_PROFILE_ID,
		"outdoor LUT was not selected by default"
	)
	_check(
		world_environment.environment.adjustment_color_correction == night.lut,
		"Environment did not receive the outdoor LUT"
	)
	controller.initialize_for_interior(true)
	_check(
		controller.get_current_profile_id() == ColorGradeController.SHELTER_PROFILE_ID,
		"interior initialization did not select the shelter LUT"
	)
	_check(
		world_environment.environment.adjustment_color_correction == shelter.lut,
		"Environment did not receive the shelter LUT"
	)
	_check(world_environment.environment.adjustment_enabled, "Environment adjustments are disabled")

	controller.free()
	root.remove_child(world_environment)
	world_environment.free()


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("color grading: %s" % message)
