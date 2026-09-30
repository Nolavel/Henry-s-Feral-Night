extends SceneTree

## Run: godot --headless --script tests/systems/test_color_grading.gd

const DAY_PATH: String = "res://resources/environment/color_grading/HFN_ColdAsh_Day.tres"
const DUSK_PATH: String = "res://resources/environment/color_grading/HFN_ColdAsh_Dusk.tres"
const NIGHT_PATH: String = "res://resources/environment/color_grading/HFN_ColdAsh_Night.tres"
const SHELTER_PATH: String = "res://resources/environment/color_grading/HFN_ColdAsh_Shelter.tres"
const LUT_SIZE: int = 33

var _failures: int = 0

func _initialize() -> void:
	var day := load(DAY_PATH) as ColorGradeProfile
	var dusk := load(DUSK_PATH) as ColorGradeProfile
	var night := load(NIGHT_PATH) as ColorGradeProfile
	var shelter := load(SHELTER_PATH) as ColorGradeProfile
	_check_profile(day, ColorGradeController.DAY_PROFILE_ID)
	_check_profile(dusk, ColorGradeController.DUSK_PROFILE_ID)
	_check_profile(night, ColorGradeController.NIGHT_PROFILE_ID)
	_check_profile(shelter, ColorGradeController.SHELTER_PROFILE_ID)
	_check_switching(day, dusk, night, shelter)
	if _failures > 0:
		push_error("color grading: %d check(s) failed" % _failures)
		quit(1)
		return
	print("color grading: four 33^3 LUT profiles, color axes and time/shelter switching passed")
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
	_check_color_axes(profile)


## Inspect the source atlas because the headless dummy renderer cannot read Texture3D data.
## Imported dimensions above and RGB landmarks below cover layout and axis direction.
func _check_color_axes(profile: ColorGradeProfile) -> void:
	var atlas := Image.new()
	var error: Error = atlas.load_png_from_buffer(FileAccess.get_file_as_bytes(profile.lut.resource_path))
	_check(error == OK, "%s has no readable source atlas" % profile.profile_id)
	if error != OK:
		return
	var previous: Color = Color(-1.0, -1.0, -1.0)
	for index: int in range(LUT_SIZE):
		var gray: Color = atlas.get_pixel(index * LUT_SIZE + index, index)
		var spread: float = maxf(gray.r, maxf(gray.g, gray.b)) - minf(gray.r, minf(gray.g, gray.b))
		_check(spread < 0.10, "%s neutral ramp has a color cast at %d" % [profile.profile_id, index])
		_check(gray.r >= previous.r and gray.g >= previous.g and gray.b >= previous.b,
			"%s neutral ramp reverses a color axis at %d" % [profile.profile_id, index])
		previous = gray
	var last: int = LUT_SIZE - 1
	var primaries: Array[Color] = [
		atlas.get_pixel(last, 0),
		atlas.get_pixel(0, last),
		atlas.get_pixel(last * LUT_SIZE, 0),
	]
	for axis: int in range(3):
		var channels: Array[float] = [primaries[axis].r, primaries[axis].g, primaries[axis].b]
		_check(channels[axis] > 0.80 and channels[(axis + 1) % 3] < 0.20
			and channels[(axis + 2) % 3] < 0.20,
			"%s primary color axis %d is mispacked" % [profile.profile_id, axis])


func _check_switching(day: ColorGradeProfile, dusk: ColorGradeProfile, night: ColorGradeProfile, shelter: ColorGradeProfile) -> void:
	if day == null or dusk == null or night == null or shelter == null:
		return
	var world_environment := WorldEnvironment.new()
	world_environment.environment = Environment.new()
	var controller := ColorGradeController.new()
	controller.world_environment = world_environment
	controller.day_profile = day
	controller.dusk_profile = dusk
	controller.night_profile = night
	controller.shelter_profile = shelter
	root.add_child(world_environment)
	controller._ready()
	_check(controller.get_current_profile_id() == ColorGradeController.DAY_PROFILE_ID, "day LUT was not selected by default")
	controller.update_for_time(18.5)
	_check(controller.get_current_profile_id() == ColorGradeController.DUSK_PROFILE_ID, "dusk LUT did not activate")
	controller.update_for_time(22.5)
	_check(controller.get_current_profile_id() == ColorGradeController.NIGHT_PROFILE_ID, "night LUT did not activate")
	world_environment.environment.ambient_light_energy = 0.92
	controller.initialize_for_interior(true)
	_check(controller.get_current_profile_id() == ColorGradeController.SHELTER_PROFILE_ID, "shelter LUT did not override outdoor")
	_check(is_equal_approx(world_environment.environment.ambient_light_energy, 0.92), "ColorGradeController must not write ambient energy")
	controller.update_for_time(12.0)
	_check(controller.get_current_profile_id() == ColorGradeController.SHELTER_PROFILE_ID, "time changed the LUT while inside")
	var day_night := DayNightManager.new()
	day_night.color_grade_controller = controller
	day_night.shelter_ambient_energy_cap = 0.20
	_check(day_night._ambient_energy_for_context(0.92) <= 0.20 + 0.001, "DayNightManager did not cap shelter ambient")
	controller.initialize_for_interior(false)
	_check(is_equal_approx(world_environment.environment.ambient_light_energy, 0.92), "ColorGradeController changed ambient while leaving shelter")
	_check(is_equal_approx(day_night._ambient_energy_for_context(0.92), 0.92), "DayNightManager did not restore outdoor ambient policy")
	_check(controller.get_current_profile_id() == ColorGradeController.DAY_PROFILE_ID, "leaving shelter did not restore current outdoor LUT")
	day_night.free()
	_check(world_environment.environment.adjustment_enabled, "Environment adjustments are disabled")
	controller.free()
	root.remove_child(world_environment)
	world_environment.free()

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("color grading: %s" % message)
