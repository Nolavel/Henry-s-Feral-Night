extends SceneTree

## HeldFit: saved per-item transforms are applied exactly, while the null-fit
## legacy path remains available for old items.
var _failures: int = 0


func _initialize() -> void:
	var prop := Node3D.new()
	var fit := HeldFit.new()
	fit.offset = Vector3(0.11, -0.22, 0.33)
	fit.rotation_deg = Vector3(12.0, 34.0, -56.0)
	fit.scale = Vector3(1.1, 0.9, 1.2)
	fit.apply_to(prop)
	_check(prop.position.is_equal_approx(fit.offset), "offset was not applied")
	_check(prop.rotation_degrees.is_equal_approx(fit.rotation_deg), "rotation was not applied")
	_check(prop.scale.is_equal_approx(fit.scale), "scale was not applied")

	var legacy := Node3D.new()
	legacy.transform = Transform3D(Basis.from_euler(Vector3(-55.0, 0.0, 0.0) * (PI / 180.0)), Vector3(0.0, 0.12, 0.06))
	var before: Transform3D = legacy.transform
	HeldFit.apply_legacy_adjustment(legacy, &"knife")
	_check(not legacy.transform.is_equal_approx(before), "legacy knife adjustment became a no-op")

	prop.free()
	legacy.free()
	if _failures == 0:
		print("held_fit: all checks passed")
	quit(_failures)


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("held_fit: " + message)
