extends SceneTree

const CURSOR_SCENE := preload("res://scenes/ui/hud/dynamic_cursor/mouse_cursor_ui.tscn")
const ENSO_PATH := "res://assets/ui/hud/dynamic_cursor/enso_cursor_ring.svg"
var failures := 0


func _initialize() -> void:
	var cursor := CURSOR_SCENE.instantiate() as MouseCursorUI
	_check(cursor != null, "cursor scene does not instantiate")
	_check(FileAccess.file_exists(ENSO_PATH), "Enso cursor asset is missing")
	var enso := load(ENSO_PATH) as Texture2D
	_check(enso != null, "Enso cursor texture does not load after import")
	if enso != null:
		_check(enso.get_width() == 512 and enso.get_height() == 512,
			"Enso texture should stay square and centered")
	if cursor != null:
		_check(is_equal_approx(cursor.cursor_enso_scale, 1.10),
			"Enso centre-ring scale changed")
		_check(cursor.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR,
			"Enso cursor is not using linear texture filtering")
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
