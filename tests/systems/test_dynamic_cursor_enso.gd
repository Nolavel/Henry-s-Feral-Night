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
		var gradient_node := cursor.get_node_or_null(^"InteractionGradient") as TextureRect
		_check(gradient_node != null, "single interaction gradient node is missing")
		_check(cursor.get_node_or_null(^"InteractionEdgeFadeLeft") == null,
			"obsolete left gradient fragment still exists")
		_check(cursor.get_node_or_null(^"InteractionEdgeFadeRight") == null,
			"obsolete right gradient fragment still exists")
		_check(is_equal_approx(cursor.interaction_gradient_core_width, 20.0),
			"interaction gradient dense core is not 20 px")
		_check(cursor.interaction_gradient_center_alpha > 0.0,
			"interaction gradient centre is transparent")
		_check(cursor.interaction_gradient_width < 468.0,
			"interaction gradient was not shortened from the previous pass")
		_check(cursor.interaction_gradient_width > cursor.prompt_content_size.x,
			"interaction gradient no longer covers the key/action content")
		_check(cursor.interaction_gradient_height < 46.0,
			"interaction gradient was not reduced in height")
		var prompt_face := cursor.get_node_or_null(^"InteractionPrompt") as ActionPromptFace
		_check(prompt_face != null, "interaction prompt face is missing")
		if prompt_face != null:
			prompt_face.set_reveal_amounts(0.25, 0.5, 0.75)
			_check(is_equal_approx(prompt_face.get_key_reveal(), 0.25),
				"key fade amount is not independent")
			_check(is_equal_approx(prompt_face.get_text_reveal(), 0.5),
				"action text fade amount is not independent")
			_check(is_equal_approx(prompt_face.get_detail_reveal(), 0.75),
				"detail fade amount is not independent")
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
