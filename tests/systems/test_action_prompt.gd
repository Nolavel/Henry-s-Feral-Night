extends SceneTree

const PROMPT_SCENE := preload("res://scenes/ui/hud/action_prompt/action_prompt_3d.tscn")
var failures := 0


func _initialize() -> void:
	var prompt := PROMPT_SCENE.instantiate() as ActionPrompt3D
	_check(prompt != null, "ActionPrompt3D scene does not instantiate")
	if prompt == null:
		quit(1)
		return
	root.add_child(prompt)
	_check(prompt.is_in_group(&"action_prompt_3d"), "prompt did not register its lookup group")
	_check(prompt.canvas_size == Vector2i(360, 150), "prompt canvas is not the compact blob layout")
	_check(is_equal_approx(prompt.billboard_pixel_size, 0.0019), "prompt scale changed")
	_check(prompt.ink_appear_duration > prompt.content_fade_in_duration,
		"blob assembly should be a distinct stage before content")
	_check(prompt.content_fade_out_duration < prompt.ink_dissolve_duration,
		"text should disappear before the longer ink dissolve")
	_check(prompt.confirm_hold_duration > 0.0,
		"pressed-key acknowledgement has no visible hold")

	var area := InteractiveArea.new()
	area.interaction_type = InteractiveArea.InteractionType.PICKUP
	area.item_name = "Firewood"
	area.description = "Dry fuel"
	var data := area.get_interaction_prompt_data()
	_check(String(data.get("key")) == "F", "prompt key is not resolved live from InputMap")
	_check(String(data.get("action")) == tr("INTERACT_PICKUP"), "pickup action text is wrong")
	_check(String(data.get("detail")) == "Dry fuel", "short description is not preserved")

	area.free()
	if prompt.get_parent() != null:
		prompt.get_parent().remove_child(prompt)
	prompt.free()
	print("test_action_prompt: %s" % ("PASS" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures > 0 else 0)


func _check(value: bool, message: String) -> void:
	if value:
		return
	failures += 1
	push_error("action prompt: %s" % message)
