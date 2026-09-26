extends SceneTree

const CURSOR_SCENE := preload("res://scenes/ui/hud/dynamic_cursor/mouse_cursor_ui.tscn")
const ENSO := preload("res://assets/ui/hud/dynamic_cursor/enso_cursor_ring.png")
var failures := 0


func _initialize() -> void:
	var cursor := CURSOR_SCENE.instantiate() as MouseCursorUI
	_check(cursor != null, "cursor scene does not instantiate")
	_check(ENSO != null, "Enso cursor texture does not load")
	if ENSO != null:
		_check(ENSO.get_width() == 128 and ENSO.get_height() == 128,
			"Enso texture should stay square and centered")
	if cursor != null:
		_check(is_equal_approx(cursor.cursor_enso_scale, 1.10),
			"Enso centre-ring scale changed")
		# Stamina/jump exports remain present: this change must not replace those systems.
		_check(cursor.sprint_arc_thickness > 0.0, "sprint stamina arcs were removed")
		_check(cursor.stamina_manager == null, "test cursor unexpectedly owns stamina state")
		cursor.free()
	print("test_dynamic_cursor_enso: %s" % ("PASS" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures > 0 else 0)


func _check(value: bool, message: String) -> void:
	if value:
		return
	failures += 1
	push_error("dynamic cursor enso: %s" % message)
