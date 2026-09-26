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
		root.add_child(cursor)
		# Runtime prompt nodes/groups are built in _ready(), not at instantiate().
		await process_frame
		_check(is_equal_approx(cursor.cursor_enso_scale, 1.10),
			"Enso centre-ring scale changed")
		_check(cursor.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR,
			"Enso cursor is not using linear texture filtering")
		_check(cursor.is_in_group(&"interaction_cursor_prompt"),
			"cursor did not register the centered interaction-prompt group")
		_check(cursor.has_center_interaction_prompt(),
			"cursor did not build the centered key/action prompt")
		_check(cursor.interaction_bracket_offset > cursor.prompt_content_size.x * 0.5,
			"interaction brackets do not clear the prompt content")
		_check(cursor.interaction_edge_fade_color.a > 0.0,
			"interaction edge fade is invisible")
		_check(cursor.interaction_edge_fade_size.x > cursor.prompt_content_size.x,
			"interaction shader strip does not extend beyond prompt content")
		_check(cursor.interaction_edge_alpha > 0.0 and cursor.interaction_edge_alpha < 1.0,
			"interaction shader edges are not semi-transparent")
		_check(cursor.interaction_edge_fade_start < 0.5,
			"interaction shader keeps too much of the strip fully opaque")
		_check(cursor.interaction_morph_duration > 0.0,
			"interaction morph has no duration")
		# Stamina/jump exports remain present: this change must not replace those systems.
		_check(cursor.sprint_arc_thickness > 0.0, "sprint stamina arcs were removed")
		_check(cursor.stamina_manager == null, "test cursor unexpectedly owns stamina state")
		root.remove_child(cursor)
		cursor.free()
	print("test_dynamic_cursor_enso: %s" % ("PASS" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures > 0 else 0)


func _check(value: bool, message: String) -> void:
	if value:
		return
	failures += 1
	push_error("dynamic cursor enso: %s" % message)
