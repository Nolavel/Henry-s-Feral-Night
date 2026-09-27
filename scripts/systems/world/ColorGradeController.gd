extends Node
class_name ColorGradeController

## Owns HFN's final Environment adjustment without replacing the Environment.
## Shelter detection stays outside this class; gameplay calls the public API.

signal profile_changed(profile_id: StringName)

const OUTDOOR_PROFILE_ID: StringName = &"HFN_ColdAsh_Night"
const SHELTER_PROFILE_ID: StringName = &"HFN_ColdAsh_Shelter"

@export var world_environment: WorldEnvironment
@export var outdoor_profile: ColorGradeProfile
@export var shelter_profile: ColorGradeProfile
@export var default_profile_id: StringName = OUTDOOR_PROFILE_ID

var _current_profile: ColorGradeProfile


func _ready() -> void:
	if not set_profile(default_profile_id):
		push_warning(
			"ColorGradeController: default profile '%s' is unavailable; using outdoor."
			% default_profile_id
		)
		use_outdoor_profile()


## Entry point for the future shelter/volume owner.
func initialize_for_interior(is_inside: bool) -> void:
	if is_inside:
		use_shelter_profile()
	else:
		use_outdoor_profile()


func use_outdoor_profile() -> bool:
	return _apply_profile(outdoor_profile)


func use_shelter_profile() -> bool:
	return _apply_profile(shelter_profile)


func set_profile(profile_id: StringName) -> bool:
	match profile_id:
		OUTDOOR_PROFILE_ID:
			return use_outdoor_profile()
		SHELTER_PROFILE_ID:
			return use_shelter_profile()
		_:
			push_warning("ColorGradeController: unknown profile '%s'." % profile_id)
			return false


func get_current_profile_id() -> StringName:
	return _current_profile.profile_id if _current_profile != null else &""


func _apply_profile(profile: ColorGradeProfile) -> bool:
	if not is_instance_valid(world_environment) or world_environment.environment == null:
		push_warning("ColorGradeController: WorldEnvironment is not ready.")
		return false
	if profile == null or profile.lut == null:
		push_warning("ColorGradeController: requested profile or LUT is missing.")
		return false

	var environment: Environment = world_environment.environment
	environment.adjustment_enabled = true
	environment.adjustment_color_correction = profile.lut
	environment.adjustment_brightness = profile.brightness
	environment.adjustment_contrast = profile.contrast
	environment.adjustment_saturation = profile.saturation

	var changed: bool = _current_profile != profile
	_current_profile = profile
	if changed:
		profile_changed.emit(profile.profile_id)
	return true
