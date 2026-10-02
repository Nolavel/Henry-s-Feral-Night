class_name CameraUserSettings
extends RefCounted

## Persistent player-owned TPS camera preferences.
## The Settings UI stages edits; only Accept writes this file.
const CONFIG_PATH: String = "user://settings.cfg"
const SECTION: String = "camera"

const DEFAULT_MOUSE_SENSITIVITY: float = 1.0
const MIN_MOUSE_SENSITIVITY: float = 0.25
const MAX_MOUSE_SENSITIVITY: float = 2.0
const DEFAULT_INVERT_Y: bool = false


static func defaults() -> Dictionary:
	return {
		"mouse_sensitivity_multiplier": DEFAULT_MOUSE_SENSITIVITY,
		"invert_y": DEFAULT_INVERT_Y,
	}


static func load_camera() -> Dictionary:
	var result: Dictionary = defaults()
	var config := ConfigFile.new()
	var error: Error = config.load(CONFIG_PATH)
	if error == ERR_FILE_NOT_FOUND:
		return result
	if error != OK:
		push_warning("CameraUserSettings: cannot read %s (error %d); using defaults" % [CONFIG_PATH, error])
		return result

	var raw_sensitivity: Variant = config.get_value(
		SECTION,
		"mouse_sensitivity_multiplier",
		DEFAULT_MOUSE_SENSITIVITY
	)
	if typeof(raw_sensitivity) == TYPE_FLOAT or typeof(raw_sensitivity) == TYPE_INT:
		result["mouse_sensitivity_multiplier"] = clampf(
			float(raw_sensitivity),
			MIN_MOUSE_SENSITIVITY,
			MAX_MOUSE_SENSITIVITY
		)

	var raw_invert_y: Variant = config.get_value(SECTION, "invert_y", DEFAULT_INVERT_Y)
	if typeof(raw_invert_y) == TYPE_BOOL:
		result["invert_y"] = bool(raw_invert_y)

	return result


static func save_camera(mouse_sensitivity_multiplier: float, invert_y: bool) -> Error:
	var config := ConfigFile.new()
	var load_error: Error = config.load(CONFIG_PATH)
	if load_error != OK and load_error != ERR_FILE_NOT_FOUND:
		config = ConfigFile.new()

	config.set_value(
		SECTION,
		"mouse_sensitivity_multiplier",
		clampf(mouse_sensitivity_multiplier, MIN_MOUSE_SENSITIVITY, MAX_MOUSE_SENSITIVITY)
	)
	config.set_value(SECTION, "invert_y", invert_y)
	return config.save(CONFIG_PATH)
